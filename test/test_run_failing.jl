@testitem "Run failing test item" setup=[TestHelpers] begin
    pkg_path = joinpath(TestHelpers.TESTDATA_DIR, "BasicPackage")
    discovered = TestHelpers.discover_test_items(pkg_path)

    failing_items = filter(i -> i.label == "failing test", discovered.items)
    @test length(failing_items) == 1

    result = TestHelpers.run_testrun(failing_items, discovered.setups)

    failed_events = filter(e -> e.event == :failed, result.events)
    @test length(failed_events) == 1
    @test length(failed_events[1].messages) >= 1
end

@testitem "Run erroring test item" setup=[TestHelpers] begin
    pkg_path = joinpath(TestHelpers.TESTDATA_DIR, "BasicPackage")
    discovered = TestHelpers.discover_test_items(pkg_path)

    erroring_items = filter(i -> i.label == "erroring test", discovered.items)
    @test length(erroring_items) == 1

    result = TestHelpers.run_testrun(erroring_items, discovered.setups)

    errored_events = filter(e -> e.event == :errored, result.events)
    @test length(errored_events) == 1
    @test length(errored_events[1].messages) >= 1

    # The error message should mention "intentional error"
    msg_text = errored_events[1].messages[1].message
    @test occursin("intentional error", msg_text)
end
