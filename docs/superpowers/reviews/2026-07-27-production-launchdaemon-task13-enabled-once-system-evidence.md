# Task 13 Enabled-Once System Evidence

Date: 2026-07-27

## Scope

One real sensor-driven production sleep cycle in `enabled` mode. Recovery resleep was excluded.

## Operator action

- Started `accept-task13-enabled-once` from the Task 13 worktree.
- Began from a clearly open lid angle, moved below the configured threshold, and held long enough
  for the close debounce.
- After sleep, moved the lid to the usable open position and woke the Mac with the keyboard because
  the machine's normal open-lid wake sensor is damaged.

## Accepted evidence

```text
armed task=13 scope=enabled-once pid=74188 action=close-lid-within-180-seconds
verified task=13 scope=enabled-once attempt-count=1 return-count=1 wake-evidence=true pid-stable=true
accepted task=13 scope=enabled-once final-mode=disabled label=com.crazydennies.macbook-lid-monitor
```

- Exactly one pre-call `sleep-request-attempted` event was observed.
- The IOKit request returned exactly once after the cycle.
- Wake-recovery evidence was observed.
- The production daemon PID remained `74188` across sleep and wake.
- Diagnostics reported loaded, disabled, `process-count=0`, and an empty production error log.
- Production logs retained mode `0600`.

## Independent post-acceptance review

- Installed mode: `disabled`.
- System launchd job: loaded, not running.
- Last exit code: `0`.
- Resident production PID: none.
- Installed version: `63caafc60230`.

## Disposition

The first real enabled sensor-driven sleep acceptance is complete. Recovery resleep and injected
failure acceptance remain separately gated Task 13 work.
