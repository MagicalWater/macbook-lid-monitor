# Task 6R — Maintenance bootout bounded-exit recovery design

日期：2026-07-31
狀態：已核准執行

## Incident authority

Milestone 17 Task 6 的第一次 production `upgrade` 在已驗證 package
`72a274e6ef29` 上執行時，先成功把 mode 改為 `disabled` 並完成
`launchctl bootout`，之後立即失敗：

```text
booted-out label=com.crazydennies.macbook-lid-monitor
error: maintenance requires no resident daemon
exit_code=70
```

失敗後只讀證據為：舊 identity 仍安裝、mode=`disabled`、job absent、process count=0。
這證明 transaction 在 payload replacement 前安全停止，但也證明 `bootout` 返回與 daemon
真正退出之間存在短暫競態。

## Root cause

`prepare_maintenance_disabled_state` 的現有順序是：

```text
set mode disabled
→ launchctl bootout
→ 立即 pgrep
```

真實系統上 `launchctl bootout` 可以在 daemon 尚處於退出過程時返回。立即 `pgrep` 因此可能
命中即將退出的舊 PID，造成 upgrade、rollback 或 uninstall 類 maintenance transaction
不穩定失敗。

現有 management tests 全部使用 `MLM_TEST_ROOT` sandbox；原程式在 sandbox 中跳過真實
`pgrep`，因此沒有 executable contract 能重現這個競態。

## Considered approaches

### A. 固定 sleep 後再檢查

實作最小，但固定延遲無法證明程序真的退出；延遲太短仍競態，太長則每次 maintenance
無條件變慢。拒絕。

### B. 有上限的 resident-process polling — selected

在 `bootout` 後，以現有精確 daemon path probe 重複確認 resident process。每 100 ms 檢查
一次，最多等待 5 秒。程序提早退出就立即繼續；超時則在 backup、acceptance invalidation
與 payload replacement 前 fail-open。這直接對應真正需要等待的條件，且有明確上限。

### C. timeout 後 SIGKILL

能提高 transaction 成功率，但會把 maintenance helper 變成強制終止 authority，掩蓋 daemon
無法正常退出的真正故障。拒絕；timeout 必須保留 fail-open evidence。

## Design

在 `scripts/manage-production-daemon.sh` 增加兩個單一責任 helper：

```bash
managed_daemon_is_resident
wait_for_managed_daemon_exit
```

`managed_daemon_is_resident`：

- 真實系統只使用目前精確 probe：
  `pgrep -f '^/Library/PrivilegedHelperTools/macbook-lid-monitor-daemon$'`；
- sandbox 可使用 deterministic remaining-probes test hook；
- test hook 僅在 `MLM_TEST_ROOT` 非空時生效，真實 production 必須忽略它。

`wait_for_managed_daemon_exit`：

- 最多執行 50 個 100 ms wait interval，總等待上限約 5 秒；
- 每次 sleep 後重新 probe，程序一退出就立即成功；
- sandbox 不做 wall-clock sleep，只消耗 deterministic probe sequence；
- 超時輸出穩定錯誤並 return 70；
- 不送額外 signal、不強殺、不無限重試。

`prepare_maintenance_disabled_state` 在 `bootout_job` 後呼叫 bounded wait。只有 wait 成功才輸出
`maintenance-state ... process-count=0`，並允許後續 backup、acceptance invalidation 與 payload
activation。

## Transaction boundary

Timeout 必須發生在以下動作之前：

```text
backup_current_set
invalidate_deployment_acceptance
activate_staged_set_disabled
restore_rollback_set_disabled
uninstall removal
```

因此 timeout safe stop 為：

```text
installed identity unchanged
mode=disabled
job=absent
payload unchanged
acceptance not invalidated by the attempted transaction
```

## Test strategy

新增 executable contracts：

1. 模擬 resident daemon 經兩次 probe 後退出，upgrade 必須等待後成功，安裝 staged payload。
2. 模擬 resident daemon 超過全部 50 次 wait 仍存在，upgrade 必須 exit 70，舊 payload、舊
   manifest 與 acceptance 保持未替換，mode 保持 disabled。
3. Test hook 必須有 source/executable contract 證明只在 sandbox path 生效。
4. 既有 upgrade、rollback、uninstall、lifecycle 與完整 90-test management suite 不回歸。

## Production boundary

Task 6R 僅允許 repository mutation、tests、build、static check 與 package prepare/verify。
在新的 final main commit 形成並重新取得批准前，不得重試 production upgrade、bootstrap、
deployment dry-run、真實睡眠或 activate。

Task 6R 執行期間 live production 必須維持：

```text
installed identity = 0885d54dbf13
mode = disabled
job = absent
process count = 0
```

## Acceptance criteria

- Real-system maintenance 不再把正常的短暫退出延遲誤判為 failure。
- Wait 有固定 5 秒上限，timeout 仍在 payload replacement 前 fail-open。
- Production path 不接受 test hook override。
- Focused RED/GREEN、90-test management suite、full Swift suite、release build、bash syntax、
  shellcheck、package prepare/verify 與 `git diff --check` 全部通過。
- Open P0 = 0；Open P1 without disposition = 0。
