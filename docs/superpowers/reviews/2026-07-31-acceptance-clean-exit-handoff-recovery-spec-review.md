# Task 6R2 — Acceptance clean-exit handoff recovery Spec Review

日期：2026-07-31
Reviewed document：
`docs/superpowers/specs/2026-07-31-acceptance-clean-exit-handoff-recovery-design.md`

## Task-level review

### Root-cause trace

Production evidence 將誤增的 timestamp 鎖定在 dry-run PID 收到 SIGTERM 與 disabled PID 啟動
的同一秒。Swift authority 顯示 clean exit 由 signal handler 中的
`ProductionDaemonSession.stop()` 寫入，而新 daemon 的 `beginRun()` 會把仍 active 的舊 run
計入 unexpected exit。Root cause 與 proposed boundary 一致。

### Scope review

- 只修 Task 13 bounded deployment acceptance cleanup：通過。
- 不 reset production crash budget：通過。
- 不修改 crash-budget Swift model：通過。
- 不把歷史 Task 12／Task 17 重構混入 Recovery Task：通過。
- Production 全程 repository-only/read-only：通過。

### Safety review

- No fixed sleep as completion proof：通過。
- No SIGKILL／force termination：通過。
- PID exit 與 clean-exit persistence 均有 bounded gate：通過。
- Timeout 不 bootstrap、不 record acceptance：通過。
- EXIT trap 不會在 failed handoff 後第二次 bootstrap：通過。
- Test hook 限制於 `MLM_TEST_ROOT`：通過。

### Testability review

- Delayed clean exit 有 deterministic probe contract：通過。
- Timeout 可在 sandbox 無 wall-clock delay重現：通過。
- Crash count preservation 有 file-level assertion：通過。
- Success／failure trap／three Task 13 call sites 皆有 coverage：通過。
- Existing Task 6R resident wait regression 被納入：通過。

### Findings

#### 6R2-S-P1-1 — 「zero PID timeout」不能與「不強殺」同時無條件保證

若 resident PID 本身超過 bounded deadline，管理腳本在禁止 SIGKILL 的前提下不能立即保證
zero PID。Spec 已將兩種 timeout 分開：resident timeout 保留 residual-process evidence；
clean-state timeout 發生時 PID 已退出，因此可保證 zero PID。Finding closed。

#### 6R2-S-P1-2 — 只等 PID 不足以提供 direct clean-state evidence

Process exit 正常代表 Swift clean-exit write 已返回，但 corrupt/missing state 仍可能被忽略。
Spec 選擇在 PID wait 後直接驗證 `runActive=false`，並拒絕 unavailable/corrupt state。Finding
closed。

## Holistic review

- Design 與 Milestone 17 的 fail-open、bounded、separate-approval 原則一致。
- 不會讓 repository-only Recovery Task 自動重跑已通過的 dry-run acceptance。
- Task 6 第四階段在 6R2 repository/deployment closure 前維持 blocked。
- Placeholder scan clean；沒有模糊 timeout 或未處置 P1。

## Decision

**Spec approved.** 使用者已以原文核准建立並執行 Task 6R2；本 written spec 是該批准的
formalization，不新增 production mutation authority。Open P0 = 0；Open P1 without
disposition = 0。可進入 Implementation Plan。

