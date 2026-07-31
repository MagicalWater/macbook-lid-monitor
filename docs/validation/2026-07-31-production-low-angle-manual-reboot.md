# Production Low-angle Manual Reboot Runtime Validation — 2026-07-31

## Scope

This document records Milestone 17 Task 7 Step 3 only: the user manually rebooted while keeping the lid
at approximately 45–55 degrees, remained at loginwindow, observed the startup-triggered sleep, reopened
above 75 degrees, allowed the observer to run, then logged in. It does not run finish verification or
remove temporary observer artifacts.

## Prepared authority

```text
installed version: 7bf98ff6ceae
installed source commit: 7bf98ff6ceae710757b38b14efa00d42c34ca573
prepared boot epoch: 1785457249
prepared PID: 99898
production before reboot: enabled / loaded / single PID
observer: root-owned, one-shot, armed
```

## Changed boot and production identity

```text
current boot epoch: 1785491605
boot local time: 2026-07-31 17:53:25 +0800
boot changed: true
current PID: 281
PID changed: true
mode: enabled
job: loaded
process count: 1
crash count: 0
circuit open: false
runActive: true
```

## Low-angle startup runtime evidence

```text
2026-07-31T09:53:39Z started pid=281 mode=enabled
2026-07-31T09:53:41Z startup-cooldown
2026-07-31T09:53:41Z monitoring-disarmed
2026-07-31T09:53:47Z startup-closed-candidate
2026-07-31T09:53:48Z startup-closed-debounce-elapsed
2026-07-31T09:53:48Z sleep-request-attempted
2026-07-31T09:53:48Z sleep-requested
2026-07-31T09:54:06Z monitoring-armed
```

This proves the new boot daemon classified a fresh low angle after startup cooldown, completed the
bounded debounce, and requested real sleep exactly once. The same PID rearmed after the lid was opened.

## Independent macOS power evidence

`pmset -g log` recorded:

```text
2026-07-31 17:54:05 +0800 Wake from Deep Idle due to trackpadkeyboard / HID Activity
2026-07-31 17:54:05 +0800 Display is turned on
```

This is consistent with the user reopening and waking the Mac after the startup sleep.

## Observer state after reboot

```text
observer job: loaded / not running
runs: 1
last exit code: 0
observer evidence owner/mode: root:wheel 0600
observer evidence mtime: 2026-07-31 17:54:07 +0800
```

The protected observer plist was updated after the new boot. Task 7 Step 4 must still run the root
verifier to prove `ConsoleUser` was a pre-login identity, boot epoch and installed identity match, the
new PID differs from the prepared PID, and health is bound to that PID. Step 4 also owns temporary
observer cleanup and final operational baseline.

## Decision

Task 7 Step 3 manual reboot and runtime observation pass. No finish、cleanup、rollback or push occurred.
