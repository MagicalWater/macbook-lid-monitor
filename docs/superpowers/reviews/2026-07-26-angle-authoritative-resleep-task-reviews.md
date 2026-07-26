# Angle-Authoritative Re-Sleep Task Reviews

## Task 1 — Policy and CLI Contract Split

### Initial findings

#### P1-1 — Obsolete option rejection lacked operator migration guidance

The parser returned `.obsoleteWakeCooldownOption`, but the top-level CLI error
path would have printed only the enum case name. That met programmatic rejection
but did not direct an operator to the replacement options required by the spec.

**Resolution:** The CLI entry point now emits:

```text
usage error: --wake-cooldown is obsolete; use --startup-cooldown and --wake-recovery
```

### Re-review

- Runtime defaults are exactly `68 / 75 / 2 / 5 / 15`.
- Supported options map one-to-one to policy fields.
- The obsolete option cannot be silently reinterpreted.
- Timing validation rejects non-finite values and enforces the specified bounds.
- Effective configuration output contains both startup and wake timing.
- The helper script still duplicates no calibrated policy value.
- Full regression suite: 67 tests, 0 failures.

### Disposition

- Open P0: 0
- Open P1: 0
- Open P2: 0
- Task 1 status: approved

## Task 2 — Angle-Authoritative State Machine

### Initial findings

No P0 or P1 finding was identified after the RED/GREEN implementation. The
review concentrated on state authority rather than coordinator scheduling,
which remains Task 3 scope.

### Re-review

- Startup begins in `startupCooldown` and can never request sleep.
- Startup below `>=75` ends in `disarmed`; `>=75` ends in `open`.
- A system wake clears all pre-wake angle evidence.
- Recovery uses only fresh valid reports received after the wake.
- Fresh `<=68` and `69...74` both request one sleep at the 15-second deadline.
- Fresh `>=75` cancels recovery immediately and rearms.
- Missing or invalid fresh recovery data ends in `disarmed` without sleeping.
- Every later wake replaces the state-machine recovery deadline.
- A sleep-request failure ends in `disarmed` and requires `>=75` to rearm.
- State-machine and full regression suites: 69 tests, 0 failures.

### Disposition

- Open P0: 0
- Open P1: 0
- Open P2: 0
- Task 2 status: approved

## Task 3 — Coordinator Scheduling and Failure Visibility

### Initial findings

#### P1-1 — Wake during startup could leave the startup deadline active

The state machine correctly entered wake recovery, but coordinator ownership
needed an explicit cancellation of the startup one-shot task before applying the
wake event. Without that cancellation, startup and recovery deadlines could both
remain scheduled.

**Resolution:** `handleWake(at:)` now cancels and clears
`startupCooldownTask` before scheduling recovery. A dedicated test proves the
only remaining deadline is `wake + 15 seconds`.

#### P1-2 — Recovery-path sleep failure needed direct regression coverage

Normal close request failure was covered, but the same no-retry guarantee had
not been asserted for a request emitted by the recovery deadline.

**Resolution:** Added a recovery failure test verifying one request, one
`sleep-request-failed` event, transition `recovery-resleep -> disarmed`, no
remaining deadline, and no retry from subsequent low-angle reports.

#### P2-1 — Legacy `cooldown` transition event was no longer reachable

Keeping the old event after splitting startup and wake recovery would make the
active output API ambiguous.

**Resolution:** Removed the unused `cooldown` event and formatter branch.

### Re-review

- Startup, close debounce, and wake recovery each own one independent task slot.
- A wake replaces startup or prior recovery work rather than adding another timer.
- Recovery `>=75` cancels the deadline and rearms without another request.
- Missing/invalid recovery data emits `recovery-sensor-unavailable` and fails open.
- Normal and recovery request failures emit one stable error and enter disarmed.
- IOKit error descriptions are stable and test-covered.
- No automatic retry, polling, per-report logging, or process termination exists.
- Coordinator and full regression suites: 76 tests, 0 failures.

### Disposition

- Open P0: 0
- Open P1: 0
- Open P2: 0
- Task 3 status: approved
