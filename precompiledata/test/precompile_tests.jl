@testitem "precompile pass" begin
    @test true
end

@testitem "precompile fail" begin
    @test false
end

@testitem "precompile error" begin
    error("intentional error for precompilation")
end
