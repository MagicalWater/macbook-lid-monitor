# Production Deployment Dry-run Acceptance — 2026-07-28

## Installed identity

```text
source commit: 412fcc207b447d42ffdf58e9e35bd545d1b04ad4
version: 412fcc207b44
hardware model: MacBookPro18,1
chip: Apple M1 Pro
profile: m1-pro-0x8104-report-id-1-v1
```

## Logged-in dry-run sensor path

The installed daemon ran as PID `51569` in dry-run and emitted:

```text
candidate-started
debounce-elapsed
sleep-request-attempted
would-sleep
```

Counts were exactly one attempted request and one `would-sleep`. The command returned the system to
loaded/disabled/zero PID and recorded `deployment-dry-run=pass` against the installed identity.

## Sleep/wake continuity

The corrected stable acceptance command ran the installed daemon as PID `14049`, invoked the
separately approved bounded `/usr/bin/pmset sleepnow`, and observed:

```text
monitoring-armed
monitoring-disarmed
monitoring-armed
```

PID remained `14049` across sleep/wake. Cleanup then stopped dry-run, restored disabled, and left
zero resident PID. This sleep was orchestration-driven, not sensor-driven real-sleep authority.

## Reopen/rearm evidence

A bounded installed dry-run run used PID `8576`. It did not reproduce another `would-sleep` before
timeout, but it observed the installed daemon move from `monitoring-disarmed` to
`monitoring-armed` after reopening. This is combined with the earlier installed close/debounce/
`would-sleep` evidence. No same-cycle production claim is made; automated integration coverage
continues to prove that state-machine sequence.

## Findings and fixes

1. Valid first-stage acceptance was mislabeled `corrupt`; observability now reports `partial`.
2. The first privileged sleep/wake wrapper omitted manager-local functions; a stable installed-only
   command now reuses reviewed orchestration without prepare/upgrade.
3. Same-cycle reopen capture timed out; accepted as split installed evidence with explicit
   disposition and no additional manual repetition.

## Verification

```text
focused partial-state regression: passed
focused stable sleep/wake regression: passed
focused stable reopen regression: passed
management suite after stable sleep/wake: 81 tests, 0 failures
final full suite: 267 tests, 0 failures
bash syntax: passed
shellcheck -x: passed
git diff --check: passed
```

## Final live state

```text
installed=true
mode=disabled
job=loaded, not running
process-count=0
last-exit-code=0
acceptance-state=partial
lease-state=missing
crash-state=closed
```
