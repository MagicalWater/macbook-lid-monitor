# Task 6R3 — Graceful shutdown single-authority recovery validation

日期：2026-07-31

## Incident baseline

```text
installed version: 99a51a4a2c45
installed commit: 99a51a4a2c454edce1344ce5f3e040a0cc2b3a0f
mode: disabled
job: absent
resident PID: none
acceptance: absent
crash: count=0 circuit=false runActive=true
```

The failed dry-run had produced the complete non-sleeping chain but stopped in cleanup after PID exit.
`event=stopping pid=90445 reason=signal` existed while crash-budget remained at the begin-run write.

## Root-cause proof

The old management sequence issued two overlapping termination operations:

```text
launchctl kill SIGTERM
launchctl bootout
```

The old signal controller restored SIGTERM/SIGINT to `SIG_DFL` before invoking the synchronous graceful
handler. A second SIGTERM during that handler therefore terminated the process before
`recordCleanExit()` completed.

## RED evidence

### True signal child

An independent xctest child started the real `ProcessSignalController`. Parent sent SIGTERM, waited until
the handler entered its completion window, then sent a second SIGTERM.

Old-code result:

```text
terminationReason = uncaughtSignal
terminationStatus = 15
completed marker = missing
focused test exit = 1
```

### Management authority

The source contract failed because both the normal helper and failed EXIT branch contained `stop_job`
before `bootout_job`.

## GREEN implementation

### Signal completion guard

`ProcessSignalController.finish(invokeHandler:)` now executes:

```text
claim completion ownership
→ SIGTERM/SIGINT = SIG_IGN
→ cancel read source
→ synchronously invoke graceful handler
→ SIGTERM/SIGINT = SIG_DFL
```

True-signal focused result:

```text
ProcessSignalControllerTests: 4 tests, 1 child-only skip, 0 failures
child termination: normal exit 0
completed marker: present
```

### Management single authority

Task 13 cleanup now executes:

```text
set mode disabled
→ bootout exactly once
→ bounded PID exit wait
→ bounded crash clean-state wait
→ bootstrap disabled job
```

The failed EXIT branch only reasserts disabled mode and bootout. No `stop_job`, bootstrap, force kill, or
unbounded wait remains in that branch.

Focused results:

```text
single-authority contract: 1/1 pass
Task 13 group: 9/9 pass
bounded deployment group: 2/2 pass
clean-exit timeout contract: 1/1 pass
```

## Holistic repository gates

```text
ProductionManagementScriptTests: 98 tests, 0 failures
Swift full suite: 299 tests, 1 child-only skip, 0 failures
release macbook-lid-monitor: pass
release macbook-lid-monitor-daemon: pass
bash -n: pass
shellcheck -x: pass
git diff --check: pass
package prepare/verify: pass
```

Pre-closure candidate identity:

```text
source commit: bd35fea2f3467e06861622b0fb89a851d92d5143
version: bd35fea2f346
binary SHA-256: 5666ac3123fab73d6acbc92bcb8243a90095eb083c822d47e3279eff5edbc044
plist SHA-256: 02ed783137c406d5baad9b07ec20ac60283b0bad8a1b2b29fa07d02d4689c24b
disabled config SHA-256: 201d3fae2c0d6266df417ce65374721b5793415d8bf4e2a9c479fe63790f77bf
```

Local-main integration requires a new final-main package identity; this pre-closure identity is not the
production deployment authority.

## Live production read-only gate

After all repository gates:

```text
installed identity: 99a51a4a2c45
mode: disabled
job: absent
resident PID: none
crash: {"circuitOpen":false,"unexpectedExitTimes":[],"runActive":true}
repository mutation to /Library: none
```

## Re-entry boundary

After ff-only local-main integration and fresh final-main verification, the already-approved production
sequence is:

1. upgrade fixed package and verify loaded／disabled／zero PID;
2. explicit crash-budget reset while disabled／zero PID;
3. deployment-dry-run;
4. deployment-enabled-once;
5. deployment-recovery-resleep.

Every acceptance stage must restore loaded／disabled／zero PID with crash count 0, circuit closed and
runActive false. Any failure stops immediately. Activate, reboot and push remain prohibited.

