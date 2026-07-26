# Angle-Authoritative Re-Sleep Spec Review

## Review Scope

Review `2026-07-26-angle-authoritative-resleep-design.md` against the approved
angle-authoritative behavior, the fifteen-second operator escape window,
sensor-data fail-open requirements, sleep-request failure visibility, and the
existing event-driven safety boundaries.

## Initial Findings

### P1-1 — Public CLI migration was deferred instead of specified

The initial spec allowed the implementation plan to choose whether
`--wake-cooldown` would be retained, renamed, or redefined. That left the public
contract ambiguous and risked silently changing an existing five-second option
into a fifteen-second post-wake policy.

**Resolution:** Fixed the contract to `--debounce`, `--startup-cooldown`, and
`--wake-recovery`. The obsolete `--wake-cooldown` option must be rejected with
migration guidance rather than silently reinterpreted.

### P1-2 — Recovery sleep-request failure did not have an exact terminal state

The initial error-handling section said a failed sleep request enters
`disarmed`, but did not explicitly bind that behavior to a failure produced by
the wake-recovery re-sleep path. An implementation could therefore leave the
recovery state or scheduling path active and issue another request.

**Resolution:** Specified that both normal-close and recovery request failures
cancel their completed scheduling path, enter `disarmed`, keep the process
alive, and require a later valid `>=75` report before any new close cycle.

### P2-1 — A valid but physically wrong sensor value cannot be proven in software

The design intentionally treats a fresh valid value below `75` as authoritative.
If faulty hardware continuously emits a valid but wrong low value, software
cannot distinguish it from a physically closed lid.

**Resolution:** Retained the approved fifteen-second recovery window as the
operator escape period. Missing, malformed, unsupported, non-integral, or
out-of-range data still fail open. This residual hardware limitation is
documented rather than hidden.

## Re-Review

- Startup safety and post-wake recovery use separate timers and semantics.
- `<=68`, `69...74`, and `>=75` have one consistent meaning throughout.
- Every wake requires fresh valid recovery data; stale pre-sleep data is cleared.
- A valid angle below `75` causes one request only after a wake notification and
  one fifteen-second timer, so no CPU/API tight loop is introduced.
- Missing or invalid fresh recovery data fails open without sleeping.
- Normal and recovery sleep-request failures are observable and terminate in
  `disarmed` without automatic retry.
- The CLI migration is exact and cannot silently change option semantics.
- No polling, LaunchAgent, persistent power mutation, UI, or privilege expansion
  entered scope.

## Final Disposition

- Open P0: 0
- Open P1: 0
- Open P2: 0
- Accepted residual hardware limitation: 1
- Spec status: approved for implementation-plan review
