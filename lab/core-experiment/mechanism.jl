# 受控實驗：重現並驗證「AbstractInterpreter 介面擴充引發編譯器自我無效化」的
# 機制與修復模式（function barrier / 具體型別特化），在未修改的 stock Julia 上執行。
#
# 對應真實案例（bench/results/toptrees-*.txt）：
#   REPL.REPLCompletions 定義 Compiler.InferenceParams(::REPLInterpreter)
#   → 無效化以抽象簽名編譯的 Compiler.get_max_methods 等 ~500 個方法。
#
# 實驗設計：
#   Framework 模組扮演 Compiler：抽象型別 AbstractInterp + 介面函數 params。
#   - vulnerable_entry(::AbstractInterp)：以「抽象呼叫 params(interp)」的方式編譯
#     （= 今日 Compiler 內部的寫法 → 會註冊抽象簽名 backedge）
#   - barriered_entry(interp::T) where T：以「每個具體型別各自特化」的方式編譯
#     （= 修復模式 → backedge 掛在具體簽名上）
#   之後載入 Extension（扮演 REPL）插入 params(::ReplLikeInterp)，
#   用 @snoop_invalidations 觀察兩種寫法各自被無效化的數量。
#
# Usage: julia --startup-file=no --project=bench lab/core-experiment/mechanism.jl

module Framework
    abstract type AbstractInterp end
    struct NativeInterp <: AbstractInterp
        max_methods::Int
    end
    params(interp::NativeInterp) = interp.max_methods

    # 今日 Compiler 的形狀：介面呼叫發生在以抽象型別編譯的函數體內
    @noinline vulnerable_inner(interp::AbstractInterp) = params(interp) + 1
    vulnerable_entry(interp::AbstractInterp) = vulnerable_inner(interp)

    # 修復模式：入口即函數屏障，內部程式碼對每個具體 interp 型別各自特化
    @noinline barriered_inner(interp::T) where {T<:AbstractInterp} = params(interp)::Int + 1
    barriered_entry(interp::AbstractInterp) = barriered_inner(interp)
end

using .Framework

# 先把兩條路徑都編譯出來（模擬 sysimage 中已存在的編譯結果）。
# 關鍵：用 precompile 強制產生「以抽象型別特化」的 MethodInstance ——
# 一般呼叫永遠以執行期具體型別特化，只有 precompile/sysimage 建置會留下抽象實例。
const ni = Framework.NativeInterp(3)
Framework.vulnerable_entry(ni)
Framework.barriered_entry(ni)
# invoke 以宣告簽名（抽象型別）強制特化，效果等同 sysimage 中的抽象實例
invoke(Framework.vulnerable_inner, Tuple{Framework.AbstractInterp}, ni)
invoke(Framework.barriered_entry, Tuple{Framework.AbstractInterp}, ni)

using SnoopCompileCore

# Extension 扮演 REPL：插入新的介面方法
invs = @snoop_invalidations begin
    @eval module Extension
        using ..Framework
        struct ReplLikeInterp <: Framework.AbstractInterp end
        Framework.params(::ReplLikeInterp) = 1
    end
end

using SnoopCompile
trees = invalidation_trees(invs)
println("== invalidation trees after inserting params(::ReplLikeInterp) ==")
dump_io = IOBuffer()
for t in trees
    show(dump_io, t)
    show(stdout, t)
    println()
end
report = String(take!(dump_io))
n_vuln = count("vulnerable", report)
n_barrier = count("barriered", report)
println()
println("MECHANISM_RESULT vulnerable_mentions=$n_vuln barriered_mentions=$n_barrier total_trees=$(length(trees))")
