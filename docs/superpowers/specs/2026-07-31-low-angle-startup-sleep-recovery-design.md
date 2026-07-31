# Milestone 17 — 低角度啟動睡眠恢復設計

日期：2026-07-31
狀態：已核准執行

## 背景與已確認根因

目前所有 auto-sleep composition 共用 `LidSleepStateMachine`。既有啟動規則在
`startupCooldown` 結束時，只有最新角度達到 `reopenThreshold` 才會進入 `.open`；其餘
情況一律進入 `.disarmed`。進入 `.disarmed` 後，所有低於 `reopenThreshold` 的角度都被
忽略，直到上蓋先重新打開一次。

這造成以下真實產品漏洞：Mac 在上蓋已完全關閉或角度 `<=68` 時冷開機、重新啟動，或
正式 daemon 重新啟動，雖然 LaunchDaemon 已於登入前運行且 HID 有有效角度資料，仍不會
自動進入睡眠。

2026-07-31 的 production evidence 顯示：

```text
daemon started
startup-cooldown
monitoring-disarmed
```

直到上蓋先打開至 `>=75` 才出現 `monitoring-armed`，之後再次降低角度才會建立 candidate
並請求睡眠。因此根因是既有 state-machine policy，而不是 LaunchDaemon、登入前權限、
HID stream 或 `IOPMSleepSystem` 失效。

## 目標

1. 所有進入 auto-sleep state machine 的 composition 使用同一套低角度啟動規則。
2. 啟動後若取得新鮮、有效且 `<=sleepThreshold` 的角度，應在 startup cooldown 後再經
   close debounce，然後只請求一次睡眠。
3. 保留 `69...74` 遲滯區間、freshness、invalid-data 與 sleep-request failure 的 fail-open
   邊界。
4. 純診斷模式不進入 auto-sleep state machine，因此行為不變。
5. 不增加輪詢、重複 timer、持久電源設定或第二套 startup policy。

## 權威取代關係

本設計明確取代以下舊規則：

```text
startup below reopen threshold remains disarmed until an explicit reopen
```

新的正式規則是：

```text
所有 auto-sleep composition 在 startup cooldown 結束時：

fresh angle >=75
→ monitoring armed / open

fresh angle <=68
→ startup closed candidate
→ close debounce 2 秒
→ 再次確認資料新鮮且仍 <=68
→ dry-run 輸出 would-sleep，真實模式請求睡眠

fresh angle 69...74
→ disarmed

無資料、資料過期、資料無效
→ disarmed
```

歷史 Spec、Plan、review 與 validation 保留其當時狀態，不回寫；自本 Milestone 起，涉及
startup auto-sleep 行為時以本設計為最新 authority。

## 適用範圍

### 套用共用規則

- 前景 auto-sleep dry-run；
- 前景 `--auto-sleep --execute-sleep`；
- production dry-run；
- production enabled。

上述模式只在最終 `SleepRequester` effect 不同：dry-run 輸出 `would-sleep`，真實模式呼叫
系統睡眠。角度判定、startup cooldown、debounce、freshness、hysteresis 與 state transition
不得因 composition 不同而分叉。

### 不適用

- `--list`；
- 一般 `--watch`；
- `--watch --raw`；
- 其他不建立 `LidSleepCoordinator` 的純診斷流程。

## 狀態機設計

新增獨立狀態：

```swift
case startupClosedCandidate(deadline: Date)
```

不得直接重用一般 `.closingCandidate`。一般 close candidate 被取消時可回到 `.open`；但
startup candidate 若角度只升到 `69...74`，不能宣告已重新打開，必須回到 `.disarmed`。

### `startupCooldownElapsed`

必須使用事件 timestamp 驗證最新 sample freshness：

- fresh `>= reopenThreshold`：轉為 `.open`；
- fresh `<= sleepThreshold`：轉為 `.startupClosedCandidate(deadline)`，排程 close debounce；
- fresh hysteresis angle、missing、invalid 或 stale：轉為 `.disarmed`。

### Startup candidate 期間

- 新角度仍 `<= sleepThreshold`：保持 candidate；
- 新角度 `>= reopenThreshold`：取消 debounce，轉為 `.open`；
- 新角度在 `sleepThreshold+1 ... reopenThreshold-1`：取消 debounce，轉為 `.disarmed`；
- invalid data：取消 debounce，轉為 `.disarmed`；
- deadline 到期但 sample stale、missing 或角度不再 `<= sleepThreshold`：不得請求睡眠，轉為
  `.disarmed`；
- deadline 到期且 sample fresh、valid、仍 `<= sleepThreshold`：轉為 `.triggered`，產生一次
  `.requestSleep`。

### Sleep request failure

維持既有規則：真實睡眠要求失敗後轉為 `.disarmed`，不得自動無限重試，必須重新達到
`>=reopenThreshold` 才可 normal rearm。

## Coordinator 與事件語意

`LidSleepCoordinator` 繼續只維護三個 one-shot task：startup cooldown、close debounce、wake
recovery。Startup closed candidate 使用既有 close debounce task，不新增第四個 scheduler。

新增可觀察 transition 名稱：

```text
startup-closed-candidate
startup-closed-cancelled
startup-closed-debounce-elapsed
```

不得加入每筆 HID report 的 production logging。既有普通 close transition 名稱保持不變。

## 測試策略

### State-machine tests

- startup fresh `<=68` 建立 startup candidate；
- startup candidate deadline 到期且仍 fresh/closed 時只 request sleep 一次；
- startup `69...74` 保持 disarmed；
- startup missing、invalid、stale data fail-open；
- startup candidate 開到 `>=75` 取消並進入 open；
- startup candidate 只升到 `69...74` 取消並進入 disarmed；
- invalid data 取消 startup candidate 並 disarm；
- normal close 與 wake recovery 行為不回歸。

### Coordinator tests

- startup cooldown 後排程同一個 close debounce task；
- startup candidate transition 輸出正確；
- dry-run 與真實 requester 都只收到一次 effect；
- stop、wake、invalid data 會取消 pending startup close debounce。

### Integration/composition tests

- 前景 dry-run 低角度啟動輸出一次 `would-sleep`；
- 注入式 execute-sleep 低角度啟動呼叫 requester 一次；
- production dry-run 與 enabled composition 使用同一 state-machine 行為；
- 純診斷流程不受影響。

## 部署與真實驗收

Binary payload 改變後，舊 installed identity 與 acceptance 不得直接沿用。正式部署必須：

1. 建置並驗證新 package；
2. `upgrade` 後保持 disabled；
3. 重新完成 dry-run、enabled-once、recovery-resleep acceptance；
4. evidence-gated `activate`；
5. 進行低角度 reboot/loginwindow 真實驗收：
   - 上蓋維持 `<=68`；
   - 使用者手動重新啟動；
   - 停留於登入畫面；
   - 驗證 daemon 於登入前啟動；
   - 約 `startupCooldown + closeDebounce` 後出現一次 sleep request；
   - 重新打開至 `>=75` 後恢復並完成 baseline；
6. 確認只有一個 production PID、single authority、temporary evidence 完整清理。

任何真實睡眠、upgrade、activate、reboot 或 production mutation 都保留獨立明確批准 gate。

## 文件同步

更新 README、正式中文操作手冊、Milestone 17 validation 與 final review，使其一致描述：

- 低角度冷開機／daemon restart 會在安全延遲後睡眠；
- `69...74`、missing、invalid、stale data 仍 fail-open；
- 純診斷模式不受影響；
- dry-run 與真實模式共用 state-machine policy。

## 驗收標準

- 所有 auto-sleep composition 使用同一 startup policy，沒有 production-only 分支。
- 新鮮 `<=68` 的 startup sample 在 5 秒 cooldown 加 2 秒 debounce 後產生一次 sleep effect。
- `69...74`、missing、invalid、stale data 不產生 sleep effect。
- 新增 transition 可被測試與 evidence 穩定辨識。
- focused、full suite、release build、package、static 與 clean-snapshot gates 全部通過。
- 真實低角度 reboot/loginwindow acceptance 通過後，production 最終保持 enabled/running。
- Open P0 = 0；Open P1 without disposition = 0。

## 安全停止

Repository implementation 可以在 isolated worktree 內進行。未取得各自批准前，不得 upgrade、
disable、activate、sleep、reboot、rollback、uninstall 或改變目前 production state。任何失敗
都必須保留目前正式服務可用，或依已批准 rollback path 恢復。
