# Production recovery-resleep acceptance — identity 7bf98ff6ceae

日期：2026-07-31

## Installed identity

```text
source commit: 7bf98ff6ceae710757b38b14efa00d42c34ca573
version: 7bf98ff6ceae
binary SHA-256: 6b30459a2168d0f409cc45e4cd152a3b535a85566347e7bc273b58109e2c6ee3
hardware model: MacBookPro18,1
chip: Apple M1 Pro
profile: m1-pro-0x8104-report-id-1-v1
```

Dry-run and enabled-once acceptance already matched this identity before the recovery-only retest.

## First bounded attempt

The initial request occurred at `16:26:05`. The display became interactive at `16:26:12`, but the power
transaction did not deliver the daemon's formal wake callback until `16:26:35`. `pmset` recorded:

```text
Delays to Sleep notifications: [LINE timed out(30000 ms)]
```

The user waited about 20 seconds from display-on, then reopened the lid to continue operating. Because
the 15-second recovery interval starts at IOKit `systemHasPoweredOn`, not display-on, the timer had not
finished. The command was manually stopped. Cleanup produced disabled／job absent／zero PID, crash count
0, and no recovery-resleep acceptance record.

## Accepted recovery-only retest

The lid was held at approximately 45–55 degrees and left unchanged for at least 60 seconds after the
first display wake. Production PID `64966` emitted:

```text
08:59:03 sleep-request-attempted
08:59:03 sleep-requested
08:59:33 first wake evidence
08:59:49 recovery-resleep
08:59:49 sleep-request-attempted
08:59:49 sleep-requested
09:00:17 second wake evidence
09:00:17 monitoring-armed after intentional reopen
```

The bounded command reported:

```text
verified task=13 scope=recovery-resleep attempt-count=2 return-count=2 recovery-count=1 wake-count=2 pid-stable=true
accepted task=13 scope=recovery-resleep final-mode=disabled
recorded deployment-acceptance stage=deployment-recovery-resleep result=pass
```

## Timing interpretation

The product contract remains:

```text
IOKit systemHasPoweredOn
→ wait 15 seconds
→ if the latest fresh lid angle is still <75, request sleep again
```

Display-off／display-on are not the timer authority. A delayed external power-notification client can make
the user-visible wait longer than 15 seconds. This accepted retest required no runtime amendment.

## Final verification

```text
deployment acceptance: dry-run + enabled-once + recovery-resleep complete
mode: disabled
job: loaded, not running
process-count: 0
crash count: 0
circuit: closed
runActive: false
activate: not executed
reboot: not executed
push: not executed
```

Task 6 recovery-resleep acceptance is complete for identity `7bf98ff6ceae`.
