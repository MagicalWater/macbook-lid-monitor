# Milestone 17 — 低角度啟動睡眠恢復 Task Reviews

日期：2026-07-31

## Task 1 — Startup-closed RED contract

### Baseline

```text
LidSleepStateMachineTests: 15 tests, 0 failures
LidSleepCoordinatorTests: 12 tests, 0 failures
live production mutation: none
```

### RED contract

State-machine tests要求：

- fresh closed startup 建立 `startupClosedCandidate`；
- deadline 只 request sleep 一次；
- hysteresis、invalid、stale data fail-open；
- reopen 取消 candidate 並進入 open。

Coordinator tests要求：

- startup cooldown 後沿用 close debounce task；
- 穩定輸出 startup candidate transitions；
- requester exactly once；
- hysteresis cancellation disarms。

### Review status

### RED execution evidence

```text
swift test --filter LidSleepStateMachineTests: failed as expected
missing API: LidSleepState.startupClosedCandidate(deadline:)

swift test --filter LidSleepCoordinatorTests: failed as expected
missing events:
- startupClosedCandidateStarted
- startupClosedCandidateCancelled
- startupClosedDebounceElapsed

unrelated failure: none
live production mutation: none
```

### Decision

**Task 1 RED approved.** 測試直接鎖定已確認根因，沒有以 mock composition 或文件字串取代
state-machine behavior。Open P0 = 0；Open P1 without disposition = 0。可進入 Task 2 GREEN。
