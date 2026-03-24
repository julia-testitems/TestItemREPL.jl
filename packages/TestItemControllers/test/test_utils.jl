@testitem "makechunks basic" begin
    using TestItemControllers: makechunks

    chunks = makechunks([1, 2, 3, 4, 5, 6], 3)
    @test length(chunks) == 3
    @test vcat(chunks...) == [1, 2, 3, 4, 5, 6]
end

@testitem "makechunks single chunk" begin
    using TestItemControllers: makechunks

    chunks = makechunks([1, 2, 3], 1)
    @test length(chunks) == 1
    @test chunks[1] == [1, 2, 3]
end

@testitem "makechunks more chunks than elements" begin
    using TestItemControllers: makechunks

    chunks = makechunks([1, 2], 3)
    @test length(chunks) == 3
    # All elements should still be present
    @test sort(vcat(chunks...)) == [1, 2]
end

@testitem "makechunks uneven split" begin
    using TestItemControllers: makechunks

    chunks = makechunks([1, 2, 3, 4, 5], 2)
    @test length(chunks) == 2
    @test vcat(chunks...) == [1, 2, 3, 4, 5]
end

@testitem "makechunks error on n < 1" begin
    using TestItemControllers: makechunks

    @test_throws ErrorException makechunks([1, 2, 3], 0)
    @test_throws ErrorException makechunks([1, 2, 3], -1)
end
