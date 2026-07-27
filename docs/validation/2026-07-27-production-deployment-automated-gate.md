# Production Deployment Automated Gate — 2026-07-27

## Candidate

- Source commit: `2c3d41860c709cfd3a706ce7d7e1a6e63a48a1d4`
- Scope: Milestone 16 Task 14 automated and clean-snapshot release gate
- Mutation boundary: no `/Library`, production launchd, sleep, reboot, merge, push, or worktree
  cleanup

## Main working tree gate

```text
Swift XCTest: 264 tests, 0 failures
release product macbook-lid-monitor: passed
release product macbook-lid-monitor-daemon: passed
release product macbook-lid-monitor-daemon-spike: passed
release product macbook-lid-monitor-sleep-probe: passed
bash -n: manager and all sourced libraries passed
shellcheck -x: passed with zero findings
plist lint: launchd, config, and manifest templates passed
package prepare: passed
package verify: passed
git diff --check: passed
```

Prepared package provenance:

```text
version=2c3d41860c70
source-commit=2c3d41860c709cfd3a706ce7d7e1a6e63a48a1d4
binary-sha256=985caffeaae2161af358fc37574a7b744d277dee0b9522e5f21c4c21243928b2
plist-sha256=02ed783137c406d5baad9b07ec20ac60283b0bad8a1b2b29fa07d02d4689c24b
disabled-config-sha256=201d3fae2c0d6266df417ce65374721b5793415d8bf4e2a9c479fe63790f77bf
```

## Independent clean snapshot gate

The source tree was copied to `/tmp/macbook-lid-monitor-task14-clean` with `.git` and `.build`
excluded. A new local Git repository and commit were created solely to provide package provenance.

```text
clean-snapshot commit=3ea4ef6b0970
Swift XCTest: 264 tests, 0 failures
four release products: passed
bash -n: passed
shellcheck -x: passed
plist lint: passed
package prepare/verify: passed
git diff --check: passed
git status: clean
```

## Read-only production residual inventory

```text
residual=absent path=/Library/PrivilegedHelperTools/macbook-lid-monitor-daemon
residual=absent path=/Library/LaunchDaemons/com.crazydennies.macbook-lid-monitor.plist
residual=absent path=/Library/Application Support/MacBookLidMonitor
residual=absent path=/Library/Logs/MacBookLidMonitor
job=absent
process-count=0
foreground-real-sleep=absent
working-tree=clean
```

## Decision

The implementation is an automated-gate-complete release candidate. Production remains
uninstalled and Task 15 retains its separate explicit merge/push approval gate.
