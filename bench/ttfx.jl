# Measures load time and time-to-first-execute (TTFX) for one package,
# in a fresh process. JIT state is per-process, so this script must be run
# via a new `julia` invocation for every measurement (see run.sh).
#
# Usage: julia --startup-file=no --project=bench bench/ttfx.jl <Package>
# Output (stdout, last line): TTFX_RESULT,<pkg>,<load_seconds>,<ttfx_seconds>

const pkg = ARGS[1]

const t_load = @elapsed @eval using $(Symbol(pkg))

# Representative "first useful unit of work" per package — the lean
# First-Run Study workload. Kept tiny so we time compilation, not computation.
function first_workload(::Val{:CSV})
    @eval CSV.File(IOBuffer("a,b\n1,2\n3,4"))
end
function first_workload(::Val{:DataFrames})
    @eval begin
        df = DataFrame(a = 1:3, b = ["x", "y", "z"])
        describe(df)
    end
end
function first_workload(::Val{:Plots})
    @eval begin
        p = plot(1:3, (1:3) .^ 2)
        savefig(p, joinpath(mktempdir(), "first.png"))
    end
end

const t_ttfx = @elapsed first_workload(Val(Symbol(pkg)))

println("TTFX_RESULT,$pkg,$t_load,$t_ttfx")
