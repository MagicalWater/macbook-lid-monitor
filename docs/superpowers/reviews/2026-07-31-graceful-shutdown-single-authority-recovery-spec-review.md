# Task 6R3 design review

日期：2026-07-31

## Layer 1 — Requirement review

- Incident evidence 區分 dry-run behavior pass 與 cleanup failure：通過。
- Root cause涵蓋 management double termination與 signal disposition window：通過。
- Production起始邊界精確為 disabled／job absent／zero PID／runActive=true：通過。
- 使用者核准的 repository、deployment、crash repair與三階段驗收範圍完整：通過。
- activate、reboot、push明確禁止：通過。

## Layer 2 — Design review

- 只延長 timeout 無法處理永久未落盤：拒絕正確。
- 只修 management 或只修 signal controller均留下單點風險：分析完整。
- Selected design 使用 single termination authority與 completion guard：通過。
- True signal-level fork test可在不殺死 XCTest parent的前提下捕捉原 bug：通過。
- Timeout／no-bootstrap／no-force-kill semantics未弱化：通過。

## Decision

**Task 6R3 design approved.** Open P0 = 0；Open P1 without disposition = 0。

