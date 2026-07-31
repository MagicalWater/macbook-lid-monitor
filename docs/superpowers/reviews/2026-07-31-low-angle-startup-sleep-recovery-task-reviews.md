# Milestone 17 — 低角度啟動睡眠恢復 Task Reviews

日期：2026-07-31

## Task 6R2 — Acceptance clean-exit handoff recovery

### Incident evidence

```text
deployment-dry-run: pass
installed identity: 93d9881ecddb
final mode/job/process: disabled / loaded / 0
crash state after cleanup: closed / count 1 / runActive false
unexpected-exit timestamp: 2026-07-31T03:44:32.310Z
same-second events:
- PID 9182 stopping reason=signal
- PID 9725 started mode=disabled
```

### Root-cause review

- Signal handler 在 `ProductionDaemonSession.stop()` 中執行 `recordCleanExit()`：confirmed。
- Cleanup `disable → bootout → bootstrap` 沒有 PID/clean-state gate：confirmed。
- 新 disabled daemon `beginRun()` 可先看到舊 `runActive=true` 並誤增 count：confirmed。
- Dry-run behavior/evidence 本身完整，問題限於 cleanup handoff：confirmed。

### Repository baseline

```text
base commit: 93d9881ecddb0256c8cce97a360e55187902b4cb
isolated worktree: macbook-lid-monitor-0d5e8167
ProductionManagementScriptTests: 93 tests, 0 failures
live production mutation: none
```

### Governance decision

Task 6R2 repository-only execution approved。Design 選擇 bounded resident-exit + direct
crash-budget clean-state verification；不 reset、不強殺、不重跑 dry-run。Task 6 enabled-once
維持 blocked。Open P0 = 0；Open P1 without disposition = 0。

### RED execution evidence

```text
testTask13DryRunCleanupWaitsForCleanExitBeforeBootstrapAndPreservesCrashCount:
failed as expected — post-verification cleanup has no daemon/clean-exit wait markers

testDeploymentDryRunCleanExitTimeoutDoesNotBootstrapOrRecordAcceptance:
failed as expected — command returned 0, bootstrapped and recorded acceptance

testTask13FailureTrapUsesBoundedCleanExitHandoff:
failed as expected — injected failure preserved, but trap emitted no clean-exit handoff evidence

testTask13AcceptanceCleanupUsesSharedSandboxIsolatedHandoff:
failed as expected — all four shared helper interfaces are absent
```

One initial failure-trap assertion used a non-authoritative wording. It was corrected to the existing
stable output `error=deployment-test-failure stage=dry-run`; the rerun then failed only because
`clean-exit-wait=pass` was absent。

### RED immediate review

- Tests execute real management commands against sandbox roots：通過。
- Timeout test proves current code can incorrectly record acceptance after the missing boundary：通過。
- Delayed test locks exact ordering rather than accepting a fixed sleep：通過。
- Failure trap is independently covered：通過。
- Production script mutation before RED：none。
- Live production mutation：none。

**Task 6R2-1 RED approved.** Open P0 = 0；Open P1 without disposition = 0。可進入
Task 6R2-2 minimal GREEN。

### GREEN implementation

新增 shared interfaces：

```text
crash_budget_clean_exit_persisted
wait_for_crash_budget_clean_exit
restore_disabled_job_after_acceptance
cleanup_acceptance_to_disabled
```

Handoff order：

```text
mode=disabled
→ SIGTERM
→ bootout
→ bounded resident PID wait
→ bounded crash-budget runActive=false wait
→ bootstrap disabled
```

`ACCEPTANCE_HANDOFF_STATE=idle|waiting|complete|failed` 防止 normal helper failure 後 EXIT trap
再次 bootstrap。Production crash-budget probe 直接解析 JSON；sandbox counter 只在
`MLM_TEST_ROOT` branch 生效。

### Focused GREEN evidence

```text
new clean-exit contracts: 4 tests, 0 failures
Task 13 focused suite: 9 tests, 0 failures
bounded deployment regression: 2 tests, 0 failures
Task 6R resident-exit regression: 1 test, 0 failures
bash -n: pass
shellcheck -x: pass
git diff --check: pass
```

### Immediate implementation review

- Delayed clean-state probes 2 次 active、第三次 pass：通過。
- Timeout return 70，timeout suffix 無 bootstrap/acceptance record：通過。
- Existing crash-budget bytes 在 successful sandbox cleanup 中保持不變：通過。
- Injected failure trap 經相同 bounded handoff 回復 disabled：通過。
- `waiting|failed` trap 只 set disabled／stop／bootout，不 bootstrap：通過。
- Production hook isolation：通過。
- Task 12 original traps remain 3；Task 17 original trap remains 1：通過。
- Task 13 shared traps = 3；success helper references = 3 paths：通過。
- SIGKILL／kill -9：0。
- reset crash budget invocation added：0。
- Live production mutation：none。

### Decision

**Task 6R2-2 approved.** Open P0 = 0；Open P1 without disposition = 0。可進入 holistic
repository gate；Task 6 enabled-once 仍 blocked。

### Holistic repository gate

```text
ProductionManagementScriptTests: 97 tests, 0 failures
Swift full suite: 296 tests, 0 failures
release macbook-lid-monitor: pass
release macbook-lid-monitor-daemon: pass
bash -n: pass
shellcheck -x: pass
package prepare/verify: pass
git diff --check: pass
implementation candidate: 04b35acf94c2e2a098112d889295f1e1a9603906
```

### Live read-only gate

```text
installed identity: 93d9881ecddb / 93d9881ecddb0256c8cce97a360e55187902b4cb
mode/job/process: disabled / loaded-not-running / 0
crash budget: count 1 / closed / runActive false
acceptance metadata: root:wheel / 600 / 1103 bytes / mtime unchanged
main working tree: clean
production mutation: none
```

### Holistic scope review

- Changed production file只有 management script：通過。
- Three Task 13 paths共用 ordered handoff：通過。
- Task 12／Task 17 untouched：通過。
- No force-kill、reset、sleep、activation、reboot addition：通過。
- Timeout no-bootstrap/no-acceptance：通過。
- Candidate package自驗證：通過。
- Reviewer subagent unavailable；使用 independent checklist + diff review + executable/full gates：
  已記錄 disposition。

### Decision

**Task 6R2 repository candidate approved.** Open P0 = 0；Open P1 without disposition = 0。
可執行 local-main ff-only integration；不得 push 或執行 production mutation。Integration 後必須
從 final main fresh tree重新測試與 prepare/verify package。

### Task 6R2 local-main integration

```text
base main: 93d9881ecddb0256c8cce97a360e55187902b4cb
reviewed closure: a0ddb32e20a01f678c29a81e3b86a58e4ff76642
method: git merge --ff-only
conflicts: none
main working tree after merge: clean
push: not executed
production mutation: none
```

Integration accepted。Task 6R2 的最後 gate 是 integration-authority commit 上的 fresh full suite、
release/static 與 final-main package prepare/verify；未通過前不得請求 production upgrade。

## Task 1 — Startup-closed RED contract

### Baseline

```text
LidSleepStateMachineTests: 15 tests, 0 failures
LidSleepCoordinatorTests: 12 tests, 0 failures
live production mutation: none
```

### RED contract

State-machine tests要求：

- fresh closed startup 建立 `startupClosedCandidate`；
- deadline 只 request sleep 一次；
- hysteresis、invalid、stale data fail-open；
- reopen 取消 candidate 並進入 open。

Coordinator tests要求：

- startup cooldown 後沿用 close debounce task；
- 穩定輸出 startup candidate transitions；
- requester exactly once；
- hysteresis cancellation disarms。

### Review status

### RED execution evidence

```text
swift test --filter LidSleepStateMachineTests: failed as expected
missing API: LidSleepState.startupClosedCandidate(deadline:)

swift test --filter LidSleepCoordinatorTests: failed as expected
missing events:
- startupClosedCandidateStarted
- startupClosedCandidateCancelled
- startupClosedDebounceElapsed

unrelated failure: none
live production mutation: none
```

### Decision

**Task 1 RED approved.** 測試直接鎖定已確認根因，沒有以 mock composition 或文件字串取代
state-machine behavior。Open P0 = 0；Open P1 without disposition = 0。可進入 Task 2 GREEN。

## Task 2 — Shared startup closed state machine

### Plan coverage finding

#### S17-T2-P1-1 — Transition enum 的兩個 output switch 未列入 Plan

新增 `AutoSleepTransitionEvent` 會同時影響前景 `OutputFormatter` 與 production
`ProductionDaemonApplication` 的 exhaustive switch。原 Task 2 files 只列 state machine、
coordinator 與 enum owner，會留下未受行為測試保護的 output mapping。

**Disposition：** Task 2 files 已補入 `OutputFormatter.swift`、
`ProductionDaemonApplication.swift`、`OutputFormatterTests.swift` 與
`ProductionDaemonCompositionTests.swift`。先加入 formatter 與 production transition RED
assertions，再實作 enum 與 mapping。Finding closed。

### Additional RED evidence

```text
OutputFormatterTests: failed as expected
missing events:
- startupClosedCandidateStarted
- startupClosedCandidateCancelled
- startupClosedDebounceElapsed

Production startup transition test: failed at the same missing enum contract
unrelated failure: none
```

### GREEN verification

```text
LidSleepStateMachineTests: 22 tests, 0 failures
LidSleepCoordinatorTests: 14 tests, 0 failures
OutputFormatterTests: 7 tests, 0 failures
Production startup transition focused test: 1 test, 0 failures
AutoSleepIntegrationTests regression suite: 9 tests, 0 failures
```

### Immediate review

- `startupClosedCandidate` 與一般 `closingCandidate` 分離：通過。
- Startup hysteresis cancellation 回到 disarmed，不會誤報 open：通過。
- `>=reopenThreshold` cancellation 取消 debounce 並 rearm：通過。
- Missing、stale、invalid data 不會 request sleep：通過。
- Startup deadline 只 request sleep 一次：通過。
- Coordinator 沿用既有 `closeDebounceTask`；未新增第四個 timer：通過。
- Wake、stop、invalid data 可取消 pending debounce：通過。
- Sleep request failure 維持 disarmed/no automatic retry：通過。
- 前景 formatter 與 production event names 皆有 executable contract：通過。
- Live production mutation：none。

### Decision

**Task 2 approved.** Open P0 = 0；Open P1 without disposition = 0。可進入 Task 3
composition equivalence verification。

## Task 3 — Shared composition equivalence

### Verification

```text
AutoSleepIntegrationTests: 11 tests, 0 failures
ProductionDaemonCompositionTests: 13 tests, 0 failures
Diagnostic-focused suites: 6 tests, 0 failures
```

### Accepted evidence

- Foreground dry-run 低角度 startup：cooldown + debounce 後 exactly one `would-sleep`。
- Foreground execute-sleep 低角度 startup：injected system operation exactly once。
- Production dry-run 低角度 startup：穩定 startup transition + `would-sleep`。
- Production enabled 低角度 startup：production requester exactly once。
- 四種模式未注入不同 startup policy；差異只存在 requester effect。
- Pure diagnostic CLI/parser、hardware ranking 與 diagnostics tests 保持通過。
- Live production mutation：none。

### Immediate review

- 測試對 real coordinator/state-machine behavior 斷言，不只搜尋 source string：通過。
- Enabled requester 使用 thread-safe counter，未改 production interface：通過。
- Dry-run 不取得 sleep authority、execute-sleep authority 規則未改：通過。
- 舊 unused test requester 已移除：通過。

### Decision

**Task 3 approved.** Open P0 = 0；Open P1 without disposition = 0。可進入 Task 4
documentation/event authority synchronization。

## Task 4 — Documentation and event authority synchronization

### RED evidence

```text
Production event privacy contract: passed immediately, generic formatter already preserves names
Runbook contract: failed on missing「低角度啟動與重新開機」
README-first contract: failed on missing Milestone 17 candidate/deployment warning
```

### GREEN verification

```text
ProductionEventTests: 3 tests, 0 failures
Production runbook contract: 1 test, 0 failures
README-first contract: 1 test, 0 failures
```

### Immediate review

- README 前 100 行揭露漏洞修復候選與「尚未部署」狀態：通過。
- README 新 startup policy 取代舊「低角度永遠 disarmed」說明：通過。
- 中文 runbook 說明 `<=68`、`69...74`、`>=75`、freshness 與 failure boundaries：通過。
- 文件未宣稱目前 installed binary 已包含 Milestone 17：通過。
- 新 production transition 保持 stable、redacted、無 raw/sensor leakage：通過。
- Pure diagnostic boundary 與 hardware support boundary 保留：通過。
- Live production mutation：none。

### Decision

**Task 4 approved.** Open P0 = 0；Open P1 without disposition = 0。可進入 Task 5
repository holistic release gate。

## Task 5 — Repository holistic release gate

### Current-checkout gate

```text
Swift XCTest: 289 tests, 0 failures
ProductionManagementScriptTests: 90 tests, 0 failures
release product macbook-lid-monitor: pass
release product macbook-lid-monitor-daemon: pass
bash -n: pass
shellcheck -x: pass
package prepare/verify: pass
git diff --check: pass
candidate implementation commit: 3d47ddd29ba4cb9773dc4db016f4dd6f6ca86b72
```

### Clean-snapshot findings

#### S17-T5-P1-1 — `/private/tmp` 不是有效的 management-test clean environment

第一次 independent clone 位於 `/private/tmp`。該目錄的 group inheritance 與使用者 home
sandbox 不同，所有建立 managed sleep-authority lease 的測試都被 verifier 正確拒絕：

```text
error=installed-set-invalid reason=group path=.../sleep-authority.lock
```

這不是 candidate behavior failure；同一 90-test management suite 在 normal checkout 已通過，
且失敗皆集中於相同 group policy boundary。

**Disposition：** 停止無效環境測試，在
`/Users/water/.devspace/clean-snapshots/` 建立 owner=`water`、group=`staff` 的 independent clean
clone，重新執行完整 gate。新環境 289 tests、release、static、package 全部通過。Finding closed。

#### S17-T5-P1-2 — Independent Swift release builds 的 binary SHA 不相同

Current checkout 與 clean clone 對同一 commit 建置的 Mach-O SHA-256 不同。調查顯示兩者
`LC_UUID` 與 linker-generated ad-hoc code signature 不同；移除 signature 後 binary 仍因 UUID
不同而不相同。Source 中未嵌入 checkout path。

既有 release authority 的 clean-snapshot contract 要求兩邊各自完成 release build 與 package
manifest self-verification，從未要求跨 build byte-for-byte reproducibility。正式安裝也只會取用
一次 final `prepare`／`verify` 產生的固定 package，不會混用兩個 build 的 manifest 或 binary。

**Disposition：** 不弱化 package checksum，也不新增不在本 Milestone scope 的 linker flag。
記錄 Swift linker UUID／ad-hoc signing 的 build non-reproducibility；兩個 package 均對自身
binary checksum 驗證通過。Deployment 前仍必須從 final main commit 重新建立並鎖定單一 package。
Finding closed。

### Valid clean-snapshot gate

```text
path owner/group: water:staff
source commit: 3d47ddd29ba4cb9773dc4db016f4dd6f6ca86b72
Swift XCTest: 289 tests, 0 failures
release product macbook-lid-monitor: pass
release product macbook-lid-monitor-daemon: pass
bash -n: pass
shellcheck -x: pass
package prepare/verify: pass
git diff --check: pass
tracked working tree: clean
```

### Live read-only gate

```text
installed source commit: 0885d54dbf133fdd8620d4a38379a8ed64819430
installed version: 0885d54dbf13
mode: enabled
launchd state: running
PID: 288
process count: 1
production mutation: none
```

### Holistic repository review

- Approved Spec supersession is reflected in source, tests, README and runbook: pass。
- All auto-sleep compositions share one startup policy: pass。
- Hysteresis/freshness/invalid/failure fail-open boundaries remain: pass。
- No fourth timer, polling loop or unrestricted retry exists: pass。
- Stable foreground and production transition evidence exists: pass。
- Current-checkout and valid independent clean-snapshot gates pass: pass。
- Current live production is explicitly still old identity/old behavior: pass。
- No upgrade, sleep, activate, reboot, rollback, uninstall or push occurred: pass。

### Decision

**Task 5 approved — repository candidate complete.** Open P0 = 0；Open P1 without disposition = 0。
Tasks 6–7 remain open and separately approval-gated. The bug is fixed in the repository candidate,
but not yet in the installed production daemon。

## Task 5 post-worktree integration and cross-conversation handoff review

### Integration evidence

```text
base main before integration: 818855fc828304187a4dc308e51827caa3022d3e
repository candidate closure: 73015cac8bce121b2ea3137c3b616f3b91eb4a03
integration method: git merge --ff-only
result: local main points to repository candidate closure before handoff synchronization
candidate commits reachable from main: yes
production mutation: none
push: none
```

### Documentation synchronization findings

#### S17-T5-P1-3 — Implementation Plan Tasks 1–5 checkboxes remained open

Task register、reviews 與 validation 均已記錄 Tasks 1–5 complete，但 Implementation Plan 的
Tasks 1–5 steps 仍為 unchecked。這會讓下一個對話誤判 repository implementation 尚未執行。

**Disposition：** 將 Tasks 1–5 全部已完成 steps 更新為 checked；Tasks 6–7 保持 unchecked。
Finding closed。

#### S17-T5-P1-4 — Validation scope header remained Tasks 1–4

Validation 正文已包含 Task 5 holistic evidence，但 scope header 仍寫 Tasks 1–4。

**Disposition：** scope 更新為 Tasks 1–5 repository candidate 與 holistic release gate。
Finding closed。

#### S17-T5-P1-5 — Missing cross-conversation authority

Repository candidate 已完成但尚無 Milestone 17 Task 5 → Task 6 handoff，且 candidate commits
仍只存在 detached worktree；直接切換對話會增加從錯誤 worktree 開始、遺漏 approval gate 或誤判
installed production 已修復的風險。

**Disposition：** 候選以 fast-forward 整合回本機 main，新增
`docs/handoffs/2026-07-31-milestone-17-task5-to-task6-handoff.md`，明確記錄 authority、Git、
live production、remaining Tasks、read order 與獨立批准邊界。Finding closed。

### Handoff holistic review

- Spec／Plan／Task／review／validation 的 Tasks 1–5 狀態一致：通過。
- Stage A／B complete；Stage C open：通過。
- Local main 已包含全部 candidate commits：通過。
- README/runbook 仍正確宣告 live production 尚未部署 Milestone 17：通過。
- Installed old identity、enabled、single PID、running：只讀核對通過。
- 下一步明確從 Task 6 開始，不沿用舊 approval：通過。
- Push、upgrade、sleep、activate、reboot：none。

### Decision

**Task 5 integration and handoff closure approved.** Open P0 = 0；Open P1 without disposition = 0。
Milestone 17 可安全切換至新對話，從 Task 6 read-only baseline audit 開始；Milestone 17 本身仍未
complete，因 Tasks 6–7／Stage C 尚未執行。

## Task 6 — First upgrade attempt safe stop

### Approved package and command

```text
repository main: 72a274e6ef2924213c1b43840bff6db34370d356
staged version: 72a274e6ef29
staged binary SHA-256: 0376080dcdc0bfa58b945658da85966a5a4df1abfe691502cc7999e47926d935
command: sudo ./scripts/manage-production-daemon.sh upgrade
```

### Failure evidence

```text
booted-out label=com.crazydennies.macbook-lid-monitor
error: maintenance requires no resident daemon
exit_code=70
```

Immediate post-failure evidence：

```text
installed version: 0885d54dbf13
installed source commit: 0885d54dbf133fdd8620d4a38379a8ed64819430
mode: disabled
job: absent
process count: 0
payload replacement: none
```

### Root-cause review

`prepare_maintenance_disabled_state` 在 `launchctl bootout` 返回後立即 `pgrep`。真實 daemon
仍可能短暫處於退出過程，造成正常 termination latency 被誤判為 resident failure。現有
`MLM_TEST_ROOT` tests 跳過 real process probe，未覆蓋該競態。

### Decision

Task 6 upgrade **not complete**。Safe stop 有效，但 Task 6 blocked by Task 6R。不得直接重試、
bootstrap、dry-run 或真實睡眠。

## Task 6R — Governance initialization

Spec、task-level Spec review、holistic Spec review、Implementation Plan、task-level Plan review 與
holistic Plan review 已建立。Recovery scope 僅限 bounded daemon-exit synchronization；production
必須維持 old identity／disabled／job absent／zero PID。

### Task 6R-1 RED contract

新增 executable contracts：

- resident daemon 經兩次 probe 後退出，upgrade 必須輸出第三次 probe 成功並替換 payload；
- resident daemon 持續超過 50 個 wait interval，upgrade 必須 return 70，且 binary、manifest、
  acceptance 與 rollback boundary 保持 transaction 前狀態；
- deterministic resident probe hook 必須只存在於 `SYSTEM_ROOT` sandbox branch，production 仍用
  exact daemon-path `pgrep`。

### RED execution evidence

```text
delayed-exit test: failed as expected
reason: upgrade completed without daemon-exit-wait evidence

timeout test: failed as expected
reason: upgrade ignored deterministic resident probes, returned 0, replaced payload,
        invalidated acceptance and created rollback slot

sandbox-only hook test: failed as expected
reason: managed_daemon_is_resident / wait_for_managed_daemon_exit do not exist

unrelated failure: none
production mutation: none
```

### RED review decision

三條 failure 都直接指向缺少 bounded-exit contract，而非 test fixture、staging identity 或 Swift
compile error。**Task 6R-1 RED approved.** Open P0 = 0；Open P1 without disposition = 0。

## Task 6R-2 — Bounded resident-process wait implementation

### GREEN evidence

```text
delayed-exit contract: 1 test, 0 failures
timeout-before-replacement contract: 1 test, 0 failures
sandbox-only hook contract: 1 test, 0 failures

upgrade-focused regressions: 7 tests, 0 failures
explicit rollback regressions: 2 tests, 0 failures
uninstall regressions: 3 tests, 0 failures

bash -n: pass
shellcheck -x: pass
git diff --check: pass
```

### Immediate review

- Production probe 使用 exact daemon path `pgrep`：通過。
- `MLM_TEST_RESIDENT_DAEMON_PROBES` 只在 `SYSTEM_ROOT` sandbox branch 生效：通過。
- Wait 上限為 50 × 100 ms，沒有 unbounded retry：通過。
- Timeout return 70，不送 SIGKILL 或其他 signal：通過。
- Timeout 發生在 backup、acceptance invalidation 與 payload activation 前：通過。
- Upgrade、rollback、uninstall 共用 `prepare_maintenance_disabled_state` boundary：通過。
- Sandbox timeout test 不做 wall-clock sleep：通過。
- Live production mutation：none。

### Decision

**Task 6R-2 approved.** Open P0 = 0；Open P1 without disposition = 0。可進入 Task 6R-3
holistic repository gate。

## Task 6R-3 — Holistic repository gate

### Verification evidence

```text
ProductionManagementScriptTests: 93 tests, 0 failures
Swift full suite: 292 tests, 0 failures
release macbook-lid-monitor: pass
release macbook-lid-monitor-daemon: pass
bash -n: pass
shellcheck -x: pass
package prepare/verify at implementation commit: pass
git diff --check: pass
```

Candidate package evidence：

```text
source commit: 0e0b8a0086c98e27b59200c0e24c6e584d430bd2
version: 0e0b8a0086c9
binary SHA-256: 313009ec8e61bd5929c63d5e37f202bc1a60f10dcaa8d2fdb815b8330500b070
```

### Independent holistic review

- Diff 僅擴充 maintenance exit synchronization，未碰 auto-sleep state machine：通過。
- Exact production probe 與 sandbox deterministic hook 分離：通過。
- 5 秒上限、timeout return 70、no kill：通過。
- Backup／acceptance invalidation／payload activation 仍在 successful wait 後：通過。
- 93-test management 與 292-test full suite 均 fresh pass：通過。
- Release/static/package gates fresh pass：通過。
- Live production old identity／disabled／job absent／zero PID：只讀通過。

### Live production evidence

```text
installed version: 0885d54dbf13
installed source commit: 0885d54dbf133fdd8620d4a38379a8ed64819430
mode: disabled
job: absent
process count: 0
production mutation: none
```

### Decision

**Task 6R repository candidate approved.** Open P0 = 0；Open P1 without disposition = 0。
Fast-forward integration 後必須從 final local main 重新 prepare/verify；Task 6 upgrade 仍需新的明確
批准，舊 `72a274e6ef29` approval 不可沿用。

## Task 6R — Local-main integration review

### Integration evidence

```text
main before integration: 72a274e6ef2924213c1b43840bff6db34370d356
recovery candidate: 79bf1396fb2af6b35bb4e3fcc86470678401c8dc
method: git merge --ff-only
conflicts: none
working tree after integration: clean
push: none
production mutation: none
```

### Decision

Task 6R is integrated into local main。This integration does not authorize production upgrade。
Final-main full verification and package prepare/verify remain required before presenting a new Task 6
upgrade gate。

## Task 6R3 — Graceful shutdown single-authority recovery review

### Incident review

- Dry-run core chain reached candidate/debounce/attempt/would-sleep exactly once: pass.
- Cleanup stopped before enabled-once and left disabled/job absent/zero PID: pass.
- `runActive=true` remained after PID exit and stopping log: confirmed.
- Root cause traced to management double termination plus signal controller restoring default before
  handler completion: confirmed.

### TDD review

```text
true double-SIGTERM RED: child terminated by signal 15, completed marker missing
true double-SIGTERM GREEN: child normal exit 0, completed marker present
single-authority RED: stop_job found in normal and failed branches
single-authority GREEN: exactly one bootout, no stop_job
```

### Holistic evidence

```text
ProductionManagementScriptTests: 98 tests, 0 failures
Swift full suite: 299 tests, 1 child-only skip, 0 failures
release builds: pass
bash -n: pass
shellcheck -x: pass
package prepare/verify: pass
candidate version: bd35fea2f346
candidate binary SHA-256: 5666ac3123fab73d6acbc92bcb8243a90095eb083c822d47e3279eff5edbc044
```

### Scope review

- Changed runtime behavior is limited to signal completion and Task 13 cleanup termination authority.
- No auto-sleep policy, activation, reboot, rollback, force-kill or reset semantics changed.
- Live production remained `99a51a4a2c45`, disabled, job absent, zero PID, runActive=true.

### Decision

**Task 6R3 repository candidate approved.** Open P0 = 0；Open P1 without disposition = 0。
Proceed to ff-only local-main integration and fresh final-main verification before production mutation.

## Task 6R3 — Local-main integration review

```text
main before integration: 99a51a4a2c454edce1344ce5f3e040a0cc2b3a0f
candidate: 65193e1bddf5b34facefac4ad95ebbcdddaeaa46
method: git merge --ff-only
conflicts: none
working tree after integration: clean
push: none
production mutation: none
```

Integration itself does not authorize deployment. Fresh verification and package prepare/verify must run
on the final local-main documentation commit before any production mutation.

## Task 6R3 — Final-main and production re-entry review

### Final-main evidence

```text
final local main: 7bf98ff6ceae710757b38b14efa00d42c34ca573
version: 7bf98ff6ceae
binary SHA-256: 6b30459a2168d0f409cc45e4cd152a3b535a85566347e7bc273b58109e2c6ee3
Swift full suite: 299 tests, 1 child-only skip, 0 failures
release/static/package gates: pass
working tree before deployment: clean
push: none
```

### Production upgrade and crash repair

- Upgrade installed the exact final-main identity and checksum: pass.
- The first post-upgrade disabled daemon briefly ran before reaching loaded／not-running; the one-shot
  orchestration script sampled too early and stopped. The process then exited zero and persisted clean
  state. This was an orchestration sampling issue, not a daemon failure.
- The inherited incident `runActive=true` was counted once by the first new daemon start, then explicitly
  reset while disabled／zero PID: pass.
- Dry-run acceptance: pass, crash count remained 0.
- Enabled-once acceptance: pass, exactly one request／return, PID stable.

### First recovery-resleep attempt review

The first attempt emitted the initial sleep request at `16:26:05`. The display became interactive at
`16:26:12`, but `pmset` recorded:

```text
16:26:35 Delays to Sleep notifications: [LINE timed out(30000 ms)]
```

The daemon received its formal wake callback at `16:26:35`; `wake-recovery=15` therefore had not expired
when the user, after waiting about 20 seconds from display-on, reopened the lid to continue operating.
The later `monitoring-armed` event is consistent with that reopen and is not evidence that the lid was
raised immediately after wake. The user stopped the bounded command with Ctrl+C. Cleanup left
disabled／job absent／zero PID and crash count 0. No acceptance was recorded for this failed attempt.

### Recovery-only retest evidence

The retest preserved the already accepted dry-run and enabled-once stages, kept the lid at approximately
45–55 degrees, and allowed at least 60 seconds after the first display wake.

```text
PID: 64966
08:59:03 first sleep-request-attempted / sleep-requested
08:59:33 first wake evidence
08:59:49 recovery-resleep
08:59:49 second sleep-request-attempted / sleep-requested
09:00:17 second wake evidence and reopen
attempt-count=2
return-count=2
recovery-count=1
wake-count=2
pid-stable=true
```

The 46-second interval from the first request to recovery-resleep is compatible with an external
30-second sleep-notification delay followed by the configured 15-second interval. The product contract
remains `systemHasPoweredOn + 15 seconds`; no display-on timer or runtime behavior amendment was approved.

### Final state and decision

```text
acceptance: deployment-dry-run, deployment-enabled-once, deployment-recovery-resleep
installed identity: 7bf98ff6ceae
mode/job/process: disabled / loaded-not-running / 0
crash: count 0 / circuit closed / runActive false
activate: not executed
reboot: not executed
push: not executed
```

**Task 6 and Task 6R3 production acceptance approved and complete.** Open P0 = 0；Open P1 without
disposition = 0。Task 7 remains the only open Stage C scope.

## Task 7 Step 1 — Persistent activation review

### Approval and preflight

Step 1 was explicitly started as a bounded activation-only operation. The operation excluded reboot
observer preparation, manual reboot, finish, rollback and push. Preflight confirmed:

```text
repository head: 5d0769556cbf0a49800c1af9b740cb398a3c7353
installed version: 7bf98ff6ceae
installed source commit: 7bf98ff6ceae710757b38b14efa00d42c34ca573
mode/job/process: disabled / loaded-not-running / 0
crash: count 0 / circuit closed / runActive false
acceptance: deployment-dry-run, deployment-enabled-once, deployment-recovery-resleep
reboot artifacts: absent
```

### Activation evidence

```text
verified deployment-acceptance stages=deployment-dry-run deployment-enabled-once deployment-recovery-resleep
booted-out label=com.crazydennies.macbook-lid-monitor
bootstrapped label=com.crazydennies.macbook-lid-monitor
activated deployment mode=enabled label=com.crazydennies.macbook-lid-monitor
baseline_wait=pass probes=5
operational_baseline=pass pid=99898
```

Root diagnostics reported exact installed integrity, target hardware, complete acceptance, managed lease,
fresh PID-bound health, and closed crash circuit. Independent post-command evidence showed:

```text
09:29:13 started pid=99898 mode=enabled
09:29:14 startup-cooldown
09:29:19 monitoring-armed
mode/job/process: enabled / loaded / 1
crash: count 0 / circuit closed / runActive true
health metadata: root:wheel 0600, updating after activation
reboot state/evidence/observer artifacts: absent
```

### Decision

**Task 7 Step 1 approved and complete.** Persistent enabled mode is intentional. Open P0 = 0；Open P1
without disposition = 0。Step 2 reboot observer preparation remains separately approval-gated；no reboot
or push occurred.

## Task 7 Step 2 — Low-angle reboot observer preparation review

### Approval and scope

The user separately approved observer preparation only. The operation was required to stop in an armed
state and prohibited automatic reboot、finish、rollback and push. A failure cleanup trap was prepared to
boot out the observer, remove all four temporary artifacts and re-check the existing enabled production
baseline.

### Preflight evidence

```text
repository head: 786f843879c9bdc84f55d2e2afdef211cbebd5a2
working tree: clean
installed version: 7bf98ff6ceae
installed source commit: 7bf98ff6ceae710757b38b14efa00d42c34ca573
mode/job/process: enabled / loaded / 1
prepared PID: 99898
boot epoch: 1785457249
crash: count 0 / circuit closed / runActive true
existing reboot artifacts: 0
operational baseline: pass
```

### Arm evidence

```text
verified deployment-acceptance stages=deployment-dry-run deployment-enabled-once deployment-recovery-resleep
wrote deployment-reboot-state boot-epoch=1785457249
armed deployment-reboot-start boot-epoch=1785457249 pid=99898
deployment_reboot_start_exit=0
```

Managed metadata and source integrity:

```text
deployment-reboot.plist: root:wheel 0600, regular file, link count 1
reboot-observer.sh: root:wheel 0700, regular file, link count 1
reboot observer LaunchDaemon plist: root:wheel 0644, regular file, link count 1
observer script SHA-256: 653cf6ef43405556bbff6bbaf8ed1fa698ee475a58521b8031df3ef2d9d1e89f
observer plist SHA-256: fd53298736e2b6c10845539628dcd00a3a11effb2f8d74e98d6c15029143e6a4
```

The RunAtLoad observer executed once on the current boot and exited normally:

```text
observer job: loaded / not running
runs: 1
last exit code: 0
initial evidence boot epoch: 1785457249
initial evidence PID: 99898
initial evidence console user: water
```

This same-boot evidence is expected and is not the reboot proof. On the next boot, launchd will execute the
one-shot observer again and overwrite the evidence with the new boot/PID/loginwindow state. Step 4 will
reject the run unless the boot epoch changed and the observed PID differs from prepared PID `99898`.

### Final state and decision

```text
production: enabled / loaded / PID 99898 / operational baseline pass
observer: armed, root-owned, one-shot, currently not running
manual reboot: not executed
finish: not executed
rollback: not executed
push: not executed
```

**Task 7 Step 2 approved and complete.** Open P0 = 0；Open P1 without disposition = 0。Step 3 manual
low-angle reboot remains separately approval-gated.

## Task 7 Step 3 — Low-angle manual reboot runtime review

### Approval and execution boundary

The user separately approved only the manual reboot and low-angle loginwindow observation. The
operation prohibited automatic finish、cleanup、rollback and push. The user manually restarted macOS,
kept the lid approximately 45–55 degrees through boot, remained at loginwindow until the startup sleep
occurred, reopened above 75 degrees, allowed observer time, then logged in and reconnected bridge-mac.

### Changed boot and PID evidence

```text
prepared boot epoch: 1785457249
current boot epoch: 1785491605
boot changed: true
prepared PID: 99898
current PID: 281
mode/job/process: enabled / loaded / 1
crash: count 0 / circuit closed / runActive true
```

The current boot time was `2026-07-31 17:53:25 +0800`. Production log evidence for PID `281` was:

```text
17:53:39 started mode=enabled
17:53:41 startup-cooldown / monitoring-disarmed
17:53:47 startup-closed-candidate
17:53:48 startup-closed-debounce-elapsed
17:53:48 sleep-request-attempted
17:53:48 sleep-requested
17:54:06 monitoring-armed
```

`pmset` independently recorded a real wake at `17:54:05` due to keyboard/trackpad HID activity. This
matches the user's observation that the low-angle startup sleep occurred and the lid was then reopened.
No second sleep request or duplicate production PID was observed.

### Observer evidence boundary

The observer LaunchDaemon remains loaded／not running with `runs=1` and `last exit code=0`. Its protected
evidence plist is root:wheel `0600` and its mtime advanced to `17:54:07`, after the new boot and rearm.
Step 3 does not claim the protected `ConsoleUser`、identity、health PID or boot fields are accepted; those
fields are intentionally verified by `deployment-reboot-finish` in Step 4 before cleanup.

### Decision

**Task 7 Step 3 manual reboot and runtime observation approved and complete.** Changed boot、new PID、
low-angle startup candidate、debounce、exactly one real sleep request、wake and same-PID rearm are proven.
Open P0 = 0；Open P1 without disposition = 0。At Step 3 closure, Step 4 finish remained separately
approval-gated and observer artifacts remained intentionally installed. Step 4 was later approved and
completed in the following review; no rollback or push occurred.

## Task 7 Step 4 — Reboot finish and cleanup review

### Approval and boundary

The user separately approved `deployment-reboot-finish` with strict fail-stop semantics. The command
was allowed to remove temporary reboot artifacts only after changed boot、pre-login observer、installed
identity、new PID、health and operational baseline all passed. Reboot、disable、rollback and push were
explicitly prohibited.

### Root verifier evidence

```text
verified deployment-reboot-state boot-changed=true start=1785457249 current=1785491605
verified reboot-observer pre-login=true pid=281 boot-epoch=1785491605
verified deployment-acceptance stages=deployment-dry-run deployment-enabled-once deployment-recovery-resleep
operational_baseline=pass pid=281
accepted deployment-reboot-finish boot-changed=true pre-login=true mode=enabled pid=281
```

This proves the protected observer fields matched the current installed identity and hardware profile,
the observed daemon PID differed from prepared PID `99898`, and PID-bound health was armed at loginwindow.

### Bounded cleanup and final live state

Cleanup ran only after all root verification succeeded. Independent post-command evidence confirmed:

```text
mode/job/process: enabled / loaded / 1
current PID: 281
operational baseline: pass
reboot artifact count: 0
observer launchd job: absent
crash: count 0 / circuit closed / runActive true
```

No production daemon restart or mode change occurred during finish. No reboot、disable、rollback or push
occurred.

### Decision

**Task 7 Step 4 approved and complete.** Changed boot、pre-login auto-start、new PID、low-angle startup
sleep, exact identity, health, baseline and temporary cleanup are all proven. Open P0 = 0；Open P1
without disposition = 0。Step 5 Milestone holistic closure remains open and separately governed.
