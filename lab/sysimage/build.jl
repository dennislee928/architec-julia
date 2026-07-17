# Builds a custom sysimage with Plots baked in (Front-End Planning:
# move the entire mobilization cost to build time, once).
# Usage: julia --startup-file=no --project=bench lab/sysimage/build.jl
using PackageCompiler
create_sysimage(
    ["Plots"];
    sysimage_path = joinpath(@__DIR__, "plots_sys.dylib"),
    precompile_execution_file = joinpath(@__DIR__, "workload.jl"),
)
println("SYSIMAGE_READY")
