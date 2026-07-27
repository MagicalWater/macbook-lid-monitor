# Task 12 Loginwindow Dry-Run System Evidence

Date: 2026-07-27

## Scope

Real system validation of the production daemon in dry-run mode across logout and the loginwindow,
using the temporary system-domain observer introduced in commit `603b271`.

## Observed acceptance output

- Finish restored the production configuration to `disabled`.
- Production system job was booted out and bootstrapped in disabled mode.
- Final diagnostics reported:
  - `job=loaded`
  - `mode=disabled`
  - `process-count=0`
  - version `7d056a175fe5`
  - checksum `2171744280fe19701bccf969cb4910c2c73c55b1cddb0a26b7fd7e61106c1029`
  - production log mode `0600`
  - production error log size `0`
- Acceptance reported `observed-console-user=root`, proving the observer collected evidence while
  the invoking user GUI session was absent.

## Independent post-acceptance re-review

- Production configuration mode: `disabled`.
- Production system job: loaded, not running.
- Production last exit code: `0`.
- Production resident PID: absent.
- Temporary observer system job: absent.
- Temporary observer executable: absent.
- Temporary observer plist: absent.
- Temporary evidence file: absent.

## Disposition

**Task 12 loginwindow dry-run acceptance passed.** The daemon remained under system launchd
authority across logout/loginwindow, evidence was collected outside the user GUI session, and all
temporary observer artifacts were removed. Final production state is installed, loaded, disabled,
and not running.
