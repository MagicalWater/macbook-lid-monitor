# Task 13 Injected Sleep-Request Failure — Real-System Evidence

## Scope

Validate the production daemon's fail-open behavior when the sleep requester fails after a real
sensor-driven close candidate and debounce, without allowing a real sleep request to reach IOKit.

## Operator result

The operator ran:

```bash
sudo ./scripts/manage-production-daemon.sh accept-task13-injected-failure
```

The command upgraded the installed package to version `20c369b823d1`, enabled the daemon with the
root-owned injected-failure selector, and armed one real lid-angle cycle.

Observed acceptance evidence:

```text
verified task=13 scope=injected-failure attempt-count=1 failure-count=1 disarmed=true retry-count=0 pid-stable=true no-real-sleep=true
accepted task=13 scope=injected-failure final-mode=disabled
```

The Mac did not enter sleep.

## Verified properties

- Exactly one `sleep-request-attempted` event was emitted.
- Exactly one injected failure was recorded.
- The state machine transitioned to disarmed.
- No retry occurred during the observation window.
- The production daemon PID remained stable during the acceptance.
- The injection selector was removed after the acceptance.
- The installed mode returned to disabled.
- The production error log remained empty.

## Independent post-command review

Independent inspection after the command confirmed:

```text
mode=disabled
job=loaded, not running
last-exit-code=0
resident-pid=absent
installed-version=20c369b823d1
MLM_SLEEP_OPERATION=absent
```

## Disposition

**Accepted.** Task 13 now has real-system evidence for the dry-run path, first enabled sleep,
recovery resleep, and injected requester failure. Task 13 is complete.
