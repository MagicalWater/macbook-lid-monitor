# Task 6R — Maintenance bootout bounded-exit recovery Spec Review

日期：2026-07-31

## Task-level review

- Incident、exit code 與 safe-stop evidence 可重現且一致：通過。
- Root cause 位於 `bootout` 返回與 PID 真正退出間的競態：通過。
- 選擇 bounded condition polling，而非固定 sleep 或強殺：通過。
- Timeout 位於 backup／invalidation／payload replacement 前：通過。
- Production 最終狀態與 Task 6 approval boundary 未被擴張：通過。

## Findings

### S17-6R-SPEC-P1-1 — Test hook 不得影響真實 production probe

若 deterministic resident-process hook 可在真實 root path 生效，就可能偽造 zero-PID safe
condition。

**Disposition：** Spec 要求 hook 只在 `MLM_TEST_ROOT` 非空時生效；production path 永遠使用
精確 `pgrep`。Finding closed。

### S17-6R-SPEC-P1-2 — Timeout 必須早於 acceptance invalidation

若先使 acceptance 失效或建立 rollback slot，再等待 resident process，正常退出延遲就會造成
不必要的 transaction side effect。

**Disposition：** Bounded wait 保持在 `prepare_maintenance_disabled_state` 內，且該 function
先於 backup、invalidation 與 activation。Finding closed。

### S17-6R-SPEC-P1-3 — Timeout 不可轉為 SIGKILL fallback

強殺會隱藏 daemon shutdown failure，並擴大 maintenance authority。

**Disposition：** Spec 明確要求 timeout return 70、維持 disabled／booted-out，不送額外 signal。
Finding closed。

Open P0 = 0。
Open P1 without disposition = 0。

## Holistic review

設計只修補已證實的 process-exit synchronization gap，不更改 payload identity、launchd label、
sleep policy 或 acceptance semantics。成功路徑允許短暫正常退出延遲，失敗路徑仍有時間上限且
在 destructive transaction boundary 前停止。

## Decision

**Spec approved.** 可建立 TDD implementation plan；production upgrade 仍被 Task 6R closure 與
新的明確批准阻擋。
