# CI Stage 1 — 品質左移閘門 (Poka-Yoke gate)
# 三道檢查，任何一道失敗即整體失敗（fail-fast）：
#   G1  JET 靜態分析 LeanDemo 本體 → 必須 0 個問題
#   G2  閘門自我測試：JET 分析反面教材 unstable_demo.jl → 必須抓到問題
#       （抓不到 = 檢測器失效，同樣視為 CI 失敗）
#   G3  Aqua 套件健康檢查（相依、compat、方法歧義）
#
# Usage: julia --startup-file=no --project=lab/quality-gate lab/quality-gate/gate.jl

using JET, Aqua, LeanDemo, Test

failures = String[]

# --- G1: the package itself must be statically clean -------------------------
let result = JET.report_package(LeanDemo; toplevel_logger = nothing)
    reports = JET.get_reports(result)
    if isempty(reports)
        println("G1 PASS — JET: LeanDemo has 0 issues")
    else
        show(stdout, result)
        push!(failures, "G1: JET found $(length(reports)) issue(s) in LeanDemo")
    end
end

# --- G2: the detector must catch the known-bad demo (gate self-test) ---------
include(joinpath(@__DIR__, "unstable_demo.jl"))
let caught = 0
    r1 = JET.report_call(UnstableDemo.demo, Tuple{})
    caught += length(JET.get_reports(r1))
    r2 = JET.report_opt(UnstableDemo.bump!, Tuple{})
    caught += length(JET.get_reports(r2))
    if caught > 0
        println("G2 PASS — JET caught $caught issue(s) in the known-bad demo")
    else
        push!(failures, "G2: detector failed to flag unstable_demo.jl — gate is blind")
    end
end

# --- G3: Aqua package hygiene ------------------------------------------------
let ts = @testset "Aqua" begin
        Aqua.test_all(LeanDemo)
    end
    if any(x -> x isa Test.Fail || x isa Test.Error, ts.results)
        push!(failures, "G3: Aqua checks failed")
    else
        println("G3 PASS — Aqua package hygiene clean")
    end
end

if isempty(failures)
    println("QUALITY_GATE_PASS")
else
    foreach(f -> println("FAIL: ", f), failures)
    println("QUALITY_GATE_FAIL")
    exit(1)
end
