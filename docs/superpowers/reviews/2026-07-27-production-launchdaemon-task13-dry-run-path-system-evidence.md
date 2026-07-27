# Task 13 Dry-run Path — Real System Evidence

Date: 2026-07-27

## Operator action

The operator started `accept-task13-dry-run-path`, began from a clearly open lid position, then moved the lid below the configured 68-degree threshold and held it for at least two seconds.

The machine has a failed normal lid-open wake sensor. That hardware condition does not invalidate this dry-run acceptance because no system sleep or wake action is part of this scope.

## Accepted evidence

The management command reported:

```text
armed task=13 scope=dry-run-path action=move-lid-below-68-degrees-and-hold-2-seconds-within-180-seconds
verified task=13 scope=dry-run-path candidate=true debounce=true attempt-count=1 would-sleep-count=1
accepted task=13 scope=dry-run-path final-mode=disabled label=com.crazydennies.macbook-lid-monitor
```

This proves the real production daemon completed the following path exactly once:

```text
HID lid-angle report
→ monitoring armed
→ closing candidate
→ close debounce elapsed
→ sleep request attempted
→ dry-run would-sleep
```

No real sleep authority was enabled in this acceptance.

## Independent final-state review

- Installed version: `8a3f2799044d`.
- Production mode: disabled.
- System job: loaded, not running.
- Last exit code: zero.
- Resident production PID: absent.
- Production stderr log: zero bytes at command completion.

The command's immediate diagnostics temporarily reported `process-count=1` after disabled bootstrap. An independent follow-up check confirmed this was the known short launchd startup/exit window and the stable final process count was zero.

## Disposition

**Task 13 dry-run sensor-to-request path approved and complete.**

The earlier enabled acceptance failure is now narrowed to the real IOKit request/return and sleep/wake timing boundary. It is not caused by missing lid-angle input, failure to arm, failure to create a candidate, or failure of the two-second debounce.
