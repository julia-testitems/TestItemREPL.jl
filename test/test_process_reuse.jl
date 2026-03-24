@testitem "Test process reused across runs" setup=[TestHelpers] begin
    using TestItemControllers: TestItemController, execute_testrun, shutdown, ControllerCallbacks
    import UUIDs

    pkg_path = joinpath(TestHelpers.TESTDATA_DIR, "BasicPackage")
    discovered = TestHelpers.discover_test_items(pkg_path)

    passing_items = filter(i -> i.label == "add works", discovered.items)
    @test length(passing_items) == 1

    process_created_ids = String[]
    process_created_lock = ReentrantLock()

    events1 = NamedTuple[]
    events1_lock = ReentrantLock()
    events2 = NamedTuple[]
    events2_lock = ReentrantLock()

    callbacks = ControllerCallbacks(
        on_testitem_started = (run_id, item_id) -> nothing,
        on_testitem_passed = (run_id, item_id, duration) -> begin
            lock(events1_lock) do; push!(events1, (event=:passed,)); end
            lock(events2_lock) do; push!(events2, (event=:passed,)); end
        end,
        on_testitem_failed = (run_id, item_id, messages, duration) -> nothing,
        on_testitem_errored = (run_id, item_id, messages, duration) -> nothing,
        on_testitem_skipped = (run_id, item_id) -> nothing,
        on_append_output = (run_id, item_id, output) -> nothing,
        on_attach_debugger = (run_id, pipe_name) -> nothing,
        on_process_created = (id, pkg_name, pkg_uri, proj_uri, coverage, env) -> lock(process_created_lock) do
            push!(process_created_ids, id)
        end,
    )

    controller = TestItemController(callbacks; log_level=:Debug)
    profile = TestHelpers.make_test_profile()

    controller_task = @async try
        run(controller)
    catch err
        @error "Controller error" exception=(err, catch_backtrace())
    end

    # First test run
    execute_testrun(
        controller,
        string(UUIDs.uuid4()),
        [profile],
        passing_items,
        discovered.setups,
        nothing
    )

    @test length(filter(e -> e.event == :passed, events1)) >= 1
    first_run_process_count = lock(process_created_lock) do
        length(process_created_ids)
    end
    @test first_run_process_count == 1

    # Clear events for second run
    lock(events2_lock) do; empty!(events2); end

    # Second test run — should reuse the existing process
    execute_testrun(
        controller,
        string(UUIDs.uuid4()),
        [profile],
        passing_items,
        discovered.setups,
        nothing
    )

    @test length(filter(e -> e.event == :passed, events2)) >= 1

    second_run_process_count = lock(process_created_lock) do
        length(process_created_ids)
    end
    # Process count should still be 1 — the process was reused
    @test second_run_process_count == 1

    @info "[test] Process reuse: shutting down"
    shutdown(controller)
    TestHelpers.timed_wait(controller_task, 120; label="process-reuse-controller")
end
