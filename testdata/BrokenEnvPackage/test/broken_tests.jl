@testitem "this should never run" begin
    using BrokenEnvPackage
    @test greet() == "Hello from BrokenEnvPackage!"
end

@testitem "this also should never run" begin
    @test true
end
