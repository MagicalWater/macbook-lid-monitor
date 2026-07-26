# LaunchDaemon Feasibility Spike Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prove, without installing a sleep-capable production service, that a system LaunchDaemon can access the verified M1 Pro lid sensor before login, receive reports across login and sleep/wake, observe system power notifications through IOKit, and invoke one separately approved one-shot daemon-context sleep probe.

**Architecture:** Extract the existing executable implementation into an internal `LidMonitorCore` library with tiny CLI and spike entry points, preserving one authoritative state machine, coordinator, HID decoder, and sleep requester. Add an injectable `IORegisterForSystemPower` observer and a permanently dry-run daemon-spike composition, then deploy it under visibly temporary `/Library` paths with `RunAtLoad` and no initial `KeepAlive`. Real sleep is isolated in a separate one-shot probe executable that is never referenced by the LaunchDaemon plist.

**Tech Stack:** Swift 6, Swift Package Manager, XCTest, Foundation, Dispatch, Darwin signals, IOKit HID, IOKit power management, launchd plist, `launchctl`, `plutil`, unified logging or bounded root-owned evidence files.

---

## Global Constraints

- The installed feasibility daemon is always dry-run.
- `macbook-lid-monitor-daemon-spike` must not accept `--execute-sleep` and must not construct `IOKitSystemSleepOperation`.
- `macbook-lid-monitor-sleep-probe` is a separate one-shot executable and is never referenced by the feasibility plist.
- No source implementation begins until this reviewed plan is explicitly approved by the user.
- No file may be copied into `/Library`, and no `launchctl bootstrap system` may run, until the user explicitly approves the installation Task.
- Logout, sleep, reboot, shutdown, and a real one-shot `IOPMSleepSystem` call each require separate explicit approval immediately before the relevant Task.
- No LaunchAgent, login item, GUI, app bundle, `SMAppService`, IPC, persistent runtime state, `pmset`, NVRAM mutation, HID write, repeating poll timer, or self-installation is allowed.
- The first LaunchDaemon plist must not use `KeepAlive`.
- Every implementation Task follows implement -> immediate review -> record findings -> fix -> re-review -> Open P0/P1 = 0 -> validation -> commit.
- After all Tasks, perform a whole-phase implementation review -> fix -> re-review -> Open P0/P1 = 0 -> final acceptance -> commit -> push only after user approval.
- All new operator-facing usage documentation and README changes use Traditional Chinese. Historical spec, plan, and review documents may remain English.

## Fixed Spike Names and Paths

```text
LaunchDaemon label:
com.crazydennies.macbook-lid-monitor.feasibility

installed binary:
/Library/PrivilegedHelperTools/macbook-lid-monitor-daemon-spike

installed plist:
/Library/LaunchDaemons/com.crazydennies.macbook-lid-monitor.feasibility.plist

optional bounded evidence directory:
/Library/Logs/MacBookLidMonitor/Feasibility

repository plist template:
packaging/launchd/com.crazydennies.macbook-lid-monitor.feasibility.plist

repository management script:
scripts/manage-feasibility-daemon.sh
```

## Planned Package and File Structure

```text
Sources/
|- LidMonitorCore/
|  |- existing non-entry-point Swift sources
|  |- CLIApplication.swift
|  |- DaemonSpikeApplication.swift
|  |- DaemonSpikeEvidence.swift
|  |- IOKitSystemPowerObserver.swift
|  |- ProcessSignalController.swift
|  `- SleepProbeApplication.swift
|- LidMonitorCLI/main.swift
|- LidMonitorDaemonSpike/main.swift
`- LidMonitorSleepProbe/main.swift

Tests/LidMonitorTests/
|- existing tests
|- DaemonSpikeCompositionTests.swift
|- DaemonSpikeEvidenceTests.swift
|- IOKitSystemPowerObserverTests.swift
|- ProcessSignalControllerTests.swift
|- SleepProbeApplicationTests.swift
`- FeasibilityPackagingTests.swift

packaging/launchd/
`- com.crazydennies.macbook-lid-monitor.feasibility.plist

scripts/
`- manage-feasibility-daemon.sh

docs/validation/
`- 2026-07-26-launchdaemon-feasibility-spike.md

docs/superpowers/reviews/
|- 2026-07-26-launchdaemon-feasibility-spike-task-reviews.md
`- 2026-07-26-launchdaemon-feasibility-spike-final-review.md
```

---

### Task 1: Extract the Shared Core and Preserve the Existing CLI

**Purpose:** Create a compile-safe shared module so the CLI, daemon spike, and sleep probe cannot duplicate accepted state-machine or HID behavior.

**Files:**
- Modify: `Package.swift`
- Move: `Sources/LidMonitor/*.swift` except the final executable statements in `main.swift` to `Sources/LidMonitorCore/`
- Create: `Sources/LidMonitorCore/CLIApplication.swift`
- Create: `Sources/LidMonitorCLI/main.swift`
- Modify: all files in `Tests/LidMonitorTests/` that import the old executable module
- Create or update: `docs/superpowers/reviews/2026-07-26-launchdaemon-feasibility-spike-task-reviews.md`

**Interfaces:**
- Produce library target `LidMonitorCore`.
- Preserve executable product name `macbook-lid-monitor` through target `LidMonitorCLI`.
- Expose one narrow entry point:

```swift
public enum LidMonitorCLIEntryPoint {
    public static func run(arguments: [String]) -> Int32
}
```

- Keep implementation types internal to `LidMonitorCore` wherever the spike entry points can be implemented inside the same module.

- [ ] **Step 1: Record the pre-change baseline**

Run:

```bash
git status --short
swift test
swift build -c release
find Sources/LidMonitor -maxdepth 1 -type f -print | sort
```

Expected:

```text
working tree clean
79 tests pass
release build passes
one existing executable target named LidMonitor
```

- [ ] **Step 2: Write the package-boundary regression test**

Add a test to `Tests/LidMonitorTests/CLIParserTests.swift` or a new focused test that imports `@testable import LidMonitorCore` and calls:

```swift
let result = LidMonitorCLIEntryPoint.run(arguments: ["--definitely-invalid"])
XCTAssertEqual(result, ExitCode.usage.rawValue)
```

The entry point must accept explicit arguments rather than reading only global `CommandLine.arguments`, so tests do not spawn a process.

- [ ] **Step 3: Run Task 1 RED**

Run:

```bash
swift test --filter CLIParserTests
```

Expected: compile failure because `LidMonitorCore` and `LidMonitorCLIEntryPoint` do not exist.

- [ ] **Step 4: Define the new SwiftPM targets**

Update `Package.swift` to this shape:

```swift
let package = Package(
    name: "macbook-lid-monitor",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "macbook-lid-monitor", targets: ["LidMonitorCLI"]),
        .executable(
            name: "macbook-lid-monitor-daemon-spike",
            targets: ["LidMonitorDaemonSpike"]
        ),
        .executable(
            name: "macbook-lid-monitor-sleep-probe",
            targets: ["LidMonitorSleepProbe"]
        )
    ],
    targets: [
        .target(
            name: "LidMonitorCore",
            linkerSettings: [
                .linkedFramework("IOKit"),
                // AppKit remains temporary only until Task 2 replaces the
                // workspace wake observer. Task 2 must remove this linkage.
                .linkedFramework("AppKit")
            ]
        ),
        .executableTarget(
            name: "LidMonitorCLI",
            dependencies: ["LidMonitorCore"]
        ),
        .executableTarget(
            name: "LidMonitorDaemonSpike",
            dependencies: ["LidMonitorCore"]
        ),
        .executableTarget(
            name: "LidMonitorSleepProbe",
            dependencies: ["LidMonitorCore"]
        ),
        .testTarget(
            name: "LidMonitorTests",
            dependencies: ["LidMonitorCore"]
        )
    ]
)
```

Temporary placeholder entry points for the two new products may return an unavailable/internal exit code until their Tasks implement them, but they must compile and must not call sleep.

- [ ] **Step 5: Move implementation into `LidMonitorCore`**

Move the existing source files into `Sources/LidMonitorCore/`. Split the current `main.swift` so all reusable composition and CLI application logic remains in `LidMonitorCore/CLIApplication.swift`, while global process exit stays only in the tiny executable entry point.

Create `Sources/LidMonitorCLI/main.swift`:

```swift
import Darwin
import LidMonitorCore

exit(
    LidMonitorCLIEntryPoint.run(
        arguments: Array(CommandLine.arguments.dropFirst())
    )
)
```

`LidMonitorCLIEntryPoint.run(arguments:)` must preserve existing error text and exit-code mapping.

- [ ] **Step 6: Update tests to import the shared module**

Replace:

```swift
@testable import LidMonitor
```

with:

```swift
@testable import LidMonitorCore
```

Do not change accepted policy values or test semantics.

- [ ] **Step 7: Add compile-only placeholder entry points**

Create `Sources/LidMonitorDaemonSpike/main.swift` and `Sources/LidMonitorSleepProbe/main.swift` as tiny wrappers around explicit core entry points. Until later Tasks, the core entry points must fail safely and perform no HID or power operation.

- [ ] **Step 8: Run Task 1 GREEN**

Run:

```bash
swift package clean
swift test
swift build -c release
.build/release/macbook-lid-monitor --list >/tmp/macbook-lid-monitor-task1-list.log
git diff --check
```

Expected:

```text
all 79 existing tests plus the new boundary test pass
all three executable products build
existing CLI lists candidates with unchanged behavior
no sleep request occurs
```

- [ ] **Step 9: Task 1 review and findings**

Review:

- no policy, threshold, state-machine, or sleep behavior changed;
- no source implementation is duplicated between targets;
- only executable wrappers are public;
- diagnostic modes still cannot construct real sleep unless the existing explicit foreground flags are used;
- new placeholder spike/probe targets are inert.

Record findings under `Task 1` in `docs/superpowers/reviews/2026-07-26-launchdaemon-feasibility-spike-task-reviews.md`, fix all P0/P1, and re-run Step 8.

- [ ] **Step 10: Commit Task 1**

```bash
git add Package.swift Sources Tests docs/superpowers/reviews/2026-07-26-launchdaemon-feasibility-spike-task-reviews.md
git commit -m "refactor: extract lid monitor core target"
```

---

### Task 2: Add an Injectable IOKit System Power Observer

**Purpose:** Replace the daemon's login-session wake dependency with system power notifications while keeping native calls unit-testable.

**Files:**
- Create: `Sources/LidMonitorCore/IOKitSystemPowerObserver.swift`
- Modify: `Sources/LidMonitorCore/SystemWakeObserver.swift`
- Modify: `Package.swift`
- Create: `Tests/LidMonitorTests/IOKitSystemPowerObserverTests.swift`
- Modify: `docs/superpowers/reviews/2026-07-26-launchdaemon-feasibility-spike-task-reviews.md`

**Interfaces:**

```swift
enum SystemPowerEvent: Equatable, Sendable {
    case canSleep
    case willSleep
    case willPowerOn
    case hasPoweredOn
}

protocol SystemPowerObserving: AnyObject, Sendable {
    func start(
        onEvent: @escaping @Sendable (SystemPowerEvent, Date) -> Void
    ) throws
    func stop()
}

protocol SystemPowerNotificationOperating: AnyObject, Sendable {
    func register(
        callback: @escaping @Sendable (UInt32, Int) -> Void
    ) throws -> SystemPowerRegistration
    func allowPowerChange(rootPort: io_connect_t, notificationID: Int)
    func deregister(_ registration: SystemPowerRegistration)
}
```

`SystemPowerRegistration` must own the root power port, notification object, notification port, and run-loop source needed for complete cleanup.

- [ ] **Step 1: Write failing message-mapping tests**

Add tests for exact mappings:

```text
kIOMessageCanSystemSleep -> .canSleep + allowPowerChange
kIOMessageSystemWillSleep -> .willSleep + allowPowerChange
kIOMessageSystemWillPowerOn -> .willPowerOn, no wake callback
kIOMessageSystemHasPoweredOn -> .hasPoweredOn, wake callback once
unknown message -> ignored
```

Use a fake operator that records register, allow, and deregister calls.

- [ ] **Step 2: Write failing lifecycle tests**

Cover:

```text
start twice -> one registration
stop twice -> one deregistration
registration failure -> throws and leaves no active registration
deinit after start -> cleanup once
has-powered-on -> existing wake adapter callback exactly once
```

- [ ] **Step 3: Run Task 2 RED**

```bash
swift test --filter IOKitSystemPowerObserverTests
```

Expected: compile failure because the observer types do not exist.

- [ ] **Step 4: Implement native registration wrapper**

Use:

```swift
IORegisterForSystemPower
IOAllowPowerChange
IODeregisterForSystemPower
IOServiceClose
IONotificationPortGetRunLoopSource
IONotificationPortDestroy
```

Schedule the notification run-loop source on a dedicated thread/run loop. The callback must copy only stable values into Swift-owned data before dispatching to the observer.

- [ ] **Step 5: Implement exact message handling**

The observer must acknowledge can-sleep and will-sleep before forwarding their events. It must not begin recovery on will-power-on. Only has-powered-on is adapted to the existing `SystemWakeObserving` callback used by `LidSleepCoordinator`.

Provide an adapter:

```swift
final class IOKitSystemWakeObserver: SystemWakeObserving {
    init(powerObserver: SystemPowerObserving = IOKitSystemPowerObserver())
}
```

Replace `WorkspaceSystemWakeObserver` in the foreground CLI composition as well.
After focused and full tests pass, remove `import AppKit`, delete the workspace
notification implementation, and remove `.linkedFramework("AppKit")` from
`Package.swift`. The resulting CLI, daemon spike, and sleep probe must link only
the frameworks they require; no executable in this package may depend on a
logged-in `NSWorkspace` notification path.

- [ ] **Step 6: Run Task 2 GREEN**

```bash
swift test --filter IOKitSystemPowerObserverTests
swift test --filter LidSleepCoordinatorTests
swift test
swift build -c release
otool -L .build/release/macbook-lid-monitor-daemon-spike | grep -F AppKit && exit 1 || true
git diff --check
```

Expected: all tests pass, with no machine sleep or LaunchDaemon registration.

- [ ] **Step 7: Task 2 review and findings**

Review callback lifetime, unmanaged context ownership, run-loop shutdown,
acknowledgement ordering, double cleanup, unknown message handling, the guarantee
that will-power-on cannot start wake recovery, and the absence of AppKit linkage
from the daemon spike. Record findings, fix P0/P1, and repeat Step 6.

- [ ] **Step 8: Commit Task 2**

```bash
git add Package.swift Sources/LidMonitorCore/IOKitSystemPowerObserver.swift Sources/LidMonitorCore/SystemWakeObserver.swift Tests/LidMonitorTests/IOKitSystemPowerObserverTests.swift docs/superpowers/reviews/2026-07-26-launchdaemon-feasibility-spike-task-reviews.md
git commit -m "feat: observe system power events with iokit"
```

---

### Task 3: Build the Permanently Dry-Run Daemon Spike Runtime

**Purpose:** Compose the accepted core into a noninteractive daemon process that can never issue a real sleep request.

**Files:**
- Create: `Sources/LidMonitorCore/DaemonSpikeApplication.swift`
- Create: `Sources/LidMonitorCore/ProcessSignalController.swift`
- Modify: `Sources/LidMonitorDaemonSpike/main.swift`
- Create: `Tests/LidMonitorTests/DaemonSpikeCompositionTests.swift`
- Create: `Tests/LidMonitorTests/ProcessSignalControllerTests.swift`
- Modify: `docs/superpowers/reviews/2026-07-26-launchdaemon-feasibility-spike-task-reviews.md`

**Interfaces:**

```swift
public enum LidMonitorDaemonSpikeEntryPoint {
    public static func run() -> Int32
}

struct DaemonSpikeDependencies {
    let enumerator: HIDDeviceEnumerating
    let streamFactory: (HIDDeviceDescriptor) throws -> HIDReportStreaming
    let decoder: LidAngleDecoding
    let scheduler: OneShotScheduling
    let wakeObserver: SystemWakeObserving
    let evidenceSink: DaemonSpikeEvidenceSinking
    let now: @Sendable () -> Date
}
```

The production composition must always create `DryRunSleepRequester`; no execution mode parameter is exposed.

- [ ] **Step 1: Write failing composition safety tests**

Add tests that inject a trap system-sleep factory and prove it is never called:

```swift
var realSleepConstructionCount = 0
let application = DaemonSpikeApplication(
    dependencies: .test(
        makeRealSleepOperation: {
            realSleepConstructionCount += 1
            return TrapSleepOperation()
        }
    )
)

XCTAssertEqual(realSleepConstructionCount, 0)
```

Prefer removing the real-sleep factory entirely from daemon dependencies. If no such dependency exists, assert the daemon composition exposes only a `DryRunSleepRequester` through an injected requester factory that accepts no mode.

- [ ] **Step 2: Write failing startup and shutdown tests**

Cover:

```text
start -> enumerate -> rank -> open stream -> start wake observer
no selectable candidate -> unavailable exit and explicit evidence
stream open failure -> I/O exit and explicit evidence
SIGTERM -> coordinator stop -> observer stop -> stream close -> process exits
stop twice -> cleanup once
```

- [ ] **Step 3: Run Task 3 RED**

```bash
swift test --filter DaemonSpikeCompositionTests
swift test --filter ProcessSignalControllerTests
```

Expected: compile failure because daemon runtime types do not exist.

- [ ] **Step 4: Implement reusable signal controller**

Extract the current pipe plus `DispatchSourceRead` pattern into `ProcessSignalController`. The C signal handler may only write a byte to the pipe. Swift cleanup runs on the dispatch source and invokes one idempotent stop closure.

Required signals:

```text
SIGTERM
SIGINT
```

- [ ] **Step 5: Implement daemon startup composition**

The entry point must:

```text
emit runtime identity
enumerate and rank candidates
emit selected candidate evidence
create IOHIDReportStream
create IOKitSystemWakeObserver
create LidSleepCoordinator with calibrated policy
create DryRunSleepRequester only
start signal handling
start coordinator
run until SIGTERM/SIGINT or startup failure
clean up exactly once
```

It must not parse command-line flags. Any arguments other than the executable name should produce a usage error and no startup.

- [ ] **Step 6: Preserve startup fail-open semantics**

The daemon starts in the existing five-second startup cooldown. Starting with a low angle remains disarmed until a later `>=75` report. No daemon-specific bypass is allowed.

- [ ] **Step 7: Run Task 3 GREEN**

```bash
swift test --filter DaemonSpikeCompositionTests
swift test --filter ProcessSignalControllerTests
swift test
swift build -c release
strings .build/release/macbook-lid-monitor-daemon-spike | grep -F -- '--execute-sleep' && exit 1 || true
git diff --check
```

Expected:

```text
all tests pass
daemon spike builds
no execute-sleep option string is present in its dedicated entry-point contract
no real sleep occurs
```

The string scan is supplementary; composition tests and source review remain authoritative because shared libraries may contain unrelated CLI strings.

- [ ] **Step 8: Task 3 review and findings**

Review dry-run construction authority, argument rejection, exactly-once startup/stop, signal safety, no terminal dependency, candidate threshold preservation, and failure exit codes. Record findings, fix P0/P1, and repeat Step 7.

- [ ] **Step 9: Commit Task 3**

```bash
git add Sources/LidMonitorCore/DaemonSpikeApplication.swift Sources/LidMonitorCore/ProcessSignalController.swift Sources/LidMonitorDaemonSpike/main.swift Tests/LidMonitorTests/DaemonSpikeCompositionTests.swift Tests/LidMonitorTests/ProcessSignalControllerTests.swift docs/superpowers/reviews/2026-07-26-launchdaemon-feasibility-spike-task-reviews.md
git commit -m "feat: add dry-run launchdaemon spike runtime"
```

---

### Task 4: Add Bounded Feasibility Evidence

**Purpose:** Produce sufficient loginwindow and lifecycle proof without per-report logging or artificial periodic wakeups.

**Files:**
- Create: `Sources/LidMonitorCore/DaemonSpikeEvidence.swift`
- Modify: `Sources/LidMonitorCore/DaemonSpikeApplication.swift`
- Modify: `Sources/LidMonitorCore/IOKitSystemPowerObserver.swift`
- Create: `Tests/LidMonitorTests/DaemonSpikeEvidenceTests.swift`
- Modify: `docs/superpowers/reviews/2026-07-26-launchdaemon-feasibility-spike-task-reviews.md`

**Interfaces:**

```swift
enum DaemonSpikeEvidenceEvent: Equatable, Sendable {
    case runtimeStarted(RuntimeIdentity)
    case candidateSelected(HIDDeviceDescriptor, score: Int)
    case hidOpened(registryID: UInt64)
    case hidOpenFailed(registryID: UInt64, code: Int32)
    case firstValidReport(angle: Int, count: UInt64)
    case reportMilestone(angle: Int, count: UInt64)
    case power(SystemPowerEvent)
    case stopping(reason: String)
}

protocol DaemonSpikeEvidenceSinking: Sendable {
    func emit(_ event: DaemonSpikeEvidenceEvent)
}
```

- [ ] **Step 1: Write failing stable-format tests**

Assert exact key-value output including ISO-8601 timestamp, PID, UID/GID where applicable, registry ID, hexadecimal HID identities, count, angle, and power event names.

Example expected line:

```text
timestamp=2026-07-26T21:30:00+08:00 event=first-valid-report pid=123 angle=172 count=1
```

- [ ] **Step 2: Write failing bounded-report tests**

Use milestones:

```text
count 1 -> first-valid-report
count 100 -> report-milestone
count 200 -> report-milestone
all other counts -> no evidence output
```

Do not schedule a timer only to emit report milestones. A report itself drives the count.

- [ ] **Step 3: Run Task 4 RED**

```bash
swift test --filter DaemonSpikeEvidenceTests
```

Expected: compile failure because evidence types do not exist.

- [ ] **Step 4: Implement evidence formatting and sink**

Use `FileHandle.standardOutput` or `FileHandle.standardError` for stable line writes so launchd can route output. Avoid `print` buffering ambiguity. Include one complete UTF-8 line per event.

Do not log raw report bytes in daemon mode.

- [ ] **Step 5: Wire lifecycle and power evidence**

Emit:

```text
runtime-started before HID discovery
candidate-selected after ranking
hid-opened only after successful stream open/start
first-valid-report and count milestones from decoded valid reports
power events from IOKit observer
stopping before cleanup
```

Policy transition output remains separate and uses the existing formatter.

- [ ] **Step 6: Run Task 4 GREEN**

```bash
swift test --filter DaemonSpikeEvidenceTests
swift test --filter DaemonSpikeCompositionTests
swift test
swift build -c release
git diff --check
```

- [ ] **Step 7: Task 4 review and findings**

Review privacy, log volume, deterministic formatting, timestamp authority, PID correlation, report count overflow behavior, no raw bytes, and no logging timer. Record findings, fix P0/P1, and repeat Step 6.

- [ ] **Step 8: Commit Task 4**

```bash
git add Sources/LidMonitorCore/DaemonSpikeEvidence.swift Sources/LidMonitorCore/DaemonSpikeApplication.swift Sources/LidMonitorCore/IOKitSystemPowerObserver.swift Tests/LidMonitorTests/DaemonSpikeEvidenceTests.swift docs/superpowers/reviews/2026-07-26-launchdaemon-feasibility-spike-task-reviews.md
git commit -m "feat: record bounded daemon feasibility evidence"
```

---

### Task 5: Add the Separately Gated One-Shot Sleep Probe

**Purpose:** Make daemon-context `IOPMSleepSystem` testable without connecting real sleep to the installed sensor-driven spike.

**Files:**
- Create: `Sources/LidMonitorCore/SleepProbeApplication.swift`
- Modify: `Sources/LidMonitorSleepProbe/main.swift`
- Create: `Tests/LidMonitorTests/SleepProbeApplicationTests.swift`
- Modify: `docs/superpowers/reviews/2026-07-26-launchdaemon-feasibility-spike-task-reviews.md`

**Command contract:**

```text
macbook-lid-monitor-sleep-probe --dry-run
macbook-lid-monitor-sleep-probe --execute-once --approval-token I-APPROVE-ONE-DAEMON-SLEEP
```

The literal token is a local safety interlock, not a substitute for conversational user approval. The real command must not be executed until the user explicitly approves the Task.

- [ ] **Step 1: Write failing parser and one-shot tests**

Cover:

```text
no args -> usage, no operation
--dry-run -> reports would-request-sleep, no operation
--execute-once without exact token -> usage, no operation
wrong token -> usage, no operation
exact execute command -> operation called exactly once
operation throws -> stable failure, no retry, nonzero exit
extra arguments -> usage, no operation
```

- [ ] **Step 2: Run Task 5 RED**

```bash
swift test --filter SleepProbeApplicationTests
```

Expected: compile failure because the sleep probe application does not exist.

- [ ] **Step 3: Implement the one-shot application**

Inject `SystemSleepOperating`. The application must call `requestSleep()` at most once, emit one stable result line, and exit. It must not initialize HID, coordinator, scheduler, or power observer.

- [ ] **Step 4: Implement the executable entry point**

`Sources/LidMonitorSleepProbe/main.swift` passes explicit command-line arguments to the core entry point and exits with its result.

- [ ] **Step 5: Run Task 5 GREEN without real sleep**

```bash
swift test --filter SleepProbeApplicationTests
swift test
swift build -c release
.build/release/macbook-lid-monitor-sleep-probe --dry-run
git diff --check
```

Expected:

```text
dry-run output only
zero real sleep operations
all tests pass
```

Do not run `--execute-once` in this Task.

- [ ] **Step 6: Task 5 review and findings**

Review command ambiguity, exact-token enforcement, exactly-once invocation, no retry, no sensor dependency, and separation from daemon plist. Record findings, fix P0/P1, and repeat Step 5.

- [ ] **Step 7: Commit Task 5**

```bash
git add Sources/LidMonitorCore/SleepProbeApplication.swift Sources/LidMonitorSleepProbe/main.swift Tests/LidMonitorTests/SleepProbeApplicationTests.swift docs/superpowers/reviews/2026-07-26-launchdaemon-feasibility-spike-task-reviews.md
git commit -m "feat: add one-shot daemon sleep probe"
```

---

### Task 6: Add Temporary LaunchDaemon Packaging and Safe Management

**Purpose:** Define transparent, allowlisted install/status/log/stop/uninstall operations without installing anything yet.

**Files:**
- Create: `packaging/launchd/com.crazydennies.macbook-lid-monitor.feasibility.plist`
- Create: `scripts/manage-feasibility-daemon.sh`
- Create: `Tests/LidMonitorTests/FeasibilityPackagingTests.swift`
- Modify: `.gitignore` only if generated local evidence requires it
- Modify: `docs/superpowers/reviews/2026-07-26-launchdaemon-feasibility-spike-task-reviews.md`

**Plist contract:**

```xml
<key>Label</key>
<string>com.crazydennies.macbook-lid-monitor.feasibility</string>
<key>ProgramArguments</key>
<array>
  <string>/Library/PrivilegedHelperTools/macbook-lid-monitor-daemon-spike</string>
</array>
<key>RunAtLoad</key>
<true/>
<key>ProcessType</key>
<string>Background</string>
<key>ThrottleInterval</key>
<integer>30</integer>
```

Do not add `KeepAlive`, `UserName`, execute-sleep arguments, shell interpreters, or user-writable paths.

- [ ] **Step 1: Write failing packaging contract tests**

Tests must parse the repository plist and assert:

```text
exact label
exact fixed binary path
RunAtLoad true
ProcessType Background
ThrottleInterval >= 30
KeepAlive absent
UserName absent for initial root feasibility
StandardOutPath/StandardErrorPath either absent or inside the fixed feasibility log directory
no execute-sleep argument
no shell command
```

Tests must inspect the management script text and assert its only mutable system paths are the fixed binary, plist, and feasibility log directory.

- [ ] **Step 2: Run Task 6 RED**

```bash
swift test --filter FeasibilityPackagingTests
```

Expected: failure because packaging files do not exist.

- [ ] **Step 3: Create the plist template**

Use the fixed contract above. If file logging is selected for loginwindow evidence, add:

```text
StandardOutPath=/Library/Logs/MacBookLidMonitor/Feasibility/stdout.log
StandardErrorPath=/Library/Logs/MacBookLidMonitor/Feasibility/stderr.log
```

The script must create the directory as root-owned before bootstrap. If unified logging alone is proven sufficient, omit both paths.

- [ ] **Step 4: Implement the management script**

Supported subcommands:

```text
prepare
install
bootstrap
status
logs
stop
bootout
uninstall
```

Required safety behavior:

- `set -euo pipefail`;
- require root only for modifying system paths;
- resolve repository release binary before copying;
- refuse install when the label is already loaded;
- copy to a temporary file in the destination directory, set `root:wheel 0755`, then atomically rename;
- install plist as `root:wheel 0644`;
- run `plutil -lint` before bootstrap;
- `status` uses `launchctl print system/<label>`;
- `stop` sends SIGTERM without deleting files;
- `bootout` unloads the exact plist/job;
- `uninstall` bootouts first, verifies no process, then removes only allowlisted paths;
- never use `rm -rf` on a variable or parent directory;
- never enable or bootstrap automatically from `install` unless the subcommand explicitly says so.

- [ ] **Step 5: Run Task 6 GREEN without sudo installation**

```bash
plutil -lint packaging/launchd/com.crazydennies.macbook-lid-monitor.feasibility.plist
bash -n scripts/manage-feasibility-daemon.sh
swift test --filter FeasibilityPackagingTests
swift test
git diff --check
```

If `shellcheck` is installed:

```bash
shellcheck scripts/manage-feasibility-daemon.sh
```

If unavailable, record that fact and perform an explicit manual shell review.

- [ ] **Step 6: Task 6 review and findings**

Review path traversal, quoting, symlink handling, ownership order, duplicate label detection, install/bootstrap separation, uninstall allowlist, and absence of `KeepAlive`. Record findings, fix P0/P1, and repeat Step 5.

- [ ] **Step 7: Commit Task 6**

```bash
git add packaging/launchd/com.crazydennies.macbook-lid-monitor.feasibility.plist scripts/manage-feasibility-daemon.sh Tests/LidMonitorTests/FeasibilityPackagingTests.swift docs/superpowers/reviews/2026-07-26-launchdaemon-feasibility-spike-task-reviews.md
git commit -m "feat: add safe feasibility daemon packaging"
```

---

### Task 7: Pre-Installation Foreground Spike Validation and Operator Documentation

**Purpose:** Prove the daemon executable, IOKit observer registration, evidence, and cleanup in a normal foreground process before requesting system installation approval.

**Files:**
- Create: `docs/validation/2026-07-26-launchdaemon-feasibility-spike.md`
- Modify: `README.md`
- Modify: `docs/superpowers/reviews/2026-07-26-launchdaemon-feasibility-spike-task-reviews.md`

- [ ] **Step 1: Add Traditional Chinese operator documentation**

Update README with a clearly experimental section that states:

```text
目前仍是前景 CLI
LaunchDaemon spike 尚未安裝
spike 永遠 dry-run
正式 daemon 尚未批准
安裝、登出、睡眠、重啟與 one-shot sleep probe 各自需要批准
```

Create the validation document with sections for baseline, foreground spike, logged-in daemon, loginwindow, power events, sleep probe, reboot, cleanup, findings, and final disposition.

- [ ] **Step 2: Run clean automated validation**

```bash
swift package clean
swift test
swift build -c release
plutil -lint packaging/launchd/com.crazydennies.macbook-lid-monitor.feasibility.plist
bash -n scripts/manage-feasibility-daemon.sh
git diff --check
```

Record exact test count and build result.

- [ ] **Step 3: Start the daemon spike manually in foreground**

Run without sudo and without installation:

```bash
.build/release/macbook-lid-monitor-daemon-spike
```

Verify:

```text
runtime identity emitted
candidate selected
HID opened
first valid report emitted
startup cooldown and rearmed behavior correct
IOKit power observer registration succeeds
no sleep-requested event
```

Move the lid only through safe dry-run positions. Do not invoke macOS sleep.

- [ ] **Step 4: Stop with SIGTERM and inspect cleanup**

From another shell:

```bash
kill -TERM <pid>
```

Verify prompt exit, final stopping evidence, no residual process, and no repeated restart.

- [ ] **Step 5: Record foreground evidence**

Add exact timestamps, PID, UID, sensor identity, first valid report, transition output, stop result, and confirmation that no `/Library` path was modified.

- [ ] **Step 6: Task 7 review and findings**

Review documentation accuracy, foreground evidence sufficiency, unexpected AppKit/session dependency, observer startup behavior, and cleanup. Fix P0/P1 and repeat Steps 2-4 as needed.

- [ ] **Step 7: Commit Task 7**

```bash
git add README.md docs/validation/2026-07-26-launchdaemon-feasibility-spike.md docs/superpowers/reviews/2026-07-26-launchdaemon-feasibility-spike-task-reviews.md
git commit -m "docs: validate foreground daemon spike"
```

**Gate after Task 7:** Stop and request explicit approval before Task 8 modifies `/Library` or calls `launchctl bootstrap system`.

---

### Task 8: Logged-In LaunchDaemon Dry-Run Acceptance

**Approval required:** Explicit user approval to install the temporary root LaunchDaemon. This approval does not authorize logout, sleep, reboot, shutdown, or the real sleep probe.

**Purpose:** Verify system-domain startup, root identity, HID open/report delivery, dry-run policy, status, stop, bootout, and reinstall while the user remains logged in.

**Files:**
- Modify: `docs/validation/2026-07-26-launchdaemon-feasibility-spike.md`
- Modify: `docs/superpowers/reviews/2026-07-26-launchdaemon-feasibility-spike-task-reviews.md`

- [ ] **Step 1: Reconfirm the approved artifact**

```bash
git status --short
swift test
swift build -c release
plutil -lint packaging/launchd/com.crazydennies.macbook-lid-monitor.feasibility.plist
shasum -a 256 .build/release/macbook-lid-monitor-daemon-spike packaging/launchd/com.crazydennies.macbook-lid-monitor.feasibility.plist
```

Record hashes before installation.

- [ ] **Step 2: Install without bootstrapping**

```bash
sudo ./scripts/manage-feasibility-daemon.sh install
```

Verify exact path, owner, group, mode, and checksum. Confirm no process exists yet.

- [ ] **Step 3: Bootstrap the system job**

```bash
sudo ./scripts/manage-feasibility-daemon.sh bootstrap
./scripts/manage-feasibility-daemon.sh status
```

Verify one loaded label and one daemon process running as UID 0.

- [ ] **Step 4: Validate HID and dry-run behavior**

Inspect logs/evidence for candidate selection, open success, first valid report, and report milestones. Move the lid below `68` long enough for the existing debounce and verify exactly:

```text
candidate-started
triggered
would-sleep
```

Verify no `sleep-requested` and no macOS sleep.

- [ ] **Step 5: Validate stop and bootout**

```bash
sudo ./scripts/manage-feasibility-daemon.sh stop
sudo ./scripts/manage-feasibility-daemon.sh bootout
```

Verify process absence and unloaded job. Because `KeepAlive` is absent, SIGTERM must not cause automatic restart.

- [ ] **Step 6: Validate manual re-bootstrap**

Bootstrap again and verify a new single process starts cleanly and reopens the sensor.

- [ ] **Step 7: Task 8 review and findings**

Review root identity, exact job count, HID/report evidence, dry-run enforcement, stop behavior, and residual files/processes. Fix P0/P1 before proceeding. Any fix requires bootout, source change, automated validation, commit, reinstall from new hashes, and re-acceptance.

- [ ] **Step 8: Commit Task 8 evidence**

```bash
git add docs/validation/2026-07-26-launchdaemon-feasibility-spike.md docs/superpowers/reviews/2026-07-26-launchdaemon-feasibility-spike-task-reviews.md
git commit -m "docs: accept logged-in launchdaemon dry-run"
```

**Gate after Task 8:** Stop and request explicit approval before logging out for Task 9.

---

### Task 9: Loginwindow HID and Report Continuity Acceptance

**Approval required:** Explicit user approval to log out. This approval does not authorize sleep, reboot, shutdown, or the real sleep probe.

**Purpose:** Prove that the system LaunchDaemon receives valid lid reports while no user is logged in and remains the same single system job after login.

**Files:**
- Modify: `docs/validation/2026-07-26-launchdaemon-feasibility-spike.md`
- Modify: `docs/superpowers/reviews/2026-07-26-launchdaemon-feasibility-spike-task-reviews.md`

- [ ] **Step 1: Establish pre-logout evidence**

Record:

```text
current daemon PID
job status
latest report count and timestamp
current valid angle
confirmation of dry-run mode
```

Ensure an emergency local recovery command is available after login:

```bash
sudo launchctl bootout system/com.crazydennies.macbook-lid-monitor.feasibility
```

- [ ] **Step 2: Log out and remain at loginwindow**

The user performs logout. Do not automate it. Remain at loginwindow for a bounded interval agreed immediately before the test.

During loginwindow, move the lid through safe observable positions while keeping the Mac usable. Do not intentionally trigger real sleep; the job is dry-run.

- [ ] **Step 3: Log back in and collect evidence**

Compare:

```text
launchd label remains loaded
PID is unchanged or any change is explained by an observed crash/restart
report milestones have timestamps inside the logged-out interval
decoded angle changes correspond to loginwindow lid movement
only one daemon process exists
no user LaunchAgent exists
```

- [ ] **Step 4: Determine disposition**

Pass requires report evidence generated during loginwindow. A gap with only pre-logout and post-login reports is a failure/unknown, not a pass.

If the sensor was unavailable only at initial boot timing but works after later publication, record the exact timing and create a new reviewed Task for event-driven IOHID matching before continuing.

- [ ] **Step 5: Task 9 review and findings**

Review timestamp correlation, PID/job continuity, duplicate process checks, session assumptions, and fail-open behavior. Any P0/P1 blocks Task 10.

- [ ] **Step 6: Commit Task 9 evidence**

```bash
git add docs/validation/2026-07-26-launchdaemon-feasibility-spike.md docs/superpowers/reviews/2026-07-26-launchdaemon-feasibility-spike-task-reviews.md
git commit -m "docs: validate loginwindow lid reports"
```

**Gate after Task 9:** Stop and request explicit approval before manually sleeping the Mac for Task 10.

---

### Task 10: IOKit Sleep/Wake Notification Dry-Run Acceptance

**Approval required:** Explicit user approval for one bounded manual sleep/wake cycle. The daemon remains dry-run and must not invoke `IOPMSleepSystem`.

**Purpose:** Verify system power callbacks, acknowledgements, wake mapping, recovery scheduling, and HID continuation in LaunchDaemon context.

**Files:**
- Modify: `docs/validation/2026-07-26-launchdaemon-feasibility-spike.md`
- Modify: `docs/superpowers/reviews/2026-07-26-launchdaemon-feasibility-spike-task-reviews.md`

- [ ] **Step 1: Establish pre-sleep state**

Verify one loaded dry-run daemon, current PID, valid reports, angle `>=75`, and no sleep-capable daemon/probe process.

- [ ] **Step 2: User manually requests macOS sleep**

Do not call the sleep probe. The user initiates sleep through macOS UI or another explicitly approved manual mechanism.

- [ ] **Step 3: Wake and exercise recovery**

After wake, verify ordered evidence:

```text
power-will-sleep
power-will-power-on
power-has-powered-on
auto-sleep: wake-recovery
fresh valid report
```

For one bounded branch, keep the angle `<75` and verify only `recovery-resleep` plus `would-sleep`; the machine must not sleep from the daemon. For another separately repeated manual cycle, or within the same approved test if explicitly agreed, open to `>=75` and verify recovery cancellation/rearm.

- [ ] **Step 4: Check acknowledgements and duplicate behavior**

Use unit-test evidence for exact `IOAllowPowerChange` calls and runtime evidence for successful sleep progression. Verify one has-powered-on event produces one recovery generation and no duplicate would-sleep.

- [ ] **Step 5: Task 10 review and findings**

Review event ordering, wake trigger choice, report resumption, duplicate callbacks, stale timers, and process continuity. Any P0/P1 blocks the real sleep probe.

- [ ] **Step 6: Commit Task 10 evidence**

```bash
git add docs/validation/2026-07-26-launchdaemon-feasibility-spike.md docs/superpowers/reviews/2026-07-26-launchdaemon-feasibility-spike-task-reviews.md
git commit -m "docs: validate daemon power notifications"
```

**Gate after Task 10:** Boot out the dry-run daemon and request explicit approval before Task 11 executes the real one-shot sleep probe.

---

### Task 11: Daemon-Context `IOPMSleepSystem` One-Shot Acceptance

**Approval required:** Explicit user approval for one real sleep request from the one-shot probe. The dry-run LaunchDaemon must be booted out first.

**Purpose:** Prove whether `IOPMSleepSystem` succeeds from the intended root/system execution context without introducing sensor-driven or retry behavior.

**Files:**
- Modify: `docs/validation/2026-07-26-launchdaemon-feasibility-spike.md`
- Modify: `docs/superpowers/reviews/2026-07-26-launchdaemon-feasibility-spike-task-reviews.md`

- [ ] **Step 1: Boot out and verify single authority**

```bash
sudo ./scripts/manage-feasibility-daemon.sh bootout
pgrep -lf macbook-lid-monitor-daemon-spike
```

Expected: no daemon-spike process.

- [ ] **Step 2: Revalidate the probe dry-run**

```bash
.build/release/macbook-lid-monitor-sleep-probe --dry-run
```

Expected: would-request output, no sleep.

- [ ] **Step 3: Execute exactly one approved root probe**

```bash
sudo .build/release/macbook-lid-monitor-sleep-probe \
  --execute-once \
  --approval-token I-APPROVE-ONE-DAEMON-SLEEP
```

Do not wrap this command in a retry, loop, launchd job, shell alias, or background supervisor.

- [ ] **Step 4: Collect independent evidence**

After wake, record:

```text
probe result line
exit behavior
macOS power-management log showing software sleep and PID attribution
no second probe process
no automatic retry
```

- [ ] **Step 5: Restore dry-run spike only if further validation is required**

Re-bootstrap only after confirming the probe process is gone. The production execute-sleep phase remains unimplemented.

- [ ] **Step 6: Task 11 review and findings**

Review root context, exactly-once execution, error propagation, independent macOS evidence, and absence of retry/sensor coupling. Record pass/fail honestly; a failed API call blocks production execute-sleep but does not erase earlier HID/loginwindow findings.

- [ ] **Step 7: Commit Task 11 evidence**

```bash
git add docs/validation/2026-07-26-launchdaemon-feasibility-spike.md docs/superpowers/reviews/2026-07-26-launchdaemon-feasibility-spike-task-reviews.md
git commit -m "docs: record daemon sleep probe acceptance"
```

---

### Task 12: Reboot Auto-Start Dry-Run Acceptance

**Approval required:** Explicit user approval to reboot. This Task remains dry-run and must not run the sleep probe.

**Purpose:** Verify that launchd starts the temporary service during normal boot before login and that loginwindow HID evidence exists after a cold service start.

**Files:**
- Modify: `docs/validation/2026-07-26-launchdaemon-feasibility-spike.md`
- Modify: `docs/superpowers/reviews/2026-07-26-launchdaemon-feasibility-spike-task-reviews.md`

- [ ] **Step 1: Prepare recoverability**

Verify FileVault remains off, the installed plist is dry-run, no sleep probe is running, and exact emergency removal steps are available. Record binary/plist hashes and current job status.

- [ ] **Step 2: Reboot**

The user performs the reboot. Do not automate reboot without the explicit approval recorded for this Task.

- [ ] **Step 3: Pause at loginwindow**

Before login, remain at loginwindow for a bounded interval and move the lid through safe observable angles. Do not intentionally close far enough to impede login.

- [ ] **Step 4: Log in and inspect boot evidence**

Verify:

```text
runtime-start timestamp precedes user login
UID is 0
candidate selected and HID opened before login or after an explicitly observed device-publication delay
valid report evidence exists during loginwindow
one job/process only
login does not replace the system job
no real sleep event
```

- [ ] **Step 5: Task 12 review and findings**

Review boot ordering, sensor publication timing, launchd restart evidence, loginwindow report proof, and duplicate process checks. A race requiring event-driven device publication must be recorded as a P1 and fixed in a newly reviewed implementation subtask before acceptance.

- [ ] **Step 6: Commit Task 12 evidence**

```bash
git add docs/validation/2026-07-26-launchdaemon-feasibility-spike.md docs/superpowers/reviews/2026-07-26-launchdaemon-feasibility-spike-task-reviews.md
git commit -m "docs: validate pre-login reboot auto-start"
```

---

### Task 13: Uninstall Acceptance and Whole-Phase Final Review

**Purpose:** Remove the temporary system artifacts, prove cleanup, review the complete implementation and evidence, and decide whether production-daemon design is unlocked.

**Files:**
- Modify: `README.md`
- Modify: `docs/validation/2026-07-26-launchdaemon-feasibility-spike.md`
- Modify: `docs/superpowers/reviews/2026-07-26-launchdaemon-feasibility-spike-task-reviews.md`
- Create: `docs/superpowers/reviews/2026-07-26-launchdaemon-feasibility-spike-final-review.md`

- [ ] **Step 1: Run safe uninstall**

```bash
sudo ./scripts/manage-feasibility-daemon.sh uninstall
```

Verify:

```text
launchctl print system/com.crazydennies.macbook-lid-monitor.feasibility fails as not found
no daemon-spike process
plist absent
installed binary absent
spike-only log directory absent or intentionally preserved only long enough to copy evidence, then removed
existing project and unrelated files untouched
```

- [ ] **Step 2: Run clean final validation**

```bash
git status --short
swift package clean
swift test
swift build -c release
plutil -lint packaging/launchd/com.crazydennies.macbook-lid-monitor.feasibility.plist
bash -n scripts/manage-feasibility-daemon.sh
git diff --check
```

Record exact test count and release artifacts.

- [ ] **Step 3: Perform whole-phase implementation review**

Review all production source changes and all Tasks for:

- shared-core integrity and no behavior regression;
- daemon dry-run mechanical enforcement;
- IOKit callback memory/lifecycle correctness;
- sleep acknowledgement correctness;
- signal-safe shutdown;
- evidence sufficiency and bounded logging;
- fixed-path packaging and uninstall safety;
- no LaunchAgent or duplicate authority;
- no restart storm policy;
- no residual system mutation;
- honest pass/fail treatment of loginwindow and sleep probe unknowns.

Record every finding with severity, evidence, resolution, and re-review result.

- [ ] **Step 4: Fix and re-review**

For code or packaging findings, reopen the relevant Task flow: add a failing test where applicable, implement the fix, run focused and full validation, update evidence if the installed artifact changed, and commit the fix separately.

Require:

```text
Open P0 = 0
Open P1 = 0
```

- [ ] **Step 5: Write final disposition**

The final review must separately state:

```text
logged-in LaunchDaemon HID: pass/fail
loginwindow HID/report delivery: pass/fail
IOKit power notification: pass/fail
daemon-context IOPMSleepSystem probe: pass/fail/not approved
reboot pre-login auto-start: pass/fail/not approved
safe stop/uninstall: pass/fail
production daemon architecture: unlocked/blocked
production execute-sleep: unlocked/blocked
```

Do not collapse a partially approved validation matrix into a blanket pass.

- [ ] **Step 6: Synchronize README in Traditional Chinese**

README must accurately say the spike was temporary and removed, summarize which feasibility claims passed, and state that no production LaunchDaemon is installed. It must not provide production installation instructions before the later production phase.

- [ ] **Step 7: Commit final review**

```bash
git add README.md docs/validation/2026-07-26-launchdaemon-feasibility-spike.md docs/superpowers/reviews/2026-07-26-launchdaemon-feasibility-spike-task-reviews.md docs/superpowers/reviews/2026-07-26-launchdaemon-feasibility-spike-final-review.md
git commit -m "docs: complete launchdaemon feasibility review"
```

- [ ] **Step 8: Push only after user approval**

Before push:

```bash
git status --short
git log --oneline --decorate -15
git diff origin/main...HEAD --check
```

Request explicit approval, then:

```bash
git push origin main
```

## Plan Completion Gate

Implementation may begin only after:

```text
plan review completed
Open P0 = 0
Open P1 = 0
user explicitly approves implementation
```

The first implementation session begins with Task 1 only. Task 8, Task 9, Task
10, Task 11, and Task 12 retain their own explicit approval gates regardless of
the general implementation approval.

