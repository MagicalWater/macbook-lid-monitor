# LaunchDaemon Feasibility Spike Design

## Status

Proposed design for the first pre-login persistence feasibility phase. This
phase is documentation-approved only after its dedicated spec review passes.
Implementation remains blocked until the user explicitly approves the plan.

## Problem

`macbook-lid-monitor` currently runs as a foreground Swift command-line process.
Its lid-angle decoding, auto-sleep state machine, one-shot scheduling, and
`IOPMSleepSystem` request path have passed automated and bounded M1 Pro hardware
acceptance. The process is not persistent and its wake integration currently
uses `NSWorkspace.didWakeNotification`, which belongs to the logged-in workspace
environment and cannot be assumed to work in a system LaunchDaemon before user
login.

The final product goal is one system-level service that starts during normal
macOS boot before login, remains the sole sleep-decision authority after login,
survives sleep and wake, and is restarted automatically after reboot. FileVault
is disabled on the validation Mac, so this project does not target FileVault
Preboot. The first unsupported environment is the normal `loginwindow` phase.

The project must not assume that a LaunchDaemon can access the verified M1 Pro
SPU hinge sensor merely because the foreground CLI can. It also must not install
a production sleep-capable daemon before loginwindow HID access, report delivery,
and system power notifications have been demonstrated with a bounded dry-run
spike.

## Phase Boundary

This specification covers only **Phase 1 — LaunchDaemon Feasibility Spike**.

It answers:

1. Can a system-domain LaunchDaemon enumerate and open the verified M1 Pro lid
   sensor before login?
2. Can that same process continue receiving valid input reports before login,
   through login, and after a manually initiated sleep/wake cycle?
3. Can an IOKit system power observer receive and correctly classify sleep/wake
   notifications in daemon context?
4. Can the existing IOKit sleep operation be invoked from daemon context in a
   separately approved bounded test, without making real sleep part of the
   default spike?
5. Does the current architecture support a future Core + CLI + daemon split
   without replacing the accepted state machine and coordinator behavior?

This phase does not produce the final production daemon architecture, installer,
upgrade mechanism, or unattended execute-sleep deployment. Those belong to a
separate production-daemon spec only if this spike passes.

## Goals

1. Add a temporary, explicitly dry-run daemon entry point suitable for a system
   LaunchDaemon feasibility test.
2. Preserve the existing foreground `macbook-lid-monitor` executable and all
   accepted auto-sleep behavior.
3. Replace the daemon's dependency on `NSWorkspace.didWakeNotification` with an
   IOKit system power notification implementation.
4. Record enough lifecycle, identity, HID, report, and power-event evidence to
   distinguish discovery, open, callback, and notification failures.
5. Verify operation in both logged-in and loginwindow contexts using the same
   LaunchDaemon job and process lifecycle.
6. Provide bounded install, status, stop, logs, and uninstall commands for the
   temporary spike.
7. Guarantee that the default spike cannot call `IOPMSleepSystem`.
8. Define a separately gated daemon-context sleep-operation probe that cannot be
   run without explicit user approval.
9. Preserve fail-open behavior whenever sensor data is absent, malformed,
   unsupported, or stale.
10. Produce a clear pass/fail decision that either unlocks or blocks the later
    production-daemon phase.

## Non-Goals

- Installing a production LaunchDaemon.
- Enabling unattended real sleep at boot or loginwindow.
- Adding a LaunchAgent, login item, menu-bar app, GUI, preferences UI, or IPC.
- Introducing `SMAppService` or an application bundle.
- Finalizing the production binary, plist, log, state, upgrade, or rollback
  layout.
- Creating a dedicated service account or declaring root to be the permanent
  runtime identity.
- Persisting lid angle, armed/disarmed state, recovery deadlines, or PID files.
- Modifying NVRAM, `pmset`, system sleep policy, or any persistent power setting.
- Writing HID reports or opening unrelated keyboard/trackpad devices.
- Testing reboot, logout, sleep, shutdown, or real `IOPMSleepSystem` without the
  user's separate explicit approval for the exact test.

## Safety Gates

### Documentation gate

The spec and plan must each follow:

```text
draft
-> immediate review
-> findings recorded
-> fixes applied
-> re-review
-> Open P0/P1 = 0
-> validation
-> commit
```

No implementation begins before the user approves the reviewed plan.

### Installation gate

Creating source files, tests, example plist content, and scripts is allowed only
after plan approval. Copying any plist or binary into `/Library`, calling
`launchctl bootstrap system`, or otherwise registering a system job requires an
additional explicit user approval at the installation task.

### Disruptive-test gate

The following actions each require explicit approval immediately before the
test:

- logging out;
- manually sleeping the Mac;
- invoking `IOPMSleepSystem` from daemon context;
- rebooting;
- shutting down.

Approval for one action does not approve the others.

### Dry-run invariant

The feasibility daemon executable must not accept an execute-sleep flag and must
not construct `IOKitSystemSleepOperation`. A test that verifies daemon-context
`IOPMSleepSystem` must use a separately built or separately gated probe with an
obvious one-shot invocation contract and must never be enabled in the installed
dry-run plist.

## Recommended Architecture

### Temporary package shape

The spike should avoid a full production target migration before feasibility is
known. It may add one temporary executable target while extracting only the
minimum shared code required to avoid copying accepted behavior.

Recommended shape:

```text
Sources/
|- LidMonitor/                 existing CLI executable
|- LidMonitorDaemonSpike/      temporary dry-run daemon entry point
`- LidMonitorShared/           minimum shared runtime components if required
```

The implementation plan must choose the smallest compile-safe extraction. It
must not duplicate the state machine, coordinator, decoder, HID discovery, or
policy constants between executables.

The future production shape remains:

```text
LidMonitorCore
macbook-lid-monitor
macbook-lid-monitor-daemon
```

but that larger restructuring is explicitly deferred until the spike proves the
system context.

### Executable roles

`macbook-lid-monitor` remains the current diagnostic and bounded foreground
tool.

`macbook-lid-monitor-daemon-spike` is temporary and must:

- run without a terminal;
- use the calibrated policy;
- be permanently dry-run;
- register IOKit system power notifications;
- enumerate and open only a sufficiently ranked sensor candidate;
- receive and decode reports through the existing event-driven stream;
- emit transition-only policy output plus bounded feasibility evidence;
- respond cleanly to `SIGTERM`;
- never install or update itself.

### Power observer

Add an IOKit-backed observer using `IORegisterForSystemPower`. The callback must
classify at least:

```text
kIOMessageCanSystemSleep
kIOMessageSystemWillSleep
kIOMessageSystemWillPowerOn
kIOMessageSystemHasPoweredOn
```

Required behavior:

- acknowledge `kIOMessageCanSystemSleep` with `IOAllowPowerChange`;
- acknowledge `kIOMessageSystemWillSleep` with `IOAllowPowerChange`;
- record `kIOMessageSystemWillPowerOn` without starting recovery;
- call the existing wake path only for `kIOMessageSystemHasPoweredOn`;
- deregister, close, remove the run-loop source, and destroy the notification
  port on stop;
- make `start()` and `stop()` idempotent;
- expose registration failure as a startup/degraded diagnostic rather than
  silently omitting wake monitoring.

The foreground CLI may continue using the existing workspace observer during
the spike unless sharing the IOKit observer is demonstrably lower-risk. The
production phase will decide whether all modes use one observer.

### HID lifecycle

The current foreground stream resolves one registry ID and opens one device.
The spike must distinguish these stages in evidence:

```text
enumeration
candidate selection
device resolution
IOHIDDeviceOpen
callback registration
first valid report
continued valid reports
```

For the feasibility spike, an initial missing sensor may either cause a bounded
startup failure or enter a documented degraded state. The implementation must
not add an unbounded polling loop. A production-quality device-publish callback
and reconnect policy is deferred unless required to make the spike reliable at
boot.

If boot timing proves that the sensor is not present when launchd first starts
the job, the spike may add event-driven `IOHIDManager` matching callbacks. That
change must be separately tested and recorded as a discovered requirement, not
silently treated as part of the original assumption.

### Process and run-loop lifecycle

The spike must own one process-level runtime that coordinates:

- HID callback run loop;
- IOKit power notification run-loop source;
- coordinator serial queue;
- signal handling;
- clean shutdown.

Signal handling must remain async-signal-safe. The existing pipe plus
`DispatchSourceRead` pattern may be reused. `SIGTERM` is the required launchd
shutdown path; `SIGINT` may remain available for manual foreground diagnosis.

No daemonization fork, double-fork, PID file, child watchdog, or self-restart is
allowed. launchd owns the process lifecycle.

## Temporary Deployment Design

### Label and paths

Use visibly temporary names so the spike cannot be confused with production:

```text
label:
com.crazydennies.macbook-lid-monitor.feasibility

binary:
/Library/PrivilegedHelperTools/macbook-lid-monitor-daemon-spike

plist:
/Library/LaunchDaemons/com.crazydennies.macbook-lid-monitor.feasibility.plist

evidence log directory, if file logging is required:
/Library/Logs/MacBookLidMonitor/Feasibility/
```

The plan may prefer unified logging for runtime output. If loginwindow evidence
collection requires a file, the file must be bounded, root-owned, and removed by
uninstall. The spike must not create a permanent state directory.

### Ownership

Initial feasibility identity is root to minimize simultaneous variables:

```text
binary: root:wheel 0755
plist:  root:wheel 0644
logs:   root:wheel, not writable by regular users
```

This does not approve root as the final production identity. The spike report
must state which operations succeeded as root and leave least-privilege testing
to the production phase unless a non-root comparison is specifically approved.

### launchd policy

The initial plist should use the smallest safe policy:

```text
RunAtLoad = true
ProcessType = Background
ThrottleInterval >= 30
```

`KeepAlive = true` must not be enabled in the first installation test. The job
must first demonstrate clean startup, status inspection, SIGTERM shutdown, and
bootout without an automatic restart. A later spike task may test bounded
restart behavior only after the user approves it and after a deliberate
non-sleeping failure mode exists.

The plist must not pass an execute-sleep argument.

### Management commands

The spike must provide exact, reviewable commands or scripts for:

```text
install
bootstrap
status
logs
stop
bootout
uninstall
```

Uninstall order is mandatory:

```text
disable if previously enabled
-> bootout
-> verify process absence
-> remove plist
-> remove binary
-> remove spike-only logs
```

The implementation must never remove files outside the fixed feasibility paths.

## Evidence Model

The daemon spike must emit stable evidence records for:

### Runtime identity

```text
event=runtime-start
pid=<pid>
uid=<uid>
gid=<gid>
session=<best available audit/session identity>
boot-id-or-start-time=<value>
```

### HID discovery and open

```text
event=hid-candidate
registry-id=<id>
vendor-id=0x05AC
product-id=0x8104
usage-page=0x0020
usage=0x008A
transport=SPU
score=<score>

event=hid-opened
registry-id=<id>

event=hid-open-failed
registry-id=<id>
io-return=<code>
```

### Report continuity

Do not log every report. Emit bounded milestones such as:

```text
event=first-valid-report angle=<value>
event=report-milestone count=100 latest-angle=<value>
event=report-stream-stalled duration=<seconds>
```

The plan must define a conservative milestone cadence and must avoid periodic
CPU wakeups solely for logging. A stall record may only be produced by an
already required validation timer or on lifecycle transition.

### Power events

```text
event=power-can-sleep
event=power-will-sleep
event=power-will-power-on
event=power-has-powered-on
```

Each record must include a timestamp and process PID so the loginwindow and
post-login evidence can prove whether one job/process continued.

### Policy events

Reuse the existing compact transition and dry-run output:

```text
auto-sleep: startup-cooldown
auto-sleep: rearmed
auto-sleep: candidate-started
auto-sleep: triggered
auto-sleep: would-sleep
auto-sleep: wake-recovery
auto-sleep: recovery-resleep
auto-sleep: recovery-sensor-unavailable
```

No real `sleep-requested` event is permitted from the installed spike.

## Daemon-Context Sleep Operation Probe

`IOPMSleepSystem` feasibility is required before the production phase, but it is
not part of the default installed dry-run daemon.

The implementation plan must define a separately gated one-shot probe with all
of these properties:

- not referenced by the feasibility LaunchDaemon plist;
- cannot be triggered by lid-angle reports;
- requires a deliberate command after explicit user approval;
- logs the exact `IOPMSleepSystem` return result;
- exits after one attempt;
- does not retry;
- can first be tested in a non-disruptive injected/mock mode;
- real invocation is deferred until loginwindow HID and notification evidence
  have passed and the user separately approves the sleep test.

The final spike disposition may be:

```text
HID/loginwindow/power notifications passed
IOPMSleepSystem daemon probe pending explicit approval
```

but the production execute-sleep phase remains blocked until the probe passes.

## Single-Authority Rules

During the spike:

- no LaunchAgent may exist;
- only one feasibility LaunchDaemon job may be bootstrapped;
- the installed daemon is always dry-run;
- foreground diagnostic `--list` and `--watch` remain allowed;
- foreground `--execute-sleep` must not be run while the spike is active;
- any later daemon sleep probe requires the spike job to be booted out first,
  unless the approved plan proves the two processes cannot both make decisions;
- installation scripts must detect an already loaded feasibility label and fail
  safely instead of creating duplicate jobs.

## Failure Handling

### HID unavailable or open failure

The spike must log the precise stage and IOReturn/error. It must remain incapable
of sleep. The implementation plan must choose one of:

1. exit once and rely on an explicitly manual restart while `KeepAlive` is off;
2. remain alive in degraded/disarmed state;
3. wait for an event-driven device-publish callback.

The plan must justify the choice based on boot feasibility and must not introduce
a fixed-interval polling loop.

### Power observer registration failure

The process must log the failure and remain dry-run/disarmed. It must not silently
fall back to workspace notifications in daemon context.

### Invalid sensor data

Existing fail-open semantics remain authoritative. Invalid data may cancel a
candidate or invalidate recovery evidence; it can never authorize a sleep or
`would-sleep` decision.

### Unexpected process exit

The first installed plist does not use `KeepAlive`. launchd status and logs must
make the exit observable. Restart-policy feasibility is evaluated only after the
basic lifecycle passes.

### Stop and uninstall

`SIGTERM` must cancel scheduler tasks, stop the wake observer, stop and close the
HID stream, flush final evidence, and exit promptly. Bootout must not leave a
running process or loaded job.

## Testing Strategy

### Automated tests

Add tests for:

- IOKit power message mapping;
- acknowledgement of can-sleep and will-sleep messages;
- wake callback only on has-powered-on;
- idempotent observer start/stop;
- observer cleanup;
- registration failure;
- daemon composition always using `DryRunSleepRequester`;
- daemon composition never constructing a real system sleep operation;
- `SIGTERM` runtime cleanup;
- stable evidence formatting;
- no duplicate feasibility label or unsafe install path;
- uninstall path allowlist;
- existing 79-test regression suite.

Native IOKit calls must be wrapped behind injectable protocols/functions so unit
tests do not sleep the machine or require a LaunchDaemon.

### Static validation

Before any installation:

```text
swift package clean
swift test
swift build -c release
git diff --check
plutil -lint <generated plist>
shellcheck or equivalent script review when available
scan installed-spike sources for IOPMSleepSystem construction
scan plist arguments for execute-sleep
```

The exact tooling available on the validation Mac must be recorded; unavailable
optional linters do not justify skipping manual review.

### Hardware acceptance stages

#### Stage A — foreground daemon-spike executable

Run the daemon entry point manually in dry-run to verify startup, HID reports,
IOKit power observer registration, signal handling, and output before touching
`/Library`.

No sleep, logout, reboot, or shutdown is required.

#### Stage B — logged-in LaunchDaemon dry-run

After explicit install approval:

```text
install fixed binary and plist
bootstrap system job
verify root identity
verify candidate and open
verify first valid report
move lid through safe dry-run angles
verify would-sleep only
verify status, SIGTERM/bootout, and restart by manual bootstrap
```

#### Stage C — loginwindow dry-run

After separate logout approval:

```text
record pre-logout PID and report count
log out
remain at loginwindow
move lid through observable angles without closing far enough to obstruct use
log back in
compare PID, timestamps, report milestones, and decoded changes
```

Pass requires evidence generated during the loginwindow interval, not merely
before logout and after login.

#### Stage D — manual sleep/wake notification dry-run

After separate sleep approval, manually request macOS sleep while the installed
spike remains dry-run. Verify:

```text
power-will-sleep
power-will-power-on
power-has-powered-on
wake-recovery
fresh-report decision
```

The installed spike must not call `IOPMSleepSystem`.

#### Stage E — daemon-context one-shot sleep probe

After the earlier stages pass and after explicit real-sleep approval, boot out
the dry-run spike and invoke the separate one-shot probe. Pass requires one
successful API return and independent macOS power evidence. Failure must be
reported without retry.

#### Stage F — reboot auto-start dry-run

Reboot testing is deferred until separately approved. It is optional for basic
API feasibility but required before declaring the future production LaunchDaemon
architecture fully validated. The dry-run job must auto-start before login and
produce loginwindow HID evidence after reboot.

## Acceptance Criteria

### Automated and static

- Existing 79 tests continue to pass.
- New power observer, daemon composition, evidence, and deployment tests pass.
- Release builds produce the existing CLI and the temporary spike executable.
- The installed spike has no code path to `IOPMSleepSystem`.
- The plist contains no execute-sleep argument.
- Plist and scripts pass syntax/static review.
- Open P0 = 0 and Open P1 = 0 for every implementation task.

### Logged-in system daemon

- The system-domain job starts under the expected identity.
- Exactly one feasibility job/process exists.
- The verified M1 Pro sensor is selected and opened.
- Fresh valid reports continue without per-report log churn.
- Lid movement produces correct dry-run state transitions.
- `SIGTERM`, bootout, and uninstall leave no process or loaded job.

### Loginwindow

- The same system job remains independent of the user login lifecycle.
- Evidence proves valid reports were received while no user was logged in.
- Logging in does not start a second decision process.
- The service remains dry-run and fail-open.

### Power lifecycle

- IOKit sleep/wake messages are received and correctly mapped.
- Required sleep acknowledgements are issued.
- wake recovery starts only on `kIOMessageSystemHasPoweredOn`.
- HID reports resume or continue after wake.
- No duplicate recovery deadline or dry-run request occurs per wake generation.

### Sleep operation probe

- A separately approved one-shot daemon-context probe can call
  `IOPMSleepSystem` exactly once and expose success/failure.
- It is not installed as the dry-run service and cannot retry.

### Phase disposition

The spike passes only when logged-in LaunchDaemon HID access, loginwindow report
delivery, and IOKit power notification stages pass with Open P0/P1 = 0. The
production execute-sleep phase additionally remains blocked until the one-shot
sleep-operation probe passes.

Any of these results blocks the production daemon design:

- sensor cannot be enumerated or opened in system context;
- no valid reports are delivered during loginwindow;
- wake events cannot be observed reliably without a logged-in workspace;
- the daemon cannot be safely stopped and removed;
- installed dry-run code can reach a real sleep operation;
- duplicate sleep-decision processes cannot be prevented.

## Documentation

During implementation, add a Traditional Chinese operator document covering:

- what the feasibility spike does and does not do;
- the exact temporary paths;
- install, status, logs, stop, and uninstall commands;
- confirmation that the installed spike is dry-run only;
- emergency removal steps;
- approval gates for logout, sleep, reboot, and the one-shot sleep probe.

Historical governance files may remain English. README must not describe the
daemon as production-ready until a later production phase is accepted.

