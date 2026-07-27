# Milestone 16 Task 16 — Disabled production installation

## Approved release

```text
release-commit=412fcc207b447d42ffdf58e9e35bd545d1b04ad4
package-version=412fcc207b44
hardware-model=MacBookPro18,1
hardware-chip=Apple M1 Pro
hardware-profile=m1-pro-0x8104-report-id-1-v1
```

## Approval and mutation boundary

The user explicitly approved installing the reviewed release into `/Library` and bootstrapping the
system-domain LaunchDaemon while keeping the managed configuration disabled. No dry-run, real sleep,
persistent activation, or reboot was authorized or performed.

## Pre-install inventory

```text
managed binary=absent
LaunchDaemon plist=absent
support directory=absent
log directory=absent
system job=absent
production daemon process=absent
foreground real-sleep process=absent
```

The historical user-owned file
`/private/tmp/macbook-lid-monitor-task15-final-test.log` was observed and deliberately preserved
because no separate deletion approval was given.

## Installed artifacts

```text
/Library/PrivilegedHelperTools/macbook-lid-monitor-daemon root:wheel 0755 links=1
/Library/LaunchDaemons/com.crazydennies.macbook-lid-monitor.plist root:wheel 0644 links=1
/Library/Application Support/MacBookLidMonitor root:wheel 0755
/Library/Application Support/MacBookLidMonitor/config.plist root:wheel 0644 links=1
/Library/Application Support/MacBookLidMonitor/manifest.plist root:wheel 0644 links=1
/Library/Logs/MacBookLidMonitor root:wheel 0755
/Library/Logs/MacBookLidMonitor/production.log root:wheel 0644 links=1
/Library/Logs/MacBookLidMonitor/production-error.log root:wheel 0644 links=1
```

The installed binary, launchd plist, config, and manifest SHA-256 values exactly matched the
prepared package. The installed manifest `SourceCommit` equals the formal release commit.

## Disabled-state acceptance

```text
installed=true
version=412fcc207b44
source_commit=412fcc207b447d42ffdf58e9e35bd545d1b04ad4
integrity=valid
mode=disabled
job=loaded
launchd-state=not-running
launchd-last-exit-code=0
process-count=0
acceptance-state=missing
reboot-state=missing
lease-state=missing
gui-duplicate-job=absent
```

## Health and crash state

The root-only health snapshot was readable, schema-valid, and identity-bound:

```text
schemaVersion=1
state=disabled
mode=disabled
pid=40699
profileID=m1-pro-0x8104-report-id-1-v1
version=412fcc207b44
```

The status interface reports this snapshot as `stale`, which is expected after a disabled daemon
exits and stops refreshing health. It is not corrupt. The crash circuit is closed:

```text
circuitOpen=false
unexpectedExitTimes=[]
runActive=false
```

## Immediate review

- Installed identity and package checksums match: pass.
- All managed artifacts have root-owned fixed metadata and single-link regular files: pass.
- System job is loaded but not running in disabled mode: pass.
- No resident production daemon or foreground real-sleep authority exists: pass.
- Deployment acceptance, reboot state, lease, and lifecycle guard are absent: pass.
- Root-only health snapshot is valid disabled evidence; stale is expected: pass.
- Crash budget is valid and closed: pass.
- Historical unrelated temp log was preserved: pass.
- No dry-run, sleep, activation, reboot, rollback, or uninstall occurred: pass.

## Final state

```text
package=installed
job=loaded
mode=disabled
process-count=0
daemon=not-running
real-sleep-authority=absent
```
