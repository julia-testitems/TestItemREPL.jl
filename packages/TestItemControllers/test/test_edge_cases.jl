@testitem "Empty test run" setup=[TestHelpers] begin
    using TestItemControllers: TestSetupDetail

    result = TestHelpers.run_testrun([], TestSetupDetail[])

    # Should complete without any events
    @test isempty(result.events)
    @test ismissing(result.coverage)
end

@testitem "Shutdown during active test run" setup=[TestHelpers] begin
    using TestItemControllers: TestItemController, TestItemDetail, execute_testrun, shutdown,
        ControllerCallbacks
    import UUIDs
    @info "[test] Shutdown during active test run: starting"

    pkg_path = joinpath(TestHelpers.TESTDATA_DIR, "BasicPackage")
    discovered = TestHelpers.discover_test_items(pkg_path)

    # Use the slow test item so it stays running long enough for us to shutdown
    slow_items = filter(i -> i.label == "slow test", discovered.items)
    @test length(slow_items) == 1

    events = NamedTuple[]
    events_lock = ReentrantLock()

    callbacks = ControllerCallbacks(
        on_testitem_started = (run_id, item_id) -> lock(events_lock) do
            push!(events, (event=:started, testitem_id=item_id))
        end,
        on_testitem_passed = (run_id, item_id, duration) -> lock(events_lock) do
            push!(events, (event=:passed, testitem_id=item_id))
        end,
        on_testitem_failed = (run_id, item_id, messages, duration) -> lock(events_lock) do
            push!(events, (event=:failed, testitem_id=item_id))
        end,
        on_testitem_errored = (run_id, item_id, messages, duration) -> lock(events_lock) do
            push!(events, (event=:errored, testitem_id=item_id))
        end,
        on_testitem_skipped = (run_id, item_id) -> lock(events_lock) do
            push!(events, (event=:skipped, testitem_id=item_id))
        end,
        on_append_output = (run_id, item_id, output) -> nothing,
        on_attach_debugger = (run_id, pipe_name) -> nothing,
    )

    controller = TestItemController(callbacks; log_level=:Debug)
    profile = TestHelpers.make_test_profile()

    controller_task = @async try
        run(controller)
    catch err
        @error "Controller error" exception=(err, catch_backtrace())
    end

    testrun_task = @async try
        execute_testrun(
            controller,
            string(UUIDs.uuid4()),
            [profile],
            slow_items,
            discovered.setups,
            nothing
        )
    catch err
        @error "Test run error" exception=(err, catch_backtrace())
    end

    # Wait briefly for the test to start, then shutdown
    @info "[test] Shutdown during active test run: waiting 5s for test to start"
    sleep(5)
    @info "[test] Shutdown during active test run: calling shutdown"
    shutdown(controller)

    # Should complete without hanging (the wait itself is the test)
    @info "[test] Shutdown during active test run: waiting for controller_task"
    TestHelpers.timed_wait(controller_task, 120; label="shutdown-controller")

    # The test run task should also finish
    @info "[test] Shutdown during active test run: waiting for testrun_task"
    TestHelpers.timed_wait(testrun_task, 120; label="shutdown-testrun")

    # The slow test should have been started but then skipped/errored due to shutdown
    terminal_events = lock(events_lock) do
        filter(e -> e.event in (:passed, :failed, :errored, :skipped), events)
    end
    @test length(terminal_events) >= 1
end

@testitem "Sequential runs with different items" setup=[TestHelpers] begin
    using TestItemControllers: TestItemController, execute_testrun, shutdown, ControllerCallbacks
    import UUIDs
    @info "[test] Sequential runs with different items: starting"

    pkg_path = joinpath(TestHelpers.TESTDATA_DIR, "BasicPackage")
    discovered = TestHelpers.discover_test_items(pkg_path)

    add_items = filter(i -> i.label == "add works", discovered.items)
    greet_items = filter(i -> i.label == "greet works", discovered.items)
    @test length(add_items) == 1
    @test length(greet_items) == 1

    events_run1 = NamedTuple[]
    events_run2 = NamedTuple[]
    events_lock = ReentrantLock()

    run1_id = string(UUIDs.uuid4())
    run2_id = string(UUIDs.uuid4())

    callbacks = ControllerCallbacks(
        on_testitem_started = (run_id, item_id) -> nothing,
        on_testitem_passed = (run_id, item_id, duration) -> lock(events_lock) do
            if run_id == run1_id
                push!(events_run1, (event=:passed, testitem_id=item_id))
            elseif run_id == run2_id
                push!(events_run2, (event=:passed, testitem_id=item_id))
            end
        end,
        on_testitem_failed = (run_id, item_id, msgs, dur) -> nothing,
        on_testitem_errored = (run_id, item_id, msgs, dur) -> nothing,
        on_testitem_skipped = (run_id, item_id) -> nothing,
        on_append_output = (run_id, item_id, output) -> nothing,
        on_attach_debugger = (run_id, pipe_name) -> nothing,
    )

    controller = TestItemController(callbacks; log_level=:Debug)
    profile = TestHelpers.make_test_profile()

    controller_task = @async try
        run(controller)
    catch err
        @error "Controller error" exception=(err, catch_backtrace())
    end

    # First run: only "add works"
    @info "[test] Sequential runs: executing first run"
    execute_testrun(controller, run1_id, [profile], add_items, discovered.setups, nothing)

    # Second run: only "greet works"
    @info "[test] Sequential runs: executing second run"
    execute_testrun(controller, run2_id, [profile], greet_items, discovered.setups, nothing)

    @info "[test] Sequential runs: shutting down"
    shutdown(controller)
    TestHelpers.timed_wait(controller_task, 120; label="sequential-runs-controller")

    # Each run should have exactly one passed event
    @test length(events_run1) == 1
    @test events_run1[1].testitem_id == add_items[1].id

    @test length(events_run2) == 1
    @test events_run2[1].testitem_id == greet_items[1].id
end

@testitem "Test items from multiple packages" setup=[TestHelpers] begin
    pkg_path_basic = joinpath(TestHelpers.TESTDATA_DIR, "BasicPackage")
    pkg_path_setup = joinpath(TestHelpers.TESTDATA_DIR, "SetupPackage")

    basic_discovered = TestHelpers.discover_test_items(pkg_path_basic)
    setup_discovered = TestHelpers.discover_test_items(pkg_path_setup)

    # Pick one passing item from each package
    basic_items = filter(i -> i.label == "add works", basic_discovered.items)
    setup_items = filter(i -> i.label == "transform with module setup", setup_discovered.items)
    @test length(basic_items) == 1
    @test length(setup_items) == 1

    all_items = vcat(basic_items, setup_items)
    all_setups = vcat(basic_discovered.setups, setup_discovered.setups)

    result = TestHelpers.run_testrun(all_items, all_setups)

    started = filter(e -> e.event == :started, result.events)
    passed = filter(e -> e.event == :passed, result.events)

    @test length(started) == 2
    @test length(passed) == 2
end
