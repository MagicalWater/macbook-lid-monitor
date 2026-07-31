# Task 6R3 Graceful Shutdown Single-Authority Recovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate the acceptance cleanup double-termination race, prove repeated real signals cannot interrupt graceful completion, and safely re-enter bounded production acceptance.

**Architecture:** `ProcessSignalController` owns signal completion and ignores repeated SIGTERM/SIGINT until its handler returns. `manage-production-daemon.sh` uses one launchd termination authority (`bootout`) before bounded PID and crash-state waits. Production re-entry is serial and fail-stop.

**Tech Stack:** Swift 6 / Foundation / Darwin / Dispatch, independent xctest subprocess, Bash, launchd, SwiftPM.

## Global Constraints

- Base commit is `99a51a4a2c454edce1344ce5f3e040a0cc2b3a0f`.
- Production begins installed at `99a51a4a2c45`, disabled, job absent, zero PID, crash `runActive=true`.
- No production mutation before repository holistic review, local-main integration, and final package verification.
- No SIGKILL, `kill -9`, unbounded waits, activate, reboot, or push.
- Any production acceptance failure stops the batch immediately and leaves disabled safe state.

---

### Task 1: True repeated-signal contract

**Files:**
- Modify: `Tests/LidMonitorTests/ProcessSignalControllerTests.swift`
- Modify: `Sources/LidMonitorCore/ProcessSignalController.swift`

**Interfaces:**
- Consumes: `ProcessSignalController.start(onSignal:)`, `Process`, `xcrun xctest`, POSIX `kill`.
- Produces: repeated SIGTERM completion guarantee; no public API change.

- [x] **Step 1: Write the failing independent-child test**

Add a child-only test that runs when `MLM_SIGNAL_PROBE_CHILD=1`, writes `ready`／`entered`／`completed`
marker files, and blocks in the handler completion window. Add parent test
`testSecondRealSIGTERMDuringHandlerDoesNotTerminateChild()` that launches:

```swift
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
process.arguments = ["xctest", "-XCTest", childName, Bundle(for: Self.self).bundleURL.path]
process.environment = childEnvironment
try process.run()
waitForMarker("ready")
kill(process.processIdentifier, SIGTERM)
waitForMarker("entered")
kill(process.processIdentifier, SIGTERM)
process.waitUntilExit()
XCTAssertEqual(process.terminationReason, .exit)
XCTAssertEqual(process.terminationStatus, 0)
XCTAssertTrue(markerExists("completed"))
```

- [x] **Step 2: Run RED**

Run:

```bash
swift test --filter ProcessSignalControllerTests.testSecondRealSIGTERMDuringHandlerDoesNotTerminateChild
```

Expected: FAIL because child xctest terminates by SIGTERM before normal exit.

- [x] **Step 3: Implement the minimal signal completion guard**

In `ProcessSignalController.finish(invokeHandler:)`, after ownership is acquired:

```swift
signal(SIGTERM, SIG_IGN)
signal(SIGINT, SIG_IGN)
resources.source?.cancel()
resources.handler?()
signal(SIGTERM, SIG_DFL)
signal(SIGINT, SIG_DFL)
```

Keep handler synchronous; do not add retries, queues, or new public state.

- [x] **Step 4: Run focused GREEN and existing signal tests**

```bash
swift test --filter ProcessSignalControllerTests
```

Expected: all tests pass, independent child exits 0.

- [x] **Step 5: Immediate review and commit**

Verify repeated signals are ignored only during owned completion and defaults are restored afterward.

```bash
git add Tests/LidMonitorTests/ProcessSignalControllerTests.swift Sources/LidMonitorCore/ProcessSignalController.swift
git commit -m "fix: guard graceful signal completion"
```

---

### Task 2: Acceptance management single authority

**Files:**
- Modify: `Tests/LidMonitorTests/ProductionManagementScriptTests.swift`
- Modify: `scripts/manage-production-daemon.sh`

**Interfaces:**
- Consumes: `bootout_job`, `wait_for_managed_daemon_exit`, `wait_for_crash_budget_clean_exit`.
- Produces: `restore_disabled_job_after_acceptance` and EXIT trap with exactly one termination authority.

- [x] **Step 1: Write RED source and sandbox contracts**

Add tests asserting:

```text
restore_disabled_job_after_acceptance:
set_managed_mode disabled
→ bootout_job
→ wait_for_managed_daemon_exit
→ wait_for_crash_budget_clean_exit
→ bootstrap_job
```

The function body must not contain `stop_job`. The `waiting|failed` EXIT branch must use `bootout_job`
without `stop_job` or `bootstrap_job`.

- [x] **Step 2: Run RED**

```bash
swift test --filter ProductionManagementScriptTests.testAcceptanceCleanupUsesSingleBootoutAuthority
```

Expected: FAIL because current helper calls `stop_job` before `bootout_job`.

- [x] **Step 3: Implement minimal management change**

Remove `stop_job` from the normal handoff and failed trap branch. Preserve mode change, bootout, both bounded waits, bootstrap ordering, return codes, and output contracts.

- [x] **Step 4: Run focused GREEN and regression groups**

```bash
swift test --filter ProductionManagementScriptTests.testAcceptanceCleanupUsesSingleBootoutAuthority
swift test --filter ProductionManagementScriptTests.testTask13
swift test --filter ProductionManagementScriptTests.testBoundedDeployment
swift test --filter ProductionManagementScriptTests.testDeploymentDryRunCleanExitTimeout
```

Expected: all pass.

- [x] **Step 5: Static review and commit**

```bash
bash -n scripts/manage-production-daemon.sh
shellcheck -x scripts/manage-production-daemon.sh scripts/lib/*.sh
git diff --check
git add Tests/LidMonitorTests/ProductionManagementScriptTests.swift scripts/manage-production-daemon.sh
git commit -m "fix: use one acceptance shutdown authority"
```

---

### Task 3: Holistic repository closure and integration

**Files:**
- Modify: `docs/superpowers/plans/2026-07-31-low-angle-startup-sleep-recovery.md`
- Modify: `docs/superpowers/tasks/2026-07-31-low-angle-startup-sleep-recovery-tasks.md`
- Modify: `docs/superpowers/reviews/2026-07-31-low-angle-startup-sleep-recovery-task-reviews.md`
- Create: `docs/validation/2026-07-31-graceful-shutdown-single-authority-recovery.md`

**Interfaces:**
- Consumes: Task 1/2 commits and verification evidence.
- Produces: approved local-main candidate and exact production re-entry identity.

- [x] **Step 1: Run repository gates**

```bash
swift test --filter ProductionManagementScriptTests
swift test
swift build -c release --product macbook-lid-monitor
swift build -c release --product macbook-lid-monitor-daemon
bash -n scripts/manage-production-daemon.sh scripts/lib/*.sh
shellcheck -x scripts/manage-production-daemon.sh scripts/lib/*.sh
./scripts/manage-production-daemon.sh prepare
./scripts/manage-production-daemon.sh verify
git diff --check
```

- [x] **Step 2: Record holistic evidence and commit closure**

Document RED/GREEN, independent true-signal child status, single-authority ordering, suite counts, package identity,
and unchanged live production state.

```bash
git add docs/superpowers docs/validation
git commit -m "docs: close graceful shutdown recovery"
```

- [x] **Step 3: Fast-forward local main only**

Require main still clean and exactly based on `99a51a4`; use `git merge --ff-only`. Do not push.

- [x] **Step 4: Fresh final-main verification**

Rerun full Swift suite, release/static checks, package prepare/verify from the integrated main tree.

---

### Task 4: Production deployment, crash repair, and bounded acceptance batch

**Files:**
- No repository source mutation after final-main package verification.
- Record production evidence in the existing validation/review authority only after all stages finish.

**Interfaces:**
- Consumes: final-main verified package.
- Produces: installed fixed identity and identity-bound dry-run/enabled-once/recovery-resleep acceptance.

- [x] **Step 1: Deploy fixed package**

Run visible Terminal `sudo ./scripts/manage-production-daemon.sh upgrade`. Verify loaded／disabled／zero PID.

- [x] **Step 2: Repair crash state**

Run explicit `sudo ./scripts/manage-production-daemon.sh reset-crash-budget` only while mode disabled and
zero PID. Verify count 0, circuit closed, runActive false or missing clean state before next start.

- [x] **Step 3: Run serial acceptance batch**

Run in order:

```text
deployment-dry-run
deployment-enabled-once
deployment-recovery-resleep
```

After each stage require matching acceptance plus loaded／disabled／zero PID and crash count 0. Any failure
stops immediately; no later stage runs.

- [x] **Step 4: Final verification**

Verify complete three-stage acceptance, rollback integrity, repository clean, no activation/reboot/push.


## Production closure note

Final local-main package identity:

```text
source commit: 7bf98ff6ceae710757b38b14efa00d42c34ca573
version: 7bf98ff6ceae
binary SHA-256: 6b30459a2168d0f409cc45e4cd152a3b535a85566347e7bc273b58109e2c6ee3
```

The first recovery-resleep attempt was manually stopped after the display had been on for about 20
seconds. `pmset` showed `LINE timed out(30000 ms)`: the display became interactive before IOKit delivered
`systemHasPoweredOn`. The 15-second recovery interval is intentionally measured from
`systemHasPoweredOn`, not display-on. No runtime policy change was approved or implemented.

A recovery-only retest kept the lid at approximately 45–55 degrees for at least 60 seconds. PID `64966`
emitted two sleep requests, one `recovery-resleep`, two wake observations and retained PID continuity.
All three deployment acceptance stages now match the installed identity. Final state is
loaded／disabled／zero PID with crash count 0; activate、reboot and push were not executed.
