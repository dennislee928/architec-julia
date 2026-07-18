# Track A Phase A1 — 漏洞呼叫點盤點 (2026-07-18)

資料來源：GHA artifact `invalidation-report-master`（Linux, stock master,
`using DataFrames` → 2,364 methods / 56 trees）+ 本機量測 + `Compiler/src` grep。

## 1. 介面無效化樹（GHA, 依危害排序）

| 樹根（REPL 插入的介面方法） | 主要受害者（instances） | 狀態 |
|---|---|---|
| `get_inference_world(::REPLInterpreter)` | `abstract_call_gf_by_type` ×76、`abstract_invoke` ×16、`return_cached_result` ×15、`edge_matches_sv` ×9、global-binding 求值器 ×~25、`abstract_applicable` ×5 | **PR-2 已實作**（`2f0ca85`，rebuild 驗證中） |
| `InferenceParams(::REPLInterpreter)` | D1 後殘餘：`typeinf_edge`、`abstract_call_method`、`builtin_tfunction`、`find_method_matches` kwcalls（全部 0 children） | **D1 已合入 branch**（`2dbb8d9`，驗證完畢） |
| 其餘 7 樹（非介面類） | DataStructures `values`、SentinelArrays 整數建構子、PooledArrays、LaTeXStrings 等 | Track B 標的（`plan.md` §4） |

註：macOS 本機 `using REPL` 另含 `abstract_eval_globalref` 覆寫類樹（PR-4 範疇）。

## 2. Compiler/src 介面呼叫點統計（grep, master @ 2026-07-18）

| 介面函數 | 呼叫點 | (a) state 在手 → 已換/可換 | (b) 無 state（入口/頂層） | 附註 |
|---|---:|---|---|---|
| `get_inference_world(interp)` | 27 | **18 已換**（abstractinterpretation.jl ×14、typeinfer.jl ×4） | 9：`typeinf_ext`、`compile!`、`_return_type`、tfuncs ×2、types.jl ×3、optimize.jl ×1 | (b) 類多為具體 interp 入口，sysimage 中未必以抽象特化 — 待量測決定是否處理 |
| `InferenceParams(interp)` | 27 | D1 已處理 `get_max_methods` 路徑；其餘讀 `.aggressive_constant_propagation` 等欄位 | 混合 | PR-1 擴充：快取整個 `inf_params` 欄位 |
| `method_table(interp)` | 7 | 部分 | 部分 | 待 PR-3 盤點 |
| `get_inference_cache(interp)` | 6 | 部分 | 部分 | 待 PR-3 盤點 |
| `OptimizationParams(interp)` | 2 | — | — | 低危害，掃尾處理 |

## 3. 已實作進度對照 `PLAN-TRACK-A.md`

- **A1 盤點**：本文件 ✅（由實測樹 + grep 產出，非猜測）
- **A2 PR-1（D1）**：`2dbb8d9` ✅ — `get_max_methods` 受害者消滅、級聯歸零、
  `test-compiler` 539,410 全過
- **A2 PR-2（world）**：`2f0ca85` — 18 呼叫點改讀 `get_inference_world(sv::AbsIntState)`
  快取欄位；rebuild + 量測進行中
- **A2 PR-3（inf_params/method_table/cache）**：未開始
- **A2 PR-4（`abstract_eval_globalref` 覆寫類）**：未開始（需設計討論）

## 4. 量測指令（重跑本盤點）

```bash
# 樹根與受害者統計（對任一 invalidation-report）
grep "^inserting" report.txt | sed 's/ @ .*//' | sort | uniq -c | sort -rn
awk '/^inserting get_inference_world/,/^----/' report.txt \
  | grep -oE "triggered MethodInstance for [A-Za-z_.]+" | sort | uniq -c | sort -rn

# 呼叫點盤點
grep -rn "get_inference_world(interp)" Compiler/src/*.jl
```
