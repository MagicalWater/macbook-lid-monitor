# 正式常駐服務操作手冊

本手冊是系統網域 MacBook 上蓋監控常駐程序的正式操作依據。
所有管理命令都應從版本庫根目錄執行。會修改 `/Library` 或 launchd 的命令需要互動式 `sudo`；管理腳本不會讀取或儲存密碼。

## 安全模型

- `install`、`upgrade`、`rollback`、`disable` 與受限部署驗收命令，除非是明確受驗證證據保護的 `activate`，否則都會強制進入或最終停在 `disabled`。
- `status`、`diagnostics`、`rotate-logs` 與 `operational-baseline` 都是唯讀命令，不會改變目前模式。常駐程序已正式啟用時，這些命令執行後仍會保持 `enabled`。
- `disable`、`upgrade`、`rollback` 與維護失敗路徑都會強制回到 `disabled`。
- 系統不存在可跳過驗收的無限制啟用命令。只有完整部署證據通過後，才能透過 `activate` 取得長期真實睡眠權限。

## 全新安裝與正式啟用

正式安裝流程一定從 `disabled` 開始。先以目前登入的版本庫使用者建置並驗證候選版本，再以 root 權限安裝並載入：

```bash
cd /Users/water/Developer/projects/macbook-lid-monitor
./scripts/manage-production-daemon.sh prepare
./scripts/manage-production-daemon.sh verify
sudo ./scripts/manage-production-daemon.sh install
sudo ./scripts/manage-production-daemon.sh bootstrap
sudo ./scripts/manage-production-daemon.sh status
```

安裝完成後的預期狀態是：

```text
mode=disabled
job=loaded
process-count=0
```

安裝本身不會授予真實睡眠權限。

新的或已更換的程式內容，必須先對同一已安裝版本識別完成以下三個受限驗收階段：

```text
deployment-dry-run
deployment-enabled-once
deployment-recovery-resleep
```

三個階段都通過後，才可執行受驗證證據保護的正式啟用：

```bash
sudo ./scripts/manage-production-daemon.sh activate
sudo ./scripts/manage-production-daemon.sh operational-baseline
```

`activate` 不是一般啟用捷徑。只要驗收證據缺失、不完整、過期、損壞，或版本識別不一致，就會拒絕啟用。

健康的最終狀態應為：

```text
mode=enabled
job=loaded
process-count=1
health_state=monitoring-armed
operational_baseline=pass
```

## 低角度啟動與重新開機

Milestone 17 候選版本修正了以下情境：Mac 在上蓋完全關閉或角度 `<=68` 時冷開機、重新啟動，
或正式常駐程序重新啟動後，舊版本會在 startup cooldown 結束時停在 `disarmed`，直到上蓋先
打開一次。

新的共用 auto-sleep 規則為：

```text
啟動後等待 5 秒 startup cooldown

最新新鮮角度 >=75
→ monitoring-armed

最新新鮮角度 <=68
→ startup-closed-candidate
→ 再等待 2 秒 close debounce
→ 角度仍 <=68 且資料仍新鮮
→ 請求一次睡眠

角度 69...74、沒有資料、資料過期或資料無效
→ fail-open，保持 monitoring-disarmed
```

Startup candidate 期間：

- 打開到 `>=75`：取消 candidate 並重新 armed。
- 只升到 `69...74`：取消 candidate 並回到 disarmed。
- 資料無效或過期：取消 candidate 並回到 disarmed。
- 睡眠要求失敗：不自動重試，回到 disarmed，必須重新打開至 `>=75` 才能 rearm。

這套規則同時適用於前景 auto-sleep dry-run、前景 execute-sleep、production dry-run 與
production enabled；差異只在 dry-run 輸出 `would-sleep`，真實模式呼叫系統睡眠。純診斷
`--list`、`--watch`、`--watch --raw` 不建立 auto-sleep coordinator，因此不受影響。

### Recovery-resleep 的計時語意

15 秒 `wake-recovery` 只在 IOKit 正式送達 `systemHasPoweredOn` 後開始，不以螢幕亮起或鍵盤
輸入作為起點。macOS 的顯示子系統可以先熄滅或先恢復互動，而系統核心仍在完成原本的
sleep／wake power transaction。

若其他已註冊 power notification 的 client 沒有及時確認 `systemWillSleep`，macOS 可能等待
最多約 30 秒後才完成交易。2026-07-31 真機驗收曾記錄：

```text
LINE timed out(30000 ms)
```

當時螢幕已先亮起，但 `systemHasPoweredOn` 較晚送達；因此從使用者看到螢幕亮起到第二次
睡眠，體感等待可能接近 `30 + 15 = 45` 秒。這不代表 recovery timer 失效。驗收或日常觀察時，
應持續保持上蓋明顯低於 `68`，直到第二次睡眠真正發生；若 15–20 秒尚未再次睡眠，不要立即
翻開上蓋判定失敗。

### Persistent activation 與低角度 reboot 驗收

Milestone 17 identity `7bf98ff6ceae` 已完成 package upgrade、三階段 acceptance 與
evidence-gated `activate`。2026-07-31 activation 後的嚴格基準為：

```text
mode=enabled
job=loaded
process-count=1
health_state=monitoring-armed
operational_baseline=pass
```

正式服務會長期自動執行真實睡眠。2026-07-31 已完成上蓋約 45–55° 的手動 reboot/loginwindow
真機驗收：prepared boot epoch `1785457249`／PID `99898` 變為新 boot epoch `1785491605`／PID
`281`；新 daemon 在登入前依序記錄 startup cooldown、`startup-closed-candidate`、debounce 與
一次 `sleep-requested`，開蓋喚醒後同一 PID 回到 `monitoring-armed`。

`deployment-reboot-finish` 隨後正式驗證：

```text
boot-changed=true
pre-login=true
mode=enabled
pid=281
operational_baseline=pass
```

finish 成功後，temporary reboot state、observer evidence、observer script、observer plist 與
observer launchd job 均已移除；production 保持 enabled／loaded／single PID。正常日常使用不需
保留或手動管理這些 temporary artifacts。

## 日常狀態檢查

```bash
sudo ./scripts/manage-production-daemon.sh status
sudo ./scripts/manage-production-daemon.sh diagnostics
sudo ./scripts/manage-production-daemon.sh operational-baseline
```

健康的正式啟用狀態應包含：`mode=enabled`、`job=loaded`、`process-count=1`、與該 PID 相符且仍在有效時間內的監控健康狀態、有效的已安裝內容完整性，以及完整且版本識別一致的驗收紀錄。

缺少的狀態會顯示為 `unavailable`；格式錯誤、不安全、過期或版本識別不一致的狀態會直接被拒絕，不會猜測或自動放行。

## 安全停用與緊急停止

正常安全停用：

```bash
sudo ./scripts/manage-production-daemon.sh disable
sudo ./scripts/manage-production-daemon.sh status
```

預期最終狀態為 `mode=disabled`。如果 disabled job 仍載入，常駐程序 PID 必須為零。

當必須立即從 launchd 移除 job 時，使用緊急 `bootout`：

```bash
sudo ./scripts/manage-production-daemon.sh disable
sudo ./scripts/manage-production-daemon.sh bootout
sudo ./scripts/manage-production-daemon.sh status
```

預期狀態為：`disabled`、job 不存在、程序數量為零。

`bootout` 不會授予任何權限，也不能取代完整性修復或完整反安裝。

## 異常退出保護機制恢復

當異常退出保護機制為 `open` 時，先確認已安裝內容集合有效、模式已是 `disabled`，且沒有常駐程序，再只重置異常退出額度：

```bash
sudo ./scripts/manage-production-daemon.sh status
sudo ./scripts/manage-production-daemon.sh disable
sudo ./scripts/manage-production-daemon.sh bootout
sudo ./scripts/manage-production-daemon.sh reset-crash-budget
sudo ./scripts/manage-production-daemon.sh bootstrap
sudo ./scripts/manage-production-daemon.sh status
```

`reset-crash-budget` 會拒絕 `enabled` 模式、仍存在的常駐程序、不安全的中繼資料與符號連結狀態。

## 日誌輪替

```bash
sudo ./scripts/manage-production-daemon.sh rotate-logs
sudo ./scripts/manage-production-daemon.sh diagnostics
```

日誌輪替會保留目前寫入程序使用的 inode，只在日誌超過 1 MiB 時建立快照，並最多保留三代。若輪替路徑不安全，會在修改前拒絕執行。

## 升級

先以目前登入的版本庫使用者執行 `prepare` 與 `verify`，再以 root 權限執行 `upgrade`：

```bash
./scripts/manage-production-daemon.sh prepare
./scripts/manage-production-daemon.sh verify
sudo ./scripts/manage-production-daemon.sh upgrade
sudo ./scripts/manage-production-daemon.sh status
```

升級會進入 `disabled`、已從 launchd 移除、沒有常駐程序的維護狀態。

- 程式內容有變更時：建立一個回滾槽位、以 `disabled` 啟用候選版本、使舊驗收紀錄失效，最後停在 `disabled`。
- 只有版本庫證據改變、已安裝程式內容識別完全相同時：視為不需變更，並保留相符的驗收紀錄。

## 回滾

```bash
sudo ./scripts/manage-production-daemon.sh rollback
sudo ./scripts/manage-production-daemon.sh status
```

回滾會在任何修改前先驗證完整回滾槽位，之後恢復前一個版本、設為 `disabled`、使驗收紀錄失效、重新載入 disabled job，並以零常駐 PID 結束。

如果回滾槽位恢復失敗，命令會回傳失敗，並刻意讓 job 保持從 launchd 移除的狀態。

## 完整性驗證失敗處理

發生完整性驗證失敗時：

- 不要繞過驗證器。
- 不要手動修改受管理檔案。
- 先取得唯讀診斷資訊。
- 能安全停用時先執行 `disable` 與 `bootout`。
- 再透過已驗證套件修復，或執行完整反安裝。

```bash
sudo ./scripts/manage-production-daemon.sh diagnostics
sudo ./scripts/manage-production-daemon.sh bootout
./scripts/manage-production-daemon.sh prepare
./scripts/manage-production-daemon.sh verify
sudo ./scripts/manage-production-daemon.sh upgrade
```

如果已安裝內容驗證阻止安全修復，應使用經審查的發布程序，不應手動逐一刪除檔案。

## 前景真實睡眠衝突

當前景命令列工具要求 `--execute-sleep`，但正式常駐服務已持有共用睡眠權限鎖時，就會發生前景真實睡眠權限衝突。

不要強制刪除或替換權限鎖檔案。應依序：

1. 停用正式常駐服務。
2. 將正式常駐服務從 launchd 移除。
3. 執行明確批准的前景命令。
4. 完成後再以 `disabled` 狀態重新載入正式常駐服務。

## 完整反安裝與乾淨移除

```bash
sudo ./scripts/manage-production-daemon.sh uninstall
```

`uninstall` 會先對所有受管理路徑執行安全檢查，接著停用並從 launchd 移除 job，然後移除：

- 正式常駐程序執行檔
- LaunchDaemon 設定檔
- 設定檔
- 版本清單
- 睡眠權限鎖
- 驗收狀態
- 重新開機驗收狀態
- 健康狀態
- 異常退出狀態
- Task 14 狀態
- 回滾槽位
- 正式服務日誌

與本服務無關的檔案會保留。

預期零殘留狀態為：

```text
loaded job: absent
daemon PID: absent
managed support directory: absent
production log directory: absent
```

`uninstall` 本身會執行嚴格的殘留狀態驗證。只要仍有任何受管理項目，命令就會以非零結束碼結束，不會錯誤宣告成功。

需要人工再次確認時，可執行：

```bash
launchctl print system/com.crazydennies.macbook-lid-monitor 2>/dev/null || echo "job 已不存在"
pgrep -f '^/Library/PrivilegedHelperTools/macbook-lid-monitor-daemon$' || echo "常駐程序已不存在"
test ! -e /Library/PrivilegedHelperTools/macbook-lid-monitor-daemon && echo "執行檔已不存在"
test ! -e /Library/LaunchDaemons/com.crazydennies.macbook-lid-monitor.plist && echo "設定檔已不存在"
test ! -e '/Library/Application Support/MacBookLidMonitor' && echo "支援目錄已不存在"
test ! -e /Library/Logs/MacBookLidMonitor && echo "日誌目錄已不存在"
```

不要以手動逐一刪除受管理檔案作為主要卸載方式。應使用 `uninstall`，才能保留路徑安全檢查、launchd 清理、程序停止與殘留驗證的一致性。

## 真實睡眠與重新開機警告

**真實睡眠警告：** `deployment-enabled-once`、`deployment-recovery-resleep`、`activate`，以及已正式啟用的常駐程序，都可能呼叫真實系統睡眠。只有在已獲得明確批准，且具備失敗或完成後回到安全狀態的清理路徑時，才可執行受限驗收命令。

**重新開機警告：** `enabled` 模式重新開機驗收是兩階段流程：

```text
deployment-reboot-start
deployment-reboot-finish
```

由使用者手動執行已批准的重新開機，並在登入畫面停留指定觀察時間。完成階段必須驗證：

- 開機時間戳已改變
- 有登入前證據
- 只有一個 `enabled` 模式常駐程序 PID
- 運作基準驗證通過
- 臨時觀察程序已清除

不可用同一次開機測試替代真正重新開機，也不可自動執行未批准的重新開機。
