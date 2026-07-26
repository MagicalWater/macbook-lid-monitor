# M1 Pro Auto-Sleep Dry-Run Validation — 2026-07-26

> **Current authority note:** Task 6–8 below record the original accepted
> startup/wake-cooldown implementation. The runtime was later refined by
> `2026-07-26-angle-authoritative-resleep-design.md`: startup remains a
> five-second fail-open gate, while a real wake now starts a separate
> fifteen-second fresh-data recovery window. Historical output is preserved
> verbatim and must not be read as the current runtime configuration.

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

## Task 7 idle-energy observation

The release dry-run was observed with the lid stationary above the reopen
threshold for 901 seconds from 2026-07-26 16:03:24 +0800 through
2026-07-26 16:18:25 +0800.

Environmental controls:

- AC power remained connected.
- No third-party `caffeinate`, Amphetamine, or equivalent inhibitor was active.
- No other `macbook-lid-monitor` process remained after cleanup.
- The normal macOS `powerd` assertion named `Powerd - Prevent sleep while
  display is on` was retained as part of the intended supported environment.
- `PreventSystemSleep` remained `0`; the application created no power
  assertion.
- The lid remained stationary above `75` and no build/test activity occurred
  during the measured interval.

One earlier, invalid measurement attempt exposed a stale foreground dry-run
process that had been running with obsolete explicit `60 / 70` arguments. That
process and the incompatible measurement script were stopped, residual process
count was confirmed as zero, and the formal 901-second observation was restarted
from a clean state. The invalid attempt is not included in the metrics below.

Observed process metrics:

| Metric | Result |
| --- | ---: |
| Samples | 31 |
| Duration | 901 seconds |
| Average sampled CPU | 0.0000% |
| Maximum sampled CPU | 0.0000% |
| Process CPU time | 0.01 s → 0.07 s |
| RSS range | 11,136–11,936 KiB |
| Thread range | 3–4 |
| Total application log lines | 15 |
| Auto-sleep transition lines | 1 |

The only transition line was the expected startup state:

```text
auto-sleep: rearmed
```

There was no periodic logging, candidate churn, trigger, or `would-sleep`
decision while stationary. RSS rose during startup and then remained within a
narrow stable range; thread count alternated between three and four without an
upward trend. Accumulated CPU time increased by only 0.06 seconds over the full
interval.

The system assertion snapshot naturally changed as user-activity and the
display-on idle assertion timed out during the observation. No application-owned
assertion appeared, and `PreventSystemSleep` was `0` both before and after.

Task 7 idle-energy decision: **Pass**. The measured implementation behaves as an
event-driven HID listener with one-shot timers rather than a polling loop.

## Task 7 whole-phase safety decision

The full implementation review covered fail-open decoding, explicit real-sleep
opt-in, one-shot triggering and hysteresis, startup/wake cooldown, process
lifecycle, diagnostic-mode separation, persistence boundaries, power settings,
and documentation accuracy.

- Open P0 findings: 0
- Open P1 findings: 0
- Open P2 findings: 1
- Real sleep invoked: No

The P2 limitation is operational visibility: if a future explicit
`IOPMSleepSystem` request fails, the requester itself returns an error and never
retries, but the coordinator currently suppresses that error. This cannot create
a sleep loop and therefore does not invalidate the safety decision; Task 8 must
still observe whether the bounded real-sleep request actually succeeds.

Task 7 decision: **Pass**. Task 8 remains blocked until the user gives separate,
explicit approval for one foreground real-sleep acceptance cycle.

## Task 8 bounded real-sleep acceptance

The user explicitly approved one foreground real-sleep cycle after reviewing
the completed Task 6 and Task 7 evidence. No background service, login item, or
persistent power-setting change was introduced.

The release executable started with:

```text
auto-sleep config: mode=execute-sleep sleep-threshold=68 reopen-threshold=75 debounce=2 wake-cooldown=5
auto-sleep: rearmed
```

The lid was then moved below the calibrated sleep threshold and held longer
than the debounce period. The process emitted exactly one request sequence:

```text
auto-sleep: candidate-started
auto-sleep: triggered
auto-sleep: sleep-requested
```

macOS power-management evidence confirmed a real software sleep rather than
display dimming only:

```text
2026-07-26 16:28:30 +0800 Sleep
Entering Sleep state due to 'Software Sleep pid=17708'
```

The Mac remained asleep until the user pressed a keyboard key. macOS recorded:

```text
2026-07-26 16:30:22 +0800 Wake
Wake from Deep Idle ... trackpadkeyboard ... HID Activity
```

After wake, the same foreground process emitted:

```text
auto-sleep: cooldown
auto-sleep: rearmed
```

No second `sleep-requested` event occurred. The lid was kept above the reopen
threshold, and the foreground process was then stopped cleanly with `Ctrl+C`.

Task 8 acceptance results:

- Explicit user approval: Yes
- Foreground `--execute-sleep`: Yes
- Real software sleep: Pass
- Sleep request count: 1
- Keyboard/trackpad wake: Pass
- Wake cooldown observed: Pass
- Rearmed above `75`: Pass
- Immediate repeat sleep: No
- Persistent service installed: No
- Persistent power setting changed: No

The Task 7 P2 visibility limitation is closed for this bounded acceptance
scenario because both the process emitted `sleep-requested` and macOS independently
recorded `Software Sleep pid=17708`.

Task 8 decision: **Pass**.

## Angle-authoritative re-sleep acceptance

The user separately approved one bounded two-sleep foreground acceptance after
the angle-authoritative implementation had passed its Task 5 holistic review
with Open P0/P1/P2 = 0.

The release executable reported the effective policy:

```text
auto-sleep config: mode=execute-sleep sleep-threshold=68 reopen-threshold=75 debounce=2 startup-cooldown=5 wake-recovery=15
auto-sleep: startup-cooldown
auto-sleep: rearmed
```

The complete process-side transition sequence was:

```text
auto-sleep: candidate-started
auto-sleep: triggered
auto-sleep: sleep-requested
auto-sleep: wake-recovery
auto-sleep: recovery-resleep
auto-sleep: sleep-requested
auto-sleep: wake-recovery
auto-sleep: rearmed
```

Independent macOS power-management evidence recorded:

```text
2026-07-26 20:16:17 +0800 Sleep
Entering Sleep state due to 'Software Sleep pid=38595'

2026-07-26 20:16:31 +0800 Wake
Wake from Deep Idle ... trackpadkeyboard ...

2026-07-26 20:16:46 +0800 Sleep
Entering DarkWake state due to 'Software Sleep pid=38595'

2026-07-26 20:17:00 +0800 Wake
DarkWake to FullWake ... due to HID Activity
```

The second software sleep request occurred exactly fifteen seconds after the
first keyboard wake. macOS represented the second low-power transition as
`Entering DarkWake state` rather than a second full `Entering Sleep state`.
The user observed the expected second sleep behavior, and both the process log
and `pmset` attribute the transition to the same foreground process and software
sleep request.

After the second wake, the lid was opened to `>=75` within the recovery window.
The process emitted `rearmed`; no third `sleep-requested` event or later
software-sleep entry occurred before the foreground process was stopped.

Acceptance results:

- Explicit approval after Task 5: Yes
- First software sleep: Pass, full Sleep
- First keyboard wake while remaining below `75`: Pass
- Recovery delay: Pass, exactly 15 seconds
- Second software sleep request: Pass
- Second macOS state: DarkWake sleep transition, recorded limitation
- Second HID wake: Pass
- Open to `>=75` within recovery window: Pass
- Recovery cancellation and `rearmed`: Pass
- Third sleep request: None
- Sleep-request failure output: None
- Residual foreground process: None after stop
- Persistent service or power mutation: None

Angle-authoritative re-sleep decision: **Pass with macOS power-state note**.
The required user-visible and state-machine behavior is accepted. The second
transition's DarkWake representation remains hardware/OS-specific evidence and
must not be generalized as proof that every supported Mac will record two
identical full Sleep entries.

## Angle-authoritative re-sleep Task 5 review

The post-acceptance refinement split startup safety from wake recovery and made
fresh lid angle authoritative after a real wake. Effective runtime policy is:

```text
sleep-threshold=68
reopen-threshold=75
debounce=2
startup-cooldown=5
wake-recovery=15
```

Clean validation completed with 79 tests and zero failures, plus a passing
release build. Static review confirmed exactly three one-shot task slots, no
polling, no power assertion, no persistent service, and no automatic retry after
a failed `IOPMSleepSystem` call.

A bounded release dry-run hardware idle observation emitted only:

```text
auto-sleep: startup-cooldown
auto-sleep: rearmed
```

CPU samples remained at `0.0%`, accumulated CPU time reached `0:00.01`, and no
transition or log churn occurred. No real sleep was invoked during Task 5.

- Open P0: 0
- Open P1: 0
- Open P2: 0
- Task 5 decision: **Pass**

The user separately approved Task 6 two-sleep real acceptance after this review.

## Angle-authoritative recovery refinement

The post-acceptance implementation now uses this runtime policy:

```text
auto-sleep config: mode=dry-run sleep-threshold=68 reopen-threshold=75 debounce=2 startup-cooldown=5 wake-recovery=15
```

Current semantics:

- Startup below `75` remains disarmed and never sleeps immediately.
- Every real wake clears pre-sleep angle evidence.
- A fresh valid angle `<75` at the fifteen-second recovery deadline requests
  one re-sleep; `69...74` remains within the closed-cycle hysteresis band.
- A fresh `>=75` angle cancels recovery and rearms.
- Missing or invalid fresh recovery data emits
  `recovery-sensor-unavailable` and fails open.
- A failed `IOPMSleepSystem` request emits
  `sleep-request-failed error=...`, enters `disarmed`, and is not retried.

Automated integration coverage verifies dry-run recovery re-sleep, recovery
cancellation on reopen, and execute-mode failure visibility. The original Task 8
real-sleep evidence remains valid for the first sleep request, but it does not
claim the new two-sleep recovery path has been physically accepted. That bounded
hardware acceptance remains separately gated.
