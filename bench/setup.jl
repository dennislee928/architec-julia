# One-time environment setup for the TTFX benchmark harness.
# Usage: julia --startup-file=no bench/setup.jl
using Pkg
Pkg.activate(@__DIR__)
Pkg.add(["CSV", "DataFrames", "Plots", "SnoopCompileCore", "SnoopCompile"])
Pkg.precompile()
println("bench environment ready")
