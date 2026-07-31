# Milestone 17 — 低角度啟動睡眠恢復 Task Register

日期：2026-07-31
狀態：Stage A／B complete。Task 6R3 已完成 repository TDD、local-main integration、final-main verification、production upgrade、crash repair與三階段 acceptance。Installed identity 為 `7bf98ff6ceae`；production loaded／disabled／zero PID、crash clean。Task 6 complete；Task 7 activation與低角度 reboot/loginwindow proof 尚未執行。

## Task register

| Task | Purpose | Primary evidence | Approval | Safe stop / rollback |
| ---: | --- | --- | --- | --- |
| 1 | Startup-closed RED contract — complete | state-machine/coordinator failing tests | repository work approved by Milestone design | abandon worktree; live production unchanged |
| 2 | Shared startup closed state machine — complete | focused GREEN tests and immediate review | none beyond repository implementation | revert Task 2 commit; live production unchanged |
| 3 | Shared composition equivalence — complete | foreground/production integration tests | none beyond repository implementation | revert Task 3 commit |
| 4 | README/runbook/event authority sync — complete | docs/event focused tests | none beyond repository implementation | revert Task 4 commit |
| 5 | Repository holistic release gate — complete | 289 tests in current/clean clone; release/static/package gates; live old identity unchanged | separate approval required for push or production mutation | candidate remains local; current production unchanged |
| 6 | Upgrade and bounded acceptance for new identity — complete | identity `7bf98ff6ceae`; dry-run、enabled-once、recovery-resleep all pass | approved fail-stop batch plus recovery-only retest | loaded/disabled/zero PID, crash count 0 |
| 6R | Repair maintenance bootout resident-process race — complete, integrated and deployed | 93 management tests, 292 full tests, timeout-before-replacement, release/static/package gates, real upgrade retry pass | completed under separate upgrade approval | installed identity `93d9881ecddb`, loaded/disabled/zero PID |
| 6R2 | Repair acceptance clean-exit/bootstrap handoff race — complete, integrated, superseded by 6R3 | 97 management tests, 296 full tests, delayed clean-state wait, timeout no-bootstrap, crash-count preservation, release/static/package gates, ff-only integration | historical recovery authority only | no independent open production scope remains |
| 6R3 | Repair overlapping termination and signal-handler completion race — complete | true double-SIGTERM child RED/GREEN, single bootout authority, 98 management tests, 299 full tests, final package `7bf98ff6ceae`, three-stage production acceptance | repository plus bounded production re-entry approved as one fail-stop batch; recovery-only retest separately approved | loaded/disabled/zero PID; crash count 0; no activate/reboot/push |
| 7 | Persistent activation and low-angle reboot/loginwindow proof | activation, changed boot, pre-login startup sleep, cleanup, baseline | activate/reboot start/manual reboot/finish separately approved | emergency disable/bootout; rollback only with approval |

## Stage gates

### Stage A — Repository behavior — complete

Tasks 1–4 已在 isolated worktree 完成並通過 immediate reviews；沒有改變 `/Library` 或 launchd。

### Stage B — Repository holistic release — complete

Task 5 已通過 current checkout 與 valid clean clone 的 289-test、release、static、package gates；live production 僅做只讀核對。候選 commits 已 fast-forward 整合回本機 `main`。

### Stage C — Production deployment — Task 6 complete, Task 7 open

Final identity `7bf98ff6ceae` 已完成 upgrade、crash-state repair、dry-run、enabled-once與
recovery-resleep。首次 recovery-resleep 人工測試因顯示器亮起後只等待約 20 秒而中止；同一
sleep transaction 的 `pmset` evidence 顯示 `LINE timed out(30000 ms)`，而 15 秒 recovery 是從
`systemHasPoweredOn` 起算。保持低角度至少 60 秒的 recovery-only retest 隨後通過。Activation與
reboot不在 Task 6 批次，仍由 Task 7 獨立治理。

## Completion rule

Milestone 17 只有在 Tasks 1–7、Stage A/B/C reviews、低角度 loginwindow reboot evidence、final
baseline 與 holistic review 全部通過後才算 complete。Repository implementation complete 不等於
production deployment complete。

## Governance findings

Open P0 = 0。
Open P1 without disposition = 0。
