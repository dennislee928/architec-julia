# Control group for the First-Run Study: identical functions defined in script
# mode — no package precompilation, no workload — so every first call pays full
# inference + codegen cost at runtime.
function summarize(v::AbstractVector{T}) where {T<:Real}
    n = length(v)
    n == 0 && return (n = 0, mean = zero(float(T)), var = zero(float(T)))
    μ = sum(v) / n
    σ² = n == 1 ? zero(float(T)) : sum(x -> abs2(x - μ), v) / (n - 1)
    return (n = n, mean = float(μ), var = float(σ²))
end

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
