# Angle-Authoritative Re-Sleep Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make fresh lid-angle data authoritative after every wake, re-sleep after a fifteen-second closed-lid recovery window, and expose failed macOS sleep requests without introducing polling or a retry loop.

**Architecture:** Split startup safety from post-wake recovery in `LidSleepPolicy` and `LidSleepStateMachine`. Keep all timing event-driven through three one-shot scheduler tasks owned by `LidSleepCoordinator`; catch `SleepRequesting` errors once, emit a stable operational error, and transition to `disarmed`. Preserve the explicit foreground dry-run/execute-sleep composition boundary.

**Tech Stack:** Swift 6, Swift Package Manager, XCTest, Foundation, Dispatch, AppKit `NSWorkspace`, IOKit power management.

## Global Constraints

- Calibrated thresholds remain `sleep <=68` and `reopen >=75`.
- Default close debounce is exactly `2` seconds.
- Default startup cooldown is exactly `5` seconds.
- Default post-wake recovery is exactly `15` seconds.
- `69...74` is not reopened; it is closed-cycle hysteresis.
- Only fresh valid reports received after wake may authorize recovery re-sleep.
- Missing or invalid fresh recovery data fails open and must not request sleep.
- Every sleep request is caused by one state transition; no polling or repeating timer.
- A failed sleep request is logged once, is not retried automatically, and enters `disarmed` until `>=75`.
- `--wake-cooldown` is rejected with migration guidance.
- No LaunchAgent, daemon, login item, persistent preference, power-setting mutation, HID write, administrator privilege, or UI is added.
- Every Task follows implement → review → fix → re-review → Open P0/P1 = 0 → validation → commit.

---

### Task 1: Policy and CLI Contract Split

**Files:**
- Modify: `Sources/LidMonitor/DiagnosticModels.swift`
- Modify: `Sources/LidMonitor/CLI.swift`
- Modify: `Sources/LidMonitor/OutputFormatter.swift`
- Modify: `Tests/LidMonitorTests/AutoSleepCLIParserTests.swift`
- Modify: `Tests/LidMonitorTests/OutputFormatterTests.swift`
- Modify: `Tests/LidMonitorTests/SingleSourceOfTruthTests.swift`

**Interfaces:**
- Consumes: existing `CLIParser.parse(_:) -> CLIOptions` and `LidSleepPolicy.calibratedDefault`.
- Produces: `LidSleepPolicy.init(sleepThreshold:reopenThreshold:closeDebounce:startupCooldown:wakeRecovery:)`, properties `closeDebounce`, `startupCooldown`, `wakeRecovery`, and CLI options `--startup-cooldown`, `--wake-recovery`.

- [x] **Step 1: Write failing policy and CLI tests**

Update test policy construction to:

```swift
try LidSleepPolicy(
    sleepThreshold: 59,
    reopenThreshold: 72,
    closeDebounce: 2.5,
    startupCooldown: 6,
    wakeRecovery: 18
)
```

Add assertions that:

```swift
LidSleepPolicy.calibratedDefault.closeDebounce == 2
LidSleepPolicy.calibratedDefault.startupCooldown == 5
LidSleepPolicy.calibratedDefault.wakeRecovery == 15
```

Add parser coverage for:

```text
--debounce 2.5 --startup-cooldown 6 --wake-recovery 18
```

Add an exact rejection test:

```swift
XCTAssertThrowsError(
    try CLIParser.parse([
        "--auto-sleep", "--dry-run", "--wake-cooldown", "5"
    ])
) { error in
    XCTAssertEqual(error as? CLIParseError, .obsoleteWakeCooldownOption)
}
```

Add validation tests requiring all three timing values to be finite, with
`closeDebounce > 0`, `startupCooldown >= 0`, and `wakeRecovery > 0`.

- [x] **Step 2: Run Task 1 RED**

Run:

```bash
swift test --filter AutoSleepCLIParserTests
swift test --filter OutputFormatterTests
swift test --filter SingleSourceOfTruthTests
```

Expected: compile/test failure because the split policy fields, new CLI options,
and obsolete-option error do not exist.

- [x] **Step 3: Implement the exact policy model**

Replace `debounce` and `wakeCooldown` with:

```swift
let closeDebounce: TimeInterval
let startupCooldown: TimeInterval
let wakeRecovery: TimeInterval
```

Add policy errors:

```swift
case invalidCloseDebounce(TimeInterval)
case invalidStartupCooldown(TimeInterval)
case invalidWakeRecovery(TimeInterval)
```

Set `calibratedDefault` to `68 / 75 / 2 / 5 / 15`.

- [x] **Step 4: Implement the CLI migration contract**

Parse:

```text
--debounce -> closeDebounce
--startup-cooldown -> startupCooldown
--wake-recovery -> wakeRecovery
```

Add:

```swift
case obsoleteWakeCooldownOption
```

and throw it immediately for `--wake-cooldown`, without consuming or accepting
its following value. Keep policy-option-without-auto-sleep validation for the
three supported options.

- [x] **Step 5: Update effective configuration output**

Emit exactly:

```text
auto-sleep config: mode=dry-run sleep-threshold=68 reopen-threshold=75 debounce=2 startup-cooldown=5 wake-recovery=15
```

Do not retain `wake-cooldown=` in active examples or runtime output.

- [x] **Step 6: Run Task 1 GREEN and regression tests**

Run:

```bash
swift test --filter AutoSleepCLIParserTests
swift test --filter OutputFormatterTests
swift test --filter SingleSourceOfTruthTests
swift test
git diff --check
```

Expected: all pass.

- [x] **Step 7: Task 1 review, fix, re-review, and commit**

Review public option behavior, finite-value validation, default authority, and
active output examples. Require Open P0 = 0 and Open P1 = 0, then commit:

```bash
git add Sources/LidMonitor/DiagnosticModels.swift Sources/LidMonitor/CLI.swift Sources/LidMonitor/OutputFormatter.swift Tests/LidMonitorTests/AutoSleepCLIParserTests.swift Tests/LidMonitorTests/OutputFormatterTests.swift Tests/LidMonitorTests/SingleSourceOfTruthTests.swift
git commit -m "feat: split startup and wake recovery policy"
```

---

### Task 2: Angle-Authoritative State Machine

**Files:**
- Modify: `Sources/LidMonitor/LidSleepStateMachine.swift`
- Modify: `Tests/LidMonitorTests/LidSleepStateMachineTests.swift`

**Interfaces:**
- Consumes: split `LidSleepPolicy` from Task 1.
- Produces: states `.startupCooldown`, `.wakeRecovery(deadline:)`, `.disarmed`, `.open`, `.closingCandidate(deadline:)`, `.triggered`; events `.startupCooldownElapsed(at:)`, `.wakeRecoveryElapsed(at:)`, `.sleepRequestFailed(at:)`; effects for all three scheduler paths.

- [x] **Step 1: Write failing startup and recovery tests**

Add state-machine tests for these exact sequences:

```swift
startupCooldown + angle 70 + startupCooldownElapsed -> disarmed
startupCooldown + angle 75 + startupCooldownElapsed -> open
triggered + systemDidWake -> wakeRecovery(deadline: wake + 15)
wakeRecovery + angle 75 -> cancelWakeRecovery + open
wakeRecovery + angle 68 + wakeRecoveryElapsed -> triggered + requestSleep
wakeRecovery + angle 74 + wakeRecoveryElapsed -> triggered + requestSleep
wakeRecovery + no fresh angle + wakeRecoveryElapsed -> disarmed
wakeRecovery + valid 68 + dataInvalid + wakeRecoveryElapsed -> disarmed
triggered + sleepRequestFailed -> disarmed
disarmed + angle 74 -> no effect
disarmed + angle 75 -> open
```

Also verify every `systemDidWake` clears pre-wake angle evidence.

- [x] **Step 2: Run Task 2 RED**

Run:

```bash
swift test --filter LidSleepStateMachineTests
```

Expected: compile/test failure because recovery states/events/effects do not exist.

- [x] **Step 3: Implement explicit states, events, and effects**

Use these concrete cases:

```swift
enum LidSleepState {
    case startupCooldown
    case wakeRecovery(deadline: Date)
    case disarmed
    case open
    case closingCandidate(deadline: Date)
    case triggered
}

enum LidSleepEvent {
    case angleChanged(Int, at: Date)
    case closeDebounceElapsed(at: Date)
    case startupCooldownElapsed(at: Date)
    case wakeRecoveryElapsed(at: Date)
    case systemDidWake(at: Date)
    case sleepRequestFailed(at: Date)
    case dataInvalid(at: Date)
}

enum LidSleepEffect {
    case scheduleCloseDebounce(deadline: Date)
    case cancelCloseDebounce
    case scheduleWakeRecovery(deadline: Date)
    case cancelWakeRecovery
    case requestSleep
    case stateChanged(LidSleepState)
}
```

Initialize in `.startupCooldown`. Startup completion never requests sleep.
`systemDidWake` clears `latestAngle`, cancels a pending close debounce when
needed, enters `.wakeRecovery`, and schedules exactly one wake-recovery deadline.

- [x] **Step 4: Implement fresh-data recovery semantics**

During `.wakeRecovery`:

```text
angle >=75 -> cancel recovery and open
valid angle <75 -> cache only; do not sleep early
invalid data -> clear cached angle
deadline + cached valid angle <75 -> triggered + requestSleep
deadline + no cached valid angle -> disarmed
```

Normal close debounce remains `<=sleepThreshold`; recovery uses `<reopenThreshold`.

- [x] **Step 5: Implement request-failure transition**

`.sleepRequestFailed` must transition `.triggered -> .disarmed`. It must not
schedule any task or request another sleep. A later `>=75` report rearms.

- [x] **Step 6: Run Task 2 GREEN and regression tests**

Run:

```bash
swift test --filter LidSleepStateMachineTests
swift test
git diff --check
```

Expected: all pass.

- [x] **Step 7: Task 2 review, fix, re-review, and commit**

Review stale-angle clearing, threshold boundaries, exactly-once effects, invalid
data behavior, and failure terminal state. Require Open P0 = 0 and Open P1 = 0,
then commit:

```bash
git add Sources/LidMonitor/LidSleepStateMachine.swift Tests/LidMonitorTests/LidSleepStateMachineTests.swift
git commit -m "feat: make wake recovery angle authoritative"
```

---

### Task 3: Coordinator Scheduling and Failure Visibility

**Files:**
- Modify: `Sources/LidMonitor/LidSleepCoordinator.swift`
- Modify: `Sources/LidMonitor/SleepRequester.swift`
- Modify: `Sources/LidMonitor/OutputFormatter.swift`
- Modify: `Tests/LidMonitorTests/LidSleepCoordinatorTests.swift`
- Modify: `Tests/LidMonitorTests/SleepRequesterTests.swift`
- Modify: `Tests/LidMonitorTests/OutputFormatterTests.swift`

**Interfaces:**
- Consumes: Task 2 state-machine effects.
- Produces: three independent one-shot task slots and operational event `.sleepRequestFailed(String)` plus transitions `.startupCooldown`, `.wakeRecovery`, `.recoveryResleep`, `.recoverySensorUnavailable`.

- [x] **Step 1: Write failing coordinator scheduling tests**

Add tests asserting:

```text
start -> only startup deadline at now + 5
wake -> startup/close task cancelled, only recovery deadline at wake + 15
fresh 75 before deadline -> recovery task cancelled, no request
fresh 68 then deadline -> exactly one request
fresh 74 then deadline -> exactly one request
invalid report after fresh 68 then deadline -> zero requests and disarmed event
stop -> all three task slots cancelled
repeated wake -> previous recovery task cancelled and replaced once
```

- [x] **Step 2: Write failing sleep-request error tests**

Make `SpySleepRequester` optionally throw a deterministic test error. Verify:

```text
request count == 1
operational events == [.sleepRequestFailed("test-sleep-failure")]
transition ends in disarmed
more low-angle reports do not retry
angle 75 rearms
```

Add formatter assertions for:

```text
auto-sleep: sleep-request-failed error=test-sleep-failure
auto-sleep: startup-cooldown
auto-sleep: wake-recovery
auto-sleep: recovery-resleep
auto-sleep: recovery-sensor-unavailable
```

- [x] **Step 3: Run Task 3 RED**

Run:

```bash
swift test --filter LidSleepCoordinatorTests
swift test --filter SleepRequesterTests
swift test --filter OutputFormatterTests
```

Expected: compile/test failure for missing events, task slots, and error handling.

- [x] **Step 4: Implement independent one-shot task ownership**

Replace `debounceTask`/`cooldownTask` with:

```swift
private var closeDebounceTask: CancellableTask?
private var startupCooldownTask: CancellableTask?
private var wakeRecoveryTask: CancellableTask?
```

`start()` schedules startup only. `handleWake(at:)` applies the wake event and
lets the state-machine effect schedule recovery. `cancelAllTasks()` cancels and
nils all three slots.

- [x] **Step 5: Implement explicit request success/failure handling**

Replace `try?` with:

```swift
do {
    try sleepRequester.requestSleep()
} catch {
    onOperationalEvent(.sleepRequestFailed(stableSleepErrorDescription(error)))
    apply(machine.handle(.sleepRequestFailed(at: now())))
}
```

Add an injected `onOperationalEvent` callback directly to
`LidSleepCoordinator`; composition passes the existing callback. Do not retry.

Use a stable description:

```swift
extension IOKitSystemSleepError: CustomStringConvertible {
    var description: String {
        switch self {
        case .powerManagementUnavailable:
            return "power-management-unavailable"
        case .requestFailed(let code):
            return "iokit-request-failed(\(code))"
        }
    }
}
```

For unknown errors, use `String(describing: error)`.

- [x] **Step 6: Map state changes to compact transition output**

Emit transition-only events without per-report logging. Distinguish recovery
deadline sleep from normal close trigger by tracking the previous state when
`.triggered` is reported.

- [x] **Step 7: Run Task 3 GREEN and regression tests**

Run:

```bash
swift test --filter LidSleepCoordinatorTests
swift test --filter SleepRequesterTests
swift test --filter OutputFormatterTests
swift test
git diff --check
```

Expected: all pass.

- [x] **Step 8: Task 3 review, fix, re-review, and commit**

Review deadlock risk, task replacement/cancellation, exactly-once request
semantics, error stability, and no retry. Require Open P0 = 0 and Open P1 = 0,
then commit:

```bash
git add Sources/LidMonitor/LidSleepCoordinator.swift Sources/LidMonitor/SleepRequester.swift Sources/LidMonitor/OutputFormatter.swift Tests/LidMonitorTests/LidSleepCoordinatorTests.swift Tests/LidMonitorTests/SleepRequesterTests.swift Tests/LidMonitorTests/OutputFormatterTests.swift
git commit -m "feat: expose recovery and sleep request failures"
```

---

### Task 4: Composition, Integration, and Documentation Synchronization

**Files:**
- Modify: `Sources/LidMonitor/main.swift`
- Modify: `Tests/LidMonitorTests/AutoSleepIntegrationTests.swift`
- Modify: `README.md`
- Modify: `docs/validation/2026-07-26-m1-pro-auto-sleep.md`
- Modify: `docs/superpowers/reviews/2026-07-26-lid-angle-auto-sleep-final-review.md`

**Interfaces:**
- Consumes: Tasks 1–3 production interfaces.
- Produces: end-to-end dry-run and injected execute-sleep behavior plus synchronized operator documentation.

- [x] **Step 1: Write failing integration tests**

Add end-to-end tests for:

```text
dry-run close -> would-sleep -> wake -> fresh 68 -> recovery deadline -> second would-sleep
dry-run close -> would-sleep -> wake -> fresh 75 -> recovery cancelled
execute-sleep close -> injected operation throws -> sleep-request-failed -> disarmed -> no retry
```

Extend `IntegrationWakeObserver` so tests can store and invoke the wake callback.
Extend `IntegrationSystemSleepOperation` with an optional deterministic error.

- [x] **Step 2: Run Task 4 RED**

Run:

```bash
swift test --filter AutoSleepIntegrationTests
```

Expected: failure until composition forwards operational errors and recovery
events correctly.

- [x] **Step 3: Update composition root**

Pass `onOperationalEvent` into the coordinator so both requester success and
coordinator-caught failures use the same output path. Ensure dry-run still never
constructs `IOKitSystemSleepOperation`.

- [x] **Step 4: Synchronize README and authority documents**

Document:

```text
startup-cooldown=5
wake-recovery=15
fresh angle <75 after wake -> re-sleep
fresh angle >=75 -> cancel and rearm
no fresh valid angle -> fail open
sleep-request-failed error=...
```

Mark the old Task 7 `disarmed-after-wake` behavior as superseded historical
evidence, not current runtime behavior. Do not rewrite the factual Task 8 log.

- [x] **Step 5: Run Task 4 GREEN and documentation scans**

Run:

```bash
swift test --filter AutoSleepIntegrationTests
swift test
swift build -c release
grep -R "wake-cooldown=" README.md Sources Tests docs --exclude='2026-07-26-m1-pro-auto-sleep.md'
git diff --check
```

Expected: tests/build pass; no active runtime/document example retains
`wake-cooldown=`. Historical validation may retain old output only when clearly
labelled as superseded.

- [x] **Step 6: Task 4 review, fix, re-review, and commit**

Review composition isolation, dry-run safety, active-vs-historical documentation,
and public CLI examples. Require Open P0 = 0 and Open P1 = 0, then commit:

```bash
git add Sources/LidMonitor/main.swift Tests/LidMonitorTests/AutoSleepIntegrationTests.swift README.md docs/validation/2026-07-26-m1-pro-auto-sleep.md docs/superpowers/reviews/2026-07-26-lid-angle-auto-sleep-final-review.md
git commit -m "docs: align angle-authoritative recovery behavior"
```

---

### Task 5: Holistic Review and Bounded Acceptance

**Files:**
- Create: `docs/superpowers/reviews/2026-07-26-angle-authoritative-resleep-final-review.md`
- Modify: `docs/validation/2026-07-26-m1-pro-auto-sleep.md`
- Modify: `docs/superpowers/plans/2026-07-26-angle-authoritative-resleep.md`

**Interfaces:**
- Consumes: complete Tasks 1–4 implementation.
- Produces: final P0/P1 disposition and dry-run acceptance evidence; real sleep remains separately gated.

- [x] **Step 1: Run full clean validation**

Run:

```bash
swift package clean
swift test
swift build -c release
git diff --check
```

Expected: all pass.

- [x] **Step 2: Perform static operational-safety review**

Verify:

- no repeating timer or polling loop;
- no per-report auto-sleep logging;
- no power assertion or persistent power mutation;
- no LaunchAgent/login item;
- exactly three one-shot task slots;
- every wake replaces the prior recovery task;
- invalid recovery data cannot request sleep;
- failed sleep request cannot automatically retry;
- diagnostic modes cannot construct a sleep requester.

- [x] **Step 3: Run bounded hardware dry-run recovery acceptance**

Start release dry-run in the foreground. Perform:

```text
open >=75
close <=68 for >2 seconds -> would-sleep
simulate an actual wake notification only through a real sleep/wake cycle is not
available in dry-run, so validate recovery timing through automated integration
tests and verify stationary idle behavior on hardware
```

Record that no real sleep was invoked in this step. Do not fake an
`NSWorkspace.didWakeNotification` production event.

- [x] **Step 4: Write holistic final review**

Record test/build evidence, static findings, accepted hardware limitation, and:

```text
Open P0 = 0
Open P1 = 0
```

Do not claim real recovery re-sleep acceptance without a separately approved
foreground execute-sleep cycle.

- [x] **Step 5: Review, fix, re-review, and commit Task 5**

Require Open P0 = 0 and Open P1 = 0, then commit:

```bash
git add docs/superpowers/reviews/2026-07-26-angle-authoritative-resleep-final-review.md docs/validation/2026-07-26-m1-pro-auto-sleep.md docs/superpowers/plans/2026-07-26-angle-authoritative-resleep.md
git commit -m "docs: complete angle-authoritative resleep review"
```

---

### Task 6: Separately Approved Real Re-Sleep Acceptance

**Files:**
- Modify: `docs/validation/2026-07-26-m1-pro-auto-sleep.md`
- Modify: `docs/superpowers/plans/2026-07-26-angle-authoritative-resleep.md`

**Interfaces:**
- Consumes: Task 5 Open P0/P1 = 0 and explicit user approval.
- Produces: one bounded real close/sleep/wake/re-sleep/open acceptance result.

- [ ] **Step 1: Confirm explicit approval after Task 5**

Do not start `--execute-sleep` unless the user separately approves this exact
two-sleep acceptance after reviewing Task 5 evidence.

- [ ] **Step 2: Run one bounded foreground recovery cycle**

```text
open >=75
close <=68 for >2 seconds
verify first Software Sleep
wake by keyboard while keeping angle <75
verify second Software Sleep occurs after approximately 15 seconds
```

- [ ] **Step 3: Verify escape window**

Wake again, open to `>=75` within fifteen seconds, and verify:

```text
recovery task cancelled
rearmed emitted
no third sleep request
```

- [ ] **Step 4: Stop foreground process and document evidence**

Record process transitions and independent `pmset -g log` Software Sleep/Wake
entries. Stop the process; confirm no residual process, service, assertion, or
persistent setting.

- [ ] **Step 5: Review and commit real acceptance**

Require no unexpected repeated request and no failed recovery cancellation, then
commit:

```bash
git add docs/validation/2026-07-26-m1-pro-auto-sleep.md docs/superpowers/plans/2026-07-26-angle-authoritative-resleep.md
git commit -m "docs: record angle-authoritative resleep acceptance"
```

## Plan Self-Review

- Spec coverage: policy split, CLI migration, fresh-data recovery, repeated wakes,
  failure visibility, no retry, docs, dry-run safety, holistic review, and gated
  real acceptance each map to a Task.
- Placeholder scan: no TBD, TODO, “similar to”, or unspecified error-handling
  step remains.
- Type consistency: policy properties, state/event/effect cases, operational and
  transition events, and CLI names are introduced once and consumed consistently.
- Scope control: no persistent service, polling, UI, settings, or power mutation
  entered the plan.
