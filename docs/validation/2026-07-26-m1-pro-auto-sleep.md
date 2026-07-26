# M1 Pro Auto-Sleep Dry-Run Validation — 2026-07-26

## Scope

This document records the bounded hardware acceptance for the foreground
auto-sleep dry-run flow. No real sleep request was executed.

Validation machine:

- Hardware: Apple Silicon MacBook Pro with M1 Pro
- macOS: 26.5.2
- Architecture: arm64
- Validation date: 2026-07-26
- Evidence recording completed: 2026-07-26 15:49 CST
- Reviewed commit before documentation: `30837d6`

Selected HID identity observed during this session:

```text
Vendor ID:  0x05AC
Product ID: 0x8104
Usage Page: 0x0020
Usage:      0x008A
Transport:  SPU
Registry ID observed: 4294968644
```

The registry ID is runtime evidence only and must not be treated as a stable
hardware identifier across boots.

## Effective policy

The executable printed the parsed effective configuration before acceptance:

```text
auto-sleep config: mode=dry-run sleep-threshold=68 reopen-threshold=75 debounce=2 wake-cooldown=5
```

`LidSleepPolicy.calibratedDefault` is the runtime authority for these defaults.
The helper script does not duplicate policy values.

The values are decoded sensor values, not guaranteed physical hinge degrees.

Observed calibration landmarks on this machine:

| Physical position | Observed sensor value | Interpretation |
| --- | ---: | --- |
| Fully open | 189 | Upper observed range |
| Approximately 90° open | 148 | Normal validation start position |
| Lowest position that must remain awake | 105 | Safely above the sleep threshold |
| Natural intended sleep position | 68 | Selected sleep threshold |
| Lowest self-supporting position | 60 | Earlier candidate threshold; rejected as impractically low |

The `105` awake-safety observation was established during the same hardware
calibration phase. The five formal stability cycles then concentrated on the
close-trigger-reopen sequence and did not require the user to reproduce an
exact sensor value of `105` in every cycle.

## Five-cycle stability acceptance

Each cycle started armed above the reopen threshold, closed clearly below the
sleep threshold for longer than the two-second debounce, and reopened above the
reopen threshold.

Every cycle produced exactly this transition sequence:

```text
auto-sleep: candidate-started
auto-sleep: triggered
auto-sleep: would-sleep
auto-sleep: rearmed
```

| Cycle | Candidate | Would-sleep count | Rearmed | Result |
| ---: | --- | ---: | --- | --- |
| 1 | Started once | 1 | Yes | Pass |
| 2 | Started once | 1 | Yes | Pass |
| 3 | Started once | 1 | Yes | Pass |
| 4 | Started once | 1 | Yes | Pass |
| 5 | Started once | 1 | Yes | Pass |

Result: **5/5 passed** with no duplicate trigger in any observed cycle.

The interactive terminal session did not persist an absolute timestamp for each
individual transition. This document therefore does not invent per-cycle times;
the ordered transition output was inspected immediately after every cycle.

## Cancellation acceptance

The lid was moved below the sleep threshold and reopened before the two-second
debounce elapsed.

Observed output:

```text
auto-sleep: candidate-started
auto-sleep: candidate-cancelled
```

No `triggered` or `would-sleep` output occurred. Result: **Pass**.

## Startup cooldown acceptance

The existing dry-run process was stopped while the lid was held clearly below
the sleep threshold. A fresh dry-run process was then started without reopening
the lid.

Observed startup output:

```text
auto-sleep: disarmed
```

No candidate, trigger, or would-sleep decision occurred during or after the
five-second startup cooldown while the lid remained below the reopen threshold.

After opening above the reopen threshold, closing below the sleep threshold for
longer than two seconds, and reopening again, the process emitted:

```text
auto-sleep: rearmed
auto-sleep: candidate-started
auto-sleep: triggered
auto-sleep: would-sleep
auto-sleep: rearmed
```

Result: **Pass**. Startup at a low angle fails safe and requires an explicit
reopen before a later close can trigger.

## Supporting verification

After centralizing the calibrated policy and aligning tests and documentation:

```text
swift test: 64 tests, 0 failures
swift build -c release: passed
git diff --check: passed
helper policy duplication scan: passed
```

The dry-run helper was also started on the validation Mac and its effective
configuration line confirmed `68 / 75 / 2 / 5` before the hardware cycles.

## Findings and decision

- Open P0 findings: 0
- Open P1 findings in Task 6 scope: 0
- Real sleep invoked: No
- Persistent service installed: No
- Persistent power setting changed: No

Task 6 dry-run hardware acceptance decision: **Pass**.

Real-sleep acceptance remains blocked until Task 7 completes the idle-energy and
whole-phase operational safety review and the user gives separate explicit
approval for one bounded foreground real-sleep test.
