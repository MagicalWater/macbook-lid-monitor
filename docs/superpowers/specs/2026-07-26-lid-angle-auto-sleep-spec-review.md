# MacBook Lid Angle Auto-Sleep Spec Review

## Review Scope

Review the design against the validated M1 Pro calibration, fail-open safety, event-driven energy requirements, and the requirement that real sleep remain explicitly gated.

## Initial Findings

### P1-1 — Cooldown completion was ambiguous for an already-closed lid

The original state diagram only allowed `cooldown → open` when the latest angle was `>= 70`, but did not define what happened when cooldown elapsed below `70`. Interpreting cooldown as permission to sleep after five seconds could cause an immediate sleep loop after wake.

**Resolution:** Added an explicit `disarmed` state. Startup or wake below `70` remains unable to sleep until a later angle report reaches `>= 70`.

### P1-2 — Wake cooldown had no concrete lifecycle source

The spec required wake handling but did not name a supported macOS event source.

**Resolution:** Defined `NSWorkspace.shared.notificationCenter` with `NSWorkspace.didWakeNotification` as the production wake event source.

### P1-3 — Real sleep mechanism was underspecified

“Bounded system API or command adapter” left an implementation choice that could accidentally introduce shell execution or persistent `pmset` changes.

**Resolution:** Fixed the production boundary to one `IOPMSleepSystem` call through an injected adapter, with no `pmset`, retries, or persistent mutation.

### P2-1 — “Stale report” was not operationally defined

An event-driven sensor can legitimately remain silent while the lid is stationary. Treating age alone as invalid would conflict with the two-second debounce.

**Resolution:** Replaced the undefined stale-data condition with explicit malformed, out-of-range, missing, and stream-failure conditions. A stationary last-known valid angle remains valid for the one-shot debounce decision.

## Re-Review

- Calibration table and threshold semantics are internally consistent.
- `105` remains awake; `60` enters the candidate region; `70` rearms.
- Startup and wake cannot trigger an immediate sleep loop.
- Wake input and real-sleep output now have exact macOS boundaries.
- No polling, persistence, privilege escalation, UI architecture, or background installation entered scope.

## Final Disposition

- Open P0: 0
- Open P1: 0
- Open P2: 0
- Spec status: approved for paired plan review
