# Lid-Angle Auto-Sleep Whole-Phase Final Review — 2026-07-26

## Review scope

This review covers the complete foreground auto-sleep implementation through
Task 7. It includes source, tests, Task 6 hardware dry-run evidence, the Task 7
901-second idle observation, and documentation. It does not approve or claim a
successful real sleep; that remains a separately gated Task 8 action.

## Evidence reviewed

- Calibrated runtime defaults: sleep `68`, reopen `75`, debounce `2` seconds,
  wake/startup cooldown `5` seconds.
- Five hardware dry-run cycles with exactly one `would-sleep` per close.
- Cancellation before debounce with no trigger.
- Low-angle startup remaining disarmed until an explicit reopen.
- Release idle observation: 31 samples over 901 seconds.
- Full automated suite and release build.

## Static energy and logging review

### Event source

Angle input is delivered by `IOHIDDeviceRegisterInputReportCallback` and a
Core Foundation run loop. Auto-sleep mode does not poll the sensor.

### Timers

Only one-shot `DispatchWorkItem` scheduling is used:

- one startup/wake cooldown task;
- one close debounce task while a candidate exists.

Both are cancelled on stop, wake, cancellation, or replacement. There is no
repeating timer.

### Logging

Auto-sleep mode prints startup metadata, the effective policy, and state or
operational transitions. It does not print every HID report. During the formal
stationary observation, the only transition was `rearmed`.

### Power assertions and persistence

The implementation contains no `IOPMAssertionCreate*` call, `caffeinate`,
`pmset`, LaunchAgent, login item, daemon, or persistent power-setting mutation.
The only power-management operation is `IOPMSleepSystem`, constructed solely
for explicit execute mode.

## Operational safety review

### Fail-open behavior — Pass

- Unsupported, malformed, non-integral, or out-of-range reports cannot request
  sleep.
- Invalid data cancels an active candidate and returns to open state.
- Starting or waking at a low angle remains disarmed after cooldown.
- A reopen at or above `75` is required before a later close can trigger.

### Real-sleep opt-in gate — Pass

- `--auto-sleep` without an execution mode is rejected.
- `--execute-sleep` without `--auto-sleep` is rejected.
- Dry-run and execute modes conflict and cannot be selected together.
- Diagnostic `--watch` and `--list` do not construct a sleep requester.
- The helper invokes only `--auto-sleep --dry-run` and does not duplicate
  threshold values.

### One-shot trigger and hysteresis — Pass

- A close candidate starts only at or below `68`.
- It must remain closed through the two-second debounce.
- The triggered state requests sleep once and remains latched.
- Values from `69` through `74` do not rearm.
- Rearming requires a value at or above `75`.

Task 6 supplied five successful physical cycles with no duplicate trigger.

### Startup and wake cooldown — Pass

The coordinator begins in cooldown and subscribes to
`NSWorkspace.didWakeNotification`. On wake it cancels any debounce, clears the
latest angle, returns to cooldown, and schedules a new one-shot cooldown. The
hardware low-angle startup test remained disarmed until reopen.

### Start/stop lifecycle and concurrency — Pass

- State-machine work is serialized on a dedicated dispatch queue.
- Start and stop are idempotent.
- Stop cancels both one-shot tasks, stops wake observation, and stops HID input.
- SIGINT/SIGTERM use a self-pipe and run-loop shutdown rather than unsafe
  high-level work inside the signal handler.
- The formal measurement process exited cleanly with no residual process.

### Diagnostic regression — Pass

List/watch CLI paths remain separate from auto-sleep composition. The automated
suite covers diagnostic parsing, candidate ranking, HID streaming, decoders,
output formatting, and auto-sleep integration.

### Documentation accuracy — Pass

README and validation documents identify dry-run as the required first mode,
state the calibrated policy authority, distinguish sensor values from physical
degrees, and state that no persistent service or power mutation is installed.

## Idle observation result

Formal interval: 2026-07-26 16:03:24 +0800 to 16:18:25 +0800.

```text
samples=31
duration_s=901
cpu_avg_pct=0.0000
cpu_max_pct=0.0000
rss_min_kb=11136
rss_max_kb=11936
threads_min=3
threads_max=4
cpu_time_start=0:00.01
cpu_time_end=0:00.07
transition_lines=1
transitions=auto-sleep: rearmed
```

Decision: no sustained CPU activity, no periodic log churn, no application
power assertion, and no evidence of a periodic wakeup loop.

## Findings

### P0

None open.

### P1

None open.

### P2 — Execute-mode request failure is not surfaced by the coordinator

`MacOSSleepRequester` propagates a failed `IOPMSleepSystem` call and does not
retry, but `LidSleepCoordinator` currently uses `try?` when invoking the
requester. The state remains triggered until reopen, so failure cannot cause
repeated requests or an unsafe loop. The cost is reduced operational
visibility. This is not a Task 7 safety blocker, but Task 8 must verify that the
single bounded request actually sleeps the machine before acceptance is
claimed.

## Verification gate

The final gate requires:

```text
swift package clean
swift test
swift build -c release
git diff --check
Open P0 = 0
Open P1 = 0
```

## Final decision

**Task 7 passes.** The implementation is event-driven, bounded, fail-open, and
does not mutate persistent power configuration. It is technically eligible for
one explicitly approved foreground Task 8 real-sleep acceptance cycle.

Eligibility is not approval. No real-sleep command may be run until the user
separately gives explicit consent after reviewing this result.
