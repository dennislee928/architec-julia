# 編譯管線、LLVM 轉譯與 GC 實作

> 任務脈絡：本文件對應 [`plan.md`](../plan.md) 的三大痛點根源 —— §3.1 型別推斷
> 決定 TTFP 與無效化（invalidation）行為（見 `bench/invalidations.jl` 的量測），
> §3.2 裝箱/拆箱決定記憶體 WIP，§3.1 的型別穩定性正是 JET.jl「品質左移」檢查的對象。

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
