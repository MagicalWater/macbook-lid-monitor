# Production Persistent Activation Acceptance — 2026-07-28

## Scope and approval

Task 20 was separately approved after dry-run, enabled-once, and recovery-resleep acceptance had
all passed against the exact installed identity. Unlike bounded Tasks 17–19, this operation
intentionally leaves the LaunchDaemon enabled and capable of sensor-driven real sleep after the
management command exits.

## Installed and acceptance identity

```text
source commit: 0885d54dbf133fdd8620d4a38379a8ed64819430
version: 0885d54dbf13
hardware model: MacBookPro18,1
chip: Apple M1 Pro
profile: m1-pro-0x8104-report-id-1-v1
acceptance stages:
  deployment-dry-run=pass
  deployment-enabled-once=pass
  deployment-recovery-resleep=pass
acceptance state: complete
```

The activation command first emitted:

```text
verified deployment-acceptance stages=deployment-dry-run deployment-enabled-once deployment-recovery-resleep
```

It then performed the evidence-bound mode transition and bootstrap:

```text
booted-out label=com.crazydennies.macbook-lid-monitor
bootstrapped label=com.crazydennies.macbook-lid-monitor
activated deployment mode=enabled label=com.crazydennies.macbook-lid-monitor
```

The command exited successfully. The fail-safe bootstrap-failure branch was not entered.

## Live enabled evidence

```text
mode: enabled
launchd state: running
process count: 1
daemon PID: 33458
last exit code: never exited
monitoring-armed: observed
crash state: closed
crash run active: true
```

Current-PID lifecycle evidence:

```text
timestamp=2026-07-28T03:44:27Z event=started pid=33458 mode=enabled profile=m1-pro-0x8104-report-id-1-v1
timestamp=2026-07-28T03:44:27Z event=transition pid=33458 name=startup-cooldown
timestamp=2026-07-28T03:44:27Z event=health-changed pid=33458 state=monitoring-disarmed
timestamp=2026-07-28T03:44:33Z event=transition pid=33458 name=monitoring-armed
timestamp=2026-07-28T03:44:33Z event=state-changed pid=33458 state=monitoring-armed
```

Root diagnostics reported:

```text
installed=true
version=0885d54dbf13
source_commit=0885d54dbf133fdd8620d4a38379a8ed64819430
mode=enabled
job=loaded
process_count=1
integrity=valid
hardware_model=MacBookPro18,1
hardware_chip=Apple M1 Pro
acceptance_state=complete
lease_state=present
health_state=monitoring-armed
health_mode=enabled
health_pid=33458
crash_state=closed
crash_count=0
crash_run_active=true
```

Strict baseline verification returned:

```text
operational_baseline=pass pid=33458
```

## Managed authority

```text
path: /Library/Application Support/MacBookLidMonitor/sleep-authority.lock
owner: root
group: wheel
mode: 0600
type: regular file
link count: 1
size: 0
```

## Review disposition

- Complete matching acceptance was required before activation.
- Exactly one resident daemon is running.
- Runtime health is fresh, enabled, armed, and PID-bound.
- Installed integrity and target hardware identity are valid.
- The crash circuit is closed.
- Persistent enabled mode is intentional and is not cleaned back to disabled.
- No reboot or push occurred.

Task 20 is accepted. Task 21 remains open and separately approval-gated. The production daemon must
remain enabled/running while awaiting enabled reboot and pre-login acceptance.
