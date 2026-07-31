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

## Task 2 — Shared startup closed state machine

### Plan coverage finding

#### S17-T2-P1-1 — Transition enum 的兩個 output switch 未列入 Plan

新增 `AutoSleepTransitionEvent` 會同時影響前景 `OutputFormatter` 與 production
`ProductionDaemonApplication` 的 exhaustive switch。原 Task 2 files 只列 state machine、
coordinator 與 enum owner，會留下未受行為測試保護的 output mapping。

**Disposition：** Task 2 files 已補入 `OutputFormatter.swift`、
`ProductionDaemonApplication.swift`、`OutputFormatterTests.swift` 與
`ProductionDaemonCompositionTests.swift`。先加入 formatter 與 production transition RED
assertions，再實作 enum 與 mapping。Finding closed。

### Additional RED evidence

```text
OutputFormatterTests: failed as expected
missing events:
- startupClosedCandidateStarted
- startupClosedCandidateCancelled
- startupClosedDebounceElapsed

Production startup transition test: failed at the same missing enum contract
unrelated failure: none
```

### GREEN verification

```text
LidSleepStateMachineTests: 22 tests, 0 failures
LidSleepCoordinatorTests: 14 tests, 0 failures
OutputFormatterTests: 7 tests, 0 failures
Production startup transition focused test: 1 test, 0 failures
AutoSleepIntegrationTests regression suite: 9 tests, 0 failures
```

### Immediate review

- `startupClosedCandidate` 與一般 `closingCandidate` 分離：通過。
- Startup hysteresis cancellation 回到 disarmed，不會誤報 open：通過。
- `>=reopenThreshold` cancellation 取消 debounce 並 rearm：通過。
- Missing、stale、invalid data 不會 request sleep：通過。
- Startup deadline 只 request sleep 一次：通過。
- Coordinator 沿用既有 `closeDebounceTask`；未新增第四個 timer：通過。
- Wake、stop、invalid data 可取消 pending debounce：通過。
- Sleep request failure 維持 disarmed/no automatic retry：通過。
- 前景 formatter 與 production event names 皆有 executable contract：通過。
- Live production mutation：none。

### Decision

**Task 2 approved.** Open P0 = 0；Open P1 without disposition = 0。可進入 Task 3
composition equivalence verification。
