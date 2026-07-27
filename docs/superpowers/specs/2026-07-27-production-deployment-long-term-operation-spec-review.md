# Milestone 16 Production Deployment and Long-term Operation Spec Review

Date: 2026-07-27

## Governance execution record

This gate was executed as:

```text
current-state audit
→ initial Spec draft
→ independent safety/operations review
→ findings recorded
→ Spec revised
→ re-review
→ closure
```

The review is limited to deployment design. It does not authorize implementation, `/Library`
mutation, launchd mutation, real sleep, persistent activation, or reboot.

## Initial draft findings

### P0 — The draft reused the `/tmp` authority lease

The initial deployment outline assumed the prior cross-process lease was already sufficient.
Review showed that a user-owned `/tmp` inode can be removed and replaced while the daemon holds the
old inode, allowing a second authority.

**Resolution:** The revised Spec requires an installer-created root-owned managed lease inside the
non-user-writable support directory, metadata/link-count validation, shared daemon/foreground use,
and inode-replacement regression tests.

### P0 — Persistent activation could have become a raw public enable command

The initial outline considered exposing the existing internal enabled setter after acceptance.
That would allow future callers to skip exact installed identity and evidence gates.

**Resolution:** The revised Spec prohibits an unrestricted `enable` alias. Bounded acceptance
returns disabled; only evidence-bound `activate` may leave enabled.

### P0 — Reboot acceptance inherited the old disabled/uninstall disposition

The prior Task 14 command proves loaded/disabled/no PID, then rolls back and uninstalls. Reusing it
would contradict the Milestone 16 final state and would not prove pre-login enabled operation.

**Resolution:** The revised Spec defines a new enabled reboot start/finish flow, manual reboot,
pre-login observer evidence, temporary-observer cleanup, operational baseline capture, and final
enabled/running state.

### P1 — Artifact identity was defined too narrowly

The initial outline referred to the existing manifest without noticing that it hashes only the
binary and that runtime composition does not validate the manifest.

**Resolution:** The revised Spec covers binary, launchd plist, normalized config policy, current
config checksum, metadata, prohibited environment entries, and shared installed-set verification
at every authority-changing boundary.

### P1 — Acceptance-only environment injection remained deployable

The draft did not disposition `MLM_SLEEP_OPERATION` after its historical Task 13 use.

**Resolution:** The revised Spec removes environment requester selection from the deployable
production composition and retains failure behavior through dependency-injected tests.

### P1 — Upgrade/rollback could restore enabled outside the activation gate

The initial outline retained existing verbatim rollback-config restoration.

**Resolution:** Explicit and automatic upgrade rollback finish disabled and invalidate acceptance.
Neither path may restore persistent enabled state; reactivation always returns through the
deployment gate.

### P1 — Operational baseline lacked a reliable health source

The initial outline expected `status` and `diagnostics` to provide health, but the existing
`DaemonHealth` object is unused and current commands cannot report the requested fields.

**Resolution:** The revised Spec connects or replaces runtime health, defines stable status,
expanded redacted diagnostics, bounded health persistence, and a strict operational-baseline
command.

### P1 — Existing rotation algorithm is not safe for an open launchd log

Renaming the active path leaves the daemon writing to the archived inode.

**Resolution:** The revised Spec requires inode-preserving rotation and real running-process
verification that new events return to the primary log.

### P1 — The operator-document requirement had no actual repository artifact

The prior plan named an operations document that was never created.

**Resolution:** The revised Spec makes the dedicated runbook an explicit completion requirement.

### P2 — Hardware evidence risked collecting unnecessary unique identifiers

System inventory exposes serial, hardware UUID, and provisioning identifiers, none of which are
needed to bind this deployment to the accepted model/profile.

**Resolution:** The revised Spec records only `MacBookPro18,1`, Apple M1 Pro, and the exact HID
profile; unique identifiers are explicitly prohibited from evidence.

## Re-review checklist

- Formal main/origin/worktree provenance is explicit: pass.
- Historical acceptance is not treated as current deployment proof: pass.
- No installation or enablement is authorized by the Spec gate: pass.
- Managed authority cannot rely on a replaceable user-owned `/tmp` inode: pass.
- Disabled and dry-run cannot construct the real requester: pass.
- Acceptance commands fail safe to disabled: pass.
- Persistent activation has one evidence-bound explicit gate: pass.
- Production requester selection has no environment override: pass.
- Binary, plist, config policy, current config, metadata, and manifest identity are covered: pass.
- Exact HID profile and non-unique Mac model binding are explicit: pass.
- Crash budget, authority, process count, CPU, memory, logs, permissions, and checksums are present
  in diagnostics/baseline requirements: pass.
- Log rotation preserves the active inode: pass.
- Upgrade/rollback cannot silently reactivate enabled: pass.
- Enabled reboot, pre-login operation, wake monitoring, and duplicate-authority proof are fresh
  acceptance requirements: pass.
- Final success cannot be disabled, rolled back, or uninstalled: pass.
- Password handling and automatic reboot remain prohibited: pass.
- Operator runbook and repository evidence are mandatory: pass.
- No placeholder, `TBD`, contradictory state, or borrowed completion claim remains: pass.

## Decision

**Spec internally approved for user review and subsequent Plan governance.** All initial P0/P1
design findings have explicit resolutions in the revised Spec. This decision does not authorize
implementation or any system mutation.

