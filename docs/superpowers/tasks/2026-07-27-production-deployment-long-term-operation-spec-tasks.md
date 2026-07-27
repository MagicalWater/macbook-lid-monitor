# Milestone 16 Spec Task Register

Status: Complete; Spec Tasks S1–S4 and both whole-Spec reviews are closed.

## Governance contract

The Milestone 16 Spec is governed as work, not treated as an unreviewed prose artifact.

```text
Spec Task S1
→ implement
→ immediate review
→ fix findings
→ re-review
→ commit-ready
→ Spec Task S2
→ repeat through S4
→ whole-Spec implementation review
→ fix and re-review
→ holistic Spec review
→ Spec closure
```

No later Spec Task may borrow an earlier Task's review result. The whole-Spec implementation review
checks the assembled design; the holistic review independently checks governance, evidence,
architecture, safety, operations, and completion semantics.

## Spec Tasks

| Spec Task | Purpose | Primary artifacts | Immediate verification | Safe rollback |
| --- | --- | --- | --- | --- |
| S1 | Establish source, system, worktree, and non-mutation baseline | audit §§1–3; Spec §§1, 3–5 | formal-main SHA/clean check, managed-path/job/PID residual check, worktree identity | revert documentation commit; no system state |
| S2 | Classify long-term deployment blockers and alternatives | audit §§4–6; Spec §§4, 6 | finding traceability, severity check, rejected approaches, fail-open consistency | revert documentation commit; no system state |
| S3 | Define deployment architecture and approval gates | Spec §§7–8 | authority/integrity/activation/upgrade/reboot state-transition review | revert documentation commit; no system state |
| S4 | Define verification, operations, evidence, and completion | Spec §§9–12 | acceptance observability, privacy, operator coverage, terminal-state consistency | revert documentation commit; no system state |

## Layer 2 reviews

| Review | Purpose | Required evidence |
| --- | --- | --- |
| Whole-Spec implementation review | Review the complete assembled Spec as one implementation-facing design | every finding maps to a requirement; every requirement has an observable acceptance or explicit non-goal |
| Holistic Spec review | Independently review governance quality and end-to-end safety | source/system baseline, task reviews, correction history, approval gates, final state, no unauthorized mutation |

## Closure rule

Spec closure is allowed only when:

- S1–S4 are individually reviewed and re-reviewed;
- no Critical/P0/P1 Spec finding remains open;
- whole-Spec implementation review passes;
- holistic Spec review passes;
- the user authorizes transition to Plan governance;
- no production implementation or system mutation has occurred.
