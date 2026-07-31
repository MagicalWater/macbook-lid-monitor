# Task 6R — Maintenance bootout bounded-exit recovery Plan Review

日期：2026-07-31

## Task-level Plan review

- RED contract 先於 shell implementation：通過。
- Delayed-exit 與 timeout safe-stop 分別可拒絕：通過。
- Test hook isolation 有獨立 contract：通過。
- Upgrade、rollback、uninstall 共用同一 maintenance boundary：通過。
- Full gate 與 production read-only gate 分離：通過。
- Recovery closure 不自動重試 upgrade：通過。

## Findings

### S17-6R-PLAN-P1-1 — Timeout test 必須證明 acceptance 未被 transaction invalidation

只驗證 binary unchanged 不足以證明 wait 位於正確 transaction boundary。

**Disposition：** RED timeout test 同時保存並比對 manifest、acceptance 與 rollback slot，要求
timeout 發生在 `backup_current_set` 和 `invalidate_deployment_acceptance` 前。Finding closed。

### S17-6R-PLAN-P1-2 — Sandbox test 不可產生 5 秒 wall-clock delay

若 timeout test 真正 sleep 50 次，management suite 會不必要變慢並鼓勵降低 production bound。

**Disposition：** Sandbox 只消耗 deterministic probes，不 sleep；production 才使用 100 ms
interval。Finding closed。

### S17-6R-PLAN-P1-3 — Closure package 必須從 final main 重建

Recovery code 改變 management script 與 source commit，先前 `72a274e6ef29` package 不再是 final
deployment authority。

**Disposition：** Task 6R-3 要求 integration 後從 final main 重新 prepare/verify，並取得新 upgrade
批准。Finding closed。

Open P0 = 0。
Open P1 without disposition = 0。

## Holistic Plan review

Plan 把 incident reproduction、minimal fix、transaction safety、full repository gate 與重新進入
production approval 的 authority 分層。沒有把 repository fix 偷渡為 upgrade approval，也沒有要求
恢復目前已安全停止的 old production service。

## Decision

**Plan and Recovery Task approved.** 可在 isolated worktree 依 TDD 執行；production 必須保持
old identity／disabled／job absent／zero PID。
