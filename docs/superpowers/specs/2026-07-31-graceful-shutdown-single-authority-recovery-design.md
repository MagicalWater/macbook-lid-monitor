# Task 6R3 — Graceful shutdown single-authority recovery design

日期：2026-07-31
狀態：使用者已核准完整執行

## Incident authority

Installed identity `99a51a4a2c45` 的 bounded `deployment-dry-run` 已完成核心 dry-run 行為：

```text
candidate=true
debounce=true
attempt-count=1
would-sleep-count=1
```

但 cleanup 在 PID 已退出後仍 timeout：

```text
daemon-exit-wait=pass probes=1
error: timed out waiting for crash-budget clean exit
```

最终安全狀態為：

```text
mode=disabled
job=absent
process-count=0
acceptance=absent
crash-count=0
circuit-open=false
runActive=true
```

Production log 已寫出：

```text
event=stopping pid=90445 reason=signal
```

但 crash-budget 最後修改時間仍停在該 daemon 的 `beginRun()`；沒有任何 clean-exit write。

## Root cause

Task 6R2 cleanup 使用：

```text
set mode disabled
→ launchctl kill SIGTERM
→ immediately launchctl bootout
→ wait for PID exit
→ wait for runActive=false
```

`ProcessSignalController.finish()` 在第一個 signal 進入後：

```text
restore SIGTERM/SIGINT to SIG_DFL
→ cancel source
→ invoke graceful handler
```

因此第一個 SIGTERM 正在同步執行 `session.stop()` 時，緊接的 `bootout` 可再送出終止動作。
第二個 signal 此時使用預設行為，能在 `coordinator.stop()` 或 `recordCleanExit()` 完成前終止程序。

Task 6R2 的 sandbox hook 只模擬 PID 與 clean-state probe 延遲；現有 signal tests 只驗證 handler
最多呼叫一次，沒有以真實 POSIX signal 驗證「第二個 signal 不得中斷第一次 graceful handler」。

## Considered approaches

### A. 只延長 clean-exit wait

程序已永久退出且不會再寫入，延長等待無法修復。拒絕。

### B. 只移除 management `stop_job`

使用單一 `bootout` authority 可消除目前已知的雙重終止窗口，且與已成功的 maintenance upgrade
模式一致；但 daemon 自身仍會在 graceful handler 執行期間暴露於第二個外部 signal。只做此項不足。

### C. 只修改 signal controller

可讓重複 signal 不再直接終止程序，但 management 仍不必要地發出兩個終止操作，保留未來平台
行為差異與 timing risk。只做此項不足。

### D. Management single authority + signal completion guard — selected

Cleanup 只使用一次 `bootout` 作為 launchd termination authority；signal controller 在 handler 完成前
把 SIGTERM／SIGINT 設為 ignore，handler 返回後才恢復 default。兩層共同移除重疊終止窗口。

## Design

### Management cleanup

`restore_disabled_job_after_acceptance` 固定順序：

```text
set mode disabled
→ bootout job exactly once
→ wait for zero resident PID
→ wait for crash-budget runActive=false
→ bootstrap disabled job
```

不得先呼叫 `stop_job`。Timeout semantics 維持：return 70、job absent、no bootstrap、no force kill。

EXIT trap 的 failed state 只重申 mode disabled 與 `bootout`；不得再呼叫 `stop_job` 或 bootstrap。

### Signal completion guard

`ProcessSignalController.finish(invokeHandler:)` 取得 ownership 後：

1. 將 SIGTERM／SIGINT 設為 `SIG_IGN`；
2. cancel read source；
3. 同步執行 handler；
4. handler 返回後恢復 `SIG_DFL`。

這保證 graceful handler 中收到的第二個 signal 被合併／忽略；`session.stop()`、
`recordCleanExit()` 與 `finished.signal()` 均在恢復 default 前完成。

### True signal-level contract

新增 fork child test：

1. child 啟動 `ProcessSignalController` 並向 parent 回報 ready；
2. parent 對 child 發出第一個真實 SIGTERM；
3. handler 回報 entered 並暫停在 completion window；
4. parent 發出第二個真實 SIGTERM；
5. child 必須完成 handler、正常 exit 0，且 handler count=1。

現有程式應以 SIGTERM signal termination 失敗；修復後必須正常通過。

### Crash-state repair and production re-entry

Repository gates、local-main integration與 final package verification通過後：

1. upgrade 至新 package，停在 loaded／disabled／zero PID；
2. 在 disabled／zero PID 下執行明確 `reset-crash-budget`，清除事故留下的 `runActive=true`；
3. 串行執行 deployment-dry-run、deployment-enabled-once、deployment-recovery-resleep；
4. 每階段均驗證 acceptance identity、loaded／disabled／zero PID、crash count 0、circuit closed、
   runActive false；任一失敗立即停止。

不得 activate、reboot 或 push。

## Test strategy

1. Fork child true-signal test：第二個 SIGTERM 不得中斷 handler。
2. Unit contract：handler 完成前 signal disposition 為 ignore，完成後恢復 default。
3. Management source/sandbox contract：acceptance cleanup 只使用一次 bootout，不呼叫 stop_job。
4. Delayed clean-state與timeout no-bootstrap contracts保持通過。
5. Full management suite、full Swift suite、release、bash syntax、shellcheck、package prepare/verify、
   `git diff --check` 全部通過。

## Acceptance criteria

- 真實雙 SIGTERM child process正常 exit 0，handler exactly once。
- Acceptance cleanup沒有 `stop_job → bootout` 重疊終止。
- Dry-run cleanup在真實 production可落盤 `runActive=false`。
- 每個 bounded acceptance成功後 crash count維持 0。
- 任一 cleanup timeout停在 disabled／job absent／zero PID，不 bootstrap、不強殺。
- Open P0 = 0；Open P1 without disposition = 0。

