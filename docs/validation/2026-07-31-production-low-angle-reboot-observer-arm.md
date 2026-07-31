# Production Low-angle Reboot Observer Arm — 2026-07-31

## Scope

This validation records Milestone 17 Task 7 Step 2 only. It prepared the one-shot reboot observer and
identity-bound reboot state. It did not reboot the Mac, run finish verification, rollback or push.

## Prepared production identity

```text
repository authority commit: 786f843879c9bdc84f55d2e2afdef211cbebd5a2
installed source commit: 7bf98ff6ceae710757b38b14efa00d42c34ca573
installed version: 7bf98ff6ceae
hardware: MacBookPro18,1 / Apple M1 Pro
hardware profile: m1-pro-0x8104-report-id-1-v1
boot epoch: 1785457249
prepared daemon PID: 99898
```

Before arming, production was enabled、loaded、single PID、monitoring-armed with complete matching
deployment acceptance, a closed crash circuit and `operational_baseline=pass`.

## Management command evidence

```text
verified deployment-acceptance stages=deployment-dry-run deployment-enabled-once deployment-recovery-resleep
wrote deployment-reboot-state boot-epoch=1785457249
armed deployment-reboot-start boot-epoch=1785457249 pid=99898 action=restart-mac-manually-and-remain-at-loginwindow
deployment_reboot_start_exit=0
```

## Managed artifact verification

```text
/Library/Application Support/MacBookLidMonitor/deployment-reboot.plist
  owner/group: root:wheel
  mode: 0600
  type: regular file
  link count: 1

/Library/Application Support/MacBookLidMonitor/reboot-observer.sh
  owner/group: root:wheel
  mode: 0700
  type: regular file
  link count: 1
  SHA-256: 653cf6ef43405556bbff6bbaf8ed1fa698ee475a58521b8031df3ef2d9d1e89f

/Library/LaunchDaemons/com.crazydennies.macbook-lid-monitor.reboot-observer.plist
  owner/group: root:wheel
  mode: 0644
  type: regular file
  link count: 1
  SHA-256: fd53298736e2b6c10845539628dcd00a3a11effb2f8d74e98d6c15029143e6a4
```

## One-shot behavior

The observer LaunchDaemon has `RunAtLoad=true` and no `KeepAlive`. It ran once on the current boot,
wrote same-boot initial evidence and exited normally:

```text
state: not running
runs: 1
last exit code: 0
evidence boot epoch: 1785457249
evidence PID: 99898
evidence console user: water
```

This is a preparation check, not the final pre-login proof. After the separately approved manual reboot,
the observer must run again and replace the evidence with a changed boot epoch, a new daemon PID and an
allowed pre-login console user. Final verification will reject unchanged boot/PID evidence.

## Final armed state

```text
production mode: enabled
production job: loaded
production PID: 99898
production baseline: pass
observer: loaded / not running / armed for next boot
reboot: false
finish: false
rollback: false
push: false
```

Task 7 Step 3 remains separately approval-gated.
