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
