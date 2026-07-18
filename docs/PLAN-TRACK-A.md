# Track A 治本計畫 — 系統性消除 AbstractInterpreter 介面無效化

> Status: **A1–A2 EXECUTED (2026-07-18)** — PR-1/2/3 實作並量測完畢、PR-4 以量測結案。
> 系列總成效：`using REPL` 無效化 **758 → 648（−14.5%）**；最熱路徑受害者歸零。
> 分支（4 個原子 commit，DCO）：`dennislee928/julia @ avoid-absint-interface-invalidation`。
> 殘餘 = 無 state 可用的入口類呼叫點（詳 `tracka-inventory.md` §2 (b)）→ A4 上游討論題。
> 定位：Track B 已止血（把成本搬走/預付）；本計畫在 core 拔除根源。

## 0. 依據（已驗證的事實）

| 證據 | 數字 | 來源 |
|---|---|---|
| 載入 REPL 使編譯器自我無效化（本機 master, macOS） | 758 methods / 9 trees | 本機 stock build 實測 |
| 載入 DataFrames（雲端 master, Linux, GHA #2） | **2,364 methods / 56 trees**，第一名 = `get_inference_world(::REPLInterpreter)` | GHA artifact `invalidation-report-master` |
| D1 補丁（快取 `max_methods`）效果 | `get_max_methods` 受害者**消滅**；`InferenceParams` 樹所有殘餘受害者 **0 children**；`test-compiler` 539,410 全過 | branch `avoid-absint-interface-invalidation` @ `2dbb8d9` |
| 機制結論 | 漏洞實例只在 sysimage bootstrap 推斷時產生；修法 = 把介面讀取移進「以具體直譯器型別特化」的建構期 | dossier §3、§6 |

**治本原則（從 D1 歸納）**：Compiler 內以抽象型別編譯的程式碼，不得直接呼叫
可擴充的 AbstractInterpreter 介面函數；介面值應在 state 建構期（具體特化）讀取一次，
之後從 state 欄位取用。

## 1. Phase A1 — 盤點（1–2 天）

以「量測驅動」列出全部漏洞呼叫點，不靠猜：

1. 從 GHA / 本機的 invalidation trees 萃取所有 mt_backedges 簽名 → 得出被
   REPL/JET 類套件插入的介面方法全集（已知：`InferenceParams`、
   `OptimizationParams`、`get_inference_world`、`get_inference_cache`、
   `cache_owner`、`method_table`、`typeinf_lattice` 家族、
   `abstract_eval_globalref` 覆寫類）。
2. `grep` Compiler/src 找出每個介面函數「在抽象編譯路徑上的呼叫點」，
   分類為：(a) sv 在手邊 → 可讀快取欄位；(b) 只有 interp → 需要傳遞 sv
   或維持現狀；(c) 建構期呼叫 → 本來就安全。
3. 產出 `docs/tracka-inventory.md`：呼叫點 × 分類 × 對應無效化樹大小（優先序）。

## 2. Phase A2 — 補丁系列（每個 PR 原子化，依 contribute.md）

依樹大小排序（先大後小），每個 PR 重複 D1 的完整迴圈
（patch → rebuild → measure → test-compiler）：

| PR | 內容 | 目標樹 |
|---|---|---|
| PR-1 | ✅ **完成** `7ee1204`：快取整個 `inf_params::InferenceParams` 欄位（併掉 D1 的 max_methods 欄位），有 state 的呼叫點改讀 `InferenceParams(sv)`；樹受害者 66 → 18 | `InferenceParams` 樹殘餘 |
| PR-2 | ✅ **完成** `db9be70`：快取 `world::UInt` + `get_inference_world(sv::AbsIntState)`，18 呼叫點；最熱受害者（`abstract_call_gf_by_type` 等）歸零 | `get_inference_world` 樹（GHA 第一名） |
| PR-3 | ✅ **完成** `ac204f8`：快取 `InferenceCache`/`cache_owner`/`method_table` + tfuncs world 殘餘；`get_inference_cache` 樹整棵消失 | cache/owner/method_table 樹 |
| PR-4 | ✅ **以量測結案**（選項 3）：補丁後該樹 0 受害者，未達 >10 動工門檻；參數化設計保留於 §2.1 供上游 issue | `abstract_eval_globalref` 樹 |

### 2.0 PR-5 設計：無狀態呼叫點的「傳遞 state」重構（2026-07-18 新增）

PR-1/2/3 後的殘餘直接受害者精確普查（`using REPL`，三棵介面樹合計 ~41 個）：

| 受害者 | 數量 | 修法 |
|---|---:|---|
| `edge_matches_sv` | 10 | 呼叫端有當前 sv：把 interp 參數改為當前 state，`cache_owner(interp)`/`InferenceParams(interp)` → `(sv)` |
| `builtin_tfunction` | 5 | `sv::Union{AbsIntState,Nothing}` → **拆成兩個方法**：`sv::AbsIntState` 走快取（熱路徑乾淨），`::Nothing` 保留介面呼叫（入口罕用） |
| `var"#..."` 閉包 | 4 | 逐一辨識所屬函數後套用同法 |
| `concrete_eval_invoke` | 3 | 檢查簽名是否帶 irinterp state → 換讀快取 |
| `force_const_prop` | 2 | 內部函數：加 `sv` 參數（呼叫端皆有 sv） |
| `find_method_matches` | 2 | kwarg 預設值讀介面 → 加 sv 參數、預設值改 `InferenceParams(sv)` |
| `abstract_eval_partition_load` | 2 | `interp::Union{Nothing,...}` → 改傳 `assume_bindings_static::Bool`（有 sv 的呼叫端從快取取值） |
| `is_same_frame` / `code_cache` / `engine_reserve` / `method_table` | 4 | 有 caller 的改讀快取；`code_cache(sv)`、`engine_reserve(mi, cache_owner(sv))` |
| `InferenceState` / `IRInterpretationState` 建構子 | 4 | **設計上不可消除**（建構期唯一一次介面讀取 = 本模式的成本下限） |

原則：這一輪允許改**內部**函數簽名（傳遞 state），但仍不動 AbstractInterpreter
公開介面。目標：`using REPL` 直接受害者僅剩建構子類（≤ 8），unique total 顯著下降。

### 2.1 PR-4 設計：覆寫型介面（behavior overrides）

取值型介面（params/world/cache/owner/method table）可用「建構期快取」根治 —
PR-1/2/3 已證明。覆寫型介面（如 REPLCompletions 覆寫 `abstract_eval_globalref`
以激進解析 global bindings）不同：插入的方法改變*行為*，快取無適用對象。

候選設計（優先序）：

1. **行為參數化（建議）**：REPLInterpreter 的覆寫本質是「更激進的 binding
   解析」這一*策略差異*。將策略升格為 `InferenceParams` 欄位（先例：
   `assume_bindings_static` 已存在），base 實作讀取參數（經 PR-1 的快取欄位，
   無新增無效化面），REPL 側改為傳參數而非插方法。**方法插入完全消失**。
   代價：params 欄位增生；僅適用於「策略型」覆寫。
2. **具體化屏障（D3 精簡版）**：確保 bootstrap 只以具體 `NativeInterpreter`
   簽名預編譯 `abstract_eval_globalref` 的呼叫者 —— 插入
   `(::REPLInterpreter, ...)` 方法便不與已編譯簽名相交。需要 bootstrap
   precompile workload 控制，脆弱且難以長期保證。
3. **接受現狀**：若量測顯示該樹已縮小（PR-2 後本機 `using REPL` 實測該樹
   0 victims），列為低優先，僅在上游 issue 中記錄設計選項。

**決策規則**：以 PR-1/2/3 rebuild 後的量測為準 — 樹 victims > 10 才推進
選項 1；否則採選項 3 並於上游 issue 記錄。

規範：每 PR 一個 commit、DCO 簽章、附 before/after 無效化量測 + `test-compiler`
結果；PR 描述引用本 repo 的 harness 供審查者重跑。

## 3. Phase A3 — 驗證與效能閘門

1. **功能**：每 PR `make test-compiler`；系列完成後 `make testall` 一次。
2. **無效化驗收**：`using REPL` 目標 **< 50 methods**（自 758）；
   GHA `using DataFrames` 目標 **< 500**（自 2,364）— 殘餘應全為與
   AbstractInterpreter 無關的類別（如 SentinelArrays 整數建構子）。
3. **效能**：介面值改為建構期讀取 = 語義上「每 state 常數化」。
   風險：某些 interpreter 動態改變 params？— 現行文件未承諾此行為；PR 中
   明文化「params/world 在單一 state 生命週期內視為常數」。以
   BaseBenchmarks 抽樣 + 上游 `@nanosoldier` 把關回歸。
4. **程式碼尺寸**：state 增加 3 欄位（Int + 2 struct refs）— 可忽略；監看
   sysimage 尺寸差異 < 0.1%。

## 4. Phase A4 — 上游流程

1. **先搜尋**：JuliaLang/julia issues/PRs 關鍵字 "AbstractInterpreter
   invalidation" / "REPLInterpreter invalidations" — 若已有 owner，把
   harness + 量測數據貢獻到該串，D1 branch 作為 draft 供參考。
2. 無既有工作 → 開 issue 附完整量測（本 repo 連結），提出治本原則，
   徵求設計回饋後再送 PR-1。
3. PR 節奏：PR-1 合併並存活一個 release cycle 後再推 PR-2/3；PR-4 獨立設計討論。

## 5. 基礎設施

- **本機**：`~/Documents/GitHub/julia`（增量 rebuild ~25 分鐘/輪）。
- **雲端**：`.github/workflows/core-validation.yml` — 對 fork branch 全量驗證
  （~30 分鐘，含 artifact 報告）。注意 julia 預設分支是 `master`。
- **量測**：本 repo `bench/` + `lab/core-experiment/`，全部可重跑。

## 6. 不做什麼（範圍界線）

- 不動 C++/LLVM 層（本問題整條鏈都在 Julia 寫的 Compiler 內）。
- 不改 AbstractInterpreter 介面簽名（JET/Cthulhu 等下游不需改動）。
- 不在本計畫內處理與介面無關的無效化（JSON/SentinelArrays/PrettyTables
  類 — 那是 plan.md §4 的 Track B 標的）。
