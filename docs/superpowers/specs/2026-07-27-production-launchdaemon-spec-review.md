# Production LaunchDaemon Spec Review

## Governance execution record

This review is the first document gate in the Production LaunchDaemon planning phase.
The gate was executed in this order:

1. Draft the architecture audit and production specification.
2. Review the draft against the required production/feasibility, authority, mode,
   sleep-safety, lifecycle, logging, hardware-compatibility, and acceptance boundaries.
3. Record findings below.
4. Revise the specification to resolve every finding.
5. Re-review the revised specification using the checklist below.
6. Close the Spec gate before treating the implementation plan as approved.

The implementation plan and task register are not evidence that this gate passed;
the pass decision is based only on the revised specification and this review record.

## Initial draft review findings

### P0 — Hardware ranking could still authorize sleep

The initial concept reused `CandidateRanker` selection for production. A high score is evidence for investigation, not proof of compatible report semantics.

**Resolution:** The revised spec requires exact profile identity and profile-bound decoding. Ranking is diagnostic-only.

### P0 — Mode validation was not composition-enforced

The initial concept described mode strings but did not guarantee that disabled/dry-run could not construct the real requester.

**Resolution:** Added the invariant that only fully validated enabled mode may construct `MacOSSleepRequester`; composition tests are mandatory.

### P0 — Freshness was implicit

Existing invalid-data fail-open behavior did not prove that old but syntactically valid data could not trigger close or recovery sleep.

**Resolution:** Added sample freshness and post-wake epoch requirements plus duplicate-request guards.

### P1 — Restart policy relied only on launchd throttling

`ThrottleInterval` reduces frequency but does not define a crash budget or operator-visible circuit breaker.

**Resolution:** Added bounded persistent crash accounting and explicit circuit-open recovery.

### P1 — Upgrade did not guarantee automatic rollback

The initial lifecycle listed upgrade and rollback but did not require restoration when health verification failed.

**Resolution:** Upgrade is now a transaction with automatic restoration and rollback health verification.

### P1 — Logging privacy was under-specified

The initial draft allowed structured sensor evidence without defining frequency or raw-report restrictions.

**Resolution:** Prohibited per-report and raw-byte production logs; sensor values are limited to transitions or explicit bounded diagnostics.

## Re-review checklist

- Problem and production/feasibility boundary: pass.
- Scope and non-goals: pass.
- Single authority and no LaunchAgent: pass.
- Disabled/dry-run/enabled semantics: pass.
- Sleep fail-open and no-retry behavior: pass.
- Install, upgrade, rollback, uninstall responsibility: pass.
- Logging, privacy, ownership, and fixed paths: pass.
- Unknown hardware/report/stale data fail-safe: pass.
- Acceptance criteria are observable and testable: pass.
- No placeholder, contradictory requirement, or unprovable completion claim: pass.

## Disposition

**Spec approved for planning.** This approval covers design documentation only. It does not approve production code changes or any system mutation.

The corresponding closure record is
`docs/superpowers/specs/2026-07-27-production-launchdaemon-spec-closure.md`.
