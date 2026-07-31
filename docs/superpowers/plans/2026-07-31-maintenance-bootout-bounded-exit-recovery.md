# Task 6R — Maintenance bootout bounded-exit recovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在不強殺 daemon、不中斷 transaction safety boundary 的前提下，讓 production maintenance 在 `launchctl bootout` 後有上限地等待 resident daemon 真正退出。

**Architecture:** 在現有 management script 內加入精確 resident probe 與 50 × 100 ms bounded wait，並讓 `prepare_maintenance_disabled_state` 在任何 backup、acceptance invalidation 或 payload replacement 前等待 zero PID。Sandbox 透過只在 `MLM_TEST_ROOT` 生效的 deterministic remaining-probes hook 驗證 delayed exit 與 timeout；production 永遠使用精確 `pgrep`。

**Tech Stack:** Bash 3.2 compatible shell、Swift 6 XCTest、launchctl、pgrep、Git worktree。

## Global Constraints

- Production path 最多等待約 5 秒：50 個 100 ms interval。
- Timeout return 70，不送 SIGKILL、不無限重試。
- Test hook 只在 `MLM_TEST_ROOT` 非空時生效。
- Timeout 必須早於 rollback backup、acceptance invalidation 與 payload replacement。
- Task 6R 全程不得使用 sudo 或修改 live production。
- Live production 必須維持舊 identity／disabled／job absent／zero PID。

---

### Task 6R-1: 建立 delayed-exit 與 timeout RED contract

**Files:**
- Modify: `Tests/LidMonitorTests/ProductionManagementScriptTests.swift`
- Modify: `docs/superpowers/reviews/2026-07-31-low-angle-startup-sleep-recovery-task-reviews.md`

**Interfaces:**
- Consumes: `runScriptResult(_:environment:)`、sandbox `MLM_TEST_ROOT`、既有 `upgrade` transaction。
- Produces: `MLM_TEST_RESIDENT_DAEMON_PROBES` failing contract，以及穩定 timeout message contract。

- [x] **Step 1: 新增 delayed-exit RED test**

加入 `testUpgradeWaitsForResidentDaemonToExitBeforeReplacingPayload`：

```swift
let output = try runScriptOutput(
    "upgrade",
    environment: [
        "MLM_TEST_ROOT": sandbox.path,
        "MLM_TEST_RESIDENT_DAEMON_PROBES": "2",
    ]
)
XCTAssertTrue(output.contains("daemon-exit-wait=pass probes=3"), output)
XCTAssertEqual(try Data(contentsOf: installedBinary), try Data(contentsOf: stagedBinary))
```

- [x] **Step 2: 新增 timeout RED test**

加入 `testUpgradeFailsBeforePayloadReplacementWhenResidentDaemonExitTimesOut`，使用 51 個 resident
probe，要求：

```swift
XCTAssertEqual(result.status, 70)
XCTAssertTrue(result.output.contains("error: timed out waiting for resident daemon exit"))
XCTAssertEqual(try Data(contentsOf: installedBinary), oldBinary)
XCTAssertEqual(try Data(contentsOf: installedManifest), oldManifest)
XCTAssertTrue(FileManager.default.fileExists(atPath: acceptance.path))
XCTAssertEqual(decodedConfig.mode, .disabled)
XCTAssertFalse(FileManager.default.fileExists(atPath: rollback.path))
```

- [x] **Step 3: 新增 sandbox-only hook contract**

加入 source contract，要求 production branch 仍直接使用 exact `pgrep`，而
`MLM_TEST_RESIDENT_DAEMON_PROBES` 只存在於 `SYSTEM_ROOT` 非空分支。

- [x] **Step 4: 執行 focused RED**

```bash
swift test --filter ProductionManagementScriptTests/testUpgradeWaitsForResidentDaemonToExitBeforeReplacingPayload
swift test --filter ProductionManagementScriptTests/testUpgradeFailsBeforePayloadReplacementWhenResidentDaemonExitTimesOut
swift test --filter ProductionManagementScriptTests/testMaintenanceResidentProbeHookIsSandboxOnly
```

Expected: delayed-exit／timeout tests 失敗，原因是 hook 與 bounded wait 尚不存在；unrelated test
不得失敗。

- [x] **Step 5: Immediate RED review and commit**

```bash
git add Tests/LidMonitorTests/ProductionManagementScriptTests.swift \
        docs/superpowers/reviews/2026-07-31-low-angle-startup-sleep-recovery-task-reviews.md
git commit -m "test: define bounded maintenance exit contract"
```

### Task 6R-2: 實作 bounded resident-process wait

**Files:**
- Modify: `scripts/manage-production-daemon.sh`
- Test: `Tests/LidMonitorTests/ProductionManagementScriptTests.swift`
- Modify: `docs/superpowers/reviews/2026-07-31-low-angle-startup-sleep-recovery-task-reviews.md`

**Interfaces:**
- Consumes: `SYSTEM_ROOT`、`MLM_TEST_RESIDENT_DAEMON_PROBES`、exact daemon path probe。
- Produces: `managed_daemon_is_resident()` 與 `wait_for_managed_daemon_exit()`；成功輸出 `daemon-exit-wait=pass probes=N`，timeout return 70。

- [x] **Step 1: 加入 sandbox-only deterministic probe**

在 script 初始化 test counter：

```bash
TEST_RESIDENT_DAEMON_PROBES_REMAINING="${MLM_TEST_RESIDENT_DAEMON_PROBES:-0}"
```

`managed_daemon_is_resident` 在 sandbox 中驗證 non-negative integer，remaining > 0 時遞減並
return 0，否則 return 1；真實系統忽略 hook 並執行 exact `pgrep`。

- [x] **Step 2: 加入 5-second bounded wait**

```bash
wait_for_managed_daemon_exit() {
    local waits=0 probes=0
    while true; do
        probes=$((probes + 1))
        if ! managed_daemon_is_resident; then
            printf 'daemon-exit-wait=pass probes=%s\n' "$probes"
            return 0
        fi
        if [[ "$waits" -ge 50 ]]; then
            printf 'error: timed out waiting for resident daemon exit\n' >&2
            return 70
        fi
        waits=$((waits + 1))
        if [[ -z "$SYSTEM_ROOT" ]]; then /bin/sleep 0.1; fi
    done
}
```

- [x] **Step 3: Wire maintenance boundary**

將 `prepare_maintenance_disabled_state` 的 immediate `pgrep` block 替換為：

```bash
bootout_job
wait_for_managed_daemon_exit
printf 'maintenance-state mode=disabled job=booted-out process-count=0\n'
```

- [x] **Step 4: 執行 focused GREEN**

```bash
swift test --filter ProductionManagementScriptTests/testUpgradeWaitsForResidentDaemonToExitBeforeReplacingPayload
swift test --filter ProductionManagementScriptTests/testUpgradeFailsBeforePayloadReplacementWhenResidentDaemonExitTimesOut
swift test --filter ProductionManagementScriptTests/testMaintenanceResidentProbeHookIsSandboxOnly
swift test --filter ProductionManagementScriptTests/testUpgrade
swift test --filter ProductionManagementScriptTests/testExplicitRollback
swift test --filter ProductionManagementScriptTests/testUninstall
```

- [x] **Step 5: Static verification**

```bash
bash -n scripts/manage-production-daemon.sh scripts/lib/*.sh
shellcheck -x scripts/manage-production-daemon.sh scripts/lib/*.sh
```

- [x] **Step 6: Immediate implementation review and commit**

確認 5 秒上限、no kill、production hook isolation、timeout-before-replacement 與 upgrade／rollback／
uninstall shared boundary。

```bash
git add scripts/manage-production-daemon.sh \
        docs/superpowers/reviews/2026-07-31-low-angle-startup-sleep-recovery-task-reviews.md
git commit -m "fix: wait for maintenance daemon exit"
```

### Task 6R-3: Holistic repository gate and Task 6 re-entry authority

**Files:**
- Modify: `docs/superpowers/plans/2026-07-31-low-angle-startup-sleep-recovery.md`
- Modify: `docs/superpowers/tasks/2026-07-31-low-angle-startup-sleep-recovery-tasks.md`
- Modify: `docs/superpowers/reviews/2026-07-31-low-angle-startup-sleep-recovery-task-reviews.md`
- Create: `docs/validation/2026-07-31-maintenance-bootout-bounded-exit-recovery.md`

**Interfaces:**
- Consumes: Task 6R-1/2 commits and focused evidence。
- Produces: final recovery candidate identity、Task 6 blocked→ready transition；不進行 production upgrade。

- [ ] **Step 1: 執行 full management and Swift gates**

```bash
swift test --filter ProductionManagementScriptTests
swift test
swift build -c release --product macbook-lid-monitor
swift build -c release --product macbook-lid-monitor-daemon
```

- [ ] **Step 2: 執行 static/package gates**

```bash
bash -n scripts/manage-production-daemon.sh scripts/lib/*.sh
shellcheck -x scripts/manage-production-daemon.sh scripts/lib/*.sh
./scripts/manage-production-daemon.sh prepare
./scripts/manage-production-daemon.sh verify
git diff --check
```

- [ ] **Step 3: Live production read-only verification**

確認仍為 old identity、mode disabled、job absent、zero PID；不得 sudo 或 bootstrap。

- [ ] **Step 4: Holistic review and docs synchronization**

記錄 RED/GREEN、90-test/full-suite、static/package、production unchanged evidence；Task 6R complete，
Task 6 upgrade 回到 open 但必須使用新的 final-main package 並重新取得批准。

- [ ] **Step 5: Commit recovery closure**

```bash
git add docs/superpowers docs/validation
git commit -m "docs: close bounded maintenance exit recovery"
```

- [ ] **Step 6: Integrate to local main only after review**

使用 fast-forward integration；不得 push。整合後從 final main 再執行一次 repository-only
`prepare`／`verify`，並將新的 package identity 提交給使用者批准 production upgrade。
