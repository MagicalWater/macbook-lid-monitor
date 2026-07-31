# Task 6R2 — Acceptance clean-exit handoff recovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 讓 Task 13 bounded deployment acceptance 在 bootstrap disabled daemon 前，有上限地等待舊 daemon 完成 PID exit 與 crash-budget clean-exit persistence。

**Architecture:** 在 management script 增加 production crash-budget clean-state probe、50 × 100 ms bounded wait 與共用 acceptance handoff state machine。Dry-run、enabled-once、recovery-resleep 的正常成功路徑和 EXIT trap 都改用同一 helper；任何 timeout 都禁止 bootstrap 與 acceptance recording。

**Tech Stack:** Bash 3.2 compatible shell、Swift 6 XCTest、launchctl、pgrep、Python 3 JSON validation、Git worktree。

## Global Constraints

- Scope 只包含 Task 13 dry-run、enabled-once、recovery-resleep 與其 failure cleanup。
- 先等待 resident PID exit，再等待 crash-budget `runActive=false`。
- 每個 wait 最多 50 × 100 ms，約 5 秒。
- Timeout return 70；不得 SIGKILL、不得 reset crash budget、不得 bootstrap。
- `MLM_TEST_CLEAN_EXIT_ACTIVE_PROBES` 只在 `MLM_TEST_ROOT` 非空時生效。
- Task 6R2 全程不得修改 `/Library`、launchd、acceptance 或 crash budget。
- Live production 必須維持 identity `93d9881ecddb`、loaded／disabled／zero PID、dry-run pass、crash count 1 closed。
- 不得重跑 dry-run、開始 enabled-once、執行真實睡眠、activate、reboot、rollback 或 push。

---

### Task 6R2-1: 建立 clean-exit handoff RED contracts

**Files:**
- Modify: `Tests/LidMonitorTests/ProductionManagementScriptTests.swift`
- Modify: `docs/superpowers/reviews/2026-07-31-low-angle-startup-sleep-recovery-task-reviews.md`

**Interfaces:**
- Consumes: existing Task 13 sandbox acceptance commands、`runScriptResult`、Task 6R `wait_for_managed_daemon_exit`。
- Produces: failing contract for `MLM_TEST_CLEAN_EXIT_ACTIVE_PROBES`、ordered handoff、timeout no-bootstrap、shared Task 13 cleanup。

- [ ] **Step 1: 新增 delayed clean-exit RED test**

新增：

```swift
func testTask13DryRunCleanupWaitsForCleanExitBeforeBootstrapAndPreservesCrashCount() throws
```

Setup：install/bootstrap sandbox，建立：

```json
{"unexpectedExitTimes":[1000.0],"circuitOpen":false,"runActive":false}
```

執行：

```swift
let output = try runScriptOutput(
    "accept-task13-dry-run-path",
    environment: [
        "MLM_TEST_ROOT": sandbox.path,
        "MLM_TEST_CLEAN_EXIT_ACTIVE_PROBES": "2",
    ]
)
```

要求 verified evidence 之後依序出現：

```text
stopped
booted-out
daemon-exit-wait=pass
clean-exit-wait=pass probes=3
bootstrapped
```

並要求 crash-budget file bytes 完全不變。

- [ ] **Step 2: 新增 clean-state timeout RED test**

新增：

```swift
func testDeploymentDryRunCleanExitTimeoutDoesNotBootstrapOrRecordAcceptance() throws
```

以 `MLM_TEST_CLEAN_EXIT_ACTIVE_PROBES=51` 執行 `deployment-dry-run`，要求：

```swift
XCTAssertEqual(result.status, 70)
XCTAssertTrue(result.output.contains("error: timed out waiting for crash-budget clean exit"))
XCTAssertFalse(FileManager.default.fileExists(atPath: acceptance.path))
XCTAssertEqual(decodedConfig.mode, .disabled)
```

並截取 timeout message 後的 suffix，要求不包含 `bootstrapped label=` 或
`recorded deployment-acceptance`。

- [ ] **Step 3: 新增 failure-trap RED test**

新增：

```swift
func testTask13FailureTrapUsesBoundedCleanExitHandoff() throws
```

使用：

```swift
"MLM_TEST_DEPLOYMENT_FAIL_STAGE": "dry-run",
"MLM_TEST_CLEAN_EXIT_ACTIVE_PROBES": "2"
```

要求原始 injected failure 保留、trap 輸出 `clean-exit-wait=pass probes=3`、mode disabled，且
不建立 acceptance。

- [ ] **Step 4: 新增 shared-scope 與 hook-isolation RED contract**

新增 source contract，要求：

- 三個 Task 13 acceptance success path 呼叫 `restore_disabled_job_after_acceptance`；
- 三個 EXIT trap 呼叫 `cleanup_acceptance_to_disabled`；
- `MLM_TEST_CLEAN_EXIT_ACTIVE_PROBES` 位於 `SYSTEM_ROOT` branch；
- production branch 使用真實 crash-budget JSON，不接受 environment override。

- [ ] **Step 5: 執行 focused RED**

```bash
swift test --filter ProductionManagementScriptTests/testTask13DryRunCleanupWaitsForCleanExitBeforeBootstrapAndPreservesCrashCount
swift test --filter ProductionManagementScriptTests/testDeploymentDryRunCleanExitTimeoutDoesNotBootstrapOrRecordAcceptance
swift test --filter ProductionManagementScriptTests/testTask13FailureTrapUsesBoundedCleanExitHandoff
swift test --filter ProductionManagementScriptTests/testTask13AcceptanceCleanupUsesSharedSandboxIsolatedHandoff
```

Expected：全部因 helper、hook、ordered wait 或 timeout semantics 尚不存在而失敗；unrelated
failure = 0。

- [ ] **Step 6: Immediate RED review and commit**

```bash
git add Tests/LidMonitorTests/ProductionManagementScriptTests.swift \
        docs/superpowers/reviews/2026-07-31-low-angle-startup-sleep-recovery-task-reviews.md
git commit -m "test: define acceptance clean-exit handoff contract"
```

### Task 6R2-2: 實作 shared bounded clean-exit handoff

**Files:**
- Modify: `scripts/manage-production-daemon.sh`
- Test: `Tests/LidMonitorTests/ProductionManagementScriptTests.swift`
- Modify: `docs/superpowers/reviews/2026-07-31-low-angle-startup-sleep-recovery-task-reviews.md`

**Interfaces:**
- Consumes: `wait_for_managed_daemon_exit()`、`MANAGED_SUPPORT/crash-budget.json`、Task 6R2 RED contract。
- Produces: `crash_budget_clean_exit_persisted()`、`wait_for_crash_budget_clean_exit()`、`restore_disabled_job_after_acceptance()`、`cleanup_acceptance_to_disabled()`。

- [ ] **Step 1: 建立 sandbox-only clean-state probe counter**

在 script 初始化：

```bash
TEST_CLEAN_EXIT_ACTIVE_PROBES_REMAINING="${MLM_TEST_CLEAN_EXIT_ACTIVE_PROBES:-0}"
ACCEPTANCE_HANDOFF_STATE=idle
```

Sandbox branch 驗證 non-negative integer；remaining > 0 時遞減並 return 1，歸零後 return 0。

- [ ] **Step 2: 實作 production crash-budget clean-state probe**

`crash_budget_clean_exit_persisted` 的 production branch 使用 `/usr/bin/python3` 讀取：

```text
$MANAGED_SUPPORT/crash-budget.json
```

驗證 `unexpectedExitTimes` 是 array、`circuitOpen` 與 `runActive` 是 boolean。Return contract：

```text
0 = runActive false
1 = runActive true
65 = missing, symlink, malformed or schema-invalid
```

不得寫回 JSON。

- [ ] **Step 3: 實作 5-second clean-state bounded wait**

```bash
wait_for_crash_budget_clean_exit() {
    local waits=0 probes=0 probe_status
    while true; do
        probes="$((probes + 1))"
        if crash_budget_clean_exit_persisted; then
            probe_status=0
        else
            probe_status=$?
        fi
        if [[ "$probe_status" -eq 0 ]]; then
            printf 'clean-exit-wait=pass probes=%s\n' "$probes"
            return 0
        fi
        [[ "$probe_status" -eq 1 ]] || return "$probe_status"
        if [[ "$waits" -ge 50 ]]; then
            printf 'error: timed out waiting for crash-budget clean exit\n' >&2
            return 70
        fi
        waits="$((waits + 1))"
        if [[ -z "$SYSTEM_ROOT" ]]; then /bin/sleep 0.1; fi
    done
}
```

- [ ] **Step 4: 實作 shared handoff state machine**

`restore_disabled_job_after_acceptance`：

```text
state=waiting
set_managed_mode disabled
stop_job
bootout_job
wait_for_managed_daemon_exit
wait_for_crash_budget_clean_exit
bootstrap_job
state=complete
```

任何 command failure 都保存原 status、設 `state=failed` 並 return；bootstrap 不能出現在任一
wait 前。

`cleanup_acceptance_to_disabled`：

```text
complete → no-op
idle → call full restore helper
waiting/failed → set disabled + stop + bootout only, never bootstrap
```

Trap 必須 return 0，不能覆蓋原始 command failure。

- [ ] **Step 5: Wire three Task 13 acceptance paths**

在 dry-run、enabled-once、recovery-resleep：

- nested EXIT cleanup 改為 `cleanup_acceptance_to_disabled`；
- success triplet 改為 `restore_disabled_job_after_acceptance`；
- diagnostics 只在 successful restore 後執行；
- `trap - EXIT` 只在 restore success 後解除。

- [ ] **Step 6: 執行 focused GREEN and regression**

```bash
swift test --filter ProductionManagementScriptTests/testTask13DryRunCleanupWaitsForCleanExitBeforeBootstrapAndPreservesCrashCount
swift test --filter ProductionManagementScriptTests/testDeploymentDryRunCleanExitTimeoutDoesNotBootstrapOrRecordAcceptance
swift test --filter ProductionManagementScriptTests/testTask13FailureTrapUsesBoundedCleanExitHandoff
swift test --filter ProductionManagementScriptTests/testTask13AcceptanceCleanupUsesSharedSandboxIsolatedHandoff
swift test --filter ProductionManagementScriptTests/testTask13
swift test --filter ProductionManagementScriptTests/testBoundedDeployment
swift test --filter ProductionManagementScriptTests/testUpgradeWaitsForResidentDaemonToExitBeforeReplacingPayload
```

- [ ] **Step 7: Static verification**

```bash
bash -n scripts/manage-production-daemon.sh scripts/lib/*.sh
shellcheck -x scripts/manage-production-daemon.sh scripts/lib/*.sh
git diff --check
```

- [ ] **Step 8: Immediate implementation review and commit**

確認 ordered handoff、preserved crash count、failed-state no-rebootstrap、sandbox hook isolation 與
no production mutation。

```bash
git add scripts/manage-production-daemon.sh \
        docs/superpowers/reviews/2026-07-31-low-angle-startup-sleep-recovery-task-reviews.md
git commit -m "fix: wait for acceptance clean-exit handoff"
```

### Task 6R2-3: Holistic repository gate and deployment re-entry authority

**Files:**
- Modify: `docs/superpowers/plans/2026-07-31-acceptance-clean-exit-handoff-recovery.md`
- Modify: `docs/superpowers/plans/2026-07-31-low-angle-startup-sleep-recovery.md`
- Modify: `docs/superpowers/tasks/2026-07-31-low-angle-startup-sleep-recovery-tasks.md`
- Modify: `docs/superpowers/reviews/2026-07-31-low-angle-startup-sleep-recovery-task-reviews.md`
- Create: `docs/validation/2026-07-31-acceptance-clean-exit-handoff-recovery.md`

**Interfaces:**
- Consumes: Task 6R2 RED/GREEN commits and current production read-only evidence。
- Produces: final repository candidate、new package identity、separate approval boundary for production upgrade/reset/revalidation；不執行任何 production mutation。

- [ ] **Step 1: 執行 holistic management and Swift gates**

```bash
swift test --filter ProductionManagementScriptTests
swift test
swift build -c release --product macbook-lid-monitor
swift build -c release --product macbook-lid-monitor-daemon
```

- [ ] **Step 2: 執行 static and package gates**

```bash
bash -n scripts/manage-production-daemon.sh scripts/lib/*.sh
shellcheck -x scripts/manage-production-daemon.sh scripts/lib/*.sh
./scripts/manage-production-daemon.sh prepare
./scripts/manage-production-daemon.sh verify
git diff --check
```

- [ ] **Step 3: Live production read-only verification**

確認：

```text
identity=93d9881ecddb
mode=disabled
job=loaded
process-count=0
deployment-dry-run=pass
crash-count=1
circuit=closed
runActive=false
```

不得 sudo mutation 或 reset。

- [ ] **Step 4: Holistic review and validation authority**

記錄 baseline、RED/GREEN、timeout、crash-count preservation、full suites、release/static/package、
production unchanged。Task 6 enabled-once 仍 blocked，直到新的 final-main package 經 separate
upgrade、crash-budget reset 與 dry-run revalidation approvals。

- [ ] **Step 5: Commit Task 6R2 closure**

```bash
git add docs/superpowers docs/validation
git commit -m "docs: close acceptance clean-exit handoff recovery"
```

- [ ] **Step 6: Local-main integration only after complete review**

使用 ff-only integration；不得 push。整合後在 final main fresh tree 重跑 full suite，重新
prepare/verify package，並提交新的 production mutation approval wording。

