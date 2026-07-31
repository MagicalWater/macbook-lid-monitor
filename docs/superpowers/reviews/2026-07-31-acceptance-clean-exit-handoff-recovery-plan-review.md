# Task 6R2 — Acceptance clean-exit handoff recovery Plan Review

日期：2026-07-31
Reviewed document：
`docs/superpowers/plans/2026-07-31-acceptance-clean-exit-handoff-recovery.md`

## Task-level review

### TDD order

- RED tests 明確早於 production script mutation：通過。
- 每個新 helper 都有 delayed、timeout 或 isolation contract：通過。
- Crash-count preservation 是 file-level assertion，不只 source string：通過。
- Failure trap 與 normal success path 都被覆蓋：通過。

### Interface review

- `crash_budget_clean_exit_persisted` return 0/1/65 定義完整：通過。
- `wait_for_crash_budget_clean_exit` 不把 invalid state 誤當 active：通過。
- `ACCEPTANCE_HANDOFF_STATE` 防止 failed EXIT trap 第二次 bootstrap：通過。
- Three Task 13 paths 共用 helper，沒有各自 timing policy：通過。

### Safety review

- Timeout 前已 disabled/booted-out，之後 no bootstrap：通過。
- No reset、no force-kill、no acceptance recording on failure：通過。
- Sandbox hook 不進入 production branch：通過。
- Repository-only plan 沒有 sudo、pmset、activate 或 reboot step：通過。

### Findings

#### 6R2-P-P1-1 — EXIT trap 可能在 normal cleanup failure 後重跑 helper

若沒有 explicit handoff state，success path helper return 70 後 EXIT trap 會再次執行 cleanup，
第二次 probe 可能耗盡 test counter 或遇到狀態變化而 bootstrap。Plan 已要求
`idle/waiting/complete/failed` state，且 waiting/failed trap 永不 bootstrap。Finding closed。

#### 6R2-P-P1-2 — Sandbox 預設沒有 daemon crash-budget persistence

現有 `MLM_TEST_ROOT` launchctl 是 no-op，不能自然重現新 daemon `beginRun()`。Plan 使用兩層
證據：deterministic active-probe contract 鎖定 ordering，file-level bytes assertion鎖定 helper
不改 count，再以 source contract證明 bootstrap 位於 clean gate 之後。Finding closed。

## Holistic review

- Spec 每項 requirement 均有對應 Task/step。
- 沒有未定 interface、模糊 error handling 或缺失 command。
- Task boundaries 分別形成 RED commit、GREEN commit、holistic closure commit。
- Task 6 enabled-once 不會因 repository completion自動解鎖。

## Decision

**Plan approved.** Open P0 = 0；Open P1 without disposition = 0。可依 TDD inline execution
開始 Task 6R2-1；不得觸碰 live production。

