# Milestone 17 — 低角度啟動睡眠恢復 Task Register

日期：2026-07-31
狀態：Stage A／B 與 Tasks 1–5 complete。Task 6R2 deployed identity `99a51a4a2c45` 的 dry-run核心行為通過，但 cleanup因重疊 termination signal留下 `runActive=true`。Task 6R3 已 ff-only 整合至 local main，fresh final-main verification pending；production disabled、job absent、zero PID，所有 acceptance absent。

## Task register

| Task | Purpose | Primary evidence | Approval | Safe stop / rollback |
| ---: | --- | --- | --- | --- |
| 1 | Startup-closed RED contract — complete | state-machine/coordinator failing tests | repository work approved by Milestone design | abandon worktree; live production unchanged |
| 2 | Shared startup closed state machine — complete | focused GREEN tests and immediate review | none beyond repository implementation | revert Task 2 commit; live production unchanged |
| 3 | Shared composition equivalence — complete | foreground/production integration tests | none beyond repository implementation | revert Task 3 commit |
| 4 | README/runbook/event authority sync — complete | docs/event focused tests | none beyond repository implementation | revert Task 4 commit |
| 5 | Repository holistic release gate — complete | 289 tests in current/clean clone; release/static/package gates; live old identity unchanged | separate approval required for push or production mutation | candidate remains local; current production unchanged |
| 6 | Upgrade and bounded acceptance for new identity | upgrade, dry-run, enabled-once, recovery-resleep evidence | each mutation/real-sleep stage separately approved | reviewed rollback package; disabled/nonresident safe stops |
| 6R | Repair maintenance bootout resident-process race — complete, integrated and deployed | 93 management tests, 292 full tests, timeout-before-replacement, release/static/package gates, real upgrade retry pass | completed under separate upgrade approval | installed identity `93d9881ecddb`, loaded/disabled/zero PID |
| 6R2 | Repair acceptance clean-exit/bootstrap handoff race — complete and integrated; final-main verification in progress | 97 management tests, 296 full tests, delayed clean-state wait, timeout no-bootstrap, crash-count preservation, release/static/package gates, ff-only integration | all production mutations remain separately gated | current identity remains loaded/disabled/zero PID; no reset or acceptance rerun |
| 6R3 | Repair overlapping termination and signal-handler completion race — integrated; final-main verification pending | true double-SIGTERM child RED/GREEN, single bootout authority, 98 management tests, 299 full tests, release/static/package gates, ff-only integration | repository plus bounded production re-entry approved as one fail-stop batch | current identity `99a51a4a2c45`, disabled/job absent/zero PID; no acceptance recorded |
| 7 | Persistent activation and low-angle reboot/loginwindow proof | activation, changed boot, pre-login startup sleep, cleanup, baseline | activate/reboot start/manual reboot/finish separately approved | emergency disable/bootout; rollback only with approval |

## Stage gates

### Stage A — Repository behavior — complete

Tasks 1–4 已在 isolated worktree 完成並通過 immediate reviews；沒有改變 `/Library` 或 launchd。

### Stage B — Repository holistic release — complete

Task 5 已通過 current checkout 與 valid clean clone 的 289-test、release、static、package gates；live production 僅做只讀核對。候選 commits 已 fast-forward 整合回本機 `main`。

### Stage C — Production deployment — open

Task 6R3 repository candidate已通過 holistic gates。Local-main integration與 final package verification
後，依已核准 fail-stop batch進行 upgrade、crash-state repair、dry-run、enabled-once與
recovery-resleep。任一階段失敗即停止；activate與reboot不在本批次。

## Completion rule

Milestone 17 只有在 Tasks 1–7、Stage A/B/C reviews、低角度 loginwindow reboot evidence、final
baseline 與 holistic review 全部通過後才算 complete。Repository implementation complete 不等於
production deployment complete。

## Governance findings

Open P0 = 0。
Open P1 without disposition = 0。
