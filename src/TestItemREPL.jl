module TestItemREPL

using ReplMaker
using TestItemRunnerCore: run_tests, kill_test_processes, terminate_process,
    get_active_processes, RunProfile, ProcessInfo,
    TestrunResult, TestrunResultTestitem, TestrunResultTestitemProfile,
    TestrunResultMessage, TestrunResultDefinitionError,
    TestrunRecord, get_run_history, get_active_runs, cancel_run,
    get_run_result, get_last_run_id,
    CancellationTokenSource, cancel, get_token
using JuliaWorkspaces
using JuliaWorkspaces.URIs2: uri2filepath
using Logging
using Dates

# ── Logging filter (suppress TestItemControllers below Warn) ──────────

struct ModuleFilterLogger <: AbstractLogger
    wrapped::AbstractLogger
end

Logging.shouldlog(logger::ModuleFilterLogger, level, _module, group, id) = true
Logging.min_enabled_level(logger::ModuleFilterLogger) = Logging.Debug
Logging.catch_exceptions(logger::ModuleFilterLogger) = Logging.catch_exceptions(logger.wrapped)

function Logging.handle_message(logger::ModuleFilterLogger, level, message, _module, group, id, filepath, line; kwargs...)
    # Suppress TestItemControllers logs below Warn
    mod_name = string(parentmodule(_module))
    if (mod_name == "TestItemControllers" || string(_module) == "TestItemControllers") && level < Logging.Warn
        return nothing
    end
    Logging.handle_message(logger.wrapped, level, message, _module, group, id, filepath, line; kwargs...)
end

# ── Background run state ──────────────────────────────────────────────

mutable struct BackgroundRun
    task::Task
    cts::CancellationTokenSource
    result::Union{Nothing,TestrunResult}
    error::Union{Nothing,Exception}
    start_time::Float64
end

const _bg_run = Ref{Union{Nothing,BackgroundRun}}(nothing)
const _last_result = Ref{Union{Nothing,TestrunResult}}(nothing)
const _last_run_id = Ref{Union{Nothing,String}}(nothing)

# ── Argument parsing ──────────────────────────────────────────────────

function parse_args(parts)
    positional = String[]
    kwargs = Dict{Symbol,String}()
    flags = Set{Symbol}()
    for p in parts
        if startswith(p, "--")
            body = p[3:end]
            if contains(body, '=')
                k, v = split(body, '='; limit=2)
                kwargs[Symbol(k)] = v
            else
                push!(flags, Symbol(body))
            end
        else
            push!(positional, p)
        end
    end
    return positional, kwargs, flags
end

# ── Commands ──────────────────────────────────────────────────────────

function cmd_help()
    printstyled("TestItemREPL commands:\n\n"; bold=true)
    println("  help                          Show this help message")
    println("  list [path]                   List discovered test items")
    println("  list --tags=tag1,tag2         Filter by tags")
    println("  run [path|name]               Run tests (blocking, ESC to cancel)")
    println("  run --tags=t1,t2              Filter by tags")
    println("  run --workers=N               Max parallel workers (default: min(nthreads,8))")
    println("  run --timeout=S               Timeout in seconds (default: 300)")
    println("  run --coverage                Enable coverage")
    println("  run& [same options]           Run tests in background")
    println("  status                        Show background run status")
    println("  cancel [id]                   Cancel background run (or run by id)")
    println("  results [id]                  Show results (last run, or run #id)")
    println("  details <name>                Show detailed results for a test item")
    println("  output <name>                 Show output log for a test item")
    println("  process-log <id>              Show output log for a test process")
    println("  runs [--active]               List all test runs (history)")
    println("  processes                     Show active test processes")
    println("  kill                          Kill all test processes")
    nothing
end

function cmd_list(args)
    positional, kwargs, flags = parse_args(args)
    path = isempty(positional) ? pwd() : positional[1]

    if !isdir(path)
        printstyled("Error: "; color=:red, bold=true)
        println("'$path' is not a directory")
        return nothing
    end

    jw = JuliaWorkspaces.workspace_from_folders([path])
    all_items = JuliaWorkspaces.get_test_items(jw)

    tag_filter = if haskey(kwargs, :tags)
        Set(Symbol.(split(kwargs[:tags], ',')))
    else
        nothing
    end

    count = 0
    for (uri, items) in pairs(all_items)
        textfile = JuliaWorkspaces.get_text_file(jw, uri)
        filepath = uri2filepath(uri)
        for item in items.testitems
            if tag_filter !== nothing && isempty(intersect(Set(item.option_tags), tag_filter))
                continue
            end
            line, _ = JuliaWorkspaces.position_at(textfile.content, item.code_range.start)
            tags_str = isempty(item.option_tags) ? "" : " [$(join(item.option_tags, ", "))]"
            printstyled("  $(item.name)"; bold=true)
            print("  $filepath:$line")
            if !isempty(tags_str)
                printstyled(tags_str; color=:cyan)
            end
            println()
            count += 1
        end
    end

    if count == 0
        println("  No test items found.")
    else
        println()
        println("$count test item(s) found.")
    end
    nothing
end

function _build_run_kwargs(args; return_results=false)
    positional, kwargs, flags = parse_args(args)
    path = nothing
    name_filter = nothing

    for p in positional
        if isdir(p)
            path = p
        else
            name_filter = p
        end
    end
    if path === nothing
        path = pwd()
    end

    run_kwargs = Dict{Symbol,Any}(
        :return_results => return_results,
        :print_failed_results => true,
        :print_summary => true,
        :progress_ui => :bar,
    )

    if haskey(kwargs, :workers)
        run_kwargs[:max_workers] = parse(Int, kwargs[:workers])
    end
    if haskey(kwargs, :timeout)
        run_kwargs[:timeout] = parse(Int, kwargs[:timeout])
    end
    if :coverage in flags
        run_kwargs[:environments] = [RunProfile("Default", true, Dict{String,Any}())]
    end

    tag_filter = if haskey(kwargs, :tags)
        Set(Symbol.(split(kwargs[:tags], ',')))
    else
        nothing
    end

    if tag_filter !== nothing || name_filter !== nothing
        run_kwargs[:filter] = function(info)
            if name_filter !== nothing && !contains(lowercase(string(info.name)), lowercase(name_filter))
                return false
            end
            if tag_filter !== nothing && isempty(intersect(Set(info.tags), tag_filter))
                return false
            end
            return true
        end
    end

    return path, run_kwargs
end

function cmd_run(args)
    _check_bg_completion()
    path, run_kwargs = _build_run_kwargs(args)

    cts = CancellationTokenSource()
    run_kwargs[:token] = get_token(cts)
    run_kwargs[:return_results] = false
    run_kwargs[:print_failed_results] = true
    run_kwargs[:print_summary] = true

    printstyled("Starting test run...\n"; color=:cyan)

    # Capture the run ID early (it's been assigned by run_tests at start)
    # We need to get it after run_tests starts but the ID is generated synchronously
    # before the async work begins, so we set it after fetch.

    # Run tests in a task so we can monitor for ESC key
    test_task = @async try
        run_tests(path; run_kwargs...)
    catch e
        e
    end

    cancelled = Ref(false)
    try
        # Try to set terminal to raw mode for ESC detection
        term = nothing
        raw_set = false
        try
            if isdefined(Base, :active_repl) && stdin isa Base.TTY
                term = stdin
                ccall(:uv_tty_set_mode, Cint, (Ptr{Cvoid}, Cint), term.handle, 1)  # UV_TTY_MODE_RAW
                raw_set = true
            end
        catch
            # Fall through — ESC detection won't work but Ctrl+C still will
        end

        try
            while !istaskdone(test_task)
                if raw_set && bytesavailable(stdin) > 0
                    b = read(stdin, UInt8)
                    if b == 0x1b  # ESC
                        cancel(cts)
                        cancelled[] = true
                        printstyled("\nTest run cancelled (ESC).\n"; color=:yellow)
                        break
                    end
                end
                sleep(0.05)
            end
        finally
            if raw_set
                try
                    ccall(:uv_tty_set_mode, Cint, (Ptr{Cvoid}, Cint), term.handle, 0)  # UV_TTY_MODE_NORMAL
                catch
                end
            end
        end

        # Retrieve run ID from return value (run_tests returns testrun_id when return_results=false)
        if !cancelled[]
            raw = try
                fetch(test_task)
            catch e
                e
            end
            if raw isa String
                _last_run_id[] = raw
                result = get_run_result(raw)
                if result !== nothing
                    _last_result[] = result
                end
            elseif raw isa Exception
                # Store run ID even if errored
                last_id = get_last_run_id()
                if last_id !== nothing
                    _last_run_id[] = last_id
                    result = get_run_result(last_id)
                    if result !== nothing
                        _last_result[] = result
                    end
                end
                throw(raw)
            end
        else
            # Still retrieve the run ID even if cancelled
            last_id = get_last_run_id()
            if last_id !== nothing
                _last_run_id[] = last_id
                result = get_run_result(last_id)
                if result !== nothing
                    _last_result[] = result
                end
            end
        end
    catch e
        if e isa InterruptException
            cancel(cts)
            printstyled("\nTest run cancelled.\n"; color=:yellow)
        else
            rethrow()
        end
    end
    nothing
end

function cmd_run_bg(args)
    _check_bg_completion()

    if _bg_run[] !== nothing && !istaskdone(_bg_run[].task)
        printstyled("A background run is already active. Use 'cancel' first.\n"; color=:yellow)
        return nothing
    end

    path, run_kwargs = _build_run_kwargs(args; return_results=true)
    cts = CancellationTokenSource()
    run_kwargs[:token] = get_token(cts)
    run_kwargs[:progress_ui] = :none
    run_kwargs[:print_summary] = false
    run_kwargs[:print_failed_results] = false

    bg = BackgroundRun(
        @async(try
            run_tests(path; run_kwargs...)
        catch e
            e
        end),
        cts,
        nothing,
        nothing,
        time(),
    )

    @async begin
        raw = try
            fetch(bg.task)
        catch e
            e
        end
        if raw isa Exception
            bg.error = raw
        elseif raw isa TestrunResult
            bg.result = raw
            _last_result[] = raw
        elseif raw isa String
            # return_results=true returns TestrunResult, but capture run ID too
            _last_run_id[] = raw
            result = get_run_result(raw)
            if result !== nothing
                bg.result = result
                _last_result[] = result
            end
        end
    end

    _bg_run[] = bg
    # Retrieve the run ID (it was just created by run_tests)
    last_id = get_last_run_id()
    if last_id !== nothing
        _last_run_id[] = last_id
    end
    id_str = _last_run_id[] !== nothing ? " #$(_last_run_id[])" : ""
    printstyled("Test run$(id_str) started in background.\n"; color=:green)
    nothing
end

function cmd_status()
    _check_bg_completion()
    bg = _bg_run[]
    if bg === nothing
        println("No background test run.")
        return nothing
    end

    elapsed = round(time() - bg.start_time; digits=1)
    if istaskdone(bg.task)
        if bg.error !== nothing
            printstyled("Background run errored"; color=:red, bold=true)
            println(" after $(elapsed)s: $(bg.error)")
        else
            printstyled("Background run completed"; color=:green, bold=true)
            println(" in $(elapsed)s. Use 'results' to see details.")
        end
    else
        printstyled("Background run in progress"; color=:yellow, bold=true)
        println(" ($(elapsed)s elapsed)")

        # Show progress details from live snapshot
        run_id = _last_run_id[]
        if run_id !== nothing
            result = get_run_result(run_id)
            if result !== nothing
                n_passed = 0; n_failed = 0; n_errored = 0; n_skipped = 0
                for ti in result.testitems
                    for prof in ti.profiles
                        if prof.status == :passed;  n_passed += 1
                        elseif prof.status == :failed;  n_failed += 1
                        elseif prof.status == :errored; n_errored += 1
                        elseif prof.status == :skipped; n_skipped += 1
                        end
                    end
                end
                done = n_passed + n_failed + n_errored + n_skipped
                # Try to get total from run history
                history = get_run_history()
                rec = nothing
                for r in history
                    if r.id == run_id
                        rec = r
                        break
                    end
                end

                parts = String[]
                n_passed > 0 && push!(parts, "\e[32m$(n_passed) passed\e[0m")
                n_failed > 0 && push!(parts, "\e[31m$(n_failed) failed\e[0m")
                n_errored > 0 && push!(parts, "\e[31m$(n_errored) errored\e[0m")
                n_skipped > 0 && push!(parts, "$(n_skipped) skipped")
                detail = isempty(parts) ? "" : " — $(join(parts, ", "))"
                println("  Progress: $done completed$detail")
            end
        end
    end
    nothing
end

function cmd_cancel(args=String[])
    if !isempty(args)
        # Cancel by run ID
        id = args[1]
        if cancel_run(id)
            printstyled("Cancel requested for run $id.\n"; color=:yellow)
        else
            println("No active run found with id '$id'.")
        end
        return nothing
    end

    bg = _bg_run[]
    if bg === nothing || istaskdone(bg.task)
        println("No active background run to cancel.")
        return nothing
    end
    cancel(bg.cts)
    printstyled("Background run cancel requested.\n"; color=:yellow)
    nothing
end

function cmd_results(args=String[])
    _check_bg_completion()

    result = nothing
    run_id = nothing
    run_record = nothing

    if !isempty(args)
        # results <id> — look up a specific run
        run_id = args[1]
        history = get_run_history()
        idx = findfirst(r -> r.id == run_id || startswith(r.id, run_id), history)
        if idx === nothing
            println("No run found with id '#$run_id'.")
            return nothing
        end
        run_record = history[idx]
        run_id = run_record.id
        result = get_run_result(run_id)
    else
        # results — show last run
        result = _last_result[]
        run_id = _last_run_id[]
        if result === nothing && run_id !== nothing
            result = get_run_result(run_id)
        end
        if run_id !== nothing
            history = get_run_history()
            idx = findfirst(r -> r.id == run_id, history)
            if idx !== nothing
                run_record = history[idx]
            end
        end
    end

    if result === nothing
        println("No test results available.")
        return nothing
    end

    # Count statuses
    n_passed = 0; n_failed = 0; n_errored = 0; n_skipped = 0
    for ti in result.testitems
        for prof in ti.profiles
            if prof.status == :passed;  n_passed += 1
            elseif prof.status == :failed;  n_failed += 1
            elseif prof.status == :errored; n_errored += 1
            elseif prof.status == :skipped; n_skipped += 1
            end
        end
    end
    total = n_passed + n_failed + n_errored + n_skipped

    # Header
    println()
    id_str = run_id !== nothing ? "Run #$run_id: " : ""
    is_active = run_record !== nothing && run_record.status == :running
    duration_str = ""
    if run_record !== nothing && run_record.end_time !== nothing
        dur = round(run_record.end_time - run_record.start_time; digits=1)
        duration_str = " ($dur s)"
    elseif is_active
        dur = round(time() - run_record.start_time; digits=1)
        duration_str = " ($dur s, in progress)"
    end

    printstyled("$(id_str)$(total) test(s)$duration_str"; bold=true)
    print(" — ")
    parts = String[]
    n_passed > 0 && push!(parts, "\e[32m$(n_passed) passed\e[0m")
    n_failed > 0 && push!(parts, "\e[31m$(n_failed) failed\e[0m")
    n_errored > 0 && push!(parts, "\e[31m$(n_errored) errored\e[0m")
    n_skipped > 0 && push!(parts, "$(n_skipped) skipped")
    println(join(parts, ", "))

    if is_active
        printstyled("  (run still in progress, showing results so far)\n"; color=:yellow)
    end

    if !isempty(result.definition_errors)
        printstyled("\nDefinition errors:\n"; color=:red, bold=true)
        for de in result.definition_errors
            println("  $(uri2filepath(de.uri)):$(de.line) — $(de.message)")
        end
    end

    # Show failed/errored details
    for ti in result.testitems
        for prof in ti.profiles
            if prof.status in (:failed, :errored)
                println()
                label = prof.status == :failed ? "FAIL" : "ERROR"
                printstyled("  [$label] $(ti.name)"; color=:red, bold=true)
                if prof.duration !== missing
                    print(" ($(prof.duration)ms)")
                end
                println()
                if prof.messages !== missing
                    for msg in prof.messages
                        println("    ", replace(msg.message, "\n" => "\n    "))
                    end
                end
            end
        end
    end

    # When all pass, show top 5 slowest tests
    if n_failed == 0 && n_errored == 0 && total > 0
        timed = Tuple{String,Float64}[]
        for ti in result.testitems
            for prof in ti.profiles
                if prof.duration !== missing
                    push!(timed, (ti.name, prof.duration))
                end
            end
        end
        if !isempty(timed)
            sort!(timed; by=last, rev=true)
            n_show = min(5, length(timed))
            println()
            printstyled("  Slowest tests:\n"; color=:light_black)
            for i in 1:n_show
                name, dur = timed[i]
                printstyled("    $(lpad(string(round(dur; digits=1)), 8))ms"; color=:light_black)
                println("  $name")
            end
        end
    end
    nothing
end

function cmd_kill()
    kill_test_processes()
    printstyled("All test processes terminated.\n"; color=:yellow)
    nothing
end

function cmd_processes()
    procs = get_active_processes()
    if isempty(procs)
        println("No active test processes.")
        return nothing
    end

    printstyled("Active test processes:\n\n"; bold=true)
    printstyled("  $(rpad("ID", 38))$(rpad("Package", 30))Status\n"; bold=true)
    printstyled("  $(repeat("─", 78))\n"; color=:light_black)
    for p in procs
        status_color = if p.status == "Running"
            :green
        elseif p.status == "Idle"
            :light_black
        elseif p.status in ("Launching", "Activating", "Revising")
            :yellow
        else
            :default
        end
        print("  $(rpad(p.id, 38))$(rpad(p.package_name, 30))")
        printstyled("$(p.status)\n"; color=status_color)
    end
    println()
    println("$(length(procs)) process(es) active.")
    nothing
end
# ── Detailed inspection commands ─────────────────────────────────────────

function _find_testitem(result::TestrunResult, name::String)
    # Exact match first, then case-insensitive contains
    for ti in result.testitems
        ti.name == name && return ti
    end
    name_lower = lowercase(name)
    matches = filter(ti -> contains(lowercase(ti.name), name_lower), result.testitems)
    if length(matches) == 1
        return matches[1]
    elseif length(matches) > 1
        printstyled("Multiple matches for '$name':\n"; color=:yellow)
        for m in matches
            println("  $(m.name)")
        end
        return nothing
    end
    return nothing
end

function cmd_output(args)
    result = _last_result[]
    if result === nothing
        println("No test results available.")
        return nothing
    end
    if isempty(args)
        println("Usage: output <test item name>")
        return nothing
    end

    name = join(args, " ")
    ti = _find_testitem(result, name)
    if ti === nothing
        println("No test item found matching '$name'.")
        return nothing
    end

    printstyled("Output for $(ti.name):\n"; bold=true)
    has_output = false
    for prof in ti.profiles
        if prof.output !== missing && !isempty(prof.output)
            if length(ti.profiles) > 1
                printstyled("  [$(prof.profile_name)]\n"; color=:cyan)
            end
            println(prof.output)
            has_output = true
        end
    end
    if !has_output
        println("  No output recorded for this test item.")
    end
    nothing
end

function cmd_process_log(args)
    result = _last_result[]
    if result === nothing
        println("No test results available.")
        return nothing
    end
    if isempty(args)
        println("Usage: process-log <process id>")
        return nothing
    end

    id = args[1]
    # Try exact match, then prefix match
    output = get(result.process_outputs, id, nothing)
    if output === nothing
        matches = filter(k -> startswith(k, id), collect(keys(result.process_outputs)))
        if length(matches) == 1
            output = result.process_outputs[matches[1]]
            id = matches[1]
        elseif length(matches) > 1
            printstyled("Multiple processes match '$id':\n"; color=:yellow)
            for m in matches
                println("  $m")
            end
            return nothing
        end
    end

    if output === nothing
        println("No process output found for '$id'.")
        return nothing
    end

    printstyled("Process output for $id:\n"; bold=true)
    println(output)
    nothing
end

function cmd_details(args)
    result = _last_result[]
    if result === nothing
        println("No test results available.")
        return nothing
    end
    if isempty(args)
        println("Usage: details <test item name>")
        return nothing
    end

    name = join(args, " ")
    ti = _find_testitem(result, name)
    if ti === nothing
        println("No test item found matching '$name'.")
        return nothing
    end

    printstyled("\n$(ti.name)"; bold=true)
    println("  $(uri2filepath(ti.uri))")

    for prof in ti.profiles
        println()
        status_color = if prof.status == :passed
            :green
        elseif prof.status in (:failed, :errored)
            :red
        elseif prof.status == :skipped
            :light_black
        else
            :default
        end
        printstyled("  [$(prof.profile_name)] $(prof.status)"; color=status_color, bold=true)
        if prof.duration !== missing
            print(" ($(prof.duration)ms)")
        end
        println()

        if prof.messages !== missing
            for msg in prof.messages
                println("    $(uri2filepath(msg.uri)):$(msg.line)")
                println("    ", replace(msg.message, "\n" => "\n    "))
            end
        end

        if prof.output !== missing && !isempty(prof.output)
            printstyled("    Output:\n"; color=:cyan)
            for line in split(prof.output, '\n')
                println("      ", line)
            end
        end
    end
    nothing
end

function cmd_runs(args)
    _, kwargs, flags = parse_args(args)
    history = get_run_history()

    if :active in flags
        history = filter(r -> r.status == :running, history)
    end

    if isempty(history)
        if :active in flags
            println("No active test runs.")
        else
            println("No test runs in history.")
        end
        return nothing
    end

    printstyled("Test runs:\n\n"; bold=true)
    printstyled("  $(rpad("#", 6))$(rpad("Started", 12))$(rpad("Duration", 12))$(rpad("Status", 12))$(rpad("Tests", 10))Path\n"; bold=true)
    printstyled("  $(repeat("─", 76))\n"; color=:light_black)

    for r in history
        started = Dates.format(Dates.unix2datetime(r.start_time), "HH:MM:SS")
        duration = if r.end_time !== nothing
            elapsed = r.end_time - r.start_time
            "$(round(elapsed; digits=1))s"
        elseif r.status == :running
            elapsed = time() - r.start_time
            "$(round(elapsed; digits=1))s…"
        else
            "-"
        end
        status_color = if r.status == :running
            :yellow
        elseif r.status == :completed
            :green
        elseif r.status in (:cancelled, :errored)
            :red
        else
            :default
        end

        # Compute test count summary
        tests_str = "-"
        res = r.result
        if res === nothing && r.status == :running
            res = get_run_result(r.id)
        end
        if res !== nothing
            n = length(res.testitems)
            n_done = sum(length(ti.profiles) for ti in res.testitems; init=0)
            tests_str = "$n_done"
        end

        print("  $(rpad(r.id, 6))$(rpad(started, 12))$(rpad(duration, 12))")
        printstyled("$(rpad(r.status, 12))"; color=status_color)
        print("$(rpad(tests_str, 10))")
        println(r.path)
    end
    println()
    println("$(length(history)) run(s). Use 'results <id>' to inspect a run.")
    nothing
end
# ── Helpers ───────────────────────────────────────────────────────────

function _check_bg_completion()
    bg = _bg_run[]
    if bg !== nothing && istaskdone(bg.task)
        if bg.result !== nothing && bg.error === nothing
            elapsed = round(time() - bg.start_time; digits=1)
            printstyled("Background run completed in $(elapsed)s. Use 'results' to see details.\n"; color=:green)
        elseif bg.error !== nothing
            printstyled("Background run errored: $(bg.error)\n"; color=:red)
        end
    end
end

# ── REPL parser ───────────────────────────────────────────────────────

function repl_parser(input::String)
    input = strip(input)
    isempty(input) && return nothing

    # Handle run& syntax: treat "run&" as background run command
    bg_run = false
    if startswith(input, "run&")
        bg_run = true
        input = "run" * input[5:end]  # remove the &
    end

    parts = split(input)
    cmd = lowercase(parts[1])
    args = parts[2:end]

    if cmd == "help" || cmd == "?"
        return cmd_help()
    elseif cmd == "list" || cmd == "ls"
        return cmd_list(args)
    elseif cmd == "run"
        if bg_run
            return cmd_run_bg(args)
        else
            return cmd_run(args)
        end
    elseif cmd == "status" || cmd == "st"
        return cmd_status()
    elseif cmd == "cancel"
        return cmd_cancel(args)
    elseif cmd == "results" || cmd == "res"
        return cmd_results(args)
    elseif cmd == "details" || cmd == "det"
        return cmd_details(args)
    elseif cmd == "output" || cmd == "out"
        return cmd_output(args)
    elseif cmd == "process-log" || cmd == "plog"
        return cmd_process_log(args)
    elseif cmd == "runs"
        return cmd_runs(args)
    elseif cmd == "processes" || cmd == "procs" || cmd == "ps"
        return cmd_processes()
    elseif cmd == "kill"
        return cmd_kill()
    else
        printstyled("Unknown command: $cmd\n"; color=:red)
        println("Type 'help' for available commands.")
        return nothing
    end
end

# ── REPL mode registration ───────────────────────────────────────────

function _register_repl_mode()
    initrepl(
        repl_parser;
        prompt_text="test> ",
        prompt_color=:yellow,
        start_key=')',
        mode_name="TestItem",
        sticky_mode=true,
        valid_input_checker=s -> true,
    )
end

function __init__()
    global_logger(ModuleFilterLogger(global_logger()))

    if isdefined(Base, :active_repl)
        _register_repl_mode()
    else
        atreplinit() do repl
            @async _register_repl_mode()
        end
    end
end

end # module TestItemREPL
