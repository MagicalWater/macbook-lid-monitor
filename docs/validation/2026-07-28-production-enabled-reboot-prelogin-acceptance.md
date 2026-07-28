# Production Enabled Reboot and Pre-login Acceptance

Date: 2026-07-28

## Identity and approval

- Installed source commit: `0885d54dbf133fdd8620d4a38379a8ed64819430`
- Hardware: `MacBookPro18,1`, `Apple M1 Pro`
- Profile: `m1-pro-0x8104-report-id-1-v1`
- Task 21 reboot preparation was explicitly approved.

## Reboot proof

```text
start boot epoch=1785132458
pre-reboot pid=33458
current boot epoch=1785226628
post-reboot pid=283
boot-changed=true
mode=enabled
job=loaded/running
process-count=1
```

## Pre-login and baseline proof

```text
verified reboot-observer pre-login=true pid=283 boot-epoch=1785226628
operational_baseline=pass pid=283
accepted deployment-reboot-finish boot-changed=true pre-login=true mode=enabled pid=283
```

The new daemon reached `monitoring-armed` at `2026-07-28T08:17:31Z` on the exact production profile.

## Cleanup and final state

All temporary reboot state, observer evidence, observer executable, observer plist, and observer
launchd job were removed. The managed package, config, manifest, acceptance, health, logs, lease,
and production LaunchDaemon remain installed.

```text
package=installed
job=loaded
mode=enabled
process-count=1
daemon=running
boot-auto-start=verified
pre-login=verified
single-authority=verified
```
