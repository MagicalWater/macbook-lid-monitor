# Production Persistent Activation — 2026-07-31

## Scope

This validation records Milestone 17 Task 7 Step 1 only. It intentionally leaves the production
LaunchDaemon enabled after verifying the exact installed identity and its complete deployment acceptance.
It does not arm the reboot observer, restart the Mac, execute reboot finish, roll back, or push.

## Repository and installed identity

```text
repository documentation head at activation: 5d0769556cbf0a49800c1af9b740cb398a3c7353
installed version: 7bf98ff6ceae
installed source commit: 7bf98ff6ceae710757b38b14efa00d42c34ca573
hardware model: MacBookPro18,1
chip: Apple M1 Pro
profile: m1-pro-0x8104-report-id-1-v1
```

The activation preflight verified matching acceptance for:

```text
deployment-dry-run
deployment-enabled-once
deployment-recovery-resleep
```

Starting state was loaded／disabled／zero PID with crash count 0, circuit closed and `runActive=false`.

## Activation command evidence

```text
verified deployment-acceptance stages=deployment-dry-run deployment-enabled-once deployment-recovery-resleep
booted-out label=com.crazydennies.macbook-lid-monitor
bootstrapped label=com.crazydennies.macbook-lid-monitor
activated deployment mode=enabled label=com.crazydennies.macbook-lid-monitor
activate_command=pass
baseline_wait=pass probes=5
operational_baseline=pass pid=99898
```

Root diagnostics:

```text
installed=true
version=7bf98ff6ceae
source_commit=7bf98ff6ceae710757b38b14efa00d42c34ca573
mode=enabled
job=loaded
process_count=1
integrity=valid
acceptance_state=complete
lease_state=present
health_state=monitoring-armed
health_mode=enabled
health_pid=99898
crash_state=closed
crash_count=0
crash_run_active=true
```

## Independent post-command evidence

Current-PID lifecycle:

```text
2026-07-31T09:29:13Z started pid=99898 mode=enabled
2026-07-31T09:29:14Z startup-cooldown
2026-07-31T09:29:14Z monitoring-disarmed
2026-07-31T09:29:19Z monitoring-armed
```

Fresh read-only verification confirmed enabled／loaded／single PID `99898`, crash count 0, circuit closed,
`runActive=true`, and root-owned `0600` health and acceptance files. Deployment reboot state, reboot
evidence, reboot observer executable, and reboot observer LaunchDaemon plist were all absent.

## Decision

Task 7 Step 1 persistent activation passes. Production intentionally remains enabled and running while
Step 2 low-angle reboot observer preparation awaits separate approval. No reboot, rollback or push occurred.
