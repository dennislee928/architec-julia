4. CONTRIBUTING.md (官方貢獻指南與 PR 工作流)
向 Julia 核心提交程式碼是一項極具挑戰但充滿成就感的過程。核心維護團隊對程式碼品質、測試覆蓋率與 Git 歷史紀錄的整潔度有著極高的標準。本指南將帶領您了解從本地開發到合併 PR（Pull Request）的完整生命週期。

4.1 開發者原創聲明 (Developer Certificate of Origin, DCO)
與許多大型開源專案（如 Python 需簽署 CLA）不同，Julia 採用較輕量但具備法律效力的 DCO 制度。

您不需要簽署冗長的法律文件。

強制要求：您每一次的 Commit Message 的最後一行，必須包含精確的 Signed-off-by: 簽章。這代表您聲明您具備該段程式碼的著作權，且同意以 MIT 授權條款貢獻給專案。

Git 實務：請使用 git commit -s -m "您的提交訊息"，Git 會自動讀取您的 user.name 與 user.email 附加此標籤。若 PR 缺少此標籤，CI 系統將自動阻擋合併。

4.2 Git 工作流與 Commit 潔癖
Julia 核心對 Git 歷史的乾淨程度有嚴苛要求。

建立特性分支 (Feature Branch)：絕對不要在 master 分支上直接開發。永遠從最新的 master 建立新的分支：git checkout -b fix-gc-memory-leak。

邏輯原子性 (Atomic Commits)：每個 Commit 應該只解決一件事情。不要將不相關的變數更名與核心邏輯修復混在同一個 Commit 中。

Squash 與 Rebase：在您的 PR 被審查的過程中，您可能會根據建議追加許多類似 "fix typo", "update feedback", "fix CI failure" 的微小 Commit。在 PR 最終合併前，維護者會要求您執行互動式重置（Interactive Rebase）：
git rebase -i HEAD~N
將所有零碎的 Commit 壓縮（Squash）成一個或數個具備完整邏輯與詳細說明（包含修復了哪個 Issue、LLVM IR 發生了什麼改變）的 Commit。

4.3 測試驅動貢獻 (Testing Driven Contribution)
任何對 /src 或 /Compiler 的修改，只要沒有被測試覆蓋，就有極高機率在未來的重構中被破壞。

完整測試套件：在提交 PR 前，必須在本地端執行 make testall。這會耗時數十分鐘至數小時不等，它會啟動數百個獨立的 Worker 行程，驗證從線性代數到多執行緒的每一個邊界條件。

子系統針對性測試：
開發過程中，反覆執行 make testall 是不切實際的。您可以針對修改的模組單獨測試：

修改了推斷引擎：執行 make test-compiler

修改了陣列底層：執行 make test-core

修改了標準庫字串：執行 ./julia test/runtests.jl strings

4.4 Nanosoldier 效能基準測試 (Benchmarking)
Julia 是一個以效能為信仰的語言。即使您的程式碼邏輯完全正確，只要它讓執行效能下降了 1%，這個 PR 就不會被接受。

@nanosoldier 的召喚：在 GitHub 的 PR 留言區，具備權限的維護者會輸入 @nanosoldier runbenchmarks("您的分支", "master")。

這會喚醒麻省理工學院（MIT）機房中的一台專用實體伺服器（Nanosoldier），它會拉取您的分支，與主分支分別編譯，然後執行 BaseBenchmarks.jl 中涵蓋數千種運算的效能測試。

數小時後，機器人會回報一份詳細的 HTML 報告。如果報告顯示您的修改導致了效能回歸（Regression），您必須利用 @code_warntype 或 @code_llvm 去尋找型別不穩定或機器碼生成的退化。

4.5 程式碼風格規範 (Coding Standards)
Julia 儲存庫包含多種語言，每種語言都有嚴格的風格規範。

C/C++ 規範：

縮排嚴格使用 4 個空格，絕對禁止使用 Tab。

修改完 /src 的程式碼後，請執行 make format-c++（背後依賴 clang-format）來自動對齊指標、括號與縮排。

變數命名：優先使用 snake_case（與一般 C++ 專案愛用的駝峰式不同），巨集（Macros）使用 UPPER_SNAKE_CASE。

Julia 規範：

遵循社群公認的 BlueStyle 指南。

函數設計應遵循多重分派的精神：將參數型別設定得盡量寬鬆（如 AbstractArray），只在需要特定行為時才限制為具體型別（如 Vector{Int}）。

核心程式碼中應極力避免動態配置。在效能關鍵的迴圈（Hot Loops）中，避免使用會觸發堆積配置的操作，優先使用原地修改（In-place mutations，如結尾帶有 ! 的函數，push!、sort!）。