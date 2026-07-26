# MacBook Lid Angle Diagnostic — Final Review

## Scope reviewed

The implementation was reviewed against all 13 sections of `docs/superpowers/specs/2026-07-26-lid-angle-diagnostic-design.md` and the six Tasks in `docs/superpowers/plans/2026-07-26-lid-angle-diagnostic.md`.

## Spec coverage

| Spec section | Coverage |
|---|---|
| 1. Purpose | Read-only Swift diagnostic implemented |
| 2. Success Criteria | Sensor discovered, raw changes captured, clamshell comparison recorded |
| 3. Scope | CLI, HID enumeration, streaming, decoding, script, tests and docs implemented; excluded features absent |
| 4. Technical Approach | Native Swift, IOHID and IORegistry adapters with isolated decoding |
| 5. Project Structure | Implemented with one additional focused stream test file and review/validation docs |
| 6. Components | CLI, discovery, stream, decoder, state reader and models implemented |
| 7. Data Flow | End-to-end device-to-output path validated on hardware |
| 8. Output Format | Deterministic formatter and raw-byte output tested |
| 9. Error Handling | Usage, unavailable, I/O and internal exit mapping implemented |
| 10. Permissions and Safety | No privilege escalation, HID writes, sleep calls or persistence |
| 11. Testing Strategy | 27 unit tests plus bounded M1 Pro hardware run |
| 12. Decision After Diagnostic | Raw sensor path works; separate auto-sleep calibration/design is justified |
| 13. Removal | Self-contained project and no persistent system changes |

## Task commits

```text
dc7eb75 feat: 建立診斷工具 CLI 基礎
acec6bf feat: 加入安全的 HID 候選裝置探索
10a8597 feat: 建立可測試的角度解碼管線
18ce62d feat: 串接唯讀 HID 報告與闔蓋狀態
84c2957 feat: 完成診斷 CLI 與輸出流程
```

Task 6 documentation, hardware evidence and final review are included in the closing commit following this review.

## Review findings

### Closed findings

- Task 1: `.build/` was initially unignored; `.gitignore` added before Task closure.
- Task 2: vendor-defined keyboard/trackpad child devices could enter ranking; name-based safety exclusion and regression test added.
- Task 4: stop/run-loop and callback-context lifetime race; cleanup order corrected and lifecycle tests rerun.
- Task 5: the known Apple Sensor/Orientation HID identity was initially below threshold; exact VID/PID/usage identity and regression test added.
- Task 6: decoder originally rejected values above 180; hardware evidence and external implementations support a 16-bit sensor range, so the bound was corrected to `0...360` with tests.

### Open findings

```text
Open P0 = 0
Open P1 = 0
Open P2 = 0
```

## Hardware result

Classification: **A**.

- The Apple HID sensor at VID `0x05AC`, PID `0x8104`, Usage Page `0x0020`, Usage `0x008A` was discovered and opened read-only.
- Three-byte input reports changed consistently with display motion.
- The decoded values formed stable plateaus and changed in the expected direction.
- `AppleClamshellState` remained `open` throughout all positions, including nearly closed.

This demonstrates that the raw lid-angle hardware path is functional while the normal macOS clamshell event path is not.

## Auto-sleep decision

A separate auto-sleep design is technically justified because a functioning independent sensor signal exists. It must not reuse an arbitrary `5°` threshold. The next phase requires a dedicated near-closure calibration, hysteresis, debounce, wake cooldown, manual disable and fail-safe behavior.

The current diagnostic remains read-only and does not sleep the Mac.
