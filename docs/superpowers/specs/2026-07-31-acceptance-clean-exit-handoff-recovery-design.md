# Task 6R2 — Acceptance clean-exit handoff recovery design

日期：2026-07-31
狀態：已核准執行

## Incident authority

Milestone 17 Task 6 的 `deployment-dry-run` 已對 installed identity
`93d9881ecddb` 成功取得：

```text
candidate-started
debounce-elapsed
sleep-request-attempted
would-sleep
accepted task=13 scope=dry-run-path final-mode=disabled
recorded deployment-acceptance stage=deployment-dry-run result=pass
```

Acceptance 結束後 production 穩定為 loaded／disabled／zero PID，但 crash budget 從 0
增加為 1：

```json
{"runActive":false,"unexpectedExitTimes":[1785469472.31077],"circuitOpen":false}
```

同一秒的 production event chain 為：

```text
PID 9182 event=stopping reason=signal
PID 9725 event=started mode=disabled
```

這證明 acceptance 行為本身通過，但 cleanup 在舊 daemon 完成 clean-exit persistence 前已
bootstrap 新 disabled daemon，讓新 daemon 的 `beginRun()` 將舊 `runActive=true` 誤判為一次
unexpected exit。

## Root cause

Task 13 bounded acceptance 的成功與 EXIT-trap cleanup 都重複使用：

```text
set mode disabled
→ SIGTERM old daemon
→ launchctl bootout
→ immediately bootstrap disabled daemon
```

`stop_job` 只送出 SIGTERM；`bootout_job` 也不保證 daemon 的 signal handler、
`ProductionDaemonSession.stop()` 與 `CrashBudget.recordCleanExit()` 已全部完成。新 daemon 若先
執行 `CrashBudget.beginRun()`，便會看到舊 run 仍 active 並增加 unexpected-exit count。

Task 6R 已提供 bounded resident-process wait，但 acceptance cleanup 尚未使用該 boundary，也
未驗證 crash-budget `runActive=false` 已落盤。

## Scope

本 Recovery Task 只處理 Milestone 17 Task 6 的 bounded deployment acceptance cleanup：

- `accept_task13_dry_run_path`
- `accept_task13_enabled_once`
- `accept_task13_recovery_resleep`
- 上述流程的 EXIT-trap failure cleanup

不在本 Task 內重構歷史 Task 12 acceptance、Task 17 reopen acceptance、daemon crash-budget
資料模型、activation、reboot、rollback 或 production reset command。

## Considered approaches

### A. Cleanup 中固定 sleep

固定延遲不能證明舊 PID 已退出或 clean-exit state 已落盤；不同機器與負載下仍會競態。
拒絕。

### B. 只等待 resident PID 消失

比固定 sleep 正確，且 process exit 正常應晚於 clean-exit write；但 completion contract 仍只
間接推論 crash state，無法在 corrupt、missing 或 delayed persistence 時提供明確 evidence。
不選為完整方案。

### C. Bounded PID exit + bounded clean-exit persistence — selected

先沿用 Task 6R 的 `wait_for_managed_daemon_exit`，再以 crash-budget authority 驗證
`runActive=false`。只有兩個 gate 都通過才 bootstrap disabled daemon。這直接鎖定真正的
handoff boundary，並能在 timeout 時保持 no-bootstrap fail-open。

### D. Cleanup 後自動 reset crash budget

只清除症狀，會掩蓋程序交接仍不正確；也違反目前「不得 reset crash budget」批准邊界。
拒絕。

## Design

### Shared handoff state

在 management script 建立 process-local handoff state：

```text
idle → waiting → complete
                 ↘ failed
```

- `idle`：acceptance 尚未開始 cleanup。
- `waiting`：已進入 disabled/stop/bootout/wait sequence。
- `complete`：PID exit、clean-exit persistence 與 disabled bootstrap 全部完成。
- `failed`：任何 bounded wait 或 bootstrap 失敗；EXIT trap 不得再次 bootstrap。

### Crash-budget clean-exit probe

新增單一責任 helper：

```bash
crash_budget_clean_exit_persisted
wait_for_crash_budget_clean_exit
```

Production probe 必須：

- 拒絕 symlink、missing、corrupt 或 schema-invalid crash-budget state；
- 只把 `runActive=false` 視為 clean-exit persistence 完成；
- 不修改 `unexpectedExitTimes`、`circuitOpen` 或任何 production state。

Sandbox 使用 deterministic remaining-active-probes hook；hook 僅在 `MLM_TEST_ROOT` 非空時
生效，production 必須永遠讀取真實 crash-budget JSON。

Wait 使用與 Task 6R 相同的 50 × 100 ms 上限，總等待約 5 秒；sandbox 不做 wall-clock
sleep。成功輸出：

```text
clean-exit-wait=pass probes=N
```

Timeout 穩定 return 70，不 reset、不強殺、不無限重試。

### Shared acceptance cleanup

新增：

```bash
restore_disabled_job_after_acceptance
cleanup_acceptance_to_disabled
```

成功順序固定為：

```text
set mode disabled
→ stop old daemon
→ bootout job
→ wait for zero resident PID
→ wait for crash-budget runActive=false
→ bootstrap disabled job
```

`restore_disabled_job_after_acceptance` 只在兩個 wait gate 都通過後執行 bootstrap。

`cleanup_acceptance_to_disabled` 作為 EXIT trap：

- state=`idle`：執行完整 shared cleanup；
- state=`complete`：no-op，避免重複 bootstrap；
- state=`failed`：只重申 mode disabled、stop／bootout，不重試 bootstrap；
- trap failure 不得覆蓋原始 command exit code。

三個 Task 13 acceptance 的正常成功路徑與 failure trap 必須共用同一 helper，不保留各自的
`disable → bootout → bootstrap` triplet。

## Failure semantics

若 resident PID timeout：

- mode 已是 disabled；
- job 已 booted out；
- 不 bootstrap 新 daemon；
- 不強殺 lingering process；
- return 70 並保留 residual-process evidence。

若 PID 已退出但 clean-exit persistence timeout：

- mode disabled；
- job booted out；
- zero resident PID；
- crash-budget state 原樣保留；
- 不 bootstrap、不 reset、return 70。

只有成功 handoff 才允許 command 回傳 acceptance pass 或記錄新的 deployment stage。

## Test strategy

新增 executable contracts：

1. Dry-run cleanup 模擬 clean-exit 經兩次 active probe 後落盤，必須在第三次 probe 才
   bootstrap，並保留原 unexpected-exit count。
2. Clean-exit persistence 超過 50 個 wait interval，`deployment-dry-run` 必須 return 70，
   不記錄 acceptance、不在 failure boundary 後 bootstrap。
3. Injected acceptance failure 的 EXIT trap 必須走相同 bounded handoff，成功時回復
   loaded／disabled，timeout 時保持 no-bootstrap safe stop。
4. Dry-run、enabled-once、recovery-resleep 的 source/executable contract 必須共用 helper。
5. Sandbox hook isolation、existing Task 6R wait、93-test management suite、full Swift suite、
   release/static/package gates 全部不回歸。

## Production boundary

Task 6R2 僅允許 repository mutation、tests、build、static check、package prepare/verify 與 live
read-only verification。不得：

- reset 現有 crash budget；
- 重跑 deployment-dry-run；
- 執行 enabled-once 或 recovery-resleep；
- 執行任何真實睡眠；
- activate、reboot、rollback、push；
- 修改 `/Library` 或 launchd state。

Task 6R2 執行期間 production 必須維持：

```text
installed identity = 93d9881ecddb
mode = disabled
job = loaded
process count = 0
deployment-dry-run acceptance = pass
crash count = 1, circuit closed, runActive=false
```

## Acceptance criteria

- Task 13 cleanup 不會在舊 daemon clean exit 完成前 bootstrap 新 disabled daemon。
- Unexpected-exit count 在成功 acceptance cleanup 中不得增加。
- Timeout 有固定約 5 秒上限，且 fail-open/no-bootstrap。
- Production path 不接受 deterministic test hook override。
- RED/GREEN、immediate reviews、management/full suites、release、bash syntax、shellcheck、package
  prepare/verify 與 `git diff --check` 全部通過。
- Open P0 = 0；Open P1 without disposition = 0。

