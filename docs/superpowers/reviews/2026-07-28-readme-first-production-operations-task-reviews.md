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

## Task 3 — Holistic review 與 closure

### Closure finding and re-review

- P1：第一次完整 management suite 發現 README 文案修正後不再包含穩定契約片段「目前已正式安裝並啟用」，造成 90 tests 中 1 failure。已改寫為「目前已正式安裝並啟用在這台已驗證的 M1 Pro Mac 上的 production LaunchDaemon」，focused test 與完整 90-test suite 重新執行後通過。
- P2：第一次 live gate 使用 `sudo -n`，因授權快取過期而失敗。該檢查本質為唯讀，改用可公開讀取的 root-owned config、`pgrep` 與 `launchctl print`，不要求 mutation 或新授權。Re-review：通過。

### Holistic review

- README 第一段現在以正式常駐服務為主，而非診斷工具：通過。
- README 前 100 行包含目前部署狀態、日常使用、常用命令、停用、卸載與正式 runbook 連結：通過。
- 前景 CLI 詳細說明保留但下移至獨立章節：通過。
- 正式 runbook 全文為繁體中文，必要命令與固定欄位保留原文：通過。
- `6c3f445` 與 `5c774a6` 的治理缺口已由本 Spec／Plan／Task／review／validation chain 補正：通過。
- Runtime、package 與 live system 未修改：通過。

### Verification

```text
README RED test: failed on old information architecture as expected
README focused GREEN: 1 test, 0 failures
runbook focused: 1 test, 0 failures
ProductionManagementScriptTests final rerun: 90 tests, 0 failures
README first 100 lines gate: pass
bash -n: pass
shellcheck -x: pass
git diff --check: pass
live mode: enabled
live process count: 1
live PID: 283
launchd state: running
```

### Decision

**Task 3 and holistic review approved.** Open P0 = 0；Open P1 without disposition = 0。Post-closure documentation remediation 可正式 closure 並推送。
