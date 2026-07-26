# Angle-Authoritative Re-Sleep and Sleep Failure Visibility Design

## Status

Approved design direction for the post-acceptance auto-sleep refinement.

## Problem

The current implementation intentionally fails open after wake. If the Mac is
woken while the lid-angle sensor still reports a closed position, the five-second
wake cooldown ends in `disarmed`. The process will not request sleep again until
the sensor reports `>=75`.

That behavior prevents a sleep loop, but it does not match the intended
workaround semantics. The lid-angle sensor exists to replace unreliable native
clamshell detection, so the measured angle must remain authoritative:

- A value `<=68` means the lid is closed and the Mac should sleep.
- A value `>=75` means the lid has genuinely reopened and auto-sleep may rearm.
- Values `69...74` remain within the closed-cycle hysteresis band and must not be
  treated as a reopen.

The current implementation also suppresses errors returned by
`IOPMSleepSystem`, which makes a failed sleep request invisible to the operator.

## Goals

1. Keep lid angle as the sole authority for close/reopen decisions.
2. After wake, provide a 15-second recovery window so an operator can open the
   lid or stop a future persistent service if the sensor is faulty.
3. If the recovery window ends without an observed `>=75`, request sleep again.
4. Continue this behavior for every wake while the lid remains closed; do not
   introduce a retry-count cutoff that leaves a closed Mac awake.
5. Cancel pending re-sleep immediately when a valid `>=75` report arrives.
6. Fail open on invalid or unavailable sensor data: no sleep request may be based
   on stale, malformed, unsupported, or out-of-range data.
7. Report `IOPMSleepSystem` failures explicitly without automatic tight-loop
   retries or process termination.
8. Preserve dry-run safety, event-driven operation, and the existing explicit
   `--auto-sleep --execute-sleep` gate.

## Non-Goals

- Installing a LaunchAgent, login item, daemon, or menu-bar application.
- Adding persistent preferences or a settings UI.
- Distinguishing keyboard wakes from network, maintenance, or DarkWake events.
- Repairing the native clamshell sensor.
- Adding a maximum re-sleep count while a valid sensor continues to report a
  closed position.

## Effective Policy

The calibrated close-cycle policy remains:

```text
sleep threshold:   <=68
reopen threshold:  >=75
close debounce:    2 seconds
wake recovery:     15 seconds
```

The existing `wakeCooldown` concept will be renamed or redefined as
`wakeRecovery`, because it now ends in one of two authoritative decisions rather
than always disarming:

```text
wake
  -> wait 15 seconds for fresh sensor data
  -> latest valid angle >=75: open/rearmed
  -> latest valid angle <75: request sleep again
  -> no fresh valid angle: fail open/disarmed with diagnostic output
```

## State-Machine Semantics

### Startup

Startup remains conservative:

1. Enter `startupCooldown` for five seconds using the existing startup safety
   duration.
2. Require fresh valid sensor data.
3. If the latest angle is `>=75`, enter `open`.
4. Otherwise enter `disarmed`; startup must never immediately sleep a machine
   that launches while already closed.
5. A later `>=75` report rearms the normal close cycle.

Startup safety and post-wake recovery are therefore separate concepts and must
not share one ambiguous timer.

### Normal close cycle

```text
open
  -> angle <=68
  -> closingCandidate for 2 seconds
  -> still <=68 with fresh valid data
  -> triggered
  -> request sleep once
```

Reports above `68` during the debounce cancel the candidate. Invalid data also
cancels the candidate and fails open.

### Wake while still closed

On `NSWorkspace.didWakeNotification`:

1. Cancel pending close debounce work.
2. Enter `wakeRecovery`.
3. Clear the pre-sleep angle so the recovery decision cannot use stale data.
4. Collect fresh valid reports for 15 seconds.
5. If any report reaches `>=75`, cancel recovery and enter `open` immediately.
6. At the deadline:
   - latest valid angle `<75`: emit a recovery re-sleep transition and request
     sleep once;
   - no fresh valid angle: emit a sensor-unavailable transition and enter
     `disarmed` without requesting sleep.

The `<75` recovery rule intentionally treats `69...74` as still closed. The
normal two-second close debounce is not repeated after wake because the
15-second recovery window already provides a longer stability period.

### Repeated wakes

Every successful wake begins a new independent 15-second recovery window. If a
fresh valid angle remains `<75`, the process requests sleep again. There is no
retry-count cutoff because such a cutoff would contradict the angle-authoritative
requirement and leave a physically closed Mac awake.

The design avoids a CPU or API retry loop because every re-sleep can occur only
after a real system wake notification followed by a 15-second one-shot timer.

## Sensor Fault Safety

Angle authority applies only to fresh, valid sensor data.

During wake recovery:

- malformed, unsupported, non-integral, or out-of-range reports clear the latest
  valid recovery angle;
- absence of a fresh valid report by the deadline prevents re-sleep;
- the process enters `disarmed` and logs that recovery could not establish a
  valid closed angle;
- a later valid `>=75` report rearms the process.

This protects a future persistent service from repeatedly sleeping the machine
when the sensor stream is missing or corrupt. A sensor that consistently emits a
valid but physically wrong value remains outside what software can prove; the
15-second window is the operator escape period for that hardware-fault case.

## Sleep Request Error Handling

`SleepRequesting.requestSleep()` remains throwing. The coordinator must stop
using `try?` and instead handle the result explicitly.

Success:

```text
auto-sleep: sleep-requested
```

Failure:

```text
auto-sleep: sleep-request-failed error=<stable diagnostic description>
```

After a failure:

- do not retry from the same state transition;
- enter `disarmed` to prevent repeated requests from subsequent identical HID
  reports;
- require `>=75` before another normal close cycle;
- keep the foreground process alive so the operator can inspect the failure.

The same handling applies whether the failed request came from the normal close
cycle or from a wake-recovery re-sleep decision. A recovery request failure
cancels the completed recovery path, enters `disarmed`, and cannot schedule
another request until a later valid `>=75` report rearms the normal close cycle.

This preserves fail-open behavior while making the failure observable.

## Components and Interfaces

### `LidSleepPolicy`

Split the timing fields:

```swift
let closeDebounce: TimeInterval
let startupCooldown: TimeInterval
let wakeRecovery: TimeInterval
```

Calibrated defaults:

```swift
closeDebounce = 2.0
startupCooldown = 5.0
wakeRecovery = 15.0
```

The public CLI contract is fixed as:

```text
--debounce 2
--startup-cooldown 5
--wake-recovery 15
```

`--wake-cooldown` is removed rather than silently reinterpreted. Supplying it
must produce a usage error that directs the operator to
`--startup-cooldown` and `--wake-recovery`. This avoids changing the meaning of
an existing five-second option into a fifteen-second post-wake policy.

### `LidSleepStateMachine`

Add explicit states and events for startup and wake recovery so their different
safety rules cannot be conflated:

```swift
case startupCooldown
case wakeRecovery(deadline: Date)
case sleepRequestFailed

case startupCooldownElapsed(at: Date)
case wakeRecoveryElapsed(at: Date)
case sleepRequestFailed(at: Date)
```

The exact names may be refined in the implementation plan, but the separate
semantics are mandatory.

### `LidSleepCoordinator`

Maintain separate cancellable one-shot tasks for:

- startup cooldown;
- close debounce;
- wake recovery.

It must feed fresh reports into the state machine and explicitly translate sleep
request success/failure into operational and state-transition output.

### Output

Add compact transition/operational messages for:

```text
auto-sleep: wake-recovery
auto-sleep: recovery-resleep
auto-sleep: recovery-sensor-unavailable
auto-sleep: sleep-request-failed error=...
```

No per-report production logging is added.

## Testing Strategy

### Pure state-machine tests

Cover:

- startup below `75` remains disarmed;
- startup at `>=75` arms normally;
- wake clears the pre-sleep angle;
- fresh `>=75` during recovery cancels re-sleep;
- fresh `<=68` at 15 seconds requests re-sleep;
- fresh `69...74` at 15 seconds also requests re-sleep;
- no fresh valid angle at 15 seconds fails open;
- invalid data during recovery removes previously cached recovery evidence;
- each later wake starts another recovery window;
- sleep-request failure transitions to disarmed and requires `>=75` to rearm.

### Coordinator tests

Cover cancellation and scheduling of all three one-shot tasks, exactly-once sleep
requests per deadline, wake observer integration, and explicit failure output.

### Integration tests

Cover both dry-run and injected execute-sleep composition:

- close -> sleep -> wake while closed -> 15 seconds -> second sleep request;
- close -> sleep -> wake -> open to `>=75` before deadline -> no second request;
- close -> sleep request throws -> failure output and no automatic retry.

### Hardware acceptance

No immediate second real-sleep test is required for implementation correctness.
Before enabling the behavior in a future persistent service, perform one bounded
foreground hardware cycle:

1. Trigger sleep below `68`.
2. Wake by keyboard while keeping the lid below `68`.
3. Verify a second sleep occurs after approximately 15 seconds.
4. Wake again and open to `>=75` within the recovery window.
5. Verify the pending re-sleep is cancelled and the process rearms.

## Documentation

Update README, policy output examples, validation documentation, and final review
status so they consistently describe:

- five-second startup safety;
- fifteen-second post-wake recovery;
- angle-authoritative re-sleep;
- fresh-data fail-open protection;
- explicit sleep-request failure output.

## Acceptance Criteria

- Runtime defaults are `68 / 75 / 2 / 5 / 15` for close, reopen, debounce,
  startup cooldown, and wake recovery respectively.
- `--wake-cooldown` is rejected with migration guidance; the supported timing
  flags are `--debounce`, `--startup-cooldown`, and `--wake-recovery`.
- A wake while fresh valid angle remains `<75` produces one sleep request after
  15 seconds.
- Opening to `>=75` before the recovery deadline cancels the request.
- Missing or invalid fresh recovery data never requests sleep.
- A failed `IOPMSleepSystem` request is visible and is not retried automatically.
- No repeating timer, polling loop, per-report logging, LaunchAgent, or persistent
  power mutation is introduced.
- Existing diagnostic modes and dry-run behavior continue to pass all tests.

