# Task 7R2 — macOS Diagnostics Process-metric Recovery

Date: 2026-07-31

## Scope

This recovery repaired the read-only production `diagnostics` command on macOS. It did not change the
auto-sleep state machine, daemon composition, README facts, package templates, installed production
payload, mode, launchd lifecycle or remote Git state.

## Trigger

The second Task 7 Step 5 run passed both repository holistic gates, then the final live read-only gate
stopped at:

```text
status_rc=0
diagnostics_rc=1
```

## Root cause

```text
old command: ps -p <pid> -o etimes=,%cpu=,rss=,vsz=
macOS result: ps: etimes: keyword not found
exit code: 1
supported field: etime
```

Sandbox tests had injected `MLM_TEST_PROCESS_METRICS`, so the real macOS field was not exercised.

## TDD repair

A focused test now launches a real `/bin/sleep` child and runs sandbox `diagnostics` with its real PID,
without injecting metrics. It requires diagnostics rc 0 and exactly one parser-friendly metric line:

```text
pid=<pid> elapsed=<value> cpu=<value> rss=<value> vsz=<value>
```

The minimal implementation change is:

```text
ps field: etimes -> etime
external output key: elapsed (unchanged)
```

## Verification

```text
focused RED: 1 test, 1 expected failure
focused GREEN: 1 test, 0 failures
current full suite: 300 tests, 1 child-only skip, 0 failures
current management suite: 99/99
independent clean snapshot: 300 tests, 1 child-only skip, 0 failures
clean management suite: 99/99
current and clean release builds: pass
bash -n: pass
shellcheck -x: pass
package prepare/verify: pass
git diff --check: pass
```

## Live read-only evidence

```text
installed identity: 7bf98ff6ceae / 7bf98ff6ceae710757b38b14efa00d42c34ca573
mode/job/process: enabled / loaded / 1
PID: 281
diagnostics_rc=0
metric_line=pid=281 elapsed=04:37:54 cpu=0.0 rss=11872 vsz=435345440
crash: count 0 / circuit closed / runActive true
artifact_count=0
observer_job=absent
candidate diff SHA unchanged
```

## Safety boundary

```text
production mutation: false
installed payload replacement: false
reboot: false
disable: false
rollback: false
push: false
```

Task 7R2 completes only this recovery. Task 7 Step 5 holistic closure remains open and must be rerun from
the beginning.
