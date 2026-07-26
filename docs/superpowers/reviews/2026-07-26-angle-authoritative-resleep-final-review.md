# Angle-Authoritative Re-Sleep Whole-Phase Final Review — 2026-07-26

## Scope

This review covers the angle-authoritative re-sleep refinement through Tasks
1–5. It includes the policy/CLI split, state machine, coordinator scheduling,
sleep-request failure visibility, integration coverage, documentation authority,
clean validation, static operational-safety review, and bounded hardware dry-run
idle observation. It does not claim real re-sleep acceptance; that remains Task 6.

## Validation evidence

- `swift package clean`: completed.
- `swift test`: 79 tests, 0 failures.
- `swift build -c release`: passed.
- `git diff --check`: passed.
- Active runtime defaults: `68 / 75 / 2 / 5 / 15`.
- Active CLI contract: `--debounce`, `--startup-cooldown`, `--wake-recovery`.
- Obsolete `--wake-cooldown` is rejected with migration guidance.

## State and scheduling review

The implementation has separate startup and wake semantics:

- startup waits five seconds and never sleeps an already-closed machine;
- every real wake creates one fresh fifteen-second recovery window;
- fresh angle `<75` at the recovery deadline requests sleep once;
- fresh angle `>=75` cancels recovery and rearms;
- absent or invalid fresh recovery data fails open into `disarmed`;
- a sleep request failure is emitted and transitions to `disarmed` without retry.

The coordinator owns exactly three independent one-shot tasks:

```text
closeDebounceTask
startupCooldownTask
wakeRecoveryTask
```

Each task is cancelled on replacement and all three are cancelled on stop. No
repeating timer, sensor polling loop, or API retry loop is present.

## Operational-safety review

Static inspection found no:

- power assertion created by the application;
- `pmset` or persistent power-setting mutation;
- LaunchAgent, login item, daemon, or background installation;
- HID output/feature-report write;
- per-report production logging;
- construction of a real sleep requester from diagnostic modes.

Sleep failure visibility is now explicit:

```text
auto-sleep: sleep-request-failed error=<stable-description>
```

The prior Task 7 P2 concerning suppressed `IOPMSleepSystem` failures is closed.

## Hardware dry-run idle observation

The release dry-run started with:

```text
auto-sleep config: mode=dry-run sleep-threshold=68 reopen-threshold=75 debounce=2 startup-cooldown=5 wake-recovery=15
auto-sleep: startup-cooldown
auto-sleep: rearmed
```

During the bounded stationary observation:

- sampled CPU remained `0.0%`;
- accumulated CPU time reached only `0:00.01`;
- RSS stabilized near 11.9 MiB;
- no candidate, trigger, `would-sleep`, recovery, or failure churn appeared;
- no real sleep was requested.

## Findings and disposition

### P0

None open.

### P1

None open.

### P2

None open.

## Final decision

**Task 5 passes.** The implementation is event-driven, angle-authoritative only
when fresh valid data exists, bounded by one-shot wake recovery, fail-open on
sensor uncertainty, and explicit on system-sleep request failure.

The feature is eligible for the separately approved foreground Task 6 real
two-sleep acceptance. Eligibility is not itself evidence that real re-sleep has
already occurred.

## Post-review Task 6 real acceptance addendum

The user subsequently gave explicit approval for the separately gated two-sleep
acceptance. The foreground process emitted exactly two `sleep-requested` events,
with `recovery-resleep` between them. The second request occurred fifteen seconds
after the first keyboard wake. Opening to `>=75` after the second wake emitted
`rearmed` and cancelled any third request.

macOS independently recorded the first request as a full Software Sleep and the
second as `Entering DarkWake state due to 'Software Sleep'`. This distinction is
retained as a platform evidence note rather than normalized away.

Task 6 disposition:

- Open P0: 0
- Open P1: 0
- Open P2: 0
- Unexpected third request: 0
- Recovery cancellation failure: 0
- Functional acceptance: Pass
- Power-state evidence: Pass with DarkWake note

The complete angle-authoritative re-sleep phase is accepted for the current
foreground-only scope. This does not approve a LaunchAgent or persistent service.
