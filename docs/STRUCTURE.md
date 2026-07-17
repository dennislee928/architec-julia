# 核心架構與記憶體佈局

> 任務脈絡：本文件是 [`plan.md`](../plan.md) Track A（核心貢獻）的背景知識。
> §2.2 的物件標頭與 §2.3 的排程器，是理解 TTFP 與記憶體（WIP）問題的物理基礎。

## 2.1 源碼樹總覽 (Source Tree Overview)

Julia 儲存庫的目錄結構嚴格反映了其架構的雙層性：底層為 C/C++ 負責系統介接與效能壓榨，高層為 Julia 負責語言語義與生態系統。

- **/src**：Julia 的心臟（C/C++）。包含 Runtime、垃圾回收器（GC）、任務排程（Task/Green Threads）、C API 定義，以及將 Julia AST 橋接至 LLVM IR 的程式碼生成器（Codegen）。
- **/Compiler**（過去位於 /base/compiler）：完全以 Julia 撰寫的編譯器前端。包含型別推斷引擎（Type Inference Engine）與高階優化 Pass。
- **/base**：標準函式庫。包含整數、浮點數、陣列、字串、基礎數學函數等實作。這部分會被烘焙（Baked）進 sys.so 中。
- **/stdlib**：隨附標準套件（如 LinearAlgebra, Pkg, Distributed）。這些套件採用延遲載入（Lazy Loading），只有在使用者輸入 `using Pkg` 時才會啟動，以減少系統記憶體足跡（Memory Footprint）。
- **/deps**：第三方依賴庫的原始碼與編譯腳本（如 LLVM, OpenBLAS, PCRE, libuv）。

## 2.2 核心資料結構與記憶體佈局 (Core Data Structures & Memory Layout)

在 /src 目錄下進行 C/C++ 開發，您必須深刻理解 Julia 在記憶體中是如何表示資料的。所有定義皆可在 `julia.h` 中找到。

### jl_value_t：萬物之源

在 Julia 的底層 C 語言表示中，所有的變數、陣列、甚至是函數本身，本質上都是一個指標：`jl_value_t*`。這是一個不透明結構（Opaque Struct）。Julia 採用了「標籤指標（Tagged Pointer）」與「物件標頭（Object Header）」結合的技術。

在堆積（Heap）上配置的每個 Julia 物件，其記憶體佈局的開頭隱藏著一個指標，指向該物件的「型別描述結構（Type Descriptor）」。這使得 Julia 能夠在執行期（Runtime）精準知道某塊記憶體是 Int64 還是 String，這正是多重分派（Multiple Dispatch）得以實現的物理基礎。

### jl_datatype_t：型別元資料

當您在 Julia 中定義一個 struct，在 C 層級就會生成一個對應的 `jl_datatype_t`。這個 C 結構包含了：

- 型別的名稱（Symbol）。
- 佔用記憶體的大小（Size in bytes）。
- 欄位名稱的陣列（Field names）。
- 記憶體佈局資訊：指示哪些欄位是純量資料（Inline data，如 Float64），哪些欄位是指標（需要被 GC 追蹤）。

### 陣列的內部結構 (jl_array_t)

Julia 的陣列效能極高，因為其內部佈局被設計為對快取極度友善（Cache-friendly）。在 `julia.h` 中，`jl_array_t` 定義了陣列的詮釋資料：

```c
// jl_array_t 的概念性結構
typedef struct {
    void *data;          // 指向實際資料的指標
    size_t length;       // 陣列總長度
    uint16_t flags;      // 包含維度資訊、是否擁有資料指標的管理權等
    uint16_t elsize;     // 每個元素的大小
    uint32_t offset;     // 用於 O(1) 時間複雜度的 pushfirst! / popfirst! 實作
    size_t nrows;        // 第一維度長度
    // 多維陣列會有額外的維度長度紀錄
} jl_array_t;
```

如果陣列元素的型別是具體的位元型別（isbits，如 Int64），`data` 會直接指向一塊連續的記憶體區塊（無指標封裝）；如果是抽象型別（如 Any），`data` 則會退化為一個指標陣列（`jl_value_t**`），這會導致嚴重的快取未命中（Cache Miss）與效能衰退。

## 2.3 執行緒與排程架構 (Threading & Task Scheduling)

位於 `/src/task.c` 與 `/src/partr.c`。Julia 的平行運算基於混合模型：

- **Task（綠色執行緒 / 協程）**：Julia 層級的非同步單元（透過 `@spawn` 或 `@async` 建立）。這是一種由軟體管理的協程（Coroutine），切換成本極低，不涉及作業系統的 Context Switch。
- **OS Threads（POSIX 執行緒）**：底層由 libuv 支援的實際作業系統執行緒。Julia 的排程器（Partr - PARallel TRansactions）採用了「工作竊取演算法（Work-Stealing Algorithm）」。每個 OS 執行緒都有自己的 Task 佇列，當某個執行緒閒置時，它會從其他繁忙執行緒的佇列尾端「竊取」Task 來執行，從而達成極佳的負載平衡（Load Balancing）。
