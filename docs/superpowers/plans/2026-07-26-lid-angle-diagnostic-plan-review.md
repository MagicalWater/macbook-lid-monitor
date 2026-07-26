# Lid Angle Diagnostic Plan Review

## Review Scope

This review treats the implementation plan as its own governed phase. It verifies that each task is independently testable, interfaces are explicit, safety constraints are enforceable, and every design requirement maps to implementation or validation work.

Reviewed plan:

```text
docs/superpowers/plans/2026-07-26-lid-angle-diagnostic.md
```

## Task-Level Review Checklist

### Structure and boundaries

- Package foundation, discovery, decoding, streaming, orchestration, and hardware validation are separate tasks.
- Each task produces interfaces consumed by later tasks.
- Hardware-dependent behavior is deferred until pure logic and resource boundaries are testable.
- Documentation and hardware evidence are deliverables rather than informal terminal output.

### TDD and verification

- Parser, ranking, decoding, formatting, and lifecycle seams have explicit failing-test steps.
- Each task contains targeted validation and a task review gate.
- Clean full-package validation is required before hardware conclusions.
- Hardware-derived decoder changes require an explicit red-green cycle.

### Safety

- List mode does not open devices.
- Forbidden HID input classes are excluded before candidate ranking.
- Low-confidence candidates cannot be opened automatically.
- No write reports, sleep calls, privilege escalation, persistence, kernel work, DriverKit, or SIP changes are planned.
- The whole-phase review includes a source scan for forbidden APIs.

### Specification coverage

- Purpose and diagnostic-only scope: Tasks 1–6 and Global Constraints.
- CLI modes and exit codes: Tasks 1 and 5.
- Device enumeration and metadata: Task 2.
- Safe candidate ranking: Task 2.
- Raw report streaming: Task 4.
- Decoding isolation: Task 3 and evidence-driven extension in Task 6.
- Clamshell comparison: Tasks 4–6.
- Deterministic output: Task 5.
- Permissions and actionable failures: Tasks 4–6.
- Unit testing: Tasks 1–5.
- Hardware validation and decision classification: Task 6.
- Removal and limitations: Task 6 README.

## Review Findings

### Finding P1 — Hardware exploration could tempt threshold bypasses

**Resolution:** The plan explicitly prohibits threshold reduction and privilege granting merely to force a result. Low-confidence devices remain metadata-only.

### Finding P1 — A guessed decoder could be mistaken for confirmed hardware support

**Resolution:** The initial two-byte decoder is labeled exploratory, and any hardware-specific decoder change requires captured fixtures, red-green tests, and repeated physical validation.

### Finding P1 — HID resource cleanup needed a test seam

**Resolution:** Task 4 introduces `HIDDeviceSession` so lifecycle order can be tested without a physical sensor callback.

### Finding P2 — Final review needed an enforceable safety check

**Resolution:** Added a repository scan for HID writes, sleep APIs, NVRAM, persistence, and privilege-escalation APIs.

### Finding P2 — Validation output could remain ephemeral

**Resolution:** Task 6 requires a committed evidence document with result classification A–E.

## Task Re-Review

After incorporating the resolutions above:

Open P0 findings: `0`

Open P1 findings: `0`

Open P2 findings: `0`

## Whole-Phase Review

The plan is scoped to one diagnostic executable and does not include the later auto-sleep service. Tasks are ordered by dependency, every meaningful boundary has its own test or review gate, and the hardware investigation has a bounded stopping rule. The plan is executable under the user's two-layer Task governance model.

The implementation plan is ready for task-by-task execution.
