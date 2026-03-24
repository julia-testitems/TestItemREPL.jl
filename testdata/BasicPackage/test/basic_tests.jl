@testitem "add works" begin
    using BasicPackage
    @test add(1, 2) == 3
    @test add(0, 0) == 0
    @test add(-1, 1) == 0
end

@testitem "greet works" begin
    using BasicPackage
    @test greet() == "Hello from BasicPackage!"
end

@testitem "failing test" begin
    @test 1 == 2
end

@testitem "erroring test" begin
    error("intentional error")
end

@testitem "output test" begin
    println("hello from output test")
    println("second line of output")
    @test true
end

@testitem "slow test" begin
    sleep(60)
    @test true
end

@testitem "exit crash" begin
    exit()
end

@testitem "abort crash" begin
    ccall(:abort, Cvoid, ())
end
