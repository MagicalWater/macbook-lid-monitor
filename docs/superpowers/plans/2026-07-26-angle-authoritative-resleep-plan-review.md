# Angle-Authoritative Re-Sleep Plan Review

## Review Scope

Review `2026-07-26-angle-authoritative-resleep.md` against the approved spec,
existing Swift interfaces, TDD sequencing, task-level review gates, hardware
safety, and documentation authority.

## Initial Findings

### P1-1 — Real recovery acceptance must not be embedded in ordinary validation

A true wake-recovery path requires a real system sleep and wake. Treating it as
an ordinary Task 5 validation could trigger sleep without a fresh explicit user
approval.

**Resolution:** Split real two-sleep acceptance into Task 6 with an explicit
post-Task-5 approval gate. Task 5 uses automated recovery tests and bounded
hardware dry-run/idle evidence only.

### P1-2 — Coordinator failure output required an explicit callback boundary

The existing coordinator only receives `onTransitionEvent`; request success is
reported by requester composition. Without a concrete interface change, caught
errors could not reach the same production output path.

**Resolution:** Task 3 explicitly adds `onOperationalEvent` to
`LidSleepCoordinator` and requires composition to pass the existing callback.

### P1-3 — Old `--wake-cooldown` behavior needed an exact migration test

Removing the old option only from parsing code could leave tests, README, helper
examples, or copied policy construction stale.

**Resolution:** Task 1 includes exact obsolete-option error coverage and updates
all policy constructors; Task 4 includes active-document scans and preserves only
clearly historical validation output.

### P2-1 — Recovery-trigger output could be confused with normal close trigger

Both paths enter `.triggered`, so mapping state alone cannot emit
`recovery-resleep` accurately.

**Resolution:** Task 3 requires transition mapping to inspect the previous state
when `.triggered` is reported.

## Re-Review

- Every spec requirement maps to a concrete Task and exact file set.
- Startup, close debounce, and wake recovery remain distinct one-shot paths.
- Test-first steps precede each implementation unit.
- Sleep failure behavior includes exact output, terminal state, and no-retry tests.
- Dry-run and diagnostic safety remain composition-level regression requirements.
- Documentation distinguishes current runtime behavior from historical evidence.
- Real sleep remains separately approved and foreground-only.
- Every Task ends with review, fix, re-review, P0/P1 gate, validation, and commit.

## Final Disposition

- Open P0: 0
- Open P1: 0
- Open P2: 0
- Plan status: approved for task execution
