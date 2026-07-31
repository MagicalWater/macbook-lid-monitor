# Milestone 17 — 低角度啟動睡眠恢復 Task Register

日期：2026-07-31
狀態：Stage A／B 與 Tasks 1–5 complete。Task 6 upgrade 與 deployment-dry-run 已通過；dry-run cleanup 在 disabled bootstrap handoff 中誤增 crash budget。Task 6R2 in progress，enabled-once blocked。Installed production identity 為 `93d9881ecddb`、loaded、disabled、zero PID；dry-run acceptance pass，crash count 1 closed。

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
| 6R2 | Repair acceptance clean-exit/bootstrap handoff race — in progress | delayed clean-state wait, timeout no-bootstrap, crash-count preservation, full repository gates | repository-only execution approved; all production mutations remain separately gated | current identity remains loaded/disabled/zero PID; no reset or acceptance rerun |
| 7 | Persistent activation and low-angle reboot/loginwindow proof | activation, changed boot, pre-login startup sleep, cleanup, baseline | activate/reboot start/manual reboot/finish separately approved | emergency disable/bootout; rollback only with approval |

## Stage gates

### Stage A — Repository behavior — complete

Tasks 1–4 已在 isolated worktree 完成並通過 immediate reviews；沒有改變 `/Library` 或 launchd。

### Stage B — Repository holistic release — complete

Task 5 已通過 current checkout 與 valid clean clone 的 289-test、release、static、package gates；live production 僅做只讀核對。候選 commits 已 fast-forward 整合回本機 `main`。

### Stage C — Production deployment — open

Task 6 upgrade 與 deployment-dry-run 已通過。Dry-run cleanup 因舊 PID clean-exit persistence
尚未完成就 bootstrap disabled daemon，誤增 crash budget。Task 6R2 必須先形成新的 final-main
package；之後 upgrade、reset、dry-run revalidation、enabled-once、recovery-resleep 都是獨立批准
gate，不能沿用既有批准。

## Completion rule

Milestone 17 只有在 Tasks 1–7、Stage A/B/C reviews、低角度 loginwindow reboot evidence、final
baseline 與 holistic review 全部通過後才算 complete。Repository implementation complete 不等於
production deployment complete。

## Governance findings

Open P0 = 0。
Open P1 without disposition = 0。
