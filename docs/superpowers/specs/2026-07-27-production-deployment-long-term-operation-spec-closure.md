# Milestone 16 Production Deployment and Long-term Operation Spec Closure

Date: 2026-07-27

## Gate

```text
Spec draft
→ review
→ findings
→ revision
→ re-review
→ closure
```

## Inputs

- `docs/audits/2026-07-27-production-deployment-long-term-operation-audit.md`
- `docs/superpowers/specs/2026-07-27-production-deployment-long-term-operation-design.md`
- `docs/superpowers/specs/2026-07-27-production-deployment-long-term-operation-spec-review.md`

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

## Findings disposition

All findings in the Spec review are resolved at the design level. Implementation evidence is not
claimed and no finding is considered operationally closed until its future Task passes immediate
review, focused/full verification, and any required real-system acceptance.

## Decision

**Closed for user review.** The Spec is the architecture and safety authority for Milestone 16
Plan governance.

The next permitted activity, after user acceptance of this Spec, is:

```text
Implementation Plan draft
→ Plan review
→ revision
→ re-review
→ Plan closure
```

Production code changes, `/Library` changes, launchd mutation, real sleep, persistent activation,
reboot, merge, push, and worktree cleanup remain prohibited at this closure.

