#!/usr/bin/env bash
# 漸進驗證管線 (Progressive Commissioning) — 三個階段依序放行，fail-fast。
# 沒有 Big-Bang Closeout：每一階段是獨立的品質閘門（Quality Gate），
# 前一道不過，後面不跑。
#
#   Stage 1  品質左移   — JET 靜態分析 + Aqua 健康檢查 (gate.jl)
#   Stage 2  功能驗證   — LeanDemo 單元測試（含 @inferred 型別穩定測試）
#   Stage 3  效能驗收   — TTFX 回歸檢查（預算制：load ≤ 1.5s, first call ≤ 5ms）
#
# Usage: bash lab/ci.sh
set -euo pipefail
cd "$(dirname "$0")/.."

echo "══ Stage 1/3: shift-left quality gate (JET + Aqua) ══"
julia --startup-file=no --project=lab/quality-gate lab/quality-gate/gate.jl \
  | grep -E "^G[123]|QUALITY_GATE" || { echo "CI FAIL @ stage 1"; exit 1; }

echo "══ Stage 2/3: unit tests ══"
julia --startup-file=no --project=lab/LeanDemo -e 'using Pkg; Pkg.test()' 2>&1 \
  | tail -2 | grep -q "tests passed" \
  && echo "TESTS PASS" || { echo "CI FAIL @ stage 2"; exit 1; }

echo "══ Stage 3/3: TTFX regression budget ══"
julia --startup-file=no --project=lab/LeanDemo -e '
t_load = @elapsed using LeanDemo
t1 = @elapsed summarize([1.0, 2.0, 3.0])
t2 = @elapsed rolling_mean([1.0, 2.0, 3.0, 4.0], 2)
println("load=$(round(t_load, digits=3))s ttfx=$(round((t1 + t2) * 1000, digits=2))ms")
budget_ok = t_load <= 1.5 && (t1 + t2) <= 0.005
println(budget_ok ? "PERF PASS" : "PERF FAIL: budget exceeded")
exit(budget_ok ? 0 : 1)' || { echo "CI FAIL @ stage 3"; exit 1; }

echo "══ CI PIPELINE PASS — all three gates green ══"
