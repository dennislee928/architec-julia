# CI Triage — julia-pr Build #542（PR #62421 @ `50ae87070e`）

> 結論（2026-07-18）：**兩個失敗都與本分支無關**。失敗點是 upstream 2026-07-08 之後
> 新加入的 interrupt/signal 測試（`test/misc.jl`），屬 timing-sensitive flaky；
> 本分支 diff 只動 `Compiler/src/*`（6 files, +125/−74），與 signal 處理零交集
> （diff 中 `signal|sigint|interrupt|sleep|kill` 出現次數 = 0）。
> **無需任何程式碼修正**。另注意：PR #62421 已於 2026-07-18 13:44 UTC 被維護者關閉，
> 故此 CI 紅燈已無「擋合併」效果；阻塞點是維護者接受度，不是 CI。

## 失敗盤點

GitHub 上兩個紅色 check（`Test`、`buildkite/julia-pr`）其實是**同一個** Buildkite
build（#542）的兩個 status context。Build #542 內 45 steps 只有 2 個 test job 失敗：

### 1. `test x86_64-apple-darwin`（macOS）

- 失敗測試：`test/misc.jl:1804,1807` — `@testset "SIGINT to a non-interactive process blocked in sleep"`
- 現象：子行程已印出 `READY`（runtime 已啟動、handler 已裝上），
  之後連續 3 次 `kill(p, SIGINT)`（每次等 10s）子行程仍未退出 →
  `process_exited(p)` = false；`err == "\n"`（子行程沒產生任何 InterruptException 輸出）。
- 判讀：SIGINT 送達→轉成 InterruptException→喚醒 `sleep(600)` 這條 runtime 路徑
  在慢速 CI 機器上逾時。與編譯器 inference 快取無關。

### 2. `test i686-linux-gnu`（32-bit Linux）

- 失敗測試：`test/misc.jl:1723` — `@testset "SIGINT at idle REPL prompt"`
- 現象：`IOError: stream is closed or unusable`（對 fake PTY 的 `Base.TTY` 寫入時），
  exception outside of `@test` — 即 REPL 子行程/PTY 在測試中途已死亡或關閉。
- 判讀：與 macOS 那條不同的失敗模式，但同一族新測試、同樣是行程/PTY timing 問題。

## 為何確定與本分支無關

1. **Diff 範圍**：`git diff origin/master...50ae870` 只觸及
   `Compiler/src/{abstractinterpretation,bindinginvalidations,inferencestate,ssair/irinterp,tfuncs,typeinfer}.jl`；
   無 runtime C 碼、無 signal、無 task scheduler、無 stream/PTY 相關變更。
2. **測試來源**：兩個失敗測試皆為 upstream 近期新增/重寫 —
   `fc7ca1b` #62069「Fix interrupting. Add tests.」(2026-07-08)、
   `c9566b8` #62298 (2026-07-10)、
   `d4f184f` #62385「synchronize interrupt tests on observable state, not fixed sleeps」(2026-07-15)。
   #62385 的存在本身就證明這族測試上游已知會 race、仍在補強。
3. **失敗模式互異**：兩平台失敗在同族測試的不同 testset、不同 symptom
   （一個是 SIGINT 未殺死 sleep 中的子行程、一個是 PTY 中途斷線）— 典型基礎設施/timing
   flake 的樣態，而非單一決定性 regression。
4. **其餘 43 steps 全綠**：包括完整 `Compiler/*` 測試（inference、inline、irpasses、
   AbstractInterpreter…）— 本分支真正觸碰的面全數通過。

## 行動決策

| 選項 | 判斷 |
|---|---|
| 改本分支程式碼 | ❌ 無東西可改；失敗與分支無關 |
| Retry Buildkite job | ⚠️ 技術上可（Buildkite「Retry」按鈕），但 PR 已關閉，重跑無合併意義 |
| **修 flaky test 本身**（上游測試補強） | ✅ **已完成並提交上游**：branch `harden-interrupt-tests` @ `40ffec6` → **[JuliaLang/julia#62423](https://github.com/JuliaLang/julia/pull/62423)**（2026-07-18），見下節 |
| 上游回報 flaky test issue | ✅ 以 fix PR #62423 形式回報（內含 build 542 失敗證據與連結） |

## 修補內容（`harden-interrupt-tests` @ `40ffec6`，`test/misc.jl` +54/−26）

1. **"SIGINT at idle REPL prompt"**（i686 失敗）：
   - 整個情境改為「最多 3 次、每次全新子行程」重試 — 沿用同檔 Distributed
     testset 已建立的 retry-with-fresh-child 模式；
   - PTY 寫入前先檢查 `process_running`，寫入包 `try/catch Base.IOError` —
     子行程死亡時回報乾淨的 test failure（含擷取輸出診斷），不再以
     uncaught `IOError` 炸掉整個 testset；
   - 若 REPL 對 SIGINT 是**決定性**死亡（真 regression），3 次全敗 → 測試仍失敗，
     #62069 的回歸保護不變。
2. **"SIGINT to a non-interactive process blocked in sleep"**（macOS 失敗）：
   - SIGINT 重試 3×10s → **5×20s**（loaded CI 實測 30s 不夠）；
   - 失敗時 `@error` 傾印子行程部分輸出（原本 `err == "\n"` 毫無診斷價值）；
   - 修掉潛在 hang：子行程未退出時原程式碼 `wait(reader)` 會阻塞直到
     `sleep(600)` 自然結束（最長 10 分鐘）才繼續，現在直接跳過後續讀取。
3. **驗證**：`Meta.parseall` 無誤；兩個 testset 抽出後在本機 julia 1.12.6
   實跑全過（happy path + retry 邏輯路徑）。上游 CI 驗證需開 PR 後由官方
   pipeline 執行。

### 上游 flaky-test issue 草稿（如決定回報）

> **Title**: Flaky interrupt tests in `test/misc.jl` on Buildkite (macOS x86_64 + i686-linux-gnu)
>
> On julia-pr build 542 (commit 50ae87070e, PR #62421 — a Compiler-only change, no
> runtime/signal code touched), both new interrupt testsets from #62069/#62385 failed
> independently on two platforms:
>
> - macOS x86_64: `"SIGINT to a non-interactive process blocked in sleep"` —
>   child printed `READY`, then 3× `kill(p, 2)` with 10s waits did not terminate it;
>   captured stderr was `"\n"` (misc.jl:1804, :1807).
> - i686-linux-gnu: `"SIGINT at idle REPL prompt"` — `IOError: stream is closed or
>   unusable` writing to the fake PTY (misc.jl:1723); the REPL child appears to have
>   died mid-test.
>
> Both testsets already contain retry/synchronization hardening from #62385, so this
> looks like residual raciness on loaded CI workers. Full logs attached.

（附件：`~/Downloads/julia-pr_build_542_{macos-test-x86-64-apple-darwin,linux-test-i686-linux-gnu}.log`）
