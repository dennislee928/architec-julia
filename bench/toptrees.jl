# Prints the largest invalidation trees caused by loading one package —
# each root is a concrete upstream PR candidate (Phase 2 target selection).
#
# Usage: julia --startup-file=no --project=bench bench/toptrees.jl <Package> [N]
# Output: human-readable summary of the top-N trees, largest last.

const pkg = ARGS[1]
const topn = length(ARGS) >= 2 ? parse(Int, ARGS[2]) : 5

using SnoopCompileCore
const invs = @snoop_invalidations @eval using $(Symbol(pkg))
using SnoopCompile

const trees = invalidation_trees(invs)  # sorted ascending by #children
println("package: $pkg — $(length(trees)) invalidation trees\n")
for tree in trees[max(1, end - topn + 1):end]
    show(stdout, tree)
    println("\n", "-"^70)
end
