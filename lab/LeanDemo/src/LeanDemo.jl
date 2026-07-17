"""
LeanDemo — 示範「品質左移」與「避免冷啟動」兩項精實原則的最小套件。

- 所有公開函數皆型別穩定（JET 檢查為 CI 第一道閘門）。
- 結尾的 PrecompileTools workload 在預編譯期先走過核心路徑
  （First-Run Study），將 TTFX 成本移出使用者的執行期。
"""
module LeanDemo

using PrecompileTools

export summarize, rolling_mean

"""
    summarize(v::AbstractVector{<:Real}) -> NamedTuple

回傳 `(n, mean, var)`。單一具體回傳型別 —— 型別穩定是防呆（Poka-Yoke）的第一原則。
"""
function summarize(v::AbstractVector{T}) where {T<:Real}
    n = length(v)
    n == 0 && return (n = 0, mean = zero(float(T)), var = zero(float(T)))
    μ = sum(v) / n
    σ² = n == 1 ? zero(float(T)) : sum(x -> abs2(x - μ), v) / (n - 1)
    return (n = n, mean = float(μ), var = float(σ²))
end

"""
    rolling_mean(v::AbstractVector{<:Real}, w::Integer) -> Vector{Float64}

視窗滑動平均。以預配置 + 原地累加避免熱迴圈中的堆積配置（WIP 上限）。
"""
function rolling_mean(v::AbstractVector{<:Real}, w::Integer)
    1 <= w <= length(v) || throw(ArgumentError("window w=$w out of range 1:$(length(v))"))
    out = Vector{Float64}(undef, length(v) - w + 1)
    s = 0.0
    @inbounds for i in 1:w
        s += v[i]
    end
    out[1] = s / w
    @inbounds for i in 2:length(out)
        s += v[i + w - 1] - v[i - 1]
        out[i] = s / w
    end
    return out
end

# Front-End Planning：在預編譯期先行編譯核心路徑，使用者程序零冷啟動。
@setup_workload begin
    data = [1.0, 2.5, 3.5, 4.0, 5.5]
    @compile_workload begin
        summarize(data)
        summarize(Int[])
        summarize(1:10)
        rolling_mean(data, 2)
        rolling_mean(1:100, 10)
    end
end

end # module
