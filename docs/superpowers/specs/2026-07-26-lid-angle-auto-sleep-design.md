# MacBook Lid Angle Auto-Sleep Design

> **Superseded:** This document defines the original cooldown/disarm behavior.
> Current post-wake behavior is governed by
> `2026-07-26-angle-authoritative-resleep-design.md`. Historical calibration and
> initial safety reasoning remain valid.

## Status

Reviewed and ready for implementation after the paired plan and holistic consistency reviews reach Open P0/P1 = 0. This phase extends the existing read-only diagnostic into a safe, event-driven auto-sleep utility.

## Goal

Restore practical lid-close sleep behavior on the validated M1 Pro MacBook by requesting macOS sleep when the calibrated hinge sensor reaches the machine-specific closed region.

## Validated Calibration

| Physical state | Sensor value |
| --- | ---: |
| Fully open | 189 |
| Approximately 90° | 148 |
| Lowest user-allowed position; nearly unusable but must remain awake | 105 |
| Lowest position that can mechanically support itself | 60 |
| Hand-supported closing threshold | 59 |
| Fully closed | 59 |

The HID value is a machine-specific hinge representation, not a guaranteed physical degree measurement. Apple does not expose a public configurable lid-angle sleep threshold, so this utility reproduces the user-visible behavior from observed hardware data rather than claiming to duplicate private Apple firmware logic.

## Default Policy

```text
sleepThreshold = 68
sleepDebounce = 2 seconds
reopenThreshold = 75
wakeCooldown = 5 seconds
```

- Enter `closingCandidate` only when the decoded value is `<= 60`.
- Return to `open` if the value rises above `60` before two continuous seconds pass.
- After two continuous seconds at `<= 60`, emit one sleep decision.
- Do not arm another decision until the lid reaches `>= 70`.
- After process start or an `NSWorkspace.didWakeNotification`, suppress sleep decisions for five seconds.
- If cooldown ends while the latest angle is below `70`, remain disarmed until a later report reaches `>= 70`; never sleep immediately from a closed startup/wake state.
- Invalid, missing, stream-failure, or out-of-range reports fail open and never request sleep.

## Architecture

Use a lightweight ports-and-adapters design:

```text
IOHID event source
       ↓
LidSleepStateMachine (pure domain logic)
       ↓
LidSleepCoordinator (timer and lifecycle orchestration)
       ↓
SleepRequesting port
       ├── DryRunSleepRequester
       └── MacOSSleepRequester
```

The existing device discovery, HID streaming, and decoding code remain infrastructure adapters. No repository, DTO, mapper, use-case hierarchy, MVVM, database, network service, or third-party dependency is introduced.

## Modes and Safety

- `--auto-sleep --dry-run`: default validation path; records `would-sleep` and never changes power state.
- `--auto-sleep --execute-sleep`: explicitly enables a real macOS sleep request.
- `--watch`: remains diagnostic-only and never sleeps.
- Real sleep must never be the implicit default.
- The process must perform no HID writes, power-setting changes, NVRAM changes, privilege escalation, kernel extension, or SIP modification.
- Sleep requests must use a bounded system API or command adapter that is injectable and never invoked by unit tests.
- The production sleep adapter uses `IOPMSleepSystem` through an injected `SystemSleepOperating` boundary; it must not invoke `pmset`, mutate persistent power settings, or retry.
- SIGINT/SIGTERM must cancel timers, stop HID streaming, and exit cleanly.

## Event and Power Model

- HID input callback is the primary trigger; no high-frequency polling loop.
- Wake lifecycle input is provided by `NSWorkspace.shared.notificationCenter` observing `NSWorkspace.didWakeNotification`.
- A timer exists only while a closing candidate is active or while cooldown is pending.
- Normal steady-state with an unmoving lid performs no periodic log write and no repeated clamshell-state query.
- Production logs are transition-based: armed, cancelled, would-sleep, sleep-requested, rearmed, error.
- A bounded energy validation must show the process idle most of the time and avoid persistent CPU wakeups caused by application timers.

## State Model

```text
cooldown
  ├─ cooldown elapsed and latest angle >= 70 ─→ open
  └─ cooldown elapsed and latest angle < 70 ─→ disarmed

disarmed
  └─ angle >= 70 ─→ open

open
  └─ angle <= 60 ─→ closingCandidate(start deadline)

closingCandidate
  ├─ angle > 60 ─→ open(cancel deadline)
  └─ deadline reached while latest angle <= 60 ─→ triggered

triggered
  └─ angle >= 70 ─→ open(rearm)
```

Duplicate reports must not restart the debounce deadline. A sleep decision is emitted at most once per close cycle. Startup and wake cooldown intentionally require a reopen observation before arming when the lid is already below `70`.

## Configuration

Phase 2 exposes CLI values for controlled validation while retaining calibrated defaults:

- `--sleep-threshold <0...360>`
- `--reopen-threshold <0...360>`; must be greater than sleep threshold.
- `--debounce <positive finite seconds>`
- `--wake-cooldown <nonnegative finite seconds>`

No persistent settings file or preference UI is added in this phase.

## Testing Strategy

- Pure state-machine tests use deterministic timestamps.
- Coordinator tests use a controllable fake scheduler, fake angle source, and spy sleep requester.
- CLI tests prove real sleep requires explicit opt-in and invalid threshold relationships are rejected.
- Integration tests prove decoded HID reports reach the coordinator without invoking real sleep.
- Hardware acceptance begins with dry-run and repeated close/open cycles before one explicitly approved real-sleep test.

## Acceptance Criteria

1. `swift test` and release build pass.
2. `--watch` remains read-only and behavior-compatible.
3. Dry-run emits exactly one `would-sleep` after `<= 60` remains stable for two seconds.
4. Returning above `60` before the deadline cancels the pending decision.
5. Values `69...74` after a trigger do not rearm; `>= 75` does.
6. Startup/wake cooldown prevents immediate sleep, and a startup/wake below `70` remains disarmed until the lid reaches `>= 70`.
7. Missing, malformed, out-of-range, or stream-failure sensor data never sleeps the Mac.
8. Real sleep is impossible without `--execute-sleep`.
9. Repeated physical dry-run tests show no trigger at the validated value `105` and reliable trigger in the `59...60` closed region.
10. Idle energy validation finds no application-created repeating high-frequency timer or continuous log churn.

## Deferred

- Menu bar application and SwiftUI/MVVM presentation.
- LaunchAgent installation and login-item management.
- Persistent preferences and calibration wizard.
- External-display clamshell policy.
- Broader power-session policy beyond `NSWorkspace.didWakeNotification` and startup cooldown.
- Distribution, notarization, and code signing.

