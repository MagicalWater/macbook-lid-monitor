# Milestone 16 Spec Task Reviews

Date: 2026-07-27

## S1 — Source, system, and non-mutation baseline

### Implemented

- Verified formal checkout `main` and `origin/main` at
  `e2b8afeac0bf8f7560d6a9d60b4da328d9650bd3` with a clean working tree.
- Verified the prior requested worktree `macbook-lid-monitor-d3aeb5a9` was absent.
- Created the managed DevSpace worktree
  `/Users/water/.devspace/worktrees/macbook-lid-monitor-7bf2a52a` from the exact baseline.
- Verified production binary, plist, support directory, log directory, launchd job, and resident
  daemon were absent.
- Recorded the historical unmanaged `/private/tmp/macbook-lid-monitor-task15-final-test.log`
  separately rather than misclassifying it as a managed production residual.

### Immediate review

Finding S1-P1: the initial wording “zero residual” could be read as no project-named file anywhere
on the machine even though a user-owned historical test log remained in `/private/tmp`.

Resolution: distinguish **managed production residual state** from broader project-owned temporary
evidence. Require explicit disposition before final pre-install baseline.

### Re-review

Pass. The Spec now makes the managed-state claim precise and requires broad pre-install residual
inventory without claiming that the unmanaged temporary log is part of the installed package.

## S2 — Risk, gap, and approach review

### Implemented

Reviewed the accepted production daemon and identified long-term deployment blockers:

- replaceable `/tmp` sleep-authority inode;
- no evidence-bound persistent activation command;
- deployable acceptance-only requester environment override;
- incomplete installed-set checksum coverage;
- disconnected runtime health contract and incomplete diagnostics;
- ambiguous enabled upgrade/rollback behavior;
- online log rotation that moves the active inode;
- missing long-term operator runbook;
- hardware wording broader than the actual HID authorization contract;
- incomplete deterministic metadata checks for long-lived state files.

Compared manual-only deployment, exposing the existing internal enabled setter, and a dedicated
evidence-bound deployment lifecycle. Selected the dedicated lifecycle.

### Immediate review

Finding S2-P0: earlier bounded acceptance proves sensor and sleep behavior but cannot prove that a
long-running authority file in `/tmp` cannot be replaced after acquisition.

Finding S2-P1: exposing the internal enabled setter would make the acceptance record advisory
rather than authoritative.

Resolution: make the managed non-replaceable lease and evidence-bound `activate` gate explicit
Spec invariants.

### Re-review

Pass. Every deployment-blocking audit finding has a corresponding normative Spec requirement,
automated verification requirement, or explicit deployment acceptance requirement.

## S3 — Architecture and approval gates

### Implemented

Defined the managed artifact set, non-replaceable shared authority, requester composition,
installed-set integrity, target hardware evidence, deployment acceptance state, management
commands, status/diagnostics/health, log maintenance, upgrade/rollback, and all approval gates.

### Immediate review

Finding S3-P0: the first rollback wording allowed a previously accepted rollback package to regain
enabled mode automatically. That created a second path around `activate`.

Finding S3-P1: the first reboot wording inherited the old Task 14 disabled/uninstall disposition.

Resolution:

- every upgrade and rollback finishes disabled;
- persistent enabled can be reached only through `activate`;
- Milestone 16 reboot proof starts and ends enabled and never uninstalls on success.

### Re-review

Pass. There is one and only one persistent activation path. Every real-sleep/reboot transition is
separately approval-gated and every bounded acceptance command remains fail-safe to disabled.

## S4 — Verification, operations, evidence, and completion

### Implemented

Defined automated verification, fresh real-system acceptance, operator documentation, evidence
privacy, Git/package provenance, operational baseline, and the required final live state.

### Immediate review

Finding S4-P1: the prior production Plan referred to an operator runbook that did not exist in the
repository.

Finding S4-P1: an operational baseline based only on existing `diagnostics` could not reliably
report runtime health, crash active-run state, or expected/actual checksums.

Resolution:

- require `docs/operations/production-daemon.md` as an actual deliverable;
- require stable status/diagnostics/baseline contracts and a connected runtime-health source;
- require final closure to name the installed release identity and prove enabled/loaded/running.

### Re-review

Pass. Every completion claim is observable, privacy-bounded, and tied to the exact installed
artifact identity. Disabled, booted-out, rolled-back, uninstalled, circuit-open, or duplicate
authority states are explicitly incomplete outcomes.

## Spec Task review disposition

S1–S4 passed their immediate review and re-review. No Spec Task finding remains open. The complete
assembled Spec proceeds to the independent whole-Spec implementation review.
