# 進階建置系統與底層依賴指南

## 1.1 專案概覽與系統架構 (Project Overview & Architecture)

Julia 是一個為高效能數值運算與通用程式設計而生的高階動態語言。其核心架構並非單一的直譯器，而是一個混合了 C、C++、Scheme 以及 Julia 語言本身的複雜虛擬機器（Virtual Machine）與即時編譯器（JIT Compiler）。Julia 的建置系統（Build System）負責協調超過二十個底層的第三方 C/C++ 函式庫，並將它們與 Julia 的核心 Runtime 以及 LLVM 靜態連結，最終產出執行檔與系統映像檔（System Image）。

## 1.2 核心依賴與建置環境 (Core Dependencies & Environment)

要從原始碼編譯 Julia 核心，系統必須準備好完整的編譯工具鏈。Julia 強度依賴 GNU Make 與 CMake 的混合架構。

- **編譯器 (Compilers)**：強烈建議使用 GCC 9.0+ 或 Clang 10.0+。因為 Julia 的 C++ 原始碼使用了 C++14/C++17 的進階特性，且其二進位介面（ABI）必須與底層的 LLVM 保持一致。
- **必備工具鏈**：`make`, `cmake`（至少 3.22）, `python3`（用於建置腳本）, `gfortran`（用於編譯底層的 LAPACK/BLAS 數學庫）, `perl`, `m4`, `patch`。
- **Tier 1 支援平台**：Linux (x86_64, aarch64), macOS (x86_64, ARM64/Apple Silicon), Windows (x86_64)。在這些平台上，建置系統預設會從 GitHub 下載預先編譯好的二進位依賴包（Tarballs），這被稱為 BinaryBuilder 機制。

## 1.3 Make.user 深度客製化 (Advanced Build Configuration)

作為底層貢獻者，預設的 `make` 指令絕對無法滿足開發與除錯需求。您必須在源碼根目錄建立一個名為 `Make.user` 的檔案，此檔案中的變數會覆寫 `Make.inc` 中的預設設定。以下是核心開發者常用的關鍵標誌（Flags）：

```makefile
# Make.user 範例配置

# 1. 強制從原始碼編譯 LLVM
# Julia 對 LLVM 進行了大量的客製化 Patch（特別是針對 GC 與型別標籤）。
# 預設會下載預編譯版本，若您要除錯 Codegen 或是修改 LLVM Pass，必須設為 0。
USE_SYSTEM_LLVM=0

# 2. 關閉預編譯二進位檔 (BinaryBuilder)
# 若您需要修改 libuv (負責非同步 I/O) 或 OpenLibm 的底層 C 語言代碼，
# 將此設為 0 會強制 Make 下載這些套件的原始碼至 /deps 目錄並手動編譯。
USE_BINARYBUILDER=0

# 3. 啟用編譯快取 (Compiler Cache)
# 修改 /src 目錄下的 C++ 代碼會觸發大量重編譯。安裝 ccache 並啟用此選項，
# 可將後續的編譯時間從 40 分鐘大幅壓縮至 1-2 分鐘。
WITH_CCACHE=1

# 4. 指定數學後端 (Math Backend)
# 預設使用 OpenBLAS。若在 Intel CPU 上追求極致的矩陣運算效能，可改用 MKL。
USE_INTEL_MKL=1

# 5. LTO (連結期最佳化)
# 啟用 Link-Time Optimization 能夠讓 LLVM 在最終連結階段跨越不同的 C++
# 原始檔進行函式內聯（Inlining），大幅減少 Julia Runtime API 的呼叫開銷。
LLVM_LTO=1
```

## 1.4 除錯與開發建置 (Debugging & Development Builds)

開發編譯器底層時，最常遭遇的錯誤是記憶體區段錯誤（Segmentation Fault）或非法指令（Illegal Instruction）。常規的 Release Build 會因為過度的優化（如暫存器分配、死碼消除）而使得 gdb 除錯變得極度困難。

**執行 `make debug`**：此指令會產出 `usr/bin/julia-debug`。這是一個帶有完整 DWARF 偵錯符號的二進位檔。它會：

1. 將巨集 `JULIA_DEBUG_BUILD` 設為 1。
2. 開啟 C++ 原始碼中所有的 `assert()` 檢查。在 Release 模式下，這些斷言會被靜默移除；在 Debug 模式下，一旦 GC 狀態異常或指標越界，系統會立刻崩潰並印出 Call Stack，這對捕捉潛在的記憶體損毀（Memory Corruption）至關重要。
3. 關閉 LLVM 中會干擾單步追蹤（Step-through）的激進優化 Pass。

**整合 Address Sanitizer (ASAN)**：若要徹底追蹤記憶體洩漏或 Use-After-Free 錯誤，可在編譯時注入 ASAN：`make default USEASAN=1`。這會讓編譯器在每一次記憶體存取前後安插檢查指令，是處理 C 核心指標問題的神兵利器。

## 1.5 系統自舉流程 (The Bootstrapping Process)

編譯 Julia 並非單純地將 C++ 程式碼編譯成執行檔，它包含一個極為複雜的「自舉（Bootstrapping）」過程，因為 Julia 的編譯器有一半是用 Julia 語言自己寫的。

1. **編譯 C/C++ Runtime**：首先編譯 `/src` 目錄下的 C++ 代碼，產生 `libjulia.so`。
2. **編譯 flisp 解析器**：編譯位於 `/src/flisp` 的 Scheme 直譯器。早期 Julia 的語法解析器是用 Scheme 寫的（目前正逐步遷移至 Julia 本身）。
3. **生成基礎映像檔 (`sys.ji`)**：使用剛剛編譯出的微型 Julia 核心（僅具備最基礎的 AST 執行能力），去載入 `/base` 目錄下的純 Julia 程式碼，進行第一次的高階編譯。
4. **生成原生共用函式庫 (`sys.so`)**：透過剛剛生成的 `sys.ji` 與編譯器，將整個 `/base` 標準函式庫編譯成高度優化的底層機器碼，打包成 `sys.so`。這就是為何啟動 Julia 時幾乎不需要等待核心庫編譯的原因。
