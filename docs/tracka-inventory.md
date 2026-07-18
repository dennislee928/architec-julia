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
- **A2 PR-2（world）**：`2f0ca85` ✅ — 18 呼叫點改讀
  `get_inference_world(sv::AbsIntState)` 快取欄位。rebuild 後實測（`using REPL`）：
  world 樹的 `abstract_call_gf_by_type` / `abstract_invoke` / `return_cached_result`
  受害者**全數歸零**；殘餘 19 個受害者恰為未換的 (b) 類入口
  （`abstract_applicable`、`_hasmethod_tfunc`、`concrete_eval_invoke`、
  `method_table` 等，tfuncs/types 檔）。分支已推上
  `dennislee928/julia@avoid-absint-interface-invalidation` 供 GHA 全量驗證。
- **A2 PR-1 擴充**：`eff8ddf` ✅ — 快取整個 `inf_params` 欄位（併掉 max_methods 欄位），
  11 個有 state 的呼叫點改讀 `InferenceParams(sv)`。InferenceParams 樹受害者 66 → **18**。
- **A2 PR-3**：`1ac0b5b` ✅ — 快取 `InferenceCache`/`cache_owner`/`method_table` 三欄位
  + tfuncs world 殘餘（`abstract_applicable`/`_hasmethod_tfunc`）。
  `get_inference_cache` 樹**整棵消失**；world 樹 19 → **13**。
  教訓：master 的 `get_inference_cache` 回傳新型別 `InferenceCache`（非
  `Vector{InferenceResult}`）— package-context 編譯檢查不會執行 state 建構，
  只有完整 bootstrap 才會抓到此類錯誤。
- **A2 PR-4**：**以量測結案** — 補丁後 `abstract_eval_globalref` 樹 0 受害者，
  依 PLAN-TRACK-A §2.1 決策規則（>10 才動工）採選項 3：不改碼，
  參數化設計記入上游 issue。
- **系列總成效**（`using REPL`，macOS）：**758 → 648 unique invalidated（−14.5%）**，
  9 → 8 trees；殘餘為無 state 可用的入口類（見 §2 (b) 欄）。
- **A2 PR-5**：`0b61fc1`（DCO）✅ — 無狀態殘餘的「傳遞 state」重構：
  `edge_matches_sv`/`is_same_frame` 改用當前 state 的快取欄位、
  `force_const_prop(sv,...)`、`find_method_matches` 呼叫端顯式傳
  `max_union_splitting`、`builtin_tfunction` 經 sv 讀參數、
  `abstract_eval_partition_load(assume_static::Bool,...)`（scan_leaf_partitions
  callers 以閉包捕獲布林）、`code_cache(sv)`/`is_nonoverlayed(sv)`/`engine_reserve`
  經 caller 快取。途中教訓：以「函數參考」傳遞的呼叫端
  （`scan_leaf_partitions(abstract_eval_partition_load, ...)`）grep 加括號會漏抓，
  bootstrap MethodError 抓到。
- **PR-5 量測**：**648 → 601（自 stock 累計 −20.7%）**；
  `InferenceParams` 樹直接受害者 18 → **2**（= 建構子實例，設計下限）、
  `cache_owner` 樹**整棵消失**、world 樹 13 → 9（入口/建構子類）。
  介面樹的可消除受害者至此**全數清除**。

## 4. 量測指令（重跑本盤點）

```bash
# 樹根與受害者統計（對任一 invalidation-report）
grep "^inserting" report.txt | sed 's/ @ .*//' | sort | uniq -c | sort -rn
awk '/^inserting get_inference_world/,/^----/' report.txt \
  | grep -oE "triggered MethodInstance for [A-Za-z_.]+" | sort | uniq -c | sort -rn

# 呼叫點盤點
grep -rn "get_inference_world(interp)" Compiler/src/*.jl
```
