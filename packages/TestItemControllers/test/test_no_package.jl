@testitem "Test item without package fails" setup=[TestHelpers] begin
    using TestItemControllers: TestItemDetail, TestSetupDetail

    # Create a test item with package_name=nothing to simulate "not inside a package"
    item = TestItemDetail(
        "orphan-item-1",
        "file:///some/test.jl",
        "orphan test",
        nothing,    # package_name
        nothing,    # package_uri
        nothing,    # project_uri
        nothing,    # env_content_hash
        true,       # option_default_imports
        String[],   # test_setups
        1, 1,       # line, column
        "@test true",
        2, 5,       # code_line, code_column
        nothing     # timeout
    )

    result = TestHelpers.run_testrun([item], TestSetupDetail[])

    failed_events = filter(e -> e.event == :failed, result.events)
    @test length(failed_events) == 1

    msg = failed_events[1].messages[1].message
    @test occursin("not inside a Julia package", msg)
end
