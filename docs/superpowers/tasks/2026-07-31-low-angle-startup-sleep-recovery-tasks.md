# Milestone 17 — 低角度啟動睡眠恢復 Task Register

日期：2026-07-31
狀態：Tasks 1–4 complete；Task 5 repository holistic gate in progress。Tasks 6–7 保留逐步 production approval gates。

## Task register

| Task | Purpose | Primary evidence | Approval | Safe stop / rollback |
| ---: | --- | --- | --- | --- |
| 1 | Startup-closed RED contract — complete | state-machine/coordinator failing tests | repository work approved by Milestone design | abandon worktree; live production unchanged |
| 2 | Shared startup closed state machine — complete | focused GREEN tests and immediate review | none beyond repository implementation | revert Task 2 commit; live production unchanged |
| 3 | Shared composition equivalence — complete | foreground/production integration tests | none beyond repository implementation | revert Task 3 commit |
| 4 | README/runbook/event authority sync — complete | docs/event focused tests | none beyond repository implementation | revert Task 4 commit |
| 5 | Repository holistic release gate | full suite, release, package, clean snapshot, live read-only gate | separate approval required for push or production mutation | candidate remains local; current production unchanged |
| 6 | Upgrade and bounded acceptance for new identity | upgrade, dry-run, enabled-once, recovery-resleep evidence | each mutation/real-sleep stage separately approved | reviewed rollback package; disabled/nonresident safe stops |
| 7 | Persistent activation and low-angle reboot/loginwindow proof | activation, changed boot, pre-login startup sleep, cleanup, baseline | activate/reboot start/manual reboot/finish separately approved | emergency disable/bootout; rollback only with approval |

## Stage gates

### Stage A — Repository behavior

Tasks 1–4。只能在 isolated worktree 修改 source/tests/docs；不得改變 `/Library` 或 launchd。

### Stage B — Repository holistic release

Task 5。Current checkout 與 clean snapshot evidence 都必須通過；live production 只讀核對。

### Stage C — Production deployment

Tasks 6–7。每次 upgrade、真實睡眠、activate、reboot 都是新的批准 gate，不能沿用前一 Task
批准。新 payload identity 必須重新建立全部 acceptance。

## Completion rule

Milestone 17 只有在 Tasks 1–7、Stage A/B/C reviews、低角度 loginwindow reboot evidence、final
baseline 與 holistic review 全部通過後才算 complete。Repository implementation complete 不等於
production deployment complete。

## Governance findings

Open P0 = 0。
Open P1 without disposition = 0。
