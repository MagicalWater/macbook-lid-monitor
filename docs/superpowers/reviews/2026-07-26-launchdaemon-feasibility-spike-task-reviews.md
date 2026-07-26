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

## Task 3 — Build the Permanently Dry-Run Daemon Spike Runtime

### Findings

#### P1-1 — Stream factory failure lacked evidence
Resolved by emitting `streamStartFailed` for both stream construction and stream start failures.

#### P1-2 — Signal-controller startup failure could leave the coordinator active
Resolved by explicitly stopping the session before propagating a signal-controller startup error.

#### P1-3 — Dispatch source file descriptors were closed before cancellation completed
Resolved by moving descriptor closure into the source cancel handler, avoiding descriptor reuse races.

### Re-review

- Production daemon composition constructs `DryRunSleepRequester` directly and exposes no execution mode.
- Extra command-line arguments are rejected before discovery or HID startup.
- Candidate ranking threshold and calibrated startup fail-open policy are unchanged.
- Start, stop, and evidence cleanup are idempotent.
- SIGTERM/SIGINT handlers only write one byte to a pipe; Swift cleanup runs on the dispatch source queue.
- HID construction/start failures map to I/O failure; enumeration/no-candidate failures map to unavailable.
- No terminal or AppKit dependency is present.

### Validation

```text
DaemonSpikeCompositionTests: 7 passed
ProcessSignalControllerTests: 2 passed
swift test: 96 tests, 0 failures
swift build -c release: passed
git diff --check: passed
```

### Disposition

- Open P0: 0
- Open P1: 0
- Open P2: 0
- Task 3: Pass

## Task 4 — Add Bounded Feasibility Evidence

### Findings

#### P1-1 — Concurrent evidence writes could interleave

HID reports, system power callbacks, and signal shutdown can emit from different threads. The initial sink wrote directly to stdout without serialization, which could break the one-complete-line evidence contract.

**Resolution:** Converted the production sink to a lock-protected class with an injectable writer. Every event is fully formatted and encoded before entering the write lock, and tests verify one complete UTF-8 line per write.

#### P2-1 — Formatter closure lacked an explicit Sendable contract

Swift 6 rejected the first implementation because a Sendable sink stored a formatter containing an unannotated closure.

**Resolution:** Made the formatter Sendable and marked its timestamp closure `@Sendable`; concurrency checking remains enabled.

### Re-review

- Runtime evidence includes PID, UID, GID, architecture, and macOS version.
- Candidate evidence includes registry ID, score, vendor/product, usage page/usage, and transport.
- HID open success is emitted only after coordinator startup succeeds; open failure records the IOReturn code when available.
- Valid report evidence is bounded to count 1 and each 100-report milestone, driven only by incoming reports.
- Raw HID bytes and unsupported/malformed payloads are not logged.
- Power events are emitted through the IOKit observer tap; only has-powered-on reaches wake recovery.
- Evidence writes are serialized as complete UTF-8 lines without a logging timer.
- Report counter saturates safely rather than overflowing.

### Validation

```text
DaemonSpikeEvidenceTests: 5 passed
DaemonSpikeCompositionTests: 7 passed
swift test: 101 tests, 0 failures
swift build -c release: passed
git diff --check: passed
```

### Disposition

- Open P0: 0
- Open P1: 0
- Open P2: 0
- Task 4: Pass

## Task 5 — Add the Separately Gated One-Shot Sleep Probe

### Findings

#### P2-1 — Entry-point extraction left trailing whitespace

The first complete validation passed all behavior tests and release build but `git diff --check` found a trailing blank line in the former placeholder location.

**Resolution:** Normalized the file ending and repeated the full Task validation.

### Re-review

- No arguments, incomplete token, wrong token, and extra arguments all return usage without constructing a sleep request.
- Dry-run emits one stable `would-request-sleep` line and never calls `SystemSleepOperating`.
- The exact execute contract calls the injected operation once; failures are visible and never retried.
- The probe initializes no HID discovery, report stream, coordinator, scheduler, or power observer.
- The probe executable is not referenced by daemon composition or packaging.
- Only the dry-run executable path was run during this Task; `--execute-once` was not executed outside unit tests with a fake operation.

### Validation

```text
SleepProbeApplicationTests: 6 passed
swift test: 107 tests, 0 failures
swift build -c release: passed
sleep probe --dry-run: would-request-sleep
git diff --check: passed
real sleep operations: 0
```

### Disposition

- Open P0: 0
- Open P1: 0
- Open P2: 0
- Task 5: Pass

## Task 6 — Add Temporary LaunchDaemon Packaging and Safe Management

### Findings

#### P1-1 — Install could overwrite existing same-name artifacts

The first script refused an already loaded job but could still replace an unloaded binary or plist at the fixed path.

**Resolution:** Installation now refuses if either fixed artifact already exists and requires explicit uninstall first.

#### P1-2 — Nested log-path symlink checks occurred after directory creation

The first sequence used `mkdir -p` before checking the project-specific log parent and leaf, allowing an existing symlink to be followed before rejection.

**Resolution:** All existing parent/leaf paths are checked before directory creation, and source binary/plist symlinks are also rejected.

#### P2-1 — Temporary cleanup used a RETURN trap

A RETURN trap is less transparent across the macOS Bash 3.2 environment.

**Resolution:** Temporary files now use an EXIT trap that is cleared only after both atomic renames succeed.

### Re-review

- Plist uses the exact system label and fixed daemon-spike binary path.
- `RunAtLoad=true`, `ProcessType=Background`, and `ThrottleInterval=30` are explicit.
- `KeepAlive`, `UserName`, shell interpreters, sleep arguments, and sleep-probe paths are absent.
- Install and bootstrap are separate subcommands; install never loads or enables the job.
- Root is required only for system mutations; prepare/status/logs remain non-mutating.
- Source and destination symlinks are rejected, ownership/mode precede atomic rename, and existing artifacts are not overwritten.
- Uninstall bootouts first, checks for a residual exact process name, and removes only fixed files plus the two fixed log files.
- No `rm -rf`, `eval`, variable parent deletion, sudo installation, `/Library` mutation, or launchctl bootstrap occurred during this Task.

### Validation

```text
plutil -lint: passed
bash -n: passed
shellcheck: passed when available
FeasibilityPackagingTests: 2 passed
swift test: 109 tests, 0 failures
git diff --check: passed
system paths modified: none
```

### Disposition

- Open P0: 0
- Open P1: 0
- Open P2: 0
- Task 6: Pass

## Task 7 — Pre-Installation Foreground Spike Validation and Operator Documentation

### Implementation review

Reviewed the foreground daemon composition, explicit IOKit registration evidence, policy-line routing, bounded evidence output, Traditional Chinese operator documentation, SIGTERM cleanup, process residue, and system-path non-modification.

### Findings

#### P1-1 — Power observer registration was only indirectly observable

The first foreground run could infer successful IOKit registration only because coordinator startup completed. That was insufficient for later loginwindow evidence, where registration success and HID success must be independently attributable.

**Resolution:** Added explicit `powerObserverRegistered` and `powerObserverRegistrationFailed` evidence. The success callback runs only after `SystemPowerObserving.start` returns successfully; registration errors remain fail-open and produce stable failure evidence.

#### P1-2 — Daemon policy transitions were not persisted through the evidence sink

The initial daemon composition used empty operational and transition callbacks. Startup cooldown, rearm, triggered, and dry-run `would-sleep` lines therefore could not be captured by launchd stdout routing.

**Resolution:** Wired the existing `OutputFormatter` into the daemon composition and routed policy lines through the same serialized evidence writer used for HID and power events.

#### P2-1 — Existing DevSpace worktree was no longer directly modifiable by the active tool boundary

The original Task 7 worktree was under a restricted DevSpace path. Continuing there would have required non-governed file writes.

**Resolution:** Created a new managed worktree from the accepted Task 6 commit `84a4c2e`, replayed the reviewed uncommitted Task 7 changes, and repeated focused, foreground, and full clean validation. The original worktree was not modified or deleted.

### Re-review

- The daemon executable remains permanently dry-run and exposes no execution argument.
- IOKit registration success is directly evidenced before HID-open success.
- Registration failure remains visible and aborts startup without constructing a real sleep path.
- Startup cooldown, rearm, and later policy transitions use the accepted formatter and one serialized writer.
- No raw HID report bytes are logged.
- The final foreground run selected the verified M1 Pro sensor, opened it, received a valid angle report, and rearmed after startup cooldown.
- SIGTERM emitted one stopping event, exited with code 0, and left no residual daemon-spike process.
- `/Library/PrivilegedHelperTools`, `/Library/LaunchDaemons`, and the feasibility log path were not created or modified.
- README and validation instructions are in Traditional Chinese and clearly preserve separate approval gates.
- No logout, sleep, real one-shot sleep probe, reboot, shutdown, sudo install, or system bootstrap occurred.

### Validation

```text
DaemonSpikeEvidenceTests: passed
IOKitSystemPowerObserverTests: passed
DaemonSpikeCompositionTests: passed
swift package clean: passed
swift test: 110 tests, 0 failures
swift build -c release: passed
plutil -lint: passed
bash -n: passed
shellcheck: passed
git diff --check: passed

foreground PID: 12790
foreground UID/GID: 501/20
power observer registered: evidenced
selected registry ID: 4294968644
first valid report: angle 161, count 1
startup cooldown and rearmed: evidenced
SIGTERM exit: 0
residual daemon process: none
system paths modified: none
real sleep operations: 0
```

### Disposition

- Open P0: 0
- Open P1: 0
- Open P2: 0
- Task 7: Pass
- Task 8: blocked pending explicit user approval to install the temporary LaunchDaemon

## Task 8 — Logged-In LaunchDaemon Dry-Run Acceptance

### Implementation review

Reviewed installation hashes and metadata, system-domain launchd state, root identity, process cardinality, HID and power-observer evidence, real lid-angle trigger behavior, dry-run enforcement, stop/bootout semantics, absence of KeepAlive restart, re-bootstrap behavior, and residual system artifacts.

### Findings

#### P1-1 — Dry-run sleep request was not persisted as evidence

The first root LaunchDaemon run correctly selected and opened the sensor. A real close cycle emitted `candidate-started` and `triggered`, but `would-sleep` was absent. The Mac did not sleep and `sleep-requested` was absent, so the operational path remained dry-run; however, the Task 8 acceptance contract required positive evidence that the dry-run requester was invoked.

**Root cause:** `DaemonSpikeApplication` constructed `DryRunSleepRequester` with an empty callback. Coordinator operational evidence did not receive requester success events.

**Resolution:** Booted out the system job before changing source. Added a controlled-scheduler regression test, verified RED with the exact missing `would-sleep` assertion, wired the requester callback to the shared formatter/evidence sink, and verified GREEN. Rebuilt the release binary, recorded the new hash, uninstalled the old artifact, installed the new artifact, and repeated the full logged-in acceptance.

#### P2-1 — Initial regression-test scheduler executed recursively

The first test scheduler immediately executed every scheduled action, causing startup cooldown and debounce scheduling to recurse synchronously and terminate the test process.

**Resolution:** Replaced it with a controlled queue scheduler and explicitly fired startup cooldown followed by close debounce. The regression then failed only on the intended missing `would-sleep` assertion before the production fix.

### Re-review

- Installed binary and plist matched the pre-install hashes, ownership, group, and modes before the first bootstrap.
- The first and second accepted daemons ran as UID/GID `0/0` in the `system` launchd domain.
- Exactly one loaded label and one daemon process existed during each running state.
- The daemon selected registry ID `4294968644`, registered the IOKit power observer, opened HID, and received a first valid report.
- After the P1 fix, one real close cycle emitted exactly one `candidate-started`, one `triggered`, and one `would-sleep`.
- `sleep-requested` remained absent and macOS did not sleep.
- The binary remains permanently dry-run and still accepts no execution arguments.
- Stop emitted the stopping evidence; bootout removed the job and process.
- Waiting five seconds after stop/bootout produced no automatic restart, consistent with the absence of `KeepAlive`.
- Manual re-bootstrap produced a new root PID `52638`, reopened HID, and received a valid angle report.
- stderr remained empty throughout accepted runs.
- Temporary system artifacts remain intentionally installed for the separately gated Task 9 loginwindow validation.
- No logout, sleep/wake acceptance, real one-shot sleep probe, reboot, or shutdown occurred.

### Validation

```text
pre-install swift test: 110 tests, 0 failures
pre-install release build: passed
pre-install plist lint: passed
initial binary SHA-256: 5dca7d7e91a6e53cef6cc751805a46717999eb8801e94eb2ef2528cdf5e4c750
plist SHA-256: 14798aa8cdfd6978e8a522a0a6731c895b897f68d9046975cfdafe8b61fbc5cc
initial root PID: 41768

regression RED: missing would-sleep assertion failed as expected
regression GREEN: passed
swift test after fix: 111 tests, 0 failures
release build after fix: passed
replacement binary SHA-256: 4a9fd2ed6c585f26954bd5316fb63253821425e78b67f6970ddedc2fd9a6e853

accepted close cycle PID: 47660
candidate-started: 1
triggered: 1
would-sleep: 1
sleep-requested: 0
actual sleep: 0

process after stop/bootout: none
job after bootout: absent
automatic restart after 5 seconds: none

re-bootstrap PID: 52638
re-bootstrap UID/GID: 0/0
re-bootstrap active count: 1
re-bootstrap process count: 1
power observer registered: evidenced
HID reopened: evidenced
first valid report: angle 159, count 1
stderr: empty
```

### Disposition

- Open P0: 0
- Open P1: 0
- Open P2: 0
- Task 8: Pass
- Task 9: blocked pending explicit approval to log out and remain at loginwindow

## Task 9 — Loginwindow HID and Report Continuity Acceptance

### Implementation review

Reviewed pre-logout baseline integrity, console logout/login timing, launchd label and PID continuity, report timestamps inside the logged-out interval, decoded sensor-value movement, dry-run transition counts, duplicate-process checks, user-domain absence, stderr, and fail-open/session assumptions.

### Findings

#### P2-1 — Operator guidance temporarily confused sensor values with physical hinge degrees

The first Task 9 instructions described values such as `0`, `90`, and `180` as ordinary physical opening angles. That contradicted the accepted M1 Pro calibration, where fully closed is approximately sensor value `59`, physical approximately 90° open is around `148`, and fully open is around `189`.

**Impact:** The error was limited to conversational operator guidance before logout. Runtime decoding, thresholds, state-machine comparisons, tests, and the installed LaunchDaemon all continued to use raw decoded sensor values with `68 / 75` policy thresholds. No implementation or prior acceptance evidence was invalidated.

**Resolution:** Stopped before logout, inspected the decoder, calibrated policy, historical hardware validation, and runtime evidence, then replaced the guidance with physical-state wording only: normal open, near-closed, reopen. Documentation now explicitly distinguishes machine-specific sensor values from physical hinge degrees.

### Re-review

- Pre-logout baseline was captured at `2026-07-26T15:44:18Z` with root PID `52638`, one system job, one process, latest report count `300`, and empty stderr.
- Console history records logout at `23:52 +0800` and login at `23:55 +0800`.
- The launchd job remained at `runs=1`; PID `52638` did not change across logout/login.
- Timestamped evidence at `2026-07-26T15:53:27Z` falls inside the loginwindow interval and records sensor value `58`, count `900`.
- Two loginwindow close cycles emitted two `candidate-started`, two `triggered`, two `would-sleep`, and zero `sleep-requested` events.
- Two `rearmed` events confirmed reopening above the accepted sensor threshold.
- Post-login evidence at `2026-07-26T15:55:07Z` records sensor value `160`, count `1000`.
- Exactly one root daemon process existed after login; no user LaunchAgent existed.
- stderr remained empty.
- No manual sleep, reboot, shutdown, or real one-shot sleep probe occurred.

### Validation

```text
pre-logout baseline: 2026-07-26T15:44:18Z
console logout: 2026-07-26 23:52 +0800
console login: 2026-07-26 23:55 +0800
PID before/after: 52638 / 52638
launchd runs: 1
process count: 1
UID/GID: 0/0
loginwindow report: 2026-07-26T15:53:27Z angle=58 count=900
post-login report: 2026-07-26T15:55:07Z angle=160 count=1000
candidate-started: 2
triggered: 2
would-sleep: 2
rearmed: 2
sleep-requested: 0
stderr bytes: 0
user LaunchAgent: absent
```

### Disposition

- Open P0: 0
- Open P1: 0
- Open P2: 0
- Task 9: Pass
- Task 10: approved and completed below

## Task 10 — IOKit Sleep/Wake Notification Dry-Run Acceptance

### Implementation review

Reviewed system-domain power callback ordering, runtime sleep progression, acknowledgement coverage, wake-to-recovery mapping, fresh HID continuation, process continuity, duplicate recovery behavior, dry-run enforcement, and both recovery outcomes: explicit reopen and low-value recovery-resleep.

### Findings

#### Acceptance gap 1 — Second cycle missed the low-value recovery branch

The second approved cycle emitted `wake-recovery → rearmed` before the user lowered the lid. The first fresh post-wake HID report was therefore `>=75`; the later low value correctly entered the ordinary close debounce path and emitted `candidate-started → triggered → would-sleep`.

**Disposition:** Not an implementation defect. The runtime behaved according to the accepted state machine, but this cycle did not satisfy the low-value recovery acceptance condition. A separately approved third cycle held the lid low before sleep and throughout the 15-second recovery window.

#### P2-1 — Low-value recovery purpose required clearer operator explanation

The initial instructions did not clearly distinguish the production intent (request sleep again if the machine wakes while the lid remains closed) from the Task 10 dry-run mechanism (record `recovery-resleep` and `would-sleep` without invoking real sleep).

**Resolution:** Clarified that `<75` means the user has not demonstrably reopened the lid, that values `<=68` are acceptable and easier to hold, and that Task 10 validates the decision path only while Task 11 separately validates the real root/system sleep API.

### Re-review

- First cycle baseline was `2026-07-26T16:01:32Z`, PID `52638`, angle `160`, count `1300`.
- First cycle emitted exactly one `will-sleep`, one `will-power-on`, and one `has-powered-on`, followed by `wake-recovery → rearmed` and a fresh angle `160` report.
- macOS independently recorded Software Sleep at `2026-07-27 00:02:32 +0800` and HID Activity wake at `00:02:55 +0800`.
- Second cycle correctly cancelled recovery on a fresh high report, then completed a normal dry-run close path; it was excluded from low-value branch acceptance.
- Third cycle baseline was `2026-07-26T16:14:18Z`, PID `52638`, angle `159`, count `2100`.
- Third cycle emitted ordered `will-sleep → will-power-on → has-powered-on → wake-recovery → recovery-resleep → would-sleep → rearmed`.
- macOS independently recorded Software Sleep at `2026-07-27 00:14:46 +0800` and HID Activity wake at `00:15:13 +0800`.
- The low-value recovery branch emitted one `recovery-resleep` and one `would-sleep`; no `sleep-requested` event or automatic second real sleep occurred.
- Unit tests verify `IOAllowPowerChange` precedes forwarding for both `canSleep` and `willSleep`.
- `has-powered-on` generated one recovery transition per cycle; no duplicate recovery timer or duplicate `would-sleep` was observed.
- PID remained `52638`, `runs=1`, process count remained one, UID/GID remained `0/0`, and stderr remained empty.
- No one-shot sleep probe, reboot, or shutdown occurred.

### Validation

```text
cycle 1:
will-sleep: 1
will-power-on: 1
has-powered-on: 1
wake-recovery: 1
rearmed: 1
fresh report: angle=160 count=1500

cycle 3:
will-sleep: 1
will-power-on: 1
has-powered-on: 1
wake-recovery: 1
recovery-resleep: 1
would-sleep after recovery: 1
rearmed after reopen: 1
sleep-requested: 0

PID before/after: 52638 / 52638
launchd runs: 1
process count: 1
UID/GID: 0/0
stderr bytes: 0
```

### Disposition

- Open P0: 0
- Open P1: 0
- Open P2: 0
- Task 10: Pass
- Task 11: approved and completed below

## Task 11 — Daemon-Context `IOPMSleepSystem` One-Shot Acceptance

### Implementation review

Reviewed single-authority enforcement, root execution context, approval-token gating, exactly-once behavior, probe output and exit code, macOS power-log attribution, residual processes, retry absence, and post-probe system state.

### Findings

No implementation finding was opened. The probe was structurally isolated from the daemon, accepted no sensor input, performed one synchronous `requestSleep()` call, and had no retry path.

### Re-review

- The dry-run LaunchDaemon was booted out before executing the probe.
- The system launchd label was absent before and after the probe.
- No daemon-spike or sleep-probe process existed before execution.
- Probe dry-run emitted exactly `sleep-probe: would-request-sleep`.
- Release probe SHA-256 was `f0e5f925e02cad9c92bbb3ce6e64201198b90171cba07b6d55b99f5105b6d82b`.
- The approved root command was executed exactly once with the fixed approval token.
- The command returned `probe-exit=0` and persisted `sleep-probe: sleep-requested`.
- macOS independently recorded `Software Sleep pid=75771` at `2026-07-27 00:23:37 +0800` and HID-activity wake at `00:24:08 +0800`.
- Probe log mtime `00:23:32 +0800` correlates with the software-sleep event.
- No probe process remained after wake; no automatic retry or second sleep request occurred.
- The dry-run daemon was not re-bootstraped after the probe.
- No reboot or shutdown occurred.

### Validation

```text
daemon system label before probe: absent
daemon process before probe: absent
probe process before probe: absent
probe dry-run: sleep-probe: would-request-sleep
probe SHA-256: f0e5f925e02cad9c92bbb3ce6e64201198b90171cba07b6d55b99f5105b6d82b
probe exit: 0
probe output: sleep-probe: sleep-requested
macOS sleep: 2026-07-27 00:23:37 +0800 Software Sleep pid=75771
macOS wake: 2026-07-27 00:24:08 +0800 HID Activity
daemon process after probe: absent
probe process after probe: absent
automatic retry: none
```

### Disposition

- Open P0: 0
- Open P1: 0
- Open P2: 0
- Task 11: Pass
- Task 12: approved and completed below

## Task 12 — Reboot Pre-login Auto-start Acceptance

### Implementation review

Reviewed pre-reboot safety state, FileVault status, installed artifact hashes, plist execution mode, shutdown handling, boot ordering, launchd auto-start timing, pre-login device publication, loginwindow HID/report delivery, dry-run policy output, process authority, restart behavior, and post-login continuity.

### Findings

No implementation finding was opened. The HID device was published and opened immediately during boot; no event-driven publication race or restart workaround was required.

### Re-review

- FileVault was Off before reboot.
- Installed daemon SHA-256 remained `4a9fd2ed6c585f26954bd5316fb63253821425e78b67f6970ddedc2fd9a6e853`.
- Installed plist SHA-256 remained `14798aa8cdfd6978e8a522a0a6731c895b897f68d9046975cfdafe8b61fbc5cc`.
- The plist contained `RunAtLoad=true`, no `KeepAlive`, no arguments, and no execute-sleep mode.
- The pre-reboot PID `80025` recorded `stopping reason=signal`.
- macOS boot time was `2026-07-27 00:32:11 +0800`.
- PID `271` recorded `runtime-started` at `00:32:25`, about 14 seconds after boot.
- Candidate selection, power-observer registration, HID open, and first valid report all completed by `00:32:27`.
- Console login occurred at `00:34`, so all startup/HID evidence above occurred at loginwindow.
- Two loginwindow close cycles each emitted `candidate-started → triggered → would-sleep → rearmed`.
- No `sleep-requested` or post-boot real sleep event occurred.
- After login the same PID `271` remained active with `runs=1`, process count one, UID/GID `0/0`.
- Report delivery continued to count `200`; stderr remained empty.
- No user LaunchAgent or duplicate authority existed.

### Validation

```text
boot: 2026-07-27 00:32:11 +0800
runtime-started: 2026-07-27 00:32:25 +0800
first-valid-report: 2026-07-27 00:32:27 +0800
console login: 2026-07-27 00:34 +0800
post-boot PID: 271
launchd runs: 1
process count: 1
UID/GID: 0/0
loginwindow close cycles: 2
would-sleep: 2
sleep-requested: 0
post-login report count: 200
stderr bytes: 0
user LaunchAgent: absent
```

### Disposition

- Open P0: 0
- Open P1: 0
- Open P2: 0
- Task 12: Pass
- Task 13: ready for uninstall acceptance and whole-phase final review

## Task 13 — Uninstall Acceptance and Whole-Phase Final Review

### Implementation review

Reviewed uninstall path safety, fixed-path ownership, symlink refusal, process shutdown ordering, residual system state, shared-core integrity, daemon dry-run enforcement, IOKit callback lifecycle, acknowledgement ordering, signal shutdown, bounded evidence, duplicate authority, restart policy, one-shot sleep isolation, reboot ordering, documentation accuracy, and final architecture disposition.

### Findings

#### P1-1 — README retained pre-acceptance feasibility status

README still stated that the spike had never been installed or bootstrapped and broadly implied that no repository workflow required administrator access.

**Impact:** Runtime and uninstall safety were unaffected, but the public project status and privilege boundary were stale after Tasks 8–12.

**Resolution:** README now distinguishes the normal foreground CLI from explicitly invoked feasibility tooling, records that the phase passed, confirms all temporary artifacts were removed, and states that production deployment remains a separate phase.

### Re-review

- `sudo ./scripts/manage-feasibility-daemon.sh uninstall` completed successfully.
- `launchctl print system/com.crazydennies.macbook-lid-monitor.feasibility` fails as not found.
- No `macbook-lid-monitor-daemon-spike` process remains.
- Installed binary, plist, active logs, bounded backup logs, and feasibility log directory are absent.
- No user LaunchAgent or duplicate authority exists.
- `swift package clean` followed by `swift test` executed 111 tests with zero failures.
- Fresh release build produced both daemon-spike and sleep-probe artifacts in the worktree only.
- Plist lint, shell syntax validation, and `git diff --check` passed.
- Clean validation did not recreate any system artifact.
- All prior P1 findings are resolved; no open P0/P1 remains.
- The feasibility results separately prove logged-in HID, loginwindow HID, power callbacks, root one-shot sleep, reboot pre-login auto-start, and uninstall safety.

### Validation

```text
system launchd label: absent
daemon process: absent
installed binary: absent
installed plist: absent
feasibility log directory: absent
tests: 111 passed, 0 failed
release daemon-spike: built
release sleep-probe: built
plist lint: passed
script syntax: passed
git diff check: passed
```

### Disposition

- Open P0: 0
- Open P1: 0
- Open P2: 0
- Task 13: Pass
- LaunchDaemon feasibility phase: Pass
- Production daemon architecture: Unlocked for a separate formal implementation phase
