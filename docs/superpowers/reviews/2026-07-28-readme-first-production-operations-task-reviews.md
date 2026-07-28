# README 優先的 Production 操作資訊架構 Task Reviews

日期：2026-07-28

## Task 1 — Post-closure 文件治理 authority 補正

### Review

- `6c3f445` 補齊生命週期操作，但缺少獨立 Task／review／closure：確認。
- `5c774a6` 將 runbook 全中文化並更新契約測試，但缺少獨立 Task／review／closure：確認。
- 本 remediation 已建立 Spec、Plan、Task register 與各層 review：通過。
- Scope 僅限 repository 文件與測試：通過。

### Decision

**Task 1 approved.** Open P0 = 0；Open P1 without disposition = 0。

## Task 2 — README 第一入口重構

### RED evidence

新增文件契約後，舊 README 因缺少 `## 目前正式狀態與快速操作` 與 `## 前景診斷與測試工具` 分界而失敗，證明測試可辨識舊資訊架構。

### Implementation review

- README 開頭改為 production 常駐服務定位：通過。
- 正式狀態、日常使用、status／diagnostics／baseline／disable／uninstall 位於前 100 行：通過。
- 完整中文 runbook 連結位於前 100 行：通過。
- 前景診斷細節移至獨立章節：通過。
- 未將 `activate` 描述為一般 enable 捷徑：通過。
- 未修改 runtime 或 production package：通過。

### Finding and re-review

- P2：第一輪文案出現「目前…目前」重複。已修正為「目前這台已驗證的 M1 Pro Mac 已正式安裝並啟用」。Re-review：通過。

### Focused verification

- README 第一入口契約：1 test，0 failures。
- 中文 runbook 契約：1 test，0 failures。
- `bash -n`：pass。
- `shellcheck -x`：pass。
- `git diff --check`：pass。

### Decision

**Task 2 approved.** Open P0 = 0；Open P1 without disposition = 0。
