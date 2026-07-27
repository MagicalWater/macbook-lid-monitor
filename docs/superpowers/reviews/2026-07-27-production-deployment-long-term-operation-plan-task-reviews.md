# Milestone 16 Plan Task Reviews

Date: 2026-07-27

## P1 — File and component responsibility map

### Immediate review finding

P1-P1: extending the existing 1,099-line management script for all deployment state,
observability, and integrity logic would make review boundaries unreliable.

### Resolution and re-review

Split focused shell libraries for installed-set verification, deployment state, and observability;
keep the top-level script as dispatcher/orchestrator. Pass.

## P2 — Runtime and packaging implementation decomposition

### Immediate review findings

P2-P0: activation was originally ordered before runtime installed-set verification, allowing the
management layer to approve enabled while the daemon lacked the same gate.

P2-P1: authority primitive and authority path-selection policy were initially one large Task,
making inode-security failures difficult to isolate from composition failures.

### Resolution and re-review

- Runtime verifier now closes in Task 5 before any deployment command in Stage B.
- Secure lease primitive is Task 1; shared path resolution/composition is Task 2.
- Requester environment removal is isolated as Task 3.

Pass.

## P3 — Automated release gate

### Immediate review finding

P3-P1: focused and full tests alone do not prove the package can be reproduced from a clean graph
or that no system mutation occurred during implementation.

### Resolution and re-review

Task 14 requires all release products, static/plist/package checks, independent clean snapshot,
residual-state proof, and holistic implementation review. Pass.

## P4 — Formal integration and real deployment

### Immediate review findings

P4-P0: package preparation from an unmerged detached worktree would violate the Spec's real-package
provenance rule.

P4-P0: one Task containing enabled sleep, recovery resleep, and persistent activation would force
three materially different approval gates to share one Task review and completion decision.

P4-P1: reboot and operational baseline were initially split such that a reboot finding could leave
the service in an ambiguous final mode.

### Resolution and re-review

- Task 15 is a distinct formal-main integration/package gate.
- Tasks 18, 19, and 20 now independently own enabled-once, recovery-resleep, and persistent
  activation, each with its own immediate review and terminal state.
- Task 17 separately owns the `/Library` dry-run mutation and evidence even though it cannot sleep.
- Task 21 owns enabled reboot, pre-login, post-reboot baseline, and final live-state review as one
  terminal stage; emergency cleanup makes the Milestone incomplete until redeployed.

Pass.

## P5 — Spec coverage and closure

### Immediate review findings

P5-P1: the initial maintenance wording did not explicitly distinguish artifact-changing upgrades
from evidence-only repository commits.

P5-P1: Tasks 1–5 used `git commit -am` even when they created new files, so the written command
could omit required artifacts.

P5-P1: Stage C had a holistic closure Task but no separately named Stage C implementation review,
contradicting the three-stage governance rule.

P5-P1: several shell Tasks described behavior without locking stable function boundaries, leaving
too much interface invention to implementation time.

P5-P0: the first formal Task decomposition still grouped three independent approval gates in one
Task, violating the one-primary-responsibility review rule.

P5-P1: the Spec required serialized install/upgrade/rollback/uninstall mutation, but the initial
Plan had no explicit lifecycle guard or concurrency test.

### Resolution and re-review

Acceptance identity is tied to installed artifacts/policy/compatibility. Artifact-changing upgrade
or rollback invalidates acceptance and finishes disabled; evidence-only commits may advance docs
while continuing to name the installed release identity. All commit commands now explicitly stage
new and modified files. Stage C now has an independent review. Tasks 6–12 name their stable shell
interfaces and transaction boundaries. Pass.
The deployment tail was expanded from Tasks 15–18 to Tasks 15–21 so install, dry-run, one-sleep,
recovery-resleep, activation, and reboot each have a distinct Task review. Pass.
Task 6 now defines an atomic transient lifecycle guard, stable busy behavior, cleanup, and a
concurrent mutation regression test. Pass.

## Disposition

Plan Tasks P1–P5 pass. No open Plan Task finding remains. Proceed to whole-Plan implementation
review.
