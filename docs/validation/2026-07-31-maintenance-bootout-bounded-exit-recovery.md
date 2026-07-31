# Task 6R — Maintenance bootout bounded-exit recovery Validation

日期：2026-07-31
範圍：Repository recovery candidate；未重試 production upgrade，未 bootstrap、dry-run 或真實睡眠。

## Incident baseline

Task 6 第一次 upgrade 使用已驗證 package `72a274e6ef29`，在 `launchctl bootout` 後立即
`pgrep`，因舊 daemon 尚在正常退出過程而 exit 70：

```text
booted-out label=com.crazydennies.macbook-lid-monitor
error: maintenance requires no resident daemon
exit_code=70
```

Safe stop：old identity unchanged、mode disabled、job absent、process count 0、payload 未替換。

## Recovery design

`prepare_maintenance_disabled_state` 現在於 `bootout_job` 後呼叫
`wait_for_managed_daemon_exit`：

```text
exact resident probe
→ process still present: wait 100 ms
→ maximum 50 waits / about 5 seconds
→ zero PID: continue transaction
→ timeout: return 70 before backup/invalidation/replacement
```

不送 SIGKILL、不增加無界 retry。`MLM_TEST_RESIDENT_DAEMON_PROBES` 只在 `MLM_TEST_ROOT`
sandbox 生效；真實 production 永遠使用精確 daemon path `pgrep`。

## TDD evidence

### RED

```text
delayed-exit: failed because no daemon-exit-wait evidence existed
timeout: failed because hook was ignored and upgrade replaced payload
sandbox-only: failed because resident/wait helpers did not exist
unrelated failure: none
```

### GREEN focused

```text
delayed-exit contract: 1 test, 0 failures
timeout-before-replacement contract: 1 test, 0 failures
sandbox-only hook contract: 1 test, 0 failures
upgrade regressions: 7 tests, 0 failures
explicit rollback regressions: 2 tests, 0 failures
uninstall regressions: 3 tests, 0 failures
```

Timeout test additionally proves：binary unchanged、manifest unchanged、acceptance preserved、mode
disabled、rollback slot absent。

## Holistic repository verification

```text
ProductionManagementScriptTests: 93 tests, 0 failures
Swift full suite: 292 tests, 0 failures
release macbook-lid-monitor: pass
release macbook-lid-monitor-daemon: pass
bash -n: pass
shellcheck -x: pass
git diff --check: pass
working tree before closure docs: clean
```

Repository candidate package at implementation commit：

```text
source commit: 0e0b8a0086c98e27b59200c0e24c6e584d430bd2
version: 0e0b8a0086c9
binary SHA-256: 313009ec8e61bd5929c63d5e37f202bc1a60f10dcaa8d2fdb815b8330500b070
package prepare/verify: pass
```

This package proves packaging compatibility for the implementation candidate. It is not the final
deployment authority because closure/integration commits change `SourceCommit`. Final local `main`
must perform a fresh single `prepare`／`verify` before any new upgrade approval。

## Independent holistic diff review

- Production change limited to one test counter, one exact probe, one bounded wait and one call site：pass。
- 50 × 100 ms bound matches approved Spec：pass。
- Probe errors propagate; timeout is stable return 70：pass。
- No SIGKILL、kill -9、new launchd authority or sleep behavior：pass。
- Timeout remains before `backup_current_set` and `invalidate_deployment_acceptance`：pass。
- Test hook is below `SYSTEM_ROOT` branch and production uses exact `pgrep`：pass。
- Existing upgrade／rollback／uninstall call graph remains shared：pass。

## Live production read-only gate

```text
installed version: 0885d54dbf13
installed source commit: 0885d54dbf133fdd8620d4a38379a8ed64819430
mode: disabled
job: absent
PID: none
process count: 0
production mutation during Task 6R: none
```

## Decision

Task 6R repository candidate passes with Open P0 = 0 and Open P1 without disposition = 0。After
fast-forward integration and final-main package prepare/verify, Task 6 may request a new explicit
production upgrade approval. No previous upgrade approval carries forward。

## Local-main integration

```text
main before integration: 72a274e6ef2924213c1b43840bff6db34370d356
candidate: 79bf1396fb2af6b35bb4e3fcc86470678401c8dc
integration: fast-forward only
conflicts: none
push: none
```

The integration synchronization commit that contains this section is the final-main source authority
for the next package prepare/verify gate。
