# Lid Angle Diagnostic Spec Review

## Review Scope

This review treats the design specification as its own governed task. It checks whether the document is sufficiently precise to produce an implementation plan without relying on hidden assumptions.

Reviewed file:

```text
docs/superpowers/specs/2026-07-26-lid-angle-diagnostic-design.md
```

## Task-Level Review Findings

### Finding S1 — Platform baseline was implicit

**Severity:** P1

The design selected Swift and macOS APIs but did not define a deployment target, Swift toolchain expectation, dependency policy, or authoritative version source. Different implementers could therefore create incompatible package manifests or duplicate version constants.

**Resolution:** Added an explicit platform baseline: Apple Silicon-first validation, macOS 13.0 minimum, Swift 6.x, Swift Package Manager, no third-party runtime, and a single `0.1.0` version source.

### Finding S2 — CLI behavior was underspecified

**Severity:** P1

The initial option list did not define conflicts, invalid duration handling, standard-error behavior, cancellation semantics, or exit codes.

**Resolution:** Added argument compatibility rules and stable exit-code meanings.

### Finding S3 — Candidate selection could open unrelated HID devices

**Severity:** P1

The original ranking guidance said matching should be narrow, but it did not establish mandatory exclusion rules or a minimum-confidence stop condition.

**Resolution:** Added exclusion of keyboard, pointing, trackpad, digitizer, and consumer-control devices; required lid-related identity or non-input usage evidence; and required stopping when confidence is insufficient.

### Finding S4 — Permission guidance risked overclaiming

**Severity:** P2

The design mentioned documenting Privacy & Security permissions without acknowledging that the exact permission depends on macOS and device classification.

**Resolution:** Required evidence-first reporting and prohibited promising that Input Monitoring is necessarily required.

### Finding S5 — Hardware success evidence was incomplete

**Severity:** P1

The validation procedure described movement but did not define the evidence needed to distinguish changing, fixed, unsupported, and interrupted streams.

**Resolution:** Added mandatory capture points for three physical positions, raw/unchanged evidence, decoder status, clamshell state, and stream resumption.

### Finding S6 — The second investigation had no hard boundary

**Severity:** P2

“Investigate once” could expand into unsafe or unbounded experiments.

**Resolution:** Limited the second investigation to IOHID metadata, IORegistry metadata, and permission-denial analysis, explicitly excluding writes, elevation, DriverKit, kernel, and SIP workarounds.

## Task Re-Review

After the above resolutions, the specification now defines:

- The supported platform and toolchain baseline.
- Complete initial CLI semantics.
- Safe device-selection boundaries.
- Stable diagnostic exit categories.
- Evidence required for hardware conclusions.
- A bounded stopping rule when safe sensor access is unavailable.

Open P0 findings: `0`

Open P1 findings: `0`

Open P2 findings: `0`

## Whole-Phase Review

The revised specification remains focused on one deliverable: a read-only diagnostic executable. It does not leak auto-sleep, persistence, system modification, or repair behavior into Phase 1. Component boundaries remain independently testable, and all later decisions depend on captured hardware evidence rather than assumptions.

The specification is ready to serve as the authority for the implementation plan.
