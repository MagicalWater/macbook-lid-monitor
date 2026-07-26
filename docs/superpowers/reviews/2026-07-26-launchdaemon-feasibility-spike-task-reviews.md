# LaunchDaemon Feasibility Spike Task Reviews

## Task 1 — Extract the Shared Core and Preserve the Existing CLI

### Implementation review

Reviewed the SwiftPM target split, the new library boundary, the three executable wrappers, all test imports, and the release CLI behavior.

### Findings

#### P2-1 — Duplicate module suffix during mechanical import migration

The RED test had already been changed to `LidMonitorCore`; the later bulk replacement transformed that one import into `LidMonitorCoreCore`, causing the first GREEN compile to fail.

**Resolution:** Corrected the import at its source and scanned all tests for the obsolete module name and duplicate suffix. The full clean test and release build then passed.

### Re-review

- Existing policy values, thresholds, state-machine transitions, scheduler behavior, and sleep-request behavior are unchanged.
- Reusable code exists only in `LidMonitorCore`; the three executable targets contain only tiny process wrappers.
- The only public declarations are the explicit executable entry-point enums required across the module boundary.
- The existing CLI still requires the accepted explicit `--auto-sleep --execute-sleep` pair before constructing the real system sleep path.
- The daemon-spike and sleep-probe placeholders return unavailable and perform no HID, power-notification, or sleep operation.
- `macbook-lid-monitor --list` still enumerates the verified M1 Pro sensor and exits successfully.

### Validation

```text
swift package clean: passed
swift test: 80 tests, 0 failures
swift build -c release: passed
macbook-lid-monitor --list: passed
all three executable products: built
git diff --check: passed
```

### Disposition

- Open P0: 0
- Open P1: 0
- Open P2: 0
- Task 1: Pass

## Task 2 — Add an Injectable IOKit System Power Observer

### Implementation review

Reviewed message mapping, acknowledgement ordering, registration ownership, callback context lifetime, dedicated run-loop shutdown, idempotent cleanup, wake adaptation, coordinator error propagation, and binary linkage.

### Findings

#### P1-1 — Registration handoff captured a mutable local in a Sendable callback

The first GREEN implementation attempted to let the notification callback read a local registration variable while that variable was still being assigned. Swift 6 correctly rejected the concurrently captured mutable state, and an immediate native callback could also have observed an incomplete handoff.

**Resolution:** Added a synchronized `SystemPowerRegistrationHolder`. Native notification delivery waits for the completed registration handoff, after which every callback reads one immutable registration containing the root power port required for acknowledgement.

#### P2-1 — Test event arrays were not concurrency-safe

The first test compile used local arrays mutated by `@Sendable` callbacks.

**Resolution:** Replaced them with a lock-protected test value collector. Production concurrency checks remain fully enabled.

### Re-review

- `canSystemSleep` and `systemWillSleep` call `IOAllowPowerChange` before forwarding their events.
- `systemWillPowerOn` is observable but cannot start coordinator wake recovery.
- Only `systemHasPoweredOn` reaches `SystemWakeObserving.onWake`.
- Unknown power messages are ignored.
- Registration, stop, and deinitialization are idempotent and perform cleanup once.
- Native registration owns the callback box for the full run-loop lifetime.
- Cleanup removes the source, deregisters the notification object, closes the root port, destroys the notification port, and stops the dedicated run loop.
- Registration errors now propagate through `SystemWakeObserving.start`, allowing coordinator startup to fail open instead of silently losing wake monitoring.
- All `NSWorkspace` and AppKit source/link dependencies have been removed from the package.
- No sleep request is made by the observer or its tests.

### Validation

```text
IOKitSystemPowerObserverTests: 7 passed
LidSleepCoordinatorTests: 12 passed
swift test: 87 tests, 0 failures
swift build -c release: passed
daemon spike AppKit linkage: absent
git diff --check: passed
```

### Disposition

- Open P0: 0
- Open P1: 0
- Open P2: 0
- Task 2: Pass
