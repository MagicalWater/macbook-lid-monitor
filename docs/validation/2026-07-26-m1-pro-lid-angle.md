# M1 Pro Lid Angle Sensor Validation

## Environment

- Date: 2026-07-26
- Hardware: Apple Silicon MacBook Pro with M1 Pro
- macOS: 26.5.2
- Tool: `macbook-lid-monitor 0.1.0`
- Command: `./scripts/run-diagnostic.sh --watch --raw --duration 120`

## Selected device

```text
Vendor ID: 0x05AC
Product ID: 0x8104
Usage Page: 0x0020 (Sensor)
Usage: 0x008A (Orientation)
Transport: SPU
Candidate score: 45
```

The identity matches the known Apple lid-angle HID device used by existing reverse-engineered implementations.

## Evidence

The operator moved the display through approximately 90°, 45°, 15°, nearly closed, and then reopened it. The exact physical angles were approximate rather than measured with a separate protractor, so the validation relies on direction, stable plateaus, and repeatability rather than exact calibration.

Representative stable samples:

| Phase | Sensor values | Raw reports | AppleClamshellState |
|---|---:|---|---|
| Initial open position | 172–173 | `01 AC 00`, `01 AD 00` | `open` |
| First intermediate position | 150–152 | `01 96 00`, `01 98 00` | `open` |
| Next intermediate position | 98 | `01 62 00` | `open` |
| Lower positions | 60–65 | `01 3C 00`, `01 41 00` | `open` |
| Reopening movement | 171–175 | `01 AB 00`, `01 AF 00` | `open` |

During movement, transient values of 184–185 were also observed. The report shape was consistently three bytes:

```text
[report ID 0x01, angle low byte, angle high byte]
```

The value is therefore decoded as a little-endian 16-bit integer. A bounded range of `0...360` is used; values above 180 are retained rather than rejected because the HID sensor representation is not limited to the mechanically usable lid range.

## Result classification

**A — Raw values change consistently; decoded values are monotonic and physically responsive; `AppleClamshellState` remains `open`.**

The raw lid-angle sensor and its HID input-report path are functioning. The failure is downstream of the raw sensor path: macOS does not convert the closure into the expected clamshell state or sleep event.

## Limitation

This run does not establish a safe automatic-sleep threshold. The lowest stable observed value was approximately 60 while the display was described as nearly closed. The operator positions were approximate and the sensor may have model-specific calibration or offset behavior.

Before any auto-sleep service is built, a separate calibration run must determine:

1. The stable sensor value immediately before the physical lid contacts the base.
2. The value after reopening a small amount.
3. A threshold and hysteresis band that cannot trigger during normal low-angle use.
4. Debounce and post-wake cooldown behavior.

No auto-sleep behavior was added during this diagnostic phase.
