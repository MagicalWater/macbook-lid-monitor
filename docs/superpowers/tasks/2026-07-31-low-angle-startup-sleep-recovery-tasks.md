# Milestone 17 — 低角度啟動睡眠恢復 Task Register

日期：2026-07-31
狀態：Stage A／B 與 Tasks 1–5 complete。Task 6 第一次 upgrade 在 payload replacement 前因 maintenance bootout 退出競態安全停止；Task 6R complete 並已 fast-forward 整合到 local main。待 final-main package 重新 prepare/verify 後，Task 6 可重新請求 upgrade 批准。Installed production 為舊 identity、disabled、job absent、zero PID。

## Task register

| Task | Purpose | Primary evidence | Approval | Safe stop / rollback |
| ---: | --- | --- | --- | --- |
| 1 | Startup-closed RED contract — complete | state-machine/coordinator failing tests | repository work approved by Milestone design | abandon worktree; live production unchanged |
| 2 | Shared startup closed state machine — complete | focused GREEN tests and immediate review | none beyond repository implementation | revert Task 2 commit; live production unchanged |
| 3 | Shared composition equivalence — complete | foreground/production integration tests | none beyond repository implementation | revert Task 3 commit |
| 4 | README/runbook/event authority sync — complete | docs/event focused tests | none beyond repository implementation | revert Task 4 commit |
| 5 | Repository holistic release gate — complete | 289 tests in current/clean clone; release/static/package gates; live old identity unchanged | separate approval required for push or production mutation | candidate remains local; current production unchanged |
| 6 | Upgrade and bounded acceptance for new identity | upgrade, dry-run, enabled-once, recovery-resleep evidence | each mutation/real-sleep stage separately approved | reviewed rollback package; disabled/nonresident safe stops |
| 6R | Repair maintenance bootout resident-process race — complete and integrated | 93 management tests, 292 full tests, timeout-before-replacement, release/static/package gates, ff-only integration | new approval required before upgrade retry | old identity remains disabled, booted out, zero PID |
| 7 | Persistent activation and low-angle reboot/loginwindow proof | activation, changed boot, pre-login startup sleep, cleanup, baseline | activate/reboot start/manual reboot/finish separately approved | emergency disable/bootout; rollback only with approval |

## Stage gates

### Stage A — Repository behavior — complete

Tasks 1–4 已在 isolated worktree 完成並通過 immediate reviews；沒有改變 `/Library` 或 launchd。

### Stage B — Repository holistic release — complete

Task 5 已通過 current checkout 與 valid clean clone 的 289-test、release、static、package gates；live production 僅做只讀核對。候選 commits 已 fast-forward 整合回本機 `main`。

### Stage C — Production deployment — open

Task 6 第一次 upgrade 已在 `bootout` 後、payload replacement 前 exit 70。Task 6R 必須先修復
bounded daemon-exit synchronization 並形成新的 final-main package。每次 upgrade、真實睡眠、
activate、reboot 都是新的批准 gate，不能沿用前一批准；新 payload identity 必須重新建立全部
acceptance。

## Completion rule

Milestone 17 只有在 Tasks 1–7、Stage A/B/C reviews、低角度 loginwindow reboot evidence、final
baseline 與 holistic review 全部通過後才算 complete。Repository implementation complete 不等於
production deployment complete。

## Governance findings

Open P0 = 0。
Open P1 without disposition = 0。
