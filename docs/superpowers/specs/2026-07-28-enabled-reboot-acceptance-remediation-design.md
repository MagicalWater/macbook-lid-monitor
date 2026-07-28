# Enabled Reboot Acceptance Remediation Design

Date: 2026-07-28

## Problem

Milestone 16 Task 21 requires an enabled reboot and pre-login acceptance flow that preserves the
installed identity and leaves production enabled/running. The repository currently exposes only the
historical `accept-task14-reboot-start` and `accept-task14-reboot-finish` commands. Those commands
require disabled mode, perform upgrade/rollback work, and uninstall the package, so they are not
valid Task 21 authority.

## Decision

Add new stable commands:

```text
deployment-reboot-start
deployment-reboot-finish
```

The historical Task 14 commands remain unchanged for backward-compatible historical evidence and
must not be used by Milestone 16 Task 21.

## Reboot start contract

`deployment-reboot-start` must:

1. require root and verify the installed set, target hardware, complete deployment acceptance,
   enabled mode, one resident daemon, fresh `monitoring-armed` health matching that PID, closed
   crash circuit, and secure managed lease metadata;
2. record the current boot epoch, installed identity, current daemon PID, hardware model/chip, and
   preparation timestamp in an atomic root-owned `0600` reboot-state file;
3. install a temporary root-owned LaunchDaemon observer that records boot epoch, observation time,
   console-user state, production job state, production PID count/PID, config mode, installed
   identity, profile, and health state/PID into a root-owned `0600` evidence file;
4. bootstrap the observer without changing production mode, production process, installed payload,
   deployment acceptance, or managed authority;
5. print explicit manual reboot instructions.

The command never reboots the Mac.

## Reboot finish contract

`deployment-reboot-finish` must:

1. require root and verify the reboot-state and observer evidence metadata and content;
2. prove the current boot epoch is greater than the prepared epoch;
3. prove installed identity, hardware model/chip, and hardware profile are unchanged;
4. prove the observer ran during the new boot before a graphical console user was present;
5. prove production remained enabled, launchd auto-loaded the job, exactly one new daemon PID ran,
   and health reached `monitoring-armed` for that PID;
6. prove the managed lease remains root:wheel `0600`, regular, single-link, and the complete
   deployment acceptance remains identity-bound;
7. run the strict operational baseline;
8. remove and boot out only the temporary observer and reboot evidence artifacts;
9. leave production enabled/running with exactly one armed daemon.

## Fail-safe behavior

- Start rejects any incomplete or unhealthy precondition before creating observer artifacts.
- Finish rejects stale, missing, unsafe, identity-mismatched, same-boot, logged-in-only, duplicate
  PID, or unhealthy evidence without disabling or replacing production.
- Temporary observer cleanup is explicit and limited to the Task 21 observer/state files.
- No Task 21 path may call upgrade, rollback, uninstall, disable, or mutate deployment acceptance.

## Testing

Sandbox tests must prove:

- stable dispatcher entries and absence of Task 21 routing to historical Task 14 commands;
- successful start preserves enabled mode and production PID;
- start rejects partial acceptance, disabled mode, duplicate PID, unsafe lease, and stale health;
- finish rejects unchanged boot, identity mismatch, logged-in observer evidence, duplicate PID, and
  health/PID mismatch;
- successful finish removes temporary artifacts and leaves enabled with one PID;
- production-only test hooks are rejected outside `MLM_TEST_ROOT`;
- Bash syntax, ShellCheck, the focused management suite, and the full Swift suite pass.

## Operational boundary

Implementation and automated verification use only repository files and `MLM_TEST_ROOT`. The live
production daemon remains enabled/running throughout remediation. Real reboot preparation is not
entered until implementation, immediate review, full verification, documentation, and an
independent remediation commit are complete.
