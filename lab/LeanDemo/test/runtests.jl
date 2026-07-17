using Test
using LeanDemo

@testset "summarize" begin
    r = summarize([1.0, 2.0, 3.0])
    @test r.n == 3
    @test r.mean ≈ 2.0
    @test r.var ≈ 1.0
    @test summarize(Int[]) == (n = 0, mean = 0.0, var = 0.0)
    @test summarize([5]).var == 0.0
    @test summarize(1:10).mean ≈ 5.5
end

@testset "rolling_mean" begin
    @test rolling_mean([1.0, 2.0, 3.0, 4.0], 2) ≈ [1.5, 2.5, 3.5]
    @test rolling_mean(1:5, 5) ≈ [3.0]
    @test_throws ArgumentError rolling_mean([1.0], 2)
    @test_throws ArgumentError rolling_mean([1.0, 2.0], 0)
end

@testset "type stability (Poka-Yoke in tests too)" begin
    @inferred summarize([1.0, 2.0])
    @inferred rolling_mean([1.0, 2.0, 3.0], 2)
end
