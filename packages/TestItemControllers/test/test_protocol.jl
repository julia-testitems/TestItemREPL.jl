@testitem "TestMessage round-trip" begin
    using TestItemControllers: TestItemControllerProtocol, JSON

    msg = TestItemControllerProtocol.TestMessage(
        message = "Test failed",
        expectedOutput = "1",
        actualOutput = "2",
        uri = "file:///test.jl",
        line = 10,
        column = 5
    )

    json_str = JSON.json(msg)
    parsed = JSON.parse(json_str)
    msg2 = TestItemControllerProtocol.TestMessage(parsed)

    @test msg2.message == "Test failed"
    @test msg2.expectedOutput == "1"
    @test msg2.actualOutput == "2"
    @test msg2.uri == "file:///test.jl"
    @test msg2.line == 10
    @test msg2.column == 5
end

@testitem "TestMessage with missing fields" begin
    using TestItemControllers: TestItemControllerProtocol, JSON

    msg = TestItemControllerProtocol.TestMessage(
        message = "Error occurred",
        expectedOutput = missing,
        actualOutput = missing,
        uri = missing,
        line = missing,
        column = missing
    )

    json_str = JSON.json(msg)
    parsed = JSON.parse(json_str)
    msg2 = TestItemControllerProtocol.TestMessage(parsed)

    @test msg2.message == "Error occurred"
    @test ismissing(msg2.expectedOutput)
    @test ismissing(msg2.actualOutput)
end

@testitem "TestItemDetail round-trip" begin
    using TestItemControllers: TestItemControllerProtocol, JSON

    item = TestItemControllerProtocol.TestItemDetail(
        id = "item-1",
        uri = "file:///test.jl",
        label = "my test",
        packageName = "MyPkg",
        packageUri = "file:///mypkg",
        projectUri = missing,
        envContentHash = "abc123",
        useDefaultUsings = true,
        testSetups = ["Setup1"],
        line = 1,
        column = 1,
        code = "@test true",
        codeLine = 2,
        codeColumn = 5
    )

    json_str = JSON.json(item)
    parsed = JSON.parse(json_str)
    item2 = TestItemControllerProtocol.TestItemDetail(parsed)

    @test item2.id == "item-1"
    @test item2.label == "my test"
    @test item2.packageName == "MyPkg"
    @test ismissing(item2.projectUri)
    @test item2.useDefaultUsings == true
    @test item2.testSetups == ["Setup1"]
    @test item2.code == "@test true"
end

@testitem "FileCoverage round-trip" begin
    using TestItemControllers: TestItemControllerProtocol, JSON

    fc = TestItemControllerProtocol.FileCoverage(
        uri = "file:///src/myfile.jl",
        coverage = [1, 0, nothing, 3, nothing]
    )

    json_str = JSON.json(fc)
    parsed = JSON.parse(json_str)
    fc2 = TestItemControllerProtocol.FileCoverage(parsed)

    @test fc2.uri == "file:///src/myfile.jl"
    @test fc2.coverage == [1, 0, nothing, 3, nothing]
end

@testitem "CreateTestRunParams round-trip" begin
    using TestItemControllers: TestItemControllerProtocol, JSON

    params = TestItemControllerProtocol.CreateTestRunParams(
        testRunId = "run-1",
        testProfiles = [
            TestItemControllerProtocol.TestProfile(
                id = "prof-1",
                label = "Default",
                juliaCmd = "julia",
                juliaArgs = String[],
                juliaNumThreads = missing,
                juliaEnv = Dict{String,Union{String,Nothing}}(),
                maxProcessCount = 1,
                mode = "Run",
                coverageRootUris = missing
            )
        ],
        testItems = TestItemControllerProtocol.TestItemDetail[],
        testSetups = TestItemControllerProtocol.TestSetupDetail[]
    )

    json_str = JSON.json(params)
    parsed = JSON.parse(json_str)
    params2 = TestItemControllerProtocol.CreateTestRunParams(parsed)

    @test params2.testRunId == "run-1"
    @test length(params2.testProfiles) == 1
    @test params2.testProfiles[1].mode == "Run"
end

@testitem "TestProfile round-trip with all fields" begin
    using TestItemControllers: TestItemControllerProtocol, JSON

    # With juliaNumThreads and coverageRootUris present
    prof = TestItemControllerProtocol.TestProfile(
        id = "prof-full",
        label = "Full Profile",
        juliaCmd = "/usr/bin/julia",
        juliaArgs = ["--optimize=2", "--check-bounds=yes"],
        juliaNumThreads = "4",
        juliaEnv = Dict{String,Union{String,Nothing}}("MY_VAR" => "value", "EMPTY" => nothing),
        maxProcessCount = 3,
        mode = "Coverage",
        coverageRootUris = ["file:///src", "file:///lib"]
    )

    json_str = JSON.json(prof)
    parsed = JSON.parse(json_str)
    prof2 = TestItemControllerProtocol.TestProfile(parsed)

    @test prof2.id == "prof-full"
    @test prof2.label == "Full Profile"
    @test prof2.juliaCmd == "/usr/bin/julia"
    @test prof2.juliaArgs == ["--optimize=2", "--check-bounds=yes"]
    @test prof2.juliaNumThreads == "4"
    @test prof2.juliaEnv["MY_VAR"] == "value"
    @test prof2.juliaEnv["EMPTY"] === nothing
    @test prof2.maxProcessCount == 3
    @test prof2.mode == "Coverage"
    @test prof2.coverageRootUris == ["file:///src", "file:///lib"]
end

@testitem "TestProfile round-trip with missing optional fields" begin
    using TestItemControllers: TestItemControllerProtocol, JSON

    prof = TestItemControllerProtocol.TestProfile(
        id = "prof-minimal",
        label = "Minimal",
        juliaCmd = "julia",
        juliaArgs = String[],
        juliaNumThreads = missing,
        juliaEnv = Dict{String,Union{String,Nothing}}(),
        maxProcessCount = 1,
        mode = "Run",
        coverageRootUris = missing
    )

    json_str = JSON.json(prof)
    parsed = JSON.parse(json_str)
    prof2 = TestItemControllerProtocol.TestProfile(parsed)

    @test prof2.id == "prof-minimal"
    @test ismissing(prof2.juliaNumThreads)
    @test ismissing(prof2.coverageRootUris)
    @test prof2.juliaArgs == String[]
    @test isempty(prof2.juliaEnv)
end

@testitem "TestMessage with all optional fields populated" begin
    using TestItemControllers: TestItemControllerProtocol, JSON

    msg = TestItemControllerProtocol.TestMessage(
        message = "Expected 42, got 43",
        expectedOutput = "42",
        actualOutput = "43",
        uri = "file:///test/mytest.jl",
        line = 25,
        column = 10
    )

    json_str = JSON.json(msg)
    parsed = JSON.parse(json_str)
    msg2 = TestItemControllerProtocol.TestMessage(parsed)

    @test msg2.message == "Expected 42, got 43"
    @test msg2.expectedOutput == "42"
    @test msg2.actualOutput == "43"
    @test msg2.uri == "file:///test/mytest.jl"
    @test msg2.line == 25
    @test msg2.column == 10
end

@testitem "CreateTestRunParams with multiple profiles" begin
    using TestItemControllers: TestItemControllerProtocol, JSON

    params = TestItemControllerProtocol.CreateTestRunParams(
        testRunId = "run-multi",
        testProfiles = [
            TestItemControllerProtocol.TestProfile(
                id = "prof-1", label = "Default",
                juliaCmd = "julia", juliaArgs = String[],
                juliaNumThreads = missing,
                juliaEnv = Dict{String,Union{String,Nothing}}(),
                maxProcessCount = 1, mode = "Run",
                coverageRootUris = missing
            ),
            TestItemControllerProtocol.TestProfile(
                id = "prof-2", label = "Coverage",
                juliaCmd = "julia", juliaArgs = ["--code-coverage=user"],
                juliaNumThreads = "auto",
                juliaEnv = Dict{String,Union{String,Nothing}}("COV" => "1"),
                maxProcessCount = 2, mode = "Coverage",
                coverageRootUris = ["file:///src"]
            ),
        ],
        testItems = TestItemControllerProtocol.TestItemDetail[],
        testSetups = TestItemControllerProtocol.TestSetupDetail[]
    )

    json_str = JSON.json(params)
    parsed = JSON.parse(json_str)
    params2 = TestItemControllerProtocol.CreateTestRunParams(parsed)

    @test params2.testRunId == "run-multi"
    @test length(params2.testProfiles) == 2
    @test params2.testProfiles[1].id == "prof-1"
    @test params2.testProfiles[1].mode == "Run"
    @test params2.testProfiles[2].id == "prof-2"
    @test params2.testProfiles[2].mode == "Coverage"
    @test params2.testProfiles[2].juliaNumThreads == "auto"
    @test params2.testProfiles[2].juliaArgs == ["--code-coverage=user"]
    @test params2.testProfiles[2].coverageRootUris == ["file:///src"]
end

@testitem "TestItemDetail round-trip with timeout" begin
    using TestItemControllers: TestItemControllerProtocol, JSON

    item = TestItemControllerProtocol.TestItemDetail(
        id = "item-timeout",
        uri = "file:///test.jl",
        label = "slow test",
        packageName = "MyPkg",
        packageUri = "file:///mypkg",
        projectUri = "file:///proj",
        envContentHash = "hash123",
        useDefaultUsings = true,
        testSetups = String[],
        line = 10,
        column = 1,
        code = "sleep(100)",
        codeLine = 11,
        codeColumn = 5,
        timeout = 30.0
    )

    json_str = JSON.json(item)
    parsed = JSON.parse(json_str)
    item2 = TestItemControllerProtocol.TestItemDetail(parsed)

    @test item2.id == "item-timeout"
    @test item2.timeout == 30.0
    @test item2.label == "slow test"
end

@testitem "TestItemDetail round-trip with missing timeout" begin
    using TestItemControllers: TestItemControllerProtocol, JSON

    item = TestItemControllerProtocol.TestItemDetail(
        id = "item-no-timeout",
        uri = "file:///test.jl",
        label = "fast test",
        packageName = "MyPkg",
        packageUri = "file:///mypkg",
        projectUri = missing,
        envContentHash = missing,
        useDefaultUsings = false,
        testSetups = ["Setup1", "Setup2"],
        line = 1,
        column = 1,
        code = "@test true",
        codeLine = 2,
        codeColumn = 5,
        timeout = missing
    )

    json_str = JSON.json(item)
    parsed = JSON.parse(json_str)
    item2 = TestItemControllerProtocol.TestItemDetail(parsed)

    @test item2.id == "item-no-timeout"
    @test ismissing(item2.timeout)
    @test ismissing(item2.projectUri)
    @test ismissing(item2.envContentHash)
    @test item2.useDefaultUsings == false
    @test item2.testSetups == ["Setup1", "Setup2"]
end
