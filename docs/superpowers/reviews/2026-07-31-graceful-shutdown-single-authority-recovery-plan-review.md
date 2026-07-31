# Task 6R3 implementation plan review

日期：2026-07-31

## Layer 1 — Coverage review

- True POSIX double-signal reproduction precedes production code: pass.
- Signal controller and management script are separate TDD/review units: pass.
- Existing timeout/no-bootstrap contracts remain explicit: pass.
- Holistic, integration, deployment, crash repair and serial acceptance are covered: pass.
- Activate, reboot and push remain prohibited: pass.

## Layer 2 — Execution review

- Independent xctest child isolates expected RED signal death from XCTest parent and avoids unsafe
  post-fork Dispatch use: pass.
- Minimal signal change ignores repeats only during synchronous handler completion: pass.
- Management change follows the already-successful maintenance single-bootout pattern: pass.
- Production batch has per-stage fail-stop gates and safe-state checks: pass.
- No unrelated daemon policy or state-machine refactor: pass.

## Decision

**Task 6R3 plan approved for inline execution.** Open P0 = 0；Open P1 without disposition = 0。

