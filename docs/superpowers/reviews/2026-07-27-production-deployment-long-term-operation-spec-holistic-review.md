# Milestone 16 Holistic Spec Review

Date: 2026-07-27

## Review boundary

Independent final review of the Spec phase, including source/system baseline, audit, Spec Tasks,
individual reviews, assembled-design review, approval boundaries, evidence privacy, and closure
semantics. This review authorizes planning only.

## Governance

- Spec Tasks S1–S4 are explicit, ordered, and independently reviewed.
- Each Task records implemented content, findings, resolution, and re-review.
- Whole-Spec implementation review did not inherit Task-level approval.
- Spec closure references all governance artifacts.
- The user explicitly authorized transition from Spec to Plan governance.

## Architecture and safety

1. Long-term enabled operation is treated as a new deployment lifecycle, not as an extension of
   historical bounded acceptance.
2. One persistent activation gate is authoritative.
3. Bounded real-sleep acceptance always cleans up to disabled.
4. Successful activation and reboot verification preserve enabled state.
5. Sleep authority is moved to a non-replaceable managed inode.
6. Runtime and management tooling both validate installed artifact identity.
7. Production requester selection cannot be changed by launchd environment configuration.
8. Upgrade and rollback cannot silently restore enabled mode.
9. Crash budget, fail-open behavior, freshness, wake epochs, and no-retry semantics remain intact.
10. Status, diagnostics, baseline, logs, operations, and emergency controls are first-class
    deliverables rather than manual notes.

## Scope and evidence

- Target remains the validated `MacBookPro18,1` / Apple M1 Pro and exact HID profile.
- No generic hardware support is implied.
- Previous acceptance informs expected behavior but cannot close fresh deployment checks.
- Passwords, serial number, hardware UUID, provisioning UDID, and raw HID reports are excluded.
- No merge, push, cleanup, `/Library` write, launchd mutation, sleep, or reboot occurred in the Spec
  phase.

## Verification evidence

The isolated worktree baseline passed 198 XCTest tests, the production daemon release build, Bash
syntax, shellcheck, plist/config/manifest lint, and `git diff --check`. Formal `main` remained clean
and synchronized at `e2b8afeac0bf8f7560d6a9d60b4da328d9650bd3`; the production package remained
uninstalled with no managed job or process.

## Decision

**Approved for Plan governance.** The Spec phase satisfies the complete dual-layer governance
model. This decision does not authorize production implementation or any system mutation.
