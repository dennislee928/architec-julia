# 反面教材：兩個典型的型別不穩定，用來驗證 JET 閘門真的抓得到問題。
# （若 JET 對本檔回報 0 個問題，代表閘門失效 —— gate.jl 會把這視為 CI 失敗。）

module UnstableDemo

# 病徵 1：依條件回傳不同型別 → 呼叫端被迫裝箱（Boxed, 見 IMPLEMENTATION.md §3.2）
function bad_parse(s::String)
    x = tryparse(Int, s)
    return x === nothing ? "invalid" : x   # Union{Int, String}
end

# 病徵 2：未型別化的全域變數 → 每次存取都是動態派發
counter = 0
function bump!()
    global counter
    counter += 1   # counter::Any，觸發 jl_apply_generic
    return counter
end

consume(s::String) = codeunits(s)

# 讓 JET 有具體的呼叫可分析：bad_parse 的 Union 回傳流進 consume(::String)
demo() = consume(bad_parse("42"))

end # module
