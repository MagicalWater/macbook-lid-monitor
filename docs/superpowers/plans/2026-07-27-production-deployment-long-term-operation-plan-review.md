# Milestone 16 Implementation Plan Review

Date: 2026-07-27

## Scope

Independent review of the complete implementation Plan after Plan Tasks P1–P5. This review does
not inherit their pass decisions.

## Spec coverage

| Spec concern | Plan Tasks |
| --- | --- |
| Source/worktree/formal-main provenance | 14–15, 18 |
| Non-replaceable shared sleep authority | 1–2, 6, 16–18 |
| No requester environment override | 3–5, 14 |
| Manifest and installed-set integrity | 4–6, 10, 14–18 |
| Target model/profile | 5, 7, 10, 16–18 |
| Acceptance identity | 7–8, 12, 16–18 |
| Persistent activation | 8, 17 |
| Runtime health/status/diagnostics/baseline | 9–10, 16–18 |
| Safe log maintenance | 11, 13, 18 |
| Disabled upgrade/rollback/uninstall | 12–13 |
| Operator runbook | 13 |
| Full/clean verification | 5, stage reviews, 14, 18 |
| Separate mutation/sleep/reboot approvals | 15–18 |
| Final installed/enabled/running state | 17–18 |

## Findings

### P1 — Runtime and shell verifiers could diverge

Two independent implementations are necessary because the daemon and operator tooling run in
different contexts, but divergent field names or normalization would create false disagreement.

Resolution: Task 4 defines the manifest schema first; Tasks 5 and 6 consume the same keys and
normalization rules. Cross-layer fixtures and exact expected/actual checksum output are required.

### P1 — Health persistence could become a high-frequency disk writer

Resolution: Task 9 limits writes to transitions/errors and a bounded heartbeat; it explicitly
prohibits per-report writes and tests throttling.

### P1 — Final activation could be lost during evidence-only documentation work

Resolution: Tasks 17–18 distinguish the installed release commit from later evidence-only commits
and prohibit mode-changing closure commands. Repository evidence may advance without touching the
installed package.

## Re-review checklist

- Dependency order is executable without forward references: pass.
- Task sizes isolate security, integrity, activation, observability, and deployment: pass.
- Every code Task begins with a failing test and has focused/full verification: pass.
- Every Task has immediate review and an independent commit: pass.
- Stage and holistic reviews do not borrow per-Task approval: pass.
- Stage A, Stage B, and Stage C each have an independently named implementation review: pass.
- Commands that create files explicitly stage those files before commit: pass.
- Shell lifecycle responsibilities have stable interfaces before implementation begins: pass.
- No system mutation occurs before the automated release gate and formal-main integration: pass.
- Install, real sleep, recovery, activation, reboot, merge/push remain separately gated: pass.
- Every failure has disabled/booted-out or redeployment-safe disposition: pass.
- Final success cannot be disabled or uninstalled: pass.

## Decision

**Approved after revision.** No Critical/P0/P1 Plan finding remains open.
