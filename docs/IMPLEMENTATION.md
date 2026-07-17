# 編譯管線、LLVM 轉譯與 GC 實作

> 任務脈絡：本文件對應 [`plan.md`](../plan.md) 的三大痛點根源 —— §3.1 型別推斷
> 決定 TTFP 行為，§3.2 裝箱/拆箱決定記憶體 WIP，型別穩定性正是 JET.jl「品質左移」
> 檢查的對象；§3.4 方法無效化與 §3.5 預編譯/pkgimages 是 Phase 2 實戰的直接機制，
> 並以 `bench/` 的實測數據佐證。

這份文件將深入解剖 Julia 最核心的兩個技術命脈：即時編譯器（JIT Compiler）的優化管線與記憶體管理系統（Garbage Collector）。

## 3.1 抽象解釋與型別推斷引擎 (Abstract Interpretation & Type Inference)

在動態語言中獲得靜態語言效能的關鍵，在於盡可能在編譯期（而非執行期）確認變數的型別。這項艱鉅的任務由 `/Compiler/src/infer.jl` 中的型別推斷引擎負責。

**格論 (Lattice Theory) 的應用**：推斷引擎將所有可能的型別視為一個數學上的「格（Lattice）」。

- **Bottom (`Union{}`)**：代表「矛盾」或「不可達狀態」。如果一個函數的返回型別被推斷為 `Union{}`，代表這個函數必定會拋出例外（Exception）或者陷入無窮迴圈，永遠不會正常返回。
- **具體型別 (Concrete Types)**：例如 `Float64`, `Array{Int64, 1}`。這是引擎努力想要達到的狀態。一旦變數被固定在此層級，稱為「型別穩定（Type Stable）」。
- **抽象型別 (Abstract Types)**：例如 `Real`, `Number`。
- **Top (`Any`)**：代表完全喪失型別資訊。此時編譯器必須放棄優化，退化為緩慢的動態派發。

**方法實例化 (Method Instantiation)**：當您呼叫 `f(1.5)` 時，引擎會尋找 `f(x)` 的定義，並為 `Float64` 生成一個專屬的 MethodInstance。編譯器會執行「抽象執行（Abstract Execution）」，不帶入實際數值，只讓型別在函數的 AST 中流動，計算出每一個內部變數與返回值的型別。如果推斷成功，這份帶有嚴格型別標註的中間表示（Typed IR）就會被送到 C++ 層的 LLVM 程式碼生成器。

## 3.2 LLVM 程式碼生成 (Codegen)

位於 `/src/codegen.cpp`。這個檔案長達數萬行，是整個 Julia 最複雜的 C++ 組件。它的任務是將 Julia 的 Typed IR 轉換為 LLVM IR。

**裝箱與拆箱 (Boxing and Unboxing)**：這是效能差異的分水嶺。在 `codegen.cpp` 中，有一個關鍵結構 `jl_cgval_t` (CodeGen Value)。它負責追蹤一個變數在 LLVM 層級的物理狀態。

- **Ghost（幽靈狀態）**：大小為 0 的單例型別（如 `Nothing`）。`codegen.cpp` 完全不會為其生成任何機器碼或配置記憶體，直接在編譯期抹除。
- **Unboxed（拆箱狀態）**：若變數是不可變的具體型別（如 `Int64`），它會被表示為 LLVM 的原生型別（如 `i64`）。這意味著這個變數可以直接儲存在 CPU 的暫存器（Registers）中，計算速度極快。
- **Boxed（裝箱狀態）**：若型別不穩定（推斷為 `Any`），系統必須呼叫 `jl_box_int64` 等 Runtime 函數，在堆積上配置一塊記憶體（包含型別標頭），並將指標傳遞。這會造成嚴重的記憶體配置開銷與指標追蹤成本。

**`emit_function` 的運作**：這個函數遍歷 Julia IR 的每個節點。遇到基本的加減乘除，它會直接呼叫 LLVM 的 `IRBuilder->CreateAdd()` 等 API 生成原生指令。遇到無法確定型別的函數呼叫，它會生成一個龐大的 C Runtime 呼叫（`jl_apply_generic`），這就是效能殺手。

## 3.3 垃圾回收機制 (Garbage Collection, GC)

Julia 的 GC 實作位於 `/src/gc.c`。這是一個非精確（Imprecise）、標記-清除（Mark-and-Sweep）、世代型（Generational）的垃圾回收器。為了滿足科學計算每秒產生數百萬個小矩陣的需求，GC 被設計得極度特化。

**記憶體池配置 (Pool Allocation)**：這是 Julia GC 效能極高的核心原因。對於小於 2048 Bytes 的小型物件，Julia 不會呼叫系統的 `malloc`。相反地，它預先向作業系統申請大區塊（Pages），並將其切割成固定大小（如 16B, 32B, 64B...）的記憶體池。當你需要配置一個小物件時，系統只需以 O(1) 的時間複雜度，從對應大小的 Pool 的 Free-list 中彈出一個指標即可。

**大物件配置 (Big Object Allocation)**：大於 2048 Bytes 的陣列，才會真正呼叫 `malloc`，並透過一個特殊的雙向鏈結串列（Doubly-linked List）被 GC 獨立追蹤。

**世代回收與寫入屏障 (Generational GC & Write Barriers)**：Julia 的記憶體被分為「年輕世代（Young Generation）」與「老世代（Old Generation）」。多數臨時變數（年輕世代）很快就會成為垃圾。GC 大部分時間只掃描年輕世代以節省時間。

- **關鍵挑戰**：如果一個已經活過多次 GC 的老世代陣列，被修改並指向了一個剛建立的年輕世代物件，會發生什麼事？如果 GC 只掃描年輕世代，它找不到從根物件到達這個新物件的路徑，會誤以為它是垃圾而將其釋放，導致嚴重的 Use-After-Free 錯誤。
- **解決方案**：C++ 原始碼中充滿了 `jl_gc_wb(parent, child)`（Write Barrier）巨集。每次修改指標前，必須觸發這個屏障，通知 GC 記錄這種「老指新」的跨世代引用。

**C 語言層的 GC 根物件保護 (JL_GC_PUSH)**：在編寫 /src 中的 C 程式碼時，任何指向 `jl_value_t*` 的本地變數都對 GC 是隱形的。如果你配置了一個物件，然後呼叫了可能觸發 GC 的函數，該物件可能會在函數返回前被意外回收。開發者必須嚴格遵守紀律，使用 `JL_GC_PUSH1(&my_val)` 將變數註冊到 GC 的 Root 堆疊中，並在使用完畢後呼叫 `JL_GC_POP()`。未遵守此規範是 Julia 核心 Segfault 最常見的來源。

## 3.4 世界年齡與方法無效化 (World Age & Method Invalidation)

這是本任務 Phase 2 的核心機制。Julia 允許在執行期新增或覆寫方法（Method），但已編譯的機器碼是基於「當時看得見的方法表」生成的 —— 兩者如何共存？答案是「世界年齡（World Age）」機制，實作於 `/src/gf.c`（generic functions）。

**世界年齡計數器**：每次有方法被定義或刪除，全域的 world counter 就會 +1。每個 `MethodInstance` 編譯出的程式碼都帶有一個有效區間 `[min_world, max_world]`。執行中的 Task 固定在進入時的 world 中執行，因此看不見「未來」定義的方法 —— 這就是 REPL 中重新定義函數後，舊的執行緒不會突然改變行為的原因。

**反向邊 (Backedges)**：當推斷引擎（§3.1）在編譯 `f` 時內聯或靜態派發了 `g`，它會在 `g` 的 MethodInstance 上登記一條指回 `f` 的 backedge。日後若有新方法插入，使得 `g` 的派發結果**可能**改變（新方法的簽名與 `g` 被呼叫時的抽象簽名有交集），Runtime 便沿著 backedges 把 `f` 以及所有依賴 `f` 的已編譯程式碼全部標記為無效（將其 `max_world` 封頂）—— 下次呼叫時必須重新推斷、重新編譯。這就是「無效化（Invalidation）」：**已完成的編譯工作被追溯作廢的重工（Rework）**。

**為何抽象呼叫最脆弱**：無效化幾乎總是發生在型別不穩定的呼叫點。若 `f` 中對 `convert(String, x::Any)` 或 `values(d::AbstractDict)` 這類**抽象簽名**做了呼叫，任何套件只要新增一個 `convert(::Type{String}, ::自家型別)` 方法，就會與該抽象簽名交集而引爆整棵無效化樹。本 repo 的實測（`bench/toptrees.jl`，2026-07-17，Julia 1.12.6）：

- 載入 CSV / DataFrames / Plots 分別無效化 973 / 1262 / 1539 個方法。
- 最大單一樹：REPL 的 `Compiler.InferenceParams(::REPLInterpreter)` 觸發 `Compiler.get_max_methods` 一節就有 396 個 children。
- 生態系典型案例：`JSON.PtrString` 的 `convert(::Type{String}, ...)`、`SentinelArrays.ChainedVectorIndex` 的整數建構子、`DataStructures.values(::Accumulator)` 打掉 `PrettyTables._preprocess_data(::AbstractDict)` 210 個 children。

**診斷與修復工具鏈**：`SnoopCompileCore.@snoop_invalidations`（量測，先載入以免污染）→ `SnoopCompile.invalidation_trees`（歸因）→ 修復手段依序為：在被害呼叫點加上具體型別標註（消除抽象呼叫）、調整新方法的簽名特異性、或以函數屏障（Function Barrier）隔離不穩定區段。修復效果可直接用本 repo 的 `bench/` 驗證。

## 3.5 預編譯與套件映像 (Precompilation & pkgimages)

**兩層快取**：自 Julia 1.9 起，`Pkg.precompile` 產出的不只是序列化的推斷結果（`.ji` 檔），還包含**原生機器碼**的套件映像（pkgimage，本質上是每個套件自己的迷你 `sys.so`）。這使得「首次執行」的成本大幅移出執行期：本 repo 實測第一次繪圖（TTFX）僅 0.86 秒，而歷史上這個數字是 10–30 秒。

**成本守恆，位置轉移**：機器碼不會憑空出現 —— 生成成本移到了預編譯階段。實測冷預編譯：CSV 18 秒、DataFrames 45 秒、Plots 55 秒（首次建置環境 180 個相依套件共 270 秒）。以精實術語說：執行期的 Start-up Loss 被「前置計畫（Front-End Planning）」搬到了動員階段，而動員階段本身現在成了 WIP 堆積地。這正是 Phase 2 之後「預編譯時間削減」（`@snoop_inference` 分析）作為備選方向的原因。

**無效化 × pkgimage 的乘法效應**：pkgimage 中的機器碼同樣受 §3.4 的無效化管轄 —— 若載入套件 B 無效化了套件 A 映像中的程式碼，A 花在預編譯的那部分工夫就白費了，還得在執行期重編譯。因此**減少無效化是讓兩層快取都保值的槓桿點**，這是 Phase 2 選擇它作為首要目標的技術依據。

**延遲的陷阱**：套件擴充（Package Extensions，如 Plots 的 `FileIOExt`）是延遲預編譯的，可能在首次使用時才觸發編譯。實測中這造成 Plots TTFX 在 0.86 秒與 3.6 秒之間波動 —— 量測與優化時必須明確固定擴充套件的預編譯狀態。
