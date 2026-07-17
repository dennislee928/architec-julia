# Counts method invalidations triggered by loading one package.
# Invalidations force recompilation of already-compiled code — Julia's
# equivalent of rework caused by a late design change (start-up loss).
#
# Usage: julia --startup-file=no --project=bench bench/invalidations.jl <Package>
# Output (stdout, last line): INVALIDATIONS_RESULT,<pkg>,<n_unique_invalidated>,<n_trees>

const pkg = ARGS[1]

using SnoopCompileCore
const invs = @snoop_invalidations @eval using $(Symbol(pkg))

# SnoopCompile (the analysis half) is loaded only AFTER measurement so its own
# loading cannot pollute the invalidation log.
using SnoopCompile

const trees = invalidation_trees(invs)
const n_unique = length(uinvalidated(invs))
println("INVALIDATIONS_RESULT,$pkg,$n_unique,$(length(trees))")
