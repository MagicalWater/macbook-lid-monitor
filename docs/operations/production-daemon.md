# Production daemon operator runbook

This runbook is the supported operating interface for the system-domain MacBook Lid Monitor daemon.
Run management commands from the repository root. Commands that mutate `/Library` or launchd require
an interactive `sudo`; the script never reads or stores a password.

## Safety model

- `install`, `upgrade`, `rollback`, `disable`, and bounded deployment acceptance force or finish in
  `disabled` unless the command is the explicit evidence-gated `activate` command.
- `status`, `diagnostics`, `rotate-logs`, and `operational-baseline` are read-only and leave the
  current mode unchanged. When the daemon is already activated, these commands **leaves enabled**.
- `disable`, `upgrade`, `rollback`, and maintenance failure paths **forces disabled**.
- There is no unrestricted enable dispatcher. Persistent real-sleep authority is available only
  through complete deployment evidence followed by `activate`.

## Routine checks

```bash
sudo ./scripts/manage-production-daemon.sh status
sudo ./scripts/manage-production-daemon.sh diagnostics
sudo ./scripts/manage-production-daemon.sh operational-baseline
```

Expected healthy activated state includes `mode=enabled`, `job=loaded`, `process-count=1`, fresh
monitoring health matching that PID, valid installed integrity, and complete matching acceptance.
Missing state is reported as `unavailable`; malformed, unsafe, stale, or identity-mismatched state
is rejected rather than guessed.

## Disable and emergency stop

Normal safe disable:

```bash
sudo ./scripts/manage-production-daemon.sh disable
sudo ./scripts/manage-production-daemon.sh status
```

Expected final state is `mode=disabled`; a loaded disabled job must have zero resident daemon PID.

For **emergency bootout** when the job must be removed from launchd immediately:

```bash
sudo ./scripts/manage-production-daemon.sh disable
sudo ./scripts/manage-production-daemon.sh bootout
sudo ./scripts/manage-production-daemon.sh status
```

Expected state is disabled, job absent, and process count zero. Bootout does not grant authority and
does not replace integrity repair or uninstall.

## Crash circuit recovery

For **circuit-open recovery**, first prove the installed set is valid, mode is disabled, and no
daemon process is resident. Then reset only the crash budget:

```bash
sudo ./scripts/manage-production-daemon.sh status
sudo ./scripts/manage-production-daemon.sh disable
sudo ./scripts/manage-production-daemon.sh bootout
sudo ./scripts/manage-production-daemon.sh reset-crash-budget
sudo ./scripts/manage-production-daemon.sh bootstrap
sudo ./scripts/manage-production-daemon.sh status
```

The reset command refuses enabled mode, a resident daemon, unsafe metadata, and symlink state.

## Log rotation

```bash
sudo ./scripts/manage-production-daemon.sh rotate-logs
sudo ./scripts/manage-production-daemon.sh diagnostics
```

Rotation preserves the active writer inode, snapshots logs only above 1 MiB, and keeps at most three
generations. Unsafe generation paths are rejected before mutation.

## Upgrade

Prepare and verify the candidate as the logged-in repository user, then upgrade as root:

```bash
./scripts/manage-production-daemon.sh prepare
./scripts/manage-production-daemon.sh verify
sudo ./scripts/manage-production-daemon.sh upgrade
sudo ./scripts/manage-production-daemon.sh status
```

Upgrade enters disabled, booted-out, nonresident maintenance state. A changed payload creates one
rollback slot, activates the candidate disabled, invalidates old acceptance, and finishes disabled.
Repository-only evidence changes with identical installed payload identity are a no-op and preserve
matching acceptance.

## Rollback

```bash
sudo ./scripts/manage-production-daemon.sh rollback
sudo ./scripts/manage-production-daemon.sh status
```

Rollback validates the complete slot before any mutation, restores the previous set disabled,
invalidates acceptance, bootstraps the disabled job, and finishes with zero resident PID. If slot
restore fails, the command returns failure and deliberately leaves the job booted out.

## Integrity failure

For an **integrity failure**, do not bypass the verifier and do not manually edit managed files.
Capture read-only diagnostics, disable/bootout where possible, then repair through a verified package
or uninstall:

```bash
sudo ./scripts/manage-production-daemon.sh diagnostics
sudo ./scripts/manage-production-daemon.sh bootout
./scripts/manage-production-daemon.sh prepare
./scripts/manage-production-daemon.sh verify
sudo ./scripts/manage-production-daemon.sh upgrade
```

If installed verification prevents safe repair, use the reviewed release procedure rather than
deleting individual files by hand.

## Foreground conflict

A **foreground real-sleep conflict** occurs when the foreground CLI requests `--execute-sleep` while
production owns the shared sleep-authority lease. Do not kill or replace the lease file. Disable and
bootout production first, run the explicit foreground command, then bootstrap production disabled.

## Uninstall

```bash
sudo ./scripts/manage-production-daemon.sh uninstall
```

Uninstall preflights every managed path, disables and bootouts the job, and removes the binary,
plist, config, manifest, authority lease, acceptance/reboot/health/crash state, Task 14 state,
rollback slot, and production logs while preserving unrelated files. Expected residual state is no
loaded job, no daemon PID, and no managed support/log directory.

## Real sleep and reboot warnings

**real sleep warning:** `deployment-enabled-once`, `deployment-recovery-resleep`, `activate`, and an
activated production daemon can invoke real system sleep. Run them only with explicit approval and
with a cleanup path that returns to disabled when the acceptance command completes or fails.

**reboot warning:** reboot acceptance is a two-phase operation. Record the pre-reboot state, perform
the approved reboot manually, then verify that boot epoch changed before rollback/uninstall
acceptance. Never substitute a same-boot test or automate an unapproved reboot.

