# Milestone 17 — 低角度啟動睡眠恢復 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修正所有 auto-sleep composition 在啟動時已處於 `<=68` 角度卻永久 disarmed 的漏洞，並以完整新 identity acceptance 與低角度 reboot/loginwindow evidence 部署到 production。

**Architecture:** 在共用 `LidSleepStateMachine` 新增獨立 `startupClosedCandidate`，沿用既有 close debounce scheduler，不增加輪詢或 composition-specific policy。Repository implementation 先在 isolated worktree 以 TDD 完成；production upgrade、真實睡眠、activate 與 reboot 分開批准。

**Tech Stack:** Swift 6、XCTest、IOHID、IOKit power management、system LaunchDaemon、Bash management scripts、Git worktree。

## Global Constraints

- Runtime defaults 保持 `68 / 75 / 2 / 5 / 15`。
- 所有 auto-sleep composition 共用同一 startup state-machine policy。
- 純診斷模式不建立 auto-sleep coordinator，行為不變。
- `69...74`、missing、invalid、stale data 必須 fail-open。
- Startup candidate 使用既有 close debounce task，不新增第四個 scheduler 或 polling loop。
- Sleep request failure 不自動重試，轉為 disarmed。
- 任何 production upgrade、真實睡眠、activate、reboot、rollback 或 uninstall 都需要獨立批准。
- Repository implementation 不得改變目前 live production state。

---

### Task 1: 建立 startup-closed RED 契約

**Files:**
- Modify: `Tests/LidMonitorTests/LidSleepStateMachineTests.swift`
- Modify: `Tests/LidMonitorTests/LidSleepCoordinatorTests.swift`

**Interfaces:**
- Consumes: 既有 `LidSleepStateMachine.handle(_:)`、`LidSleepCoordinator` 與 manual scheduler fixtures。
- Produces: startup closed state/effect 的 failing executable contract，供 Task 2 實作。

- [x] **Step 1: 新增 state-machine RED tests**

新增明確測試，預期 API 為：

```swift
case startupClosedCandidate(deadline: Date)
```

並覆蓋：fresh closed startup 建立 candidate、deadline request once、hysteresis cancellation
disarms、reopen cancellation opens、invalid/stale fail-open。

- [x] **Step 2: 新增 coordinator RED tests**

驗證 startup cooldown 後排程 close debounce、transition 為
`.startupClosedCandidateStarted`，並在 deadline 只呼叫 requester 一次。

- [x] **Step 3: 執行 focused tests 證明 RED**

```bash
swift test --filter LidSleepStateMachineTests
swift test --filter LidSleepCoordinatorTests
```

Expected: compile 或 assertion failure，原因只指向缺少 startup closed contract；既有 unrelated
tests 不得失敗。

- [x] **Step 4: Task-level RED review**

記錄失敗名稱、失敗原因、無 production mutation，以及 Open P0/P1 disposition。

- [x] **Step 5: Commit**

```bash
git add Tests/LidMonitorTests/LidSleepStateMachineTests.swift \
        Tests/LidMonitorTests/LidSleepCoordinatorTests.swift \
        docs/superpowers/reviews/2026-07-31-low-angle-startup-sleep-recovery-task-reviews.md
git commit -m "test: define low-angle startup sleep contract"
```

### Task 2: 實作共用 startup closed state machine

**Files:**
- Modify: `Sources/LidMonitorCore/LidSleepStateMachine.swift`
- Modify: `Sources/LidMonitorCore/LidSleepCoordinator.swift`
- Modify: `Sources/LidMonitorCore/SleepRequester.swift`
- Modify: `Sources/LidMonitorCore/OutputFormatter.swift`
- Modify: `Sources/LidMonitorCore/Production/ProductionDaemonApplication.swift`
- Test: `Tests/LidMonitorTests/LidSleepStateMachineTests.swift`
- Test: `Tests/LidMonitorTests/LidSleepCoordinatorTests.swift`
- Test: `Tests/LidMonitorTests/OutputFormatterTests.swift`
- Test: `Tests/LidMonitorTests/ProductionDaemonCompositionTests.swift`

**Interfaces:**
- Consumes: Task 1 failing contract；既有 `scheduleCloseDebounce(deadline:)` 與 `cancelCloseDebounce` effects。
- Produces: `.startupClosedCandidate(deadline:)` 與穩定 transition event，不改 requester interface。

- [x] **Step 1: 新增 state 與 transition event**

State：

```swift
case startupClosedCandidate(deadline: Date)
```

Transition event：

```swift
case startupClosedCandidateStarted
case startupClosedCandidateCancelled
case startupClosedDebounceElapsed
```

- [x] **Step 2: 實作 startup cooldown classification**

在 `.startupCooldownElapsed(at:)` 依最新 sample freshness 與角度分類：`>=75` open、`<=68`
startup candidate、其餘 disarmed。

- [x] **Step 3: 實作 candidate cancellation 與 deadline**

`>=75` 取消並 open；`69...74` 或 invalid 取消並 disarm；fresh `<=68` deadline 只產生一次
`.requestSleep`；stale/missing fail-open。

- [x] **Step 4: Coordinator 映射共用 debounce task**

沿用 `closeDebounceTask`；新增 transition output，不新增 scheduler property。

- [x] **Step 5: 執行 focused GREEN tests**

```bash
swift test --filter LidSleepStateMachineTests
swift test --filter LidSleepCoordinatorTests
```

Expected: all selected tests pass。

- [x] **Step 6: Immediate implementation review**

檢查 ordinary close、wake recovery、sleep failure、stop cancellation 與 no-fourth-timer constraints。

- [x] **Step 7: Commit**

```bash
git add Sources/LidMonitorCore Tests/LidMonitorTests \
        docs/superpowers/reviews/2026-07-31-low-angle-startup-sleep-recovery-task-reviews.md
git commit -m "fix: sleep after closed low-angle startup"
```

### Task 3: 驗證所有 auto-sleep composition 共用規則

**Files:**
- Modify: `Tests/LidMonitorTests/AutoSleepIntegrationTests.swift`
- Modify: `Tests/LidMonitorTests/ProductionDaemonCompositionTests.swift`

**Interfaces:**
- Consumes: Task 2 shared coordinator behavior。
- Produces: dry-run、execute-sleep、production dry-run、production enabled 的 equivalence evidence。

- [x] **Step 1: 新增 foreground integration tests**

低角度 startup 必須在 cooldown + debounce 後：dry-run 一次 `would-sleep`；injected real requester
一次 request。

- [x] **Step 2: 新增 production composition tests**

驗證 production 不注入 startup policy override，兩種 production mode 只替換 requester effect。

- [x] **Step 3: 驗證 pure diagnostic boundary**

既有 list/watch parser 與 diagnostic tests 必須保持不建立 auto-sleep side effect。

- [x] **Step 4: 執行 focused composition tests**

```bash
swift test --filter AutoSleepIntegrationTests
swift test --filter ProductionDaemonCompositionTests
swift test --filter Diagnostic
```

- [x] **Step 5: Task-level review and commit**

```bash
git add Sources Tests docs/superpowers/reviews/2026-07-31-low-angle-startup-sleep-recovery-task-reviews.md
git commit -m "test: verify shared startup sleep composition"
```

### Task 4: 文件、事件與 package authority 同步

**Files:**
- Modify: `README.md`
- Modify: `docs/operations/production-daemon.md`
- Modify: relevant production event tests
- Create: `docs/validation/2026-07-31-low-angle-startup-sleep-repository-validation.md`

**Interfaces:**
- Consumes: Tasks 1–3 final behavior and stable transition names。
- Produces: README-first product semantics、中文 operator guidance、repository validation evidence。

- [x] **Step 1: 更新 README 第一入口**

說明低角度冷開機／daemon restart 會在約 7 秒安全延遲後睡眠；`69...74` 與 stale/invalid
仍 fail-open。

- [x] **Step 2: 更新正式中文操作手冊**

加入低角度 reboot 行為、驗收與 troubleshooting；不得暗示任意硬體支援。

- [x] **Step 3: 更新 event contract tests**

驗證新 transition name 穩定、redacted，且無 raw angle per-report production logging。

- [x] **Step 4: 執行 focused docs/event tests**

```bash
swift test --filter ProductionEventTests
swift test --filter ProductionManagementScriptTests/testProductionRunbookDocumentsOnlyRealManagementCommandsAndStateSemantics
swift test --filter ProductionManagementScriptTests/testReadmePresentsProductionQuickStartBeforeForegroundDetails
```

- [x] **Step 5: Immediate review and commit**

```bash
git add README.md docs Tests
git commit -m "docs: document low-angle startup sleep recovery"
```

### Task 5: Repository holistic release gate

**Files:**
- Modify: `docs/superpowers/reviews/2026-07-31-low-angle-startup-sleep-recovery-task-reviews.md`
- Modify: `docs/superpowers/tasks/2026-07-31-low-angle-startup-sleep-recovery-tasks.md`
- Modify: repository validation evidence

**Interfaces:**
- Consumes: Tasks 1–4 commits。
- Produces: implementation-complete candidate commit；不改 production。

- [x] **Step 1: 執行 current checkout full suite**

```bash
swift test
swift build -c release --product macbook-lid-monitor
swift build -c release --product macbook-lid-monitor-daemon
```

- [x] **Step 2: 執行 package/static gates**

```bash
bash -n scripts/manage-production-daemon.sh scripts/lib/*.sh
shellcheck -x scripts/manage-production-daemon.sh scripts/lib/*.sh
./scripts/manage-production-daemon.sh prepare
./scripts/manage-production-daemon.sh verify
git diff --check
```

- [x] **Step 3: 執行 independent clean snapshot gate**

在 repository-controlled temporary clean snapshot 執行相同 full suite、release build 與 package
verification；不得讀取 uncommitted working-tree state。

- [x] **Step 4: Live read-only gate**

確認目前 production 仍是原 identity、enabled、running、single PID；不執行 sudo mutation。

- [x] **Step 5: Holistic repository review and commit**

Open P0 = 0、Open P1 without disposition = 0 後，提交 candidate closure。不得 push 或 upgrade，
除非使用者另行批准。

### Task 6: 新 identity production upgrade 與 bounded acceptance

**Approval:** 每個 mutation 子階段獨立批准。

**Files:**
- Modify: production system state through reviewed management commands
- Create: production validation evidence

- [x] **Step 1: 批准並執行 verified package upgrade**

Upgrade 必須結束於 loaded/disabled/zero PID；舊 acceptance 因 payload identity 改變而失效。

- [x] **Step 2: 批准並執行 deployment dry-run acceptance**

在低角度 startup path 取得 candidate、debounce、一次 `would-sleep` evidence，最後 disabled。

- [x] **Step 3: 批准並執行 enabled-once acceptance**

真實 sleep request exactly once，完成後 disabled。此 step 因 dry-run cleanup 誤增 crash budget
曾被 blocked；Task 6R3 修復、重新部署、reset 與 dry-run revalidation 後已通過。

- [x] **Step 4: 批准並執行 recovery-resleep acceptance**

維持既有 exactly-two-attempt boundary，完成後 disabled。

- [x] **Step 5: Task review**

每個 acceptance identity 必須與新 installed source commit/version 完全一致。

### Task 6R: Maintenance bootout bounded-exit recovery

**Status:** complete and integrated；Task 6 production upgrade retry 已使用修復後 package 成功。

**Authority:**

```text
docs/superpowers/specs/2026-07-31-maintenance-bootout-bounded-exit-recovery-design.md
docs/superpowers/plans/2026-07-31-maintenance-bootout-bounded-exit-recovery.md
```

### Task 6R2: Acceptance clean-exit handoff recovery

**Status:** repository fix complete and integrated；production re-entry reached `99a51a4a2c45` but the
first dry-run exposed a second graceful-shutdown race. Superseded by Task 6R3.

**Authority:**

```text
docs/superpowers/specs/2026-07-31-acceptance-clean-exit-handoff-recovery-design.md
docs/superpowers/plans/2026-07-31-acceptance-clean-exit-handoff-recovery.md
```

Task 6R2 repository-only TDD 與 local-main ff-only integration 已完成；其 production incident
baseline 與 blocked 狀態屬歷史證據。後續第二個 graceful-shutdown race 由 Task 6R3 接管並完成
修復、部署與 acceptance。Task 6R2 不再擁有任何獨立 open production scope。

### Task 6R3: Graceful shutdown single-authority recovery

**Status:** complete、integrated、deployed and production-accepted；activation/reboot remain separate gates。

**Authority:**

```text
docs/superpowers/specs/2026-07-31-graceful-shutdown-single-authority-recovery-design.md
docs/superpowers/plans/2026-07-31-graceful-shutdown-single-authority-recovery.md
docs/validation/2026-07-31-graceful-shutdown-single-authority-recovery.md
```

Task 6R3 adds an independent true double-SIGTERM child contract, guards signal-handler completion, and
removes the overlapping management `stop_job` authority. Repository gates pass at 98 management tests
and 299 full tests. Final local-main identity `7bf98ff6ceae` was deployed; crash state was explicitly reset;
dry-run、enabled-once、recovery-resleep acceptance all passed for the same identity. Final production state
is loaded／disabled／zero PID、crash count 0、circuit closed、runActive false. No activate、reboot or push。

### Task 7: Persistent activation 與低角度 reboot/loginwindow acceptance

**Approval:** `activate`、reboot preparation、使用者手動 reboot、finish 各自獨立批准。

- [x] **Step 1: Persistent activation**

驗證 complete matching acceptance，activate 後 single PID、monitoring-armed、baseline pass。

2026-07-31 已完成：installed identity `7bf98ff6ceae` 的三階段 acceptance 驗證通過；
`activate` 成功後 PID `99898` 進入 `monitoring-armed`，`operational_baseline=pass`。最終保持
enabled／loaded／single PID、crash count 0。Step 1 完成當時 reboot observer 尚未建立；Step 2 隨後已另行批准並完成 arm。未 reboot、未 push。

- [x] **Step 2: Arm low-angle reboot observer**

記錄 boot epoch、PID、identity；observer 必須 one-shot、root-owned、bounded cleanup。

2026-07-31 已完成：以目前 enabled production PID `99898`、boot epoch `1785457249` 與
installed identity `7bf98ff6ceae` 建立 deployment reboot state。Observer script／LaunchDaemon
分別為 root:wheel `0700`／`0644`；state 與 initial observer evidence 為 root:wheel `0600`。
Observer LaunchDaemon 已在目前 boot 執行一次並正常退出（runs=1、last exit code=0），保留為
下一次開機的 RunAtLoad one-shot。Production 在 arm 前後均為 enabled／loaded／single PID，
`operational_baseline=pass`。未 reboot、未 finish、未 rollback、未 push。

- [x] **Step 3: 使用者在上蓋 `<=68` 時手動重新啟動**

停留 loginwindow，等待 startup cooldown + debounce + bounded observation window。

2026-07-31 已完成手動 reboot 與低角度 runtime observation：boot epoch 從 `1785457249`
變為 `1785491605`，production PID 從 `99898` 變為 `281`。新 PID 在登入前啟動後依序記錄
`startup-closed-candidate`、`startup-closed-debounce-elapsed`、一次
`sleep-request-attempted`／`sleep-requested`；`pmset` 隨後記錄 17:54:05 的 keyboard/trackpad
wake。開蓋後同一 PID 回到 `monitoring-armed`。Observer evidence mtime 更新至 17:54:07，
但受保護 plist 的 pre-login console user、identity 與 PID 綁定仍由 Step 4 root verifier 驗證。

- [x] **Step 4: Finish and verify**

changed boot、new PID、pre-login daemon、startup-closed candidate、一次 sleep request、reopen recovery、
baseline pass、temporary observer cleanup。

2026-07-31 已完成：root verifier 確認 reboot state 從 boot epoch `1785457249` 變為
`1785491605`，observer evidence 為 `pre-login=true`、PID `281`，且 installed identity、完整
deployment acceptance、monitoring health 與 PID 綁定全部相符。`operational_baseline=pass`
後才執行 bounded cleanup；deployment reboot state、observer evidence、observer executable、
observer plist 與 launchd job 均為 absent。Production 最終保持 enabled／loaded／single PID
`281`、crash count 0。未 reboot、未 disable、未 rollback、未 push。

- [ ] **Step 5: Milestone holistic closure**

同步 README/runbook/validation/reviews/task register；current checkout 與 clean snapshot gates 重新
通過；production 最終 enabled/running；取得 push 批准後 push。

### Task 7R: README deployment-state contract synchronization

**Status:** complete；Task 7 Step 5 re-entry unblocked，但 Step 5 本身仍 open。

2026-07-31 第一次 Step 5 current-checkout full suite 在
`testReadmePresentsProductionQuickStartBeforeForegroundDetails` fail-stop：測試仍要求候選階段的
`Milestone 17 候選版本` 與 `尚未部署到目前正式常駐服務`，但 README 已依 Steps 1–4 的正式
evidence 正確更新為 identity `7bf98ff6ceae` 已部署、persistent activation 與低角度
reboot/loginwindow proof 已完成。

Task 7R 先重現 focused RED（1 test、2 assertions），再只修改
`Tests/LidMonitorTests/ProductionManagementScriptTests.swift` 的 README required-text contract，改為
鎖定 deployed identity、identity-bound acceptance、persistent activation、reboot/loginwindow 真機
驗收，以及僅剩 holistic closure 與未批准 push。README、runtime source、scripts、packaging 與
production state均未修改。

驗證結果：focused GREEN 1/1；完整 suite 299 tests、1 child-only skip、0 failures，其中
ProductionManagementScriptTests 98/98。Open P0 = 0；Open P1 without disposition = 0。


### Task 7R2: macOS diagnostics process-metric compatibility

**Status:** complete；Task 7 Step 5 re-entry unblocked again，但 Step 5 本身仍 open。

2026-07-31 第二次 Step 5 已通過 current checkout 與 independent clean snapshot 的完整 repository
gates，但在最後 live read-only gate 依 fail-stop 規則停止：`status` 成功，`diagnostics` 回傳 1，
因此 `operational-baseline` 未執行。Root cause 是 production observability 使用 macOS `ps` 不支援的
`etimes` 欄位；sandbox tests 以 `MLM_TEST_PROCESS_METRICS` 注入值，未覆蓋真實 `ps` contract。

Task 7R2 新增不注入 metrics fixture、以真實 `/bin/sleep` 子進程 PID 執行 `diagnostics` 的 focused
contract。RED 精確為 diagnostics rc 1；最小 GREEN 僅將 `ps -o etimes=` 改為 macOS 支援的
`ps -o etime=`，仍輸出 parser-friendly `elapsed=... cpu=... rss=... vsz=...`。未修改 daemon
sleep policy、README、packaging 或 production installed payload。

驗證結果：focused GREEN 1/1；current checkout 與 independent clean snapshot 均為 300 tests、
1 child-only skip、0 failures，其中 ProductionManagementScriptTests 99/99；兩邊 release、bash -n、
shellcheck、package prepare/verify 與 diff gates 全部通過。Live read-only diagnostics 對 PID `281`
回傳 rc 0 與有效 metrics；前後 production enabled／loaded／single PID、crash clean、artifact count 0，
Git candidate diff SHA 不變。Open P0 = 0；Open P1 without disposition = 0。
