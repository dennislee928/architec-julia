# Lab Results — 六大精實原則的實作與量測 (2026-07-17)

Julia 1.12.6 · Apple Silicon macOS · all measurements in fresh processes.
Baselines from `bench/results/baseline-2026-07-17.md`.

## 1. 避免冷啟動 Front-End Planning — `lab/sysimage/`

PackageCompiler 自訂系統映像（Plots + 使用者旅程 workload 烘焙進 image）：

| Stage | Stock 1.12 | Custom sysimage | Improvement |
|---|---:|---:|---|
| `using Plots` | 5,978 ms | 0.6 ms | ~10,000× |
| first `plot()` | 199 ms | 1.4 ms | ~140× |
| first `savefig` | 893 ms | 644 ms | GR/FileIO 執行期初始化為主，非編譯 |
| **User journey total** | **~7.1 s** | **~0.65 s** | **~11×** |

## 2. 持續整合 First-Run Study — PrecompileTools workload (`lab/LeanDemo/`)

同一份程式碼，套件化 + `@compile_workload` vs. 裸腳本：

| | bare script | package + workload | Improvement |
|---|---:|---:|---|
| first `summarize` call | 106.7 ms | 0.03 ms | ~3,500× |
| first `rolling_mean` call | 29.1 ms | 0.03 ms | ~970× |

## 3. 限制 WIP — `lab/small-binary/` (juliac `--trim`)

| Deployment artifact | Size | Startup |
|---|---:|---:|
| 痛點主張：naive bundle | > 1 GB | — |
| Custom sysimage (含完整 runtime + Plots) | 462 MB | ~ms-load |
| **juliac `--experimental --trim=safe` executable** | **1.1 MB** | **~130 ms** |

Tree-shaking（死碼消除）將部署體積縮小 3 個數量級 — WIP 上限的直接實作。

## 4. 品質左移 Poka-Yoke — `lab/quality-gate/`

- **G1** JET 靜態分析 LeanDemo：0 issues（必要條件）。
- **G2** 閘門自我測試：JET 對反面教材 `unstable_demo.jl` 抓到 2 個問題
  （Union 回傳型別流入具體簽名 → no-matching-method；未型別化全域 → dynamic dispatch）。
- **G3** Aqua 健康檢查：**曾實際攔截本 repo 的真實缺陷**（LeanDemo 的 `[extras]`
  `Test` 缺 compat bound）→ 修復後全綠。防呆機制在開發期就發揮作用的實證。

## 5+6. 漸進驗證 / 禁止 Big-Bang — `lab/ci.sh`

三階段 fail-fast 管線（靜態分析 → 單元測試 → TTFX 預算制回歸），全綠：
`load=0.275s ttfx=0.11ms`（預算 1.5 s / 5 ms）。品質驗證分散於每一階段，
不存在末端一次性驗收。

## Track A — 核心貢獻 (`lab/core-experiment/`)，2026-07-18 更新

- 根因定位：`Compiler/src/inferencestate.jl:1312` 的抽象呼叫點 ×
  `REPL/src/REPLCompletions.jl:535` 的介面擴充 → 編譯器自我無效化
  （最大樹 396 children）。詳見 `TRACKA-DOSSIER.md`。
- 負面實驗結果（`mechanism.jl`）：stock 1.12 執行期無法重現該 backedge —
  漏洞實例源自 sysimage bootstrap 推斷，驗證必須 rebuild core。
- **D1 補丁完成整個迴圈**（patch → rebuild → measure → test）：
  `get_max_methods` 受害者消滅、`InferenceParams` 樹所有殘餘受害者 0 children、
  `make test-compiler` **539,410 全過**（branch
  `avoid-absint-interface-invalidation` @ `2dbb8d9`，DCO 簽章）。
- **雲端獨立驗證**（GHA run #2，ubuntu-latest，stock master，30m42s）：
  `using DataFrames` 無效化 **2,364 methods / 56 trees**；第一名
  `get_inference_world(::REPLInterpreter)` — 同一根因，跨 OS、跨觸發套件成立。

## 定論與下一步

治標在套件層（本檔前五節的 10× 速贏 = 成本搬移/預付）；治本在 core
（無效化重工、二進位膨脹、編譯期保證皆內生於編譯器）。
系統性治本計畫：[`docs/PLAN-TRACK-A.md`](../docs/PLAN-TRACK-A.md)。
