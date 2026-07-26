# MacBook Lid Angle Auto-Sleep Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the existing diagnostic CLI with an event-driven, calibrated, fail-open auto-sleep engine that defaults to dry-run and requires explicit opt-in for real sleep.

**Architecture:** Preserve the current Swift executable and add a pure state machine plus a coordinator behind small angle-source, scheduler, and sleep-request ports. Existing IOHID code supplies events; dry-run and macOS sleep adapters sit at the edge, while all timing and threshold behavior remains deterministic under XCTest.

**Tech Stack:** Swift 6.x, Swift Package Manager, Foundation, AppKit, IOKit/IOHID, XCTest, macOS 13+, no third-party dependencies.

## Global Constraints

- Calibrated defaults: sleep threshold `60`, debounce `2.0` seconds, reopen threshold `70`, wake cooldown `5.0` seconds.
- HID values are machine-specific sensor values, not guaranteed physical degrees.
- Event driven only; do not add a repeating high-frequency poller.
- Real sleep must require `--auto-sleep --execute-sleep`; dry-run is the safe default for auto-sleep validation.
- Invalid, missing, out-of-range, stream-failure, or undecodable reports fail open and never request sleep.
- Startup and `NSWorkspace.didWakeNotification` begin a five-second cooldown; if the lid is still below `70` afterward, the engine stays disarmed until `>= 70`.
- At most one sleep decision per close/open cycle.
- Existing `--list`, `--watch`, `--raw`, and `--duration` diagnostic behavior must remain compatible.
- No third-party dependency, HID write, `pmset` configuration mutation, NVRAM mutation, privilege escalation, DriverKit, kernel extension, or SIP modification.
- Every Task follows implement → targeted tests → review → fix → re-review → Open P0/P1 = 0 → commit.

---

## Planned File Map

```text
Sources/LidMonitor/
├── CLI.swift                         # Extend modes and validated policy arguments
├── DiagnosticModels.swift            # Auto-sleep configuration and decisions
├── LidSleepStateMachine.swift         # Pure calibrated state transitions
├── LidSleepCoordinator.swift          # Angle events, one-shot deadlines, lifecycle
├── SleepRequester.swift               # Sleep port, dry-run, and real macOS adapter
├── Scheduler.swift                    # Production and deterministic timer ports
├── SystemWakeObserver.swift            # NSWorkspace wake notification adapter
├── OutputFormatter.swift              # Transition-only operational output
└── main.swift                         # Composition root and explicit safety gate
Tests/LidMonitorTests/
├── AutoSleepCLIParserTests.swift
├── LidSleepStateMachineTests.swift
├── LidSleepCoordinatorTests.swift
├── SleepRequesterTests.swift
└── AutoSleepIntegrationTests.swift
scripts/
├── run-diagnostic.sh
└── run-auto-sleep-dry-run.sh
docs/validation/
└── 2026-07-26-m1-pro-auto-sleep.md
```

## Task Governance Contract

For each Task:

```text
Write/adjust failing tests
→ verify RED
→ implement the minimum behavior
→ verify GREEN
→ review interfaces, safety, concurrency, and regressions
→ fix and re-run
→ require Open P0/P1 = 0
→ commit
```

After all Tasks:

```text
full test + release build + diff check
→ whole-phase implementation review
→ bounded dry-run hardware acceptance
→ energy/idle review
→ explicit approval before any real-sleep acceptance
→ final review and documentation
```

---

### Task 1: Auto-Sleep CLI Contract and Configuration Validation

**Files:**
- Modify: `Sources/LidMonitor/CLI.swift`
- Modify: `Sources/LidMonitor/DiagnosticModels.swift`
- Modify: `Sources/LidMonitor/main.swift`
- Create: `Tests/LidMonitorTests/AutoSleepCLIParserTests.swift`

**Interfaces:**
- Produces: `enum AutoSleepExecutionMode: Equatable { case dryRun; case executeSleep }`
- Produces: `struct LidSleepPolicy: Equatable, Sendable`
- Produces: `DiagnosticMode.autoSleep(AutoSleepExecutionMode, LidSleepPolicy)`
- Consumes: existing `CLIParser.parse(_:)`, `CLIOptions`, and diagnostic modes.

- [ ] **Step 1: Write failing parser tests**

Add tests proving:

```swift
XCTAssertEqual(
    try CLIParser.parse(["--auto-sleep", "--dry-run"]).mode,
    .autoSleep(.dryRun, .calibratedDefault)
)

XCTAssertThrowsError(try CLIParser.parse(["--auto-sleep"]))
XCTAssertThrowsError(try CLIParser.parse(["--execute-sleep"]))
XCTAssertThrowsError(try CLIParser.parse([
    "--auto-sleep", "--dry-run",
    "--sleep-threshold", "70",
    "--reopen-threshold", "60"
]))
```

Also cover nonfinite/negative timing values, values outside `0...360`, conflicting `--dry-run` and `--execute-sleep`, and incompatible diagnostic flags.

- [ ] **Step 2: Run RED**

Run:

```bash
swift test --filter AutoSleepCLIParserTests
```

Expected: compilation or assertions fail because auto-sleep options do not exist.

- [ ] **Step 3: Implement exact configuration types**

Add:

```swift
struct LidSleepPolicy: Equatable, Sendable {
    let sleepThreshold: Int
    let reopenThreshold: Int
    let debounce: TimeInterval
    let wakeCooldown: TimeInterval

    static let calibratedDefault = LidSleepPolicy(
        sleepThreshold: 68,
        reopenThreshold: 75,
        debounce: 2.0,
        wakeCooldown: 5.0
    )

    init(
        sleepThreshold: Int,
        reopenThreshold: Int,
        debounce: TimeInterval,
        wakeCooldown: TimeInterval
    ) throws
}
```

Validation must require `0...360`, `reopenThreshold > sleepThreshold`, positive finite debounce, and nonnegative finite cooldown.

- [ ] **Step 4: Run GREEN and regression tests**

```bash
swift test --filter AutoSleepCLIParserTests
swift test --filter CLIParserTests
```

- [ ] **Step 5: Review and commit**

Confirm that no argument path implicitly enables real sleep, then commit:

```bash
git add Sources/LidMonitor/CLI.swift Sources/LidMonitor/DiagnosticModels.swift Sources/LidMonitor/main.swift Tests/LidMonitorTests/AutoSleepCLIParserTests.swift
git commit -m "feat: define safe auto-sleep CLI contract"
```

---

### Task 2: Pure Lid Sleep State Machine

**Files:**
- Create: `Sources/LidMonitor/LidSleepStateMachine.swift`
- Create: `Tests/LidMonitorTests/LidSleepStateMachineTests.swift`

**Interfaces:**
- Consumes: `LidSleepPolicy` from Task 1.
- Produces: `enum LidSleepState: Equatable, Sendable`
- Produces: `enum LidSleepEffect: Equatable, Sendable`
- Produces: `mutating func handle(_ event: LidSleepEvent) -> [LidSleepEffect]`

- [ ] **Step 1: Write state transition tests**

Use deterministic timestamps and cover:

```swift
// 61 stays open.
// 60 enters closingCandidate with one deadline.
// Duplicate 60 reports do not extend the deadline.
// 61 before deadline cancels.
// Deadline at 2 seconds while latest value <= 60 emits requestSleep once.
// 69...74 after trigger does not rearm.
// 70 rearms.
// Cooldown blocks closing until elapsed.
// Cooldown ending below 75 enters disarmed; only >=75 enters open.
// Invalid angle fails open and cancels any candidate.
```

- [ ] **Step 2: Run RED**

```bash
swift test --filter LidSleepStateMachineTests
```

- [ ] **Step 3: Implement the state machine without timers or I/O**

Use these public shapes:

```swift
enum LidSleepEvent: Equatable, Sendable {
    case angleChanged(Int, at: Date)
    case debounceElapsed(at: Date)
    case cooldownElapsed(at: Date)
    case systemDidWake(at: Date)
    case dataInvalid(at: Date)
}

enum LidSleepEffect: Equatable, Sendable {
    case scheduleDebounce(deadline: Date)
    case cancelDebounce
    case requestSleep
    case stateChanged(LidSleepState)
}
```

The state machine must never call Foundation timers, IOKit, shell commands, or sleep APIs.

- [ ] **Step 4: Run GREEN**

```bash
swift test --filter LidSleepStateMachineTests
```

- [ ] **Step 5: Review and commit**

Review boundary values `59`, `60`, `61`, `69`, and `70`, duplicate deadlines, and one-shot behavior. Commit:

```bash
git add Sources/LidMonitor/LidSleepStateMachine.swift Tests/LidMonitorTests/LidSleepStateMachineTests.swift
git commit -m "feat: add calibrated lid sleep state machine"
```

---

### Task 3: Scheduler and Coordinator Ports

**Files:**
- Modify: `Package.swift`
- Create: `Sources/LidMonitor/Scheduler.swift`
- Create: `Sources/LidMonitor/LidSleepCoordinator.swift`
- Create: `Sources/LidMonitor/SleepRequester.swift`
- Create: `Sources/LidMonitor/SystemWakeObserver.swift`
- Create: `Tests/LidMonitorTests/LidSleepCoordinatorTests.swift`

**Interfaces:**
- Consumes: `HIDReportStreaming`, existing decoder, `LidSleepStateMachine`.
- Produces: `protocol OneShotScheduling`
- Produces: `protocol SleepRequesting`
- Produces: `protocol SystemWakeObserving`
- Produces: `final class LidSleepCoordinator`

- [ ] **Step 1: Write coordinator tests with fakes**

Create a fake angle source, manual scheduler, fake wake observer, and spy requester. Prove that:

```swift
// Start subscribes once.
// Angle 60 schedules one deadline.
// Angle 61 cancels it.
// Firing the deadline invokes requester once only.
// A wake event cancels pending debounce and starts one cooldown deadline.
// Cooldown ending below 75 remains disarmed until a >=75 report.
// Stop cancels the deadline and stream.
// Decode failure dispatches dataInvalid and never sleeps.
```

- [ ] **Step 2: Run RED**

```bash
swift test --filter LidSleepCoordinatorTests
```

- [ ] **Step 3: Implement injectable one-shot scheduling**

Define:

```swift
protocol CancellableTask: Sendable { func cancel() }

protocol OneShotScheduling: Sendable {
    func schedule(at deadline: Date, _ action: @escaping @Sendable () -> Void) -> CancellableTask
}
```

Production implementation may use `DispatchQueue.asyncAfter`; it must create no repeating timer.

Define the wake port in `SystemWakeObserver.swift`:

```swift
protocol SystemWakeObserving: AnyObject, Sendable {
    func start(onWake: @escaping @Sendable (Date) -> Void)
    func stop()
}
```

The production adapter registers only with `NSWorkspace.shared.notificationCenter` for `NSWorkspace.didWakeNotification` and removes its observer idempotently on stop.

Update `Package.swift` to link `AppKit` in addition to the existing `IOKit` framework so the wake adapter has an explicit build dependency.

- [ ] **Step 4: Implement the coordinator**

The coordinator serializes state-machine events on one queue, owns at most one pending debounce task and one cooldown task, routes wake notifications into `.systemDidWake`, routes `requestSleep` effects to `SleepRequesting`, and exposes idempotent `start()`/`stop()`.

- [ ] **Step 5: Run GREEN and concurrency review**

```bash
swift test --filter LidSleepCoordinatorTests
swift test
```

Review for callback-after-stop, duplicate timer, retain cycle, and data race risks.

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources/LidMonitor/Scheduler.swift Sources/LidMonitor/LidSleepCoordinator.swift Sources/LidMonitor/SleepRequester.swift Sources/LidMonitor/SystemWakeObserver.swift Tests/LidMonitorTests/LidSleepCoordinatorTests.swift
git commit -m "feat: coordinate event-driven lid sleep decisions"
```

---

### Task 4: Dry-Run and macOS Sleep Request Adapters

**Files:**
- Modify: `Sources/LidMonitor/SleepRequester.swift`
- Modify: `Sources/LidMonitor/OutputFormatter.swift`
- Create: `Tests/LidMonitorTests/SleepRequesterTests.swift`

**Interfaces:**
- Consumes: `SleepRequesting` from Task 3.
- Produces: `DryRunSleepRequester`, `MacOSSleepRequester`, and transition events.

- [ ] **Step 1: Write failing adapter tests**

Prove dry-run records exactly one `would-sleep` event and does not invoke the injected system operation. Prove the real adapter maps success and nonzero/error outcomes without retry loops.

- [ ] **Step 2: Run RED**

```bash
swift test --filter SleepRequesterTests
```

- [ ] **Step 3: Implement adapters with an injectable system operation**

Use:

```swift
protocol SystemSleepOperating: Sendable {
    func requestSleep() throws
}
```

`MacOSSleepRequester` delegates once to this port. The concrete implementation obtains the root power-domain connection with `IOPMCopySystemPowerConnection()`, calls `IOPMSleepSystem(connection)` once, closes the connection, and maps non-success `IOReturn` values to a typed error. It must not invoke `pmset`, mutate persistent power settings, or retry.

- [ ] **Step 4: Add transition-only output**

Output only state changes and decisions; do not emit one line per HID report in auto-sleep mode.

- [ ] **Step 5: Run GREEN, safety scan, and commit**

```bash
swift test --filter SleepRequesterTests
grep -R "IOHIDDeviceSetReport\|pmset\|nvram\|SMJobBless\|AuthorizationExecuteWithPrivileges" Sources Tests && exit 1 || true
git add Sources/LidMonitor/SleepRequester.swift Sources/LidMonitor/OutputFormatter.swift Tests/LidMonitorTests/SleepRequesterTests.swift
git commit -m "feat: add dry-run and bounded sleep adapters"
```

---

### Task 5: Composition Root and End-to-End Dry-Run

**Files:**
- Modify: `Sources/LidMonitor/main.swift`
- Modify: `Sources/LidMonitor/CLI.swift`
- Create: `Tests/LidMonitorTests/AutoSleepIntegrationTests.swift`
- Create: `scripts/run-auto-sleep-dry-run.sh`

**Interfaces:**
- Consumes: all prior Task interfaces.
- Produces: runnable `--auto-sleep --dry-run` and explicitly gated `--execute-sleep` flows.

- [ ] **Step 1: Write an end-to-end test with fake hardware**

Compose fake HID reports encoding `105 → 60 → deadline → 59 → 70`; assert one dry-run decision, no decision at `105`, and rearm at `70`.

- [ ] **Step 2: Run RED**

```bash
swift test --filter AutoSleepIntegrationTests
```

- [ ] **Step 3: Wire production composition**

`main.swift` must:

1. Parse options.
2. Discover only the validated high-confidence lid device.
3. Create the existing read-only HID stream and decoder.
4. Select dry-run or real requester solely from explicit CLI mode.
5. Install signal handlers that call coordinator `stop()`.
6. Register the AppKit wake observer used by the coordinator.
7. Keep the process alive with `RunLoop.main.run()` rather than a polling loop.

- [ ] **Step 4: Add the dry-run helper script**

Create an executable script that runs:

```bash
swift run -c release macbook-lid-monitor \
  --auto-sleep --dry-run
```

The helper must not duplicate calibrated policy values. It consumes
`LidSleepPolicy.calibratedDefault`, the single runtime authority.

- [ ] **Step 5: Run GREEN and regression validation**

```bash
swift test --filter AutoSleepIntegrationTests
swift test
swift build -c release
./scripts/run-diagnostic.sh --list
```

- [ ] **Step 6: Review and commit**

Confirm `--watch` cannot reach a sleep requester and real sleep remains explicit. Commit:

```bash
git add Sources/LidMonitor/main.swift Sources/LidMonitor/CLI.swift Tests/LidMonitorTests/AutoSleepIntegrationTests.swift scripts/run-auto-sleep-dry-run.sh
git commit -m "feat: wire safe auto-sleep dry-run flow"
```

---

### Task 6: Dry-Run Hardware Acceptance and Calibration Evidence

**Files:**
- Create: `docs/validation/2026-07-26-m1-pro-auto-sleep.md`
- Modify: `README.md`

**Interfaces:**
- Consumes: release dry-run executable from Task 5.
- Produces: documented evidence and go/no-go decision for real sleep.

- [x] **Step 1: Run five bounded dry-run cycles**

For each cycle record:

```text
start near 90° (~148)
pause at lowest allowed (~105): must not trigger
close to <=68 and hold >2 seconds: exactly one would-sleep
open only to 69...74: must remain latched
open to >=75: must rearm
```

- [x] **Step 2: Test cancellation**

Enter `<=68` for less than two seconds, return above `68`, and verify no `would-sleep` occurs.

- [x] **Step 3: Test startup cooldown**

Start dry-run while the lid is at `<=68`; verify no sleep decision during the first five seconds and that it remains disarmed afterward. Open to `>=75`, close again, and verify the normal two-second candidate then triggers exactly once.

- [x] **Step 4: Document results and README usage**

The validation document must list timestamps, observed sensor values, trigger counts, failures, and whether Open P0/P1 findings remain. README must clearly label dry-run as the first required mode.

- [x] **Step 5: Review and commit**

```bash
git add docs/validation/2026-07-26-m1-pro-auto-sleep.md README.md
git commit -m "docs: validate calibrated auto-sleep dry-run"
```

Real-sleep acceptance is blocked unless all five cycles and cancellation/cooldown tests pass with Open P0/P1 = 0.

---

### Task 7: Idle Energy and Operational Safety Review

**Files:**
- Modify: `docs/validation/2026-07-26-m1-pro-auto-sleep.md`
- Create: `docs/superpowers/reviews/2026-07-26-lid-angle-auto-sleep-final-review.md`

**Interfaces:**
- Consumes: dry-run production process.
- Produces: evidence that the implementation is event-driven and ready or not ready for real sleep.

- [x] **Step 1: Inspect timers and logging statically**

Verify source contains no repeating timer for angle monitoring and no per-report production logging in auto-sleep mode.

- [x] **Step 2: Run an idle observation**

Run release dry-run with the lid stationary for at least 15 minutes. Record process CPU time/percentage samples, wakeup observations available from standard macOS tools, log line count, and HID transition count. The acceptance decision is qualitative and evidence-based: no sustained CPU activity, no log churn, and no application-created periodic wakeup loop.

- [x] **Step 3: Perform whole-phase review**

Review:

- Fail-open behavior.
- Real-sleep opt-in gate.
- One-shot trigger and hysteresis.
- Start/stop lifecycle and concurrency.
- Startup and `NSWorkspace.didWakeNotification` cooldown/disarm behavior.
- Diagnostic mode regression.
- No persistent power mutation.
- Documentation accuracy.

- [x] **Step 4: Fix all findings and rerun full validation**

```bash
swift package clean
swift test
swift build -c release
git diff --check
```

- [x] **Step 5: Commit the final review**

Require Open P0 = 0 and Open P1 = 0, then commit:

```bash
git add docs/validation/2026-07-26-m1-pro-auto-sleep.md docs/superpowers/reviews/2026-07-26-lid-angle-auto-sleep-final-review.md
git commit -m "docs: complete auto-sleep safety review"
```

---

### Task 8: Explicitly Approved Real-Sleep Acceptance

**Files:**
- Modify: `docs/validation/2026-07-26-m1-pro-auto-sleep.md`

**Interfaces:**
- Consumes: reviewed `--execute-sleep` mode and passing dry-run evidence.
- Produces: one bounded real-sleep result; no background installation.

- [ ] **Step 1: Confirm prerequisites**

Do not proceed unless the user explicitly approves a real-sleep test after reviewing Task 6 and Task 7 evidence.

- [ ] **Step 2: Run one foreground real-sleep cycle**

Start the executable manually with `--auto-sleep --execute-sleep`, close through `60` for more than two seconds, and verify the Mac enters sleep once.

- [ ] **Step 3: Reopen and verify recovery**

Verify the process does not immediately request sleep during the five-second cooldown and rearms only after `>=75`.

- [ ] **Step 4: Document and stop**

Record the outcome. Do not create a LaunchAgent or login item in this phase.

- [ ] **Step 5: Commit acceptance evidence**

```bash
git add docs/validation/2026-07-26-m1-pro-auto-sleep.md
git commit -m "docs: record bounded real-sleep acceptance"
```

## Plan Self-Review

- Spec coverage: calibrated thresholds, debounce, hysteresis, cooldown, dry-run, explicit real sleep, fail-open behavior, event-driven power model, regression safety, hardware acceptance, and energy review each map to a Task.
- Placeholder scan: no unresolved placeholder or unspecified error-handling step remains.
- Type consistency: `LidSleepPolicy`, `LidSleepStateMachine`, `OneShotScheduling`, `SleepRequesting`, and coordinator interfaces are introduced once and consumed by later Tasks consistently.
- Scope control: menu bar UI, MVVM, LaunchAgent installation, persistent preferences, and distribution remain explicitly deferred.

