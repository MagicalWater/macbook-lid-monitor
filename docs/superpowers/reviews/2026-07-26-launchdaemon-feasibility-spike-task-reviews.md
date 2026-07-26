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
