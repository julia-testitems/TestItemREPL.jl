@testitem "Cancel running test run" setup=[TestHelpers] begin
    using TestItemControllers: TestItemController, TestProfile, TestItemDetail, TestSetupDetail,
        execute_testrun, shutdown, CancellationTokens, ControllerCallbacks
    import UUIDs

    pkg_path = joinpath(TestHelpers.TESTDATA_DIR, "BasicPackage")
    discovered = TestHelpers.discover_test_items(pkg_path)

    events = NamedTuple[]
    events_lock = ReentrantLock()

    callbacks = ControllerCallbacks(
        on_testitem_started = (run_id, item_id) -> lock(events_lock) do; push!(events, (event=:started, testitem_id=item_id)); end,
        on_testitem_passed = (run_id, item_id, duration) -> lock(events_lock) do; push!(events, (event=:passed, testitem_id=item_id)); end,
        on_testitem_failed = (run_id, item_id, messages, duration) -> lock(events_lock) do; push!(events, (event=:failed, testitem_id=item_id)); end,
        on_testitem_errored = (run_id, item_id, messages, duration) -> lock(events_lock) do; push!(events, (event=:errored, testitem_id=item_id)); end,
        on_testitem_skipped = (run_id, item_id) -> lock(events_lock) do; push!(events, (event=:skipped, testitem_id=item_id)); end,
        on_append_output = (run_id, item_id, output) -> nothing,
        on_attach_debugger = (run_id, pipe_name) -> nothing,
    )

    controller = TestItemController(callbacks; log_level=:Debug)
    profile = TestHelpers.make_test_profile()
    testrun_id = string(UUIDs.uuid4())

    cs = CancellationTokens.CancellationTokenSource()
    token = CancellationTokens.get_token(cs)

    controller_task = @async try
        run(controller)
    catch err
        @error "Controller error" exception=(err, catch_backtrace())
    end

    testrun_task = @async try
        execute_testrun(
            controller,
            testrun_id,
            [profile],
            discovered.items,
            discovered.setups,
            token
        )
    catch err
        @error "Test run error" exception=(err, catch_backtrace())
    end

    # Cancel immediately
    CancellationTokens.cancel(cs)

    # Wait for testrun to complete
    @info "[test] Cancel running test run: waiting for testrun"
    TestHelpers.timed_wait(testrun_task, 120; label="cancel-testrun")

    @info "[test] Cancel running test run: shutting down"
    shutdown(controller)
    TestHelpers.timed_wait(controller_task, 120; label="cancel-controller")

    # After cancellation, items should be skipped or already completed
    completed = filter(e -> e.event in (:passed, :failed, :errored, :skipped), events)
    @test length(completed) == length(discovered.items)
end
