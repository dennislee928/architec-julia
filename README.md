# architec-julia — Julia 核心貢獻任務基地

本 repo 是「以精實建設（Lean Construction）框架改善 Julia 語言」的任務控制中心。
四大痛點（TTFP 冷啟動、生態系規模、記憶體/執行檔膨脹、缺乏靜態防呆）×
六大對策，已全數實作並量測（2026-07-17，Julia 1.12.6）：

| 精實對策 | 實作工件 | 實測結果 |
|---|---|---|
| 避免冷啟動 Front-End Planning | [`lab/sysimage/`](lab/sysimage/) | Plots 旅程 7.1 s → **0.65 s**（`using` 5,978 → 0.6 ms） |
| 持續整合 First-Run Study | [`lab/LeanDemo/`](lab/LeanDemo/) + PrecompileTools | 首次呼叫 106.7 → **0.03 ms** |
| 限制 WIP（Tree-shaking） | [`lab/small-binary/`](lab/small-binary/) juliac `--trim` | **1.1 MB** 執行檔、130 ms 啟動（對照 sysimage 462 MB） |
| 品質左移 Poka-Yoke | [`lab/quality-gate/`](lab/quality-gate/) JET + Aqua | 三道閘全綠；曾實際攔截真實 compat 缺陷 |
| 漸進驗證 + 禁止 Big-Bang | [`lab/ci.sh`](lab/ci.sh) | 靜態 → 單元 → 效能預算，fail-fast 全綠 |
| 兩軌貢獻 Track B→A | [`plan.md`](plan.md) §4–5 | 4 個具名上游 PR 標的；**core 補丁 D1 已實作並驗證**（[dossier](lab/core-experiment/TRACKA-DOSSIER.md)） |

## 結論：治標在套件層，治本在 core（2026-07-18 定論）

| 痛點 | 解在哪裡 | 關鍵證據 |
|---|---|---|
| TTFP 冷啟動 | 套件層拿 10× 速贏（成本預付）；**殘餘重工只有 core 能除** | sysimage 7.1s→0.65s；D1 補丁消滅 396-children 級聯，`test-compiler` 539,410 全過 |
| 記憶體 / 執行檔膨脹 | **Core**（juliac `--trim` 的靜態可達性分析） | 1.1 MB 執行檔 vs PackageCompiler 462 MB 映像 |
| 缺乏靜態防呆 | 套件層（JET 复用 core 推斷引擎） | 閘門全綠 + 實際攔截缺陷 |
| 生態系規模 | 只能靠套件層；core 降低貢獻摩擦 | harness + 4 個具名 PR 標的 |

雲端獨立驗證（GHA #2, Linux, stock master）：`using DataFrames` 無效化
**2,364 methods / 56 trees**，第一名 `get_inference_world(::REPLInterpreter)` —
與本機 macOS 量測同一根因。

**治本已執行（2026-07-18，含 PR-5）**：[`docs/PLAN-TRACK-A.md`](docs/PLAN-TRACK-A.md)
全系列（快取 + 無狀態殘餘重構）完畢 —— `using REPL` 無效化 **758 → 601（−20.7%）**、
可消除的介面樹受害者**全數清除**（僅剩建構子設計下限與真入口點）；
5 個原子 DCO commit 在 `dennislee928/julia @ avoid-absint-interface-invalidation`。
盤點與逐 PR 量測：[`docs/tracka-inventory.md`](docs/tracka-inventory.md)。
雲端 A/B 對照與 release 管線：[`.github/workflows/`](.github/workflows/)

導覽：

- **任務計畫與進度**：[`plan.md`](plan.md)（Track B → A；Phase 1–2.5 完成，Phase 3 進行中）
- **基準測量**：[`bench/`](bench/) — 冷預編譯 / 載入 / TTFX / 方法無效化基準；
  [基線報告](bench/results/baseline-2026-07-17.md) ·
  [無效化樹](bench/results/toptrees-DataFrames.txt)
- **對策實驗室**：[`lab/`](lab/) — 全部可重跑；彙總見 [`lab/RESULTS.md`](lab/RESULTS.md)
- **參考文件**（Julia 內部研究筆記）：本文件（建置系統）、[`docs/STRUCTURE.md`](docs/STRUCTURE.md)、[`docs/IMPLEMENTATION.md`](docs/IMPLEMENTATION.md)、[`contribute.md`](contribute.md)

---

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
