# Milestone 16 Production Deployment and Long-term Operation Spec Closure

Date: 2026-07-27

## Gate

```text
Spec Tasks S1–S4
→ each Task implement
→ immediate review
→ findings/fix/re-review
→ whole-Spec implementation review
→ holistic Spec review
→ closure
```

## Inputs

- `docs/audits/2026-07-27-production-deployment-long-term-operation-audit.md`
- `docs/superpowers/specs/2026-07-27-production-deployment-long-term-operation-design.md`
- `docs/superpowers/specs/2026-07-27-production-deployment-long-term-operation-spec-review.md`
- `docs/superpowers/tasks/2026-07-27-production-deployment-long-term-operation-spec-tasks.md`
- `docs/superpowers/reviews/2026-07-27-production-deployment-long-term-operation-spec-task-reviews.md`
- `docs/superpowers/reviews/2026-07-27-production-deployment-long-term-operation-spec-implementation-review.md`
- `docs/superpowers/reviews/2026-07-27-production-deployment-long-term-operation-spec-holistic-review.md`

## Closure checks

- The final state is installed, loaded, enabled, running, boot-persistent, and pre-login capable.
- The prior acceptance/uninstall milestone is distinguished from permanent deployment.
- Formal-main source provenance and isolated-worktree governance are explicit.
- Replaceable `/tmp` authority is prohibited for installed production.
- Production environment requester injection is removed from the deployment design.
- Installed binary, plist, normalized config, current config, manifest, ownership, modes, and link
  safety have a complete verification contract.
- Bounded real-sleep acceptance remains separately approval-gated and returns disabled.
- Final persistent activation is evidence-bound and has no unrestricted enable shortcut.
- Enabled reboot and pre-login verification leave the service enabled.
- Crash budget, health, CPU/memory, authority, logs, and checksums are part of operational evidence.
- Online log rotation preserves the active inode.
- Upgrade/rollback cannot silently restore enabled outside the deployment gate.
- Emergency disable/reset/rollback/uninstall remain available but are not successful closure steps.
- Operator documentation and fresh deployment evidence are mandatory.
- No password handling, automatic reboot, raw HID evidence, or unnecessary unique device ID is
  authorized.
- Spec Tasks S1–S4 each completed immediate review, findings disposition, correction where
  required, and re-review before the next Spec Task began.
- The assembled Spec passed an independent whole-Spec implementation review and a holistic review.

## Findings disposition

All findings in the Spec Task reviews, original Spec review, whole-Spec implementation review, and
holistic review are resolved at the design level. Implementation evidence is not claimed and no
finding is considered operationally closed until its future implementation Task passes immediate
review, focused/full verification, and any required real-system acceptance.

## Decision

**Closed and user-approved.** The Spec is the architecture and safety authority for Milestone 16
Plan governance under the complete dual-layer governance model.

The user authorized the following next activity on 2026-07-27:

```text
Implementation Plan draft
→ Plan review
→ revision
→ re-review
→ Plan closure
```

Production code changes remain prohibited until Plan and Task governance close. `/Library`
changes, launchd mutation, real sleep, persistent activation, and reboot remain separately
approval-gated. Merge, push, and worktree cleanup remain prohibited without explicit approval.

