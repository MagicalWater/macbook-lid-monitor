# Production LaunchDaemon Phase Merge-Gate Review

Date: 2026-07-27
Baseline: `589dc7a6e4f0c6a29ccf5333becd22f839631732`
Reviewed head before corrections: `b2382dd3b6d120130cb35466bbc484e27ef86ca8`

## Purpose

Independent large-phase review after Tasks 1–15 and before any merge to `main`. This review does
not inherit Task 15's approval claim. It rechecks governance, architecture, process safety,
packaging, real-system evidence, tests, documentation, residual state, and Git integration risk.

## Review coverage

- Spec → review → revision → closure and post-implementation disposition.
- Plan → review → revision → closure and completed checklist.
- Task register → review → revision → closure, Tasks 1–15, and Stage A/B/C reviews.
- Production configuration, exact hardware profile, freshness/epochs, requester composition,
  power recovery, logging, crash protection, and process authority.
- Install, upgrade, rollback, disable, bootout, reboot proof, uninstall, permissions, symlink
  refusal, checksum, and residual-state checks.
- Logged-in, loginwindow, sleep/wake, enabled sleep, recovery resleep, injected failure, reboot,
  rollback, and uninstall evidence.
- Current checkout and independent clean snapshot verification.
- Detached-HEAD commit range and merge readiness.

## Findings

### Important 1 — Unclean runtime exits were not persisted

The budget API recorded handled startup failures, but an actual crash or `SIGKILL` could not call
`recordUnexpectedExit`. Therefore the next launch had no evidence that the prior lifetime ended
uncleanly.

**Correction:** persist `runActive=true` before runtime startup; clear it on deliberate disabled or
signal stop; count a still-active prior lifetime on the next begin. Add rolling-window, repeated
unclean-run, clean-exit, corrupt-state, atomic-write, and legacy-schema regression tests.

### Important 2 — Circuit-open returned a restartable exit

The plist uses `KeepAlive.SuccessfulExit=false`, but circuit-open returned non-zero. launchd would
therefore continue throttled restarts even though the application refused HID and sleep startup.

**Correction:** circuit-open emits degraded evidence and returns success, preventing further
automatic restart. It remains fail-open until explicit operator recovery.

### Important 3 — Explicit recovery existed only as an internal API

The Spec and Plan required an operator reset, but no management command exposed it.

**Correction:** add `reset-crash-budget`, constrained to root, installed regular config, disabled
mode, zero resident daemon, and non-symlink state. It does not enable or bootstrap.

### Important 4 — Foreground CLI could overlap production authority

The package rejected a duplicate LaunchAgent label, but foreground `--execute-sleep` and the
system daemon had no shared cross-process exclusion.

**Correction:** add one fixed non-blocking POSIX lease used by both real-sleep compositions.
Dry-run and diagnostics do not acquire it. Lock conflict, symlink, or non-regular paths fail open.

### Documentation consistency

Chronological task-review sections contained historical “pending” statements. Added an explicit
historical-status note and updated README, Spec, Plan, Task register, Task 15 review, and final
review with the corrected lifecycle and authority contracts.

## Re-review

- Real unclean lifetime accounting: covered by fresh unit tests.
- Circuit-open stops launchd retry: immediate exit mapping is success and regression tested.
- Operator reset: management command and sandbox tests pass; no automatic enable/bootstrap.
- Cross-process lease: exclusivity, release, symlink refusal, daemon conflict, CLI dry-run bypass,
  and CLI execute-sleep acquisition are covered.
- Previously accepted sensor/state-machine/IOKit behavior is unchanged after authority acquisition.
- Final system state remains uninstalled with no job, PID, binary, plist, support, or log path.

## Fresh verification

Current checkout:

- XCTest: 198 tests, 0 failures.
- Four release products: passed.
- Bash syntax and shellcheck: passed.
- Plist/config/manifest lint: passed.
- Production package `prepare` and `verify`: passed.
- Plan unchecked items: zero.
- System job, process, binary, plist, support directory, and log directory: absent.
- `git diff --check`: passed.

Independent snapshot copied from the complete working tree while excluding `.git` and `.build`:

- XCTest: 198 tests, 0 failures.
- Four release products: passed.
- Bash syntax and shellcheck: passed.
- Plist/config/manifest lint: passed.
- Production package `prepare` and `verify`: passed.
- Tracked working tree after verification: clean.

## Merge disposition

**Approved for integration.** All Critical and Important findings discovered by this independent
large-phase review were corrected and re-reviewed. No open merge-blocking finding remains.

This approval does not itself authorize merge, push, or worktree cleanup. The repository remains
on detached HEAD until the user explicitly authorizes the integration operation.
