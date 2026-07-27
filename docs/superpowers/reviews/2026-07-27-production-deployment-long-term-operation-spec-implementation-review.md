# Milestone 16 Whole-Spec Implementation Review

Date: 2026-07-27

## Scope

Review the assembled Milestone 16 Spec after Spec Tasks S1–S4, without relying on the individual
Task pass decisions. The review asks whether an implementation team could build and verify the
requested long-term deployment without inventing missing safety or lifecycle semantics.

## Traceability review

| Audit finding | Normative Spec authority | Observable verification |
| --- | --- | --- |
| Replaceable `/tmp` authority inode | §§6.7, 7.1, 7.2 | managed lease metadata and replacement/inode-split tests |
| No persistent activation entry | §§6.3, 7.6, 7.7, Gate 5 | acceptance-bound `activate` tests and final one-PID state |
| Requester environment override | §7.3 | deployable composition/source and plist prohibition tests |
| Incomplete installed integrity | §7.4 | binary/plist/normalized-config checksums and runtime gate tests |
| Incomplete health/diagnostics | §§7.8, 7.9 | stable output/parser tests and real operational baseline |
| Ambiguous upgrade/rollback | §7.11 | forced-disabled transaction tests and acceptance invalidation |
| Unsafe active-log rotation | §7.10 | running-writer copy-and-truncate regression test |
| Missing runbook | §11 | repository document plus command-to-doc review |
| Broad hardware wording | §7.5 | model/chip preflight plus exact HID runtime authorization |
| Long-lived state metadata | §§7.1, 7.4, 7.6 | owner/mode/type/link-count and symlink-ancestor tests |

## Implementation-readiness findings

### P1 — Upgrade acceptance reuse needed an explicit conservative default

Artifact-identical docs-only changes do not invalidate the installed identity, but any executable,
plist, manifest, policy, authority, or lifecycle change must invalidate acceptance. The initial
language could have led an implementer to preserve acceptance too broadly based only on source
commit.

Resolution: acceptance identity is based on the deployed artifact/checksum set and compatibility
fields. Changed deployment artifacts or policy invalidate it; evidence-only commits may differ only
when the installed release identity remains named explicitly.

### P1 — Foreground fallback needed a strict installed-package boundary

The foreground CLI still needs a usable authority when no production package exists. A fallback is
safe only when binary, plist, support/manifest markers, and loaded system job are all absent.

Resolution: §7.2 prohibits fallback whenever production is installed or registered and requires
the managed lease for both real-sleep compositions in that state.

## Re-review

- Components have explicit responsibilities and fixed paths: pass.
- Data/state flow from package preparation through activation and reboot: pass.
- Failure behavior is fail-open and has a safe stop: pass.
- Every system mutation and real sleep/reboot has a separate gate: pass.
- Tests can observe every security and lifecycle invariant: pass.
- Final state is unambiguous and differs correctly from prior acceptance: pass.
- No implementation detail requires unique device identifiers or password handling: pass.

## Decision

**Pass.** The Spec is implementation-ready. No Critical/P0/P1 whole-Spec finding remains open.
