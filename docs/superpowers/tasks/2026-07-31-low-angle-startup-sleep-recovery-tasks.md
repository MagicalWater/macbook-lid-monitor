# Milestone 17 — 低角度啟動睡眠恢復 Task Register

日期：2026-07-31
狀態：Stage A／B complete。Task 6R3 已完成 repository TDD、local-main integration、final-main verification、production upgrade、crash repair與三階段 acceptance。Installed identity 為 `7bf98ff6ceae`。Task 7 Steps 1–4 已完成；changed boot、pre-login observer、新 PID `281`、低角度 startup sleep、baseline 與 temporary cleanup 均已驗證。Production enabled／loaded／single PID、monitoring-armed、crash clean。僅 Step 5 holistic closure 尚未執行。

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
| 7 | Persistent activation and low-angle reboot/loginwindow proof — Steps 1–4 complete, Step 5 open | prepared boot/PID `1785457249`/`99898`; new boot/PID `1785491605`/`281`; pre-login=true; startup candidate、debounce、one sleep request、wake/rearm、baseline、artifact cleanup verified | activate、reboot preparation、manual reboot、finish completed; holistic closure remains open | production remains enabled/single PID; emergency disable/bootout only with approval |

## Stage gates

### Stage A — Repository behavior — complete

Tasks 1–4 已在 isolated worktree 完成並通過 immediate reviews；沒有改變 `/Library` 或 launchd。

### Stage B — Repository holistic release — complete

Task 5 已通過 current checkout 與 valid clean clone 的 289-test、release、static、package gates；live production 僅做只讀核對。候選 commits 已 fast-forward 整合回本機 `main`。

### Stage C — Production deployment — Task 6 complete, Task 7 Steps 1–4 complete

Final identity `7bf98ff6ceae` 已完成 upgrade、crash-state repair、dry-run、enabled-once與
recovery-resleep。首次 recovery-resleep 人工測試因顯示器亮起後只等待約 20 秒而中止；同一
sleep transaction 的 `pmset` evidence 顯示 `LINE timed out(30000 ms)`，而 15 秒 recovery 是從
`systemHasPoweredOn` 起算。保持低角度至少 60 秒的 recovery-only retest 隨後通過。

Task 7 Step 1 已在完整 matching acceptance 下執行 evidence-gated `activate`。PID `99898` 完成
startup cooldown 後進入 `monitoring-armed`，`operational_baseline=pass`；最終 production 為
enabled／loaded／single PID、crash count 0。Step 2 隨後以 boot epoch `1785457249` 與 prepared
PID `99898` 建立 root-owned one-shot reboot observer；目前 observer loaded／not running、runs=1、
last exit code 0。Step 3 隨後由使用者手動 reboot 並在低角度停留 loginwindow。新 boot epoch
為 `1785491605`，production PID 為 `281`；新 PID 在 startup cooldown 後進入
`startup-closed-candidate`，完成 debounce 並發出 exactly one sleep request。17:54:05 wake 後
同一 PID 回到 `monitoring-armed`。Observer evidence 在新 boot 更新，但其受保護的 pre-login
console user、identity 與 PID 欄位已由 Step 4 root verifier 正式驗證：boot-changed=true、
pre-login=true、new PID `281`、完整 acceptance 與 `operational_baseline=pass`。只有全部驗證通過
後才清理 temporary reboot state、observer evidence、observer executable、observer plist 與
observer launchd job；cleanup 後 artifact count 0，production 仍 enabled／loaded／single PID、
crash count 0。Milestone holistic closure 仍由 Step 5 獨立治理。

## Completion rule

Milestone 17 只有在 Tasks 1–7、Stage A/B/C reviews、低角度 loginwindow reboot evidence、final
baseline 與 holistic review 全部通過後才算 complete。Repository implementation complete 不等於
production deployment complete。

## Governance findings

Open P0 = 0。
Open P1 without disposition = 0。
