#!/usr/bin/env bash
# TTFX baseline harness — the lean "First-Run Study" for Julia cold-start cost.
#
# For each target package, measured in SEPARATE processes (JIT state is
# per-process; a warm rerun inside one process would measure nothing):
#   1. precompile  — wall time of Pkg.precompile after purging the package's
#                    compiled cache (true cold mobilization)
#   2. load        — `using Pkg` time in a fresh process, pkgimage already cached
#   3. ttfx        — first representative call in that same fresh process
#   4. invalidations — unique methods invalidated by loading the package
#
# Usage: bash bench/run.sh
set -euo pipefail

cd "$(dirname "$0")/.."
PACKAGES=(CSV DataFrames Plots)
STAMP=$(date +%F)
OUT="bench/results/baseline-$STAMP.csv"
mkdir -p bench/results
: > "$OUT"

echo "julia_version,$(julia --startup-file=no -e 'print(VERSION)')" >> "$OUT"

for pkg in "${PACKAGES[@]}"; do
  echo "=== $pkg ==="

  # 1. cold precompile: purge this package's compiled cache, then re-precompile
  julia --startup-file=no --project=bench -e "
    using Pkg
    for dir in Base.DEPOT_PATH
        cache = joinpath(dir, \"compiled\", \"v$(VERSION.major).$(VERSION.minor)\", \"$pkg\")
        isdir(cache) && rm(cache; recursive=true)
    end
    t = @elapsed Pkg.precompile(\"$pkg\")
    println(\"PRECOMPILE_RESULT,$pkg,\", t)
  " | tee -a /dev/stderr | grep '^PRECOMPILE_RESULT' >> "$OUT"

  # 2+3. load + TTFX in one fresh process
  julia --startup-file=no --project=bench bench/ttfx.jl "$pkg" \
    | tee -a /dev/stderr | grep '^TTFX_RESULT' >> "$OUT"

  # 4. invalidation count in another fresh process
  julia --startup-file=no --project=bench bench/invalidations.jl "$pkg" \
    | tee -a /dev/stderr | grep '^INVALIDATIONS_RESULT' >> "$OUT"
done

echo "Results written to $OUT"
