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

## Task 4 — Composition, Integration, and Documentation Synchronization

### Initial findings

#### P1-1 — README still advertised the obsolete combined cooldown policy

The runtime and tests used separate startup/recovery fields, but README still
showed `wake-cooldown=5` and did not explain angle-authoritative re-sleep.

**Resolution:** README now shows `startup-cooldown=5` and
`wake-recovery=15`, documents `<75` recovery re-sleep, `>=75` cancellation,
fresh-data fail-open behavior, obsolete-option migration, and request failures.

#### P1-2 — Historical acceptance documents could be mistaken for current authority

The original design, plan, final review, and Task 8 validation correctly recorded
the old cooldown/disarm behavior, but lacked an explicit supersession marker.

**Resolution:** Added authority notes that preserve historical evidence verbatim
while directing current runtime interpretation to the angle-authoritative spec,
plan, task reviews, and final review.

### Re-review

- Dry-run close/wake/closed recovery emits a second `would-sleep` after 15 seconds.
- Reopening to `>=75` cancels recovery and emits `rearmed`.
- Injected execute-mode failure is surfaced and disarmed end-to-end.
- Dry-run composition never constructs or invokes the real IOKit operation.
- Active source, tests, and README contain no `wake-cooldown=` runtime output.
- Historical old output is retained only under explicit superseded notes.
- Integration suite: 6 tests, 0 failures.
- Full suite: 79 tests, 0 failures.
- Release build: passed.

### Disposition

- Open P0: 0
- Open P1: 0
- Open P2: 0
- Task 4 status: approved

## Task 6 Review

### Evidence

- User gave explicit approval after Task 5 passed.
- Process emitted two and only two `sleep-requested` events.
- `recovery-resleep` occurred between the requests.
- The second request occurred fifteen seconds after the first wake.
- Opening to `>=75` after the second wake emitted `rearmed`.
- No third sleep request occurred before process shutdown.
- `pmset` independently attributed both low-power transitions to the same
  foreground process.

### Finding P2-1 — Second transition was represented as DarkWake

The first request produced a full `Entering Sleep state` entry. The second
request produced `Entering DarkWake state due to 'Software Sleep'`, followed by
an HID-triggered FullWake. Treating both as identical full Sleep entries would
overstate the evidence.

**Resolution:** Validation and final-review documents preserve the exact macOS
state distinction while accepting the angle-authoritative behavior and timing.

### Re-review

- Two exactly-once process requests: Pass
- Fifteen-second recovery timing: Pass
- Open-to-cancel behavior: Pass
- Third request prevention after reopen: Pass
- Honest platform evidence wording: Pass
- Residual process after stop: None

### Final disposition

- Open P0: 0
- Open P1: 0
- Open P2: 0
- Task 6 status: Pass with macOS DarkWake evidence note
