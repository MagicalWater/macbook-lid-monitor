# Milestone 16 Task Register Review

Date: 2026-07-27

## Review method

1. Compare every Task against the closed Spec and Plan.
2. Check one primary responsibility per Task.
3. Check dependency order and file ownership.
4. Check focused/full verification and independent commit boundary.
5. Check every mutation/power/Git approval separately.
6. Check safe stop, rollback, and final state.
7. Revise the Plan/register, then re-review from Task 1 through Task 21.

## Initial findings

### P0 — Three independent approvals shared one implementation Task

The first Plan grouped one-sleep acceptance, recovery-resleep, and persistent activation. Passing
or failing that Task would have obscured which authority was actually approved and verified.

**Resolution:** Split them into Tasks 18, 19, and 20. Task 17 separately owns dry-run mode mutation;
Task 21 owns reboot/pre-login/baseline closure.

### P1 — Dry-run was combined with installation

Installation should prove only the safest disabled package state. Dry-run changes config and job
state and therefore needs its own explanation, approval, evidence, and cleanup review.

**Resolution:** Task 16 ends loaded/disabled/zero PID. Task 17 independently performs and reviews
installed dry-run acceptance.

### P1 — Lifecycle mutation serialization was not an explicit Task outcome

The Spec requires install, upgrade, rollback, and uninstall to serialize mutation, but the first
Plan relied on command ordering.

**Resolution:** Task 6 now owns `with_lifecycle_guard`, stable busy failure, cleanup, unsafe-path
rejection, and concurrent sandbox coverage.

### P1 — Root-owned lease tests require a non-root unit-test seam

Normal `swift test` cannot create actual root-owned files. A test that silently weakens expected
ownership would fail to verify production policy.

**Resolution:** Task 1 must inject expected owner/group and filesystem metadata for unit tests while
the production constructor hard-codes root/wheel policy. Real root metadata remains part of Task 16
installation acceptance.

### P1 — Runtime and shell installed verification could normalize config differently

**Resolution:** Task 4 defines manifest fields and disabled-template checksum first. Tasks 5 and 6
must share fixtures that prove identical mode-only normalization and mismatch results.

### P1 — Health persistence failure needed an authority disposition

A failed health write must not cause repeated sleep or accidentally make unhealthy state appear
healthy.

**Resolution:** Task 9 records a stable degraded-observability event, retains existing sleep safety,
and requires status to report health unavailable/stale rather than synthesizing health.

### P1 — Online copy/truncate needed a running-writer acceptance

Unit tests that only inspect generations would not prove launchd's active descriptor still targets
the primary file.

**Resolution:** Task 11 records inode before/after rotation and writes a post-rotation event through
the already-open descriptor.

## Re-review checklist

- Tasks 1–5 close runtime authority/integrity before activation tooling: pass.
- Tasks 6–13 close management lifecycle and operations before release acceptance: pass.
- Task 14 is a complete non-mutating release gate: pass.
- Task 15 separates Git integration/package provenance from installation: pass.
- Tasks 16–21 each have one primary system responsibility and independent approval where needed:
  pass.
- Every Task has focused verification, review/fix/re-review, evidence, and independent commit:
  pass.
- Every mutating Task has a safe stop or rollback disposition: pass.
- Successful final state cannot be disabled, rolled back, or uninstalled: pass.
- No Task authorizes password handling, automatic reboot, unique device IDs, or raw HID logs: pass.

## Decision

**Approved after revision.** No Critical/P0/P1 Task-register finding remains open.
