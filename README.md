# macbook-lid-monitor

`macbook-lid-monitor` 是一個已在 M1 Pro MacBook 完成實機驗收的 macOS system-domain 常駐服務，用於處理原生闔蓋睡眠偵測不可靠的情況。它能在開機與使用者登入前自動啟動，長期監控上蓋角度，並在符合安全條件時請求 macOS 睡眠。

Production LaunchDaemon 只會透過 `scripts/manage-production-daemon.sh` 的明確管理命令修改 `/Library`。未知硬體、錯誤設定、過期感測器資料或睡眠 API 失敗均採 fail-open，不會猜測或放寬真實睡眠權限。

## 目前正式狀態與快速操作

目前已正式安裝並啟用在這台已驗證的 M1 Pro Mac 上的 production LaunchDaemon。它會在開機時由 macOS 自動載入，且不依賴使用者登入；平常不需要開啟 Terminal、App、專案或 ChatGPT。

日常使用方式：

- 正常使用 Mac 即可；上蓋降低到已校準門檻並持續約 2 秒時，服務會請求 macOS 睡眠。
- Mac 被意外喚醒但上蓋仍未重新打開時，服務會在 recovery window 後再次請求睡眠。
- 上蓋重新打開後，服務會重新進入監控狀態。

> **部署狀態提醒：** Milestone 17 identity `7bf98ff6ceae` 已完成 upgrade、三階段
> identity-bound acceptance 與 evidence-gated persistent activation；目前 production 為
> `enabled`、single PID、`monitoring-armed`，低角度啟動規則已在 live binary 中生效。尚未完成的
> 是上蓋 `<=68` 時重新啟動並停留 loginwindow 的獨立真機證明；在該驗收完成前，不宣稱整個
> Milestone 17 已收尾。

最常用管理命令：

```bash
cd /Users/water/Developer/projects/macbook-lid-monitor

# 查看目前狀態
sudo ./scripts/manage-production-daemon.sh status

# 查看完整診斷與嚴格運作基準
sudo ./scripts/manage-production-daemon.sh diagnostics
sudo ./scripts/manage-production-daemon.sh operational-baseline

# 安全停用
sudo ./scripts/manage-production-daemon.sh disable

# 完整反安裝並驗證零殘留
sudo ./scripts/manage-production-daemon.sh uninstall
```

完整的安裝、正式啟用、停用、緊急停止、升級、回滾、異常恢復與乾淨移除流程，請直接閱讀：

**[正式常駐服務操作手冊](docs/operations/production-daemon.md)**

> `activate` 不是一般 enable 捷徑。新的或已更換的 installed payload 必須先完成 identity-bound acceptance，才能取得持久真實睡眠權限。

## 系統需求

- Apple Silicon MacBook
- macOS 13.0 或更新版本
- 透過 Xcode Command Line Tools 提供的 Swift 6.x

第一台完成驗證的設備是搭載 M1 Pro、執行 macOS 26.5.2 的 MacBook。

## 前景診斷與測試工具

診斷模式只會讀取資料。前景自動睡眠必須明確選擇，且預設為只輸出 `would-sleep` 的 dry-run 模式；真正要求 macOS 睡眠時，還必須額外傳入 `--execute-sleep`。一般前景 CLI 不會修改持久電源設定、不會修改 NVRAM、不會安裝 LaunchAgent、不會要求系統管理員權限，也不會寫入 HID report。

只列出並排序唯讀候選裝置，不開啟任何 HID 裝置：

```bash
./scripts/run-diagnostic.sh --list
```

監看信心分數最高的候選裝置：

```bash
./scripts/run-diagnostic.sh --watch
```

同時顯示已複製的原始 report bytes：

```bash
./scripts/run-diagnostic.sh --watch --raw
```

在指定秒數後自動停止：

```bash
./scripts/run-diagnostic.sh --watch --raw --duration 120
```

未提供參數時，預設使用 watch 模式。未設定停止時間時，可按 `Ctrl+C` 結束監看。

### 自動睡眠 dry-run

任何真實睡眠測試前，都應先執行 dry-run：

```bash
./scripts/run-auto-sleep-dry-run.sh
```

校準後的政策只定義於 `LidSleepPolicy.calibratedDefault`。輔助腳本刻意不重複寫入角度門檻或時間參數，避免產生多個真相來源。

程式啟動時會輸出實際生效的設定，目前預設為：

```text
auto-sleep config: mode=dry-run sleep-threshold=68 reopen-threshold=75 debounce=2 startup-cooldown=5 wake-recovery=15
```

上述角度是感測器解碼值，不保證等同於實際鉸鏈物理角度。

在 dry-run 模式下，角度低於關閉門檻並持續超過 debounce 時間後，只會輸出：

```text
auto-sleep: would-sleep
```

dry-run 不會向 macOS 發出真正的睡眠要求。

### 啟動與喚醒規則

啟動與睡眠後喚醒採用不同的安全規則：

- 所有 auto-sleep 模式共用同一套啟動 state-machine policy；純診斷 `--list`／`--watch` 不進入此流程。
- 程式啟動後先等待 5 秒 startup cooldown，不會在 daemon 剛啟動時立刻睡眠。
- Startup cooldown 結束時，若最新有效且未過期的角度 `>=75`，會進入正常 `armed` 狀態。
- Startup cooldown 結束時，若最新有效且未過期的角度 `<=68`，會建立 `startup-closed-candidate`；再保持約 2 秒且資料仍新鮮、角度仍 `<=68` 時，dry-run 輸出 `would-sleep`，真實模式請求睡眠。
- Startup cooldown 結束時若角度為 `69...74`，或沒有新鮮有效資料，會 fail-open 保持 `disarmed`。
- Startup candidate 期間打開到 `>=75` 會取消 candidate 並 rearm；只升到 `69...74`、資料無效或資料過期會取消並回到 `disarmed`。
- 真實睡眠後收到喚醒通知時，程式會清除睡眠前的舊角度資料，並進入 15 秒 `wake-recovery`。
- recovery 到期時，若最新有效角度仍 `<75`，代表上蓋尚未真正重新打開，程式會再次要求睡眠。
- `69...74` 屬於遲滯區間，不視為重新開蓋。
- recovery 期間只要取得新的 `>=75` 角度，就會立即取消待執行的再次睡眠並重新啟用自動睡眠。
- recovery 期間若沒有新的有效資料，或資料格式無效，程式會採用 fail-open：不要求睡眠並進入 `disarmed`。

`wake-recovery` 的 15 秒從 IOKit 正式送達 `systemHasPoweredOn` 時開始，不是從螢幕亮起或
鍵盤按下時開始。若其他已註冊 power notification 的程式延遲 macOS 睡眠交易，螢幕可能先
熄滅、之後也能先亮起，但正式 wake callback 仍較晚到達。2026-07-31 真機驗收曾觀察到
`LINE timed out(30000 ms)`；在這種情況下，從螢幕亮起到 recovery-resleep 的體感等待可能接近
45 秒。只要上蓋持續低於 `75` 且資料有效，正式 wake callback 後約 15 秒仍會再次睡眠。

在預設 `5` 秒 startup cooldown 與 `2` 秒 close debounce 下，低角度啟動從 daemon 開始運行到
提出睡眠要求約需 7 秒；實際時間仍受 HID 新鮮資料與系統排程影響。

目前支援的時間參數為：

```text
--debounce <正數秒數>
--startup-cooldown <大於或等於 0 的秒數>
--wake-recovery <正數秒數>
```

舊的 `--wake-cooldown` 已停止支援。因為啟動安全等待與睡眠後 recovery 已不再具有相同語意，程式會拒絕這個舊參數並提示改用：

```text
--startup-cooldown
--wake-recovery
```

### 睡眠要求失敗

如果 macOS 睡眠 API 呼叫失敗，前景程序不會退出，並會輸出一次明確錯誤，例如：

```text
auto-sleep: sleep-request-failed error=power-management-unavailable
```

失敗後不會自動重試。程式會保持 `disarmed`，直到取得新的 `>=75` 角度。

### 執行真實睡眠

輔助腳本不會啟用真實睡眠。真實睡眠只能以前景方式明確執行：

```bash
swift run -c release macbook-lid-monitor --auto-sleep --execute-sleep
```

使用真實睡眠前，必須先確認 dry-run、角度校準及安全驗證均已通過。

M1 Pro 的完整實機驗證證據記錄於：

```text
docs/validation/2026-07-26-m1-pro-auto-sleep.md
```

## 輸出說明

成功解碼範例：

```text
2026-07-26T11:01:58+08:00 angle=173.0 raw=01 AD 00 clamshell=open
```

不支援的 report 格式範例：

```text
2026-07-26T11:00:33+08:00 angle=unsupported reportLength=3 raw=01 AC 00 clamshell=open
```

候選裝置輸出包含：

- 排名分數
- 是否達到可選門檻
- Registry ID
- Vendor ID／Product ID
- Usage Page／Usage
- Transport
- 評分原因

## 結束碼

| 結束碼 | 說明 |
| ---: | --- |
| `0` | 成功列出候選裝置，或正常完成監看 |
| `64` | 命令列參數錯誤 |
| `69` | 沒有足夠可信的候選裝置，或無法列舉 HID 裝置 |
| `70` | 未預期的內部錯誤 |
| `74` | HID 裝置開啟或資料串流失敗 |

## 感測器識別與解碼器狀態

已驗證的 M1 Pro 使用以下感測器：

```text
Vendor ID:  0x05AC
Product ID: 0x8104
Usage Page: 0x0020
Usage:      0x008A
Transport:  SPU
```

目前觀察到的輸入 report 為 3 bytes：

1. Report ID `1`
2. 角度低位元 byte
3. 角度高位元 byte

例如：

```text
01 AC 00
```

會解碼為感測器值 `172`。此值在已驗證機型上可單調反映上蓋位置，但不應直接解讀為一般幾何鉸鏈角度。

這個解碼器目前只以已擷取的 M1 Pro 證據為權威。舊的 2-byte、十分之一度解碼器仍屬探索用途；在其他硬體上沒有取得相符證據前，不應視為可靠來源。

## 權限與錯誤處理

程式不會提升權限。如果 macOS 拒絕 HID 存取，程式會輸出實際的開啟錯誤並結束。

不同 macOS 版本可能顯示不同的「隱私權與安全性」權限項目，因此本專案不保證只要開啟某一個特定權限，就一定能解決所有 HID 存取問題。

如果沒有候選裝置達到門檻，應先使用 `--list` 輸出作為調查證據，不應只是為了強制開啟裝置而降低候選門檻。

## 安全邊界

- 不寫入 HID，也不發送 feature report request
- 診斷模式與 dry-run 模式永遠不要求系統睡眠
- 真實睡眠必須明確傳入 `--auto-sleep --execute-sleep`
- 一般前景流程不安裝常駐服務；feasibility tooling 只有經明確批准才會暫時安裝，且已完成 uninstall acceptance
- 不修改持久電源設定
- 不擷取無關的鍵盤或觸控板資料
- HID callback 收到的 bytes 會先複製，再交由解碼器處理
- 不使用輪詢 loop
- 僅使用一次性 timer
- 睡眠 API 失敗不會形成自動重試循環

本工具無法修復損壞的原生闔蓋感測器。自動睡眠 workaround 採用事件驅動，且目前只以前景程序執行。

在已驗證的 M1 Pro 上，目前已完成：

- dry-run 實機驗收
- 閒置能耗與事件驅動審查
- 原始單次真實睡眠驗收
- 角度權威的兩次睡眠驗收
- 睡眠 API 錯誤可觀測性驗證

兩次睡眠驗收中，第二次睡眠要求確實在第一次喚醒後 15 秒發生；第二次喚醒後開到 `>=75`，成功取消第三次睡眠要求。

macOS 將第二次低功耗轉換記錄為 DarkWake，而不是與第一次完全相同的完整 Sleep。這是平台層 power state 的差異，完整證據保留在 validation 文件中。

前景 CLI 的真實睡眠始終需要操作者明確執行 `--auto-sleep --execute-sleep`。Production LaunchDaemon 則只有在 root-owned 固定設定被切換為 `enabled` 時才具有真實睡眠權限；安裝與模式切換都必須透過管理腳本明確執行。

驗收結果與感測器格式具有硬體相依性。其他 MacBook 型號或其他 report 格式，在使用真實睡眠功能前必須重新完成校準與 dry-run 驗證。

## Production LaunchDaemon

Routine operation, failure recovery, upgrade/rollback semantics, command final modes, and emergency
procedures are documented in [`docs/operations/production-daemon.md`](docs/operations/production-daemon.md).

正式 daemon product 為：

```text
macbook-lid-monitor-daemon
```

管理入口：

```bash
./scripts/manage-production-daemon.sh prepare
./scripts/manage-production-daemon.sh verify
sudo ./scripts/manage-production-daemon.sh install
sudo ./scripts/manage-production-daemon.sh bootstrap
sudo ./scripts/manage-production-daemon.sh status
```

模式控制：

```bash
sudo ./scripts/manage-production-daemon.sh disable
sudo ./scripts/manage-production-daemon.sh dry-run
```

`enabled` 只在受控 acceptance 命令中開放；一般操作沒有提供一個可不經驗收直接永久啟用真實睡眠的捷徑。

固定 managed paths：

```text
/Library/PrivilegedHelperTools/macbook-lid-monitor-daemon
/Library/LaunchDaemons/com.crazydennies.macbook-lid-monitor.plist
/Library/Application Support/MacBookLidMonitor/
/Library/Logs/MacBookLidMonitor/
```

Production 支援邊界目前只涵蓋已驗證的 M1 Pro exact hardware profile。其他 MacBook 型號必須先新增 exact profile、decoder 證據與完整 dry-run／enabled 驗收，不能依賴診斷候選排名自動取得 production 權限。

完整 production 設計、計畫、Task、實機證據與 final review 位於：

```text
docs/superpowers/specs/2026-07-27-production-launchdaemon-design.md
docs/superpowers/plans/2026-07-27-production-launchdaemon.md
docs/superpowers/tasks/2026-07-27-production-launchdaemon-tasks.md
docs/superpowers/reviews/2026-07-27-production-launchdaemon-final-review.md
```

### Production 安裝、啟用與移除

全新安裝預設保持 `disabled`：

```bash
cd /Users/water/Developer/projects/macbook-lid-monitor
./scripts/manage-production-daemon.sh prepare
./scripts/manage-production-daemon.sh verify
sudo ./scripts/manage-production-daemon.sh install
sudo ./scripts/manage-production-daemon.sh bootstrap
sudo ./scripts/manage-production-daemon.sh status
```

只有完成相同 installed identity 的 dry-run、單次真實睡眠與 recovery-resleep acceptance 後，
才可執行持久啟用：

```bash
sudo ./scripts/manage-production-daemon.sh activate
sudo ./scripts/manage-production-daemon.sh operational-baseline
```

安全停用：

```bash
sudo ./scripts/manage-production-daemon.sh disable
```

完整反安裝與乾淨移除：

```bash
sudo ./scripts/manage-production-daemon.sh uninstall
```

`uninstall` 會停止並 bootout system job，移除所有 managed binary、plist、config、manifest、
lease、acceptance、health、crash、rollback 與 production logs，並執行 residual-state check。
完整安裝、升級、回滾、緊急停止與零殘留驗證方式請以
[`docs/operations/production-daemon.md`](docs/operations/production-daemon.md) 為正式操作依據。

若 persistent crash budget 因連續未乾淨退出而開啟 circuit，daemon 會以成功碼停在
fail-open 狀態，避免 `KeepAlive.SuccessfulExit=false` 再形成 restart storm。確認 package
已切回 `disabled`、且沒有 resident daemon 後，操作者可明確重置：

```bash
sudo ./scripts/manage-production-daemon.sh reset-crash-budget
```

重置只移除 crash-budget state，不會自動啟用或 bootstrap daemon。

production `enabled` 與前景 `--execute-sleep` 共用一個非阻塞 sleep-authority lease。
任一方已持有時，另一方會 fail-open，不能建立第二個真實睡眠 authority。diagnostic 與
dry-run 不取得這個 lease。

解除安裝會停止並 bootout system job，移除 binary、plist、config、manifest、rollback slot、crash-budget state、production logs 與 Task acceptance state。可用 acceptance／review 中的 residual-state check 驗證零殘留。

## 前景工具移除方式

先停止正在執行的程序，再刪除專案目錄：

```text
~/Developer/projects/macbook-lid-monitor
```

診斷與前景自動睡眠流程不會安裝系統服務，也不會修改任何持久系統設定，因此不需要額外解除安裝步驟。

## LaunchDaemon 可行性與歷史工具

系統層 `LaunchDaemon` feasibility phase 先證明 M1 Pro 上的 system-domain daemon 可於登入前啟動、讀取 lid HID、接收 IOKit power notification，且 root/system context 可透過獨立 one-shot probe 成功呼叫 `IOPMSleepSystem`。其後 production phase 已完成正式 composition、固定設定、exact hardware authorization、logging、crash budget、transactional install／upgrade／rollback／uninstall，以及完整硬體 acceptance。

歷史 Task 14 曾驗證 rollback 與 uninstall 的零殘留能力；後續 Milestone 16 已重新完成正式部署與持久啟用。目前 production LaunchDaemon 已安裝、開機自動載入，並在使用者登入前即可運行。

`macbook-lid-monitor-daemon-spike` 與 `macbook-lid-monitor-sleep-probe` 保留為歷史驗證與回歸工具，不屬於 production package，也不會被 production plist 安裝或啟動。Spike 仍具有以下實驗限制：

- 永遠使用 dry-run，不包含切換為真實睡眠的參數。
- 只用於驗證系統層 HID、IOKit power notification、程序生命週期與登入前執行環境。
- 暫時 plist 不含 `KeepAlive`，停止後不會自動重啟。
- binary 與 plist 只用於受控 feasibility acceptance；最終已安全解除安裝。

feasibility phase 執行時，下列操作均分別取得明確批准，沒有由一次批准概括授權：

- 安裝暫時 LaunchDaemon
- 登出並停留在 loginwindow
- 執行睡眠／喚醒驗收
- 執行一次性真實睡眠 probe
- 重新開機驗收

`macbook-lid-monitor-sleep-probe` 與 daemon spike 是分離的 executable。probe 預設不執行睡眠；真實 probe 需要固定 approval token，且不會被 LaunchDaemon plist 啟動。

完整 feasibility 結論與逐 Task 證據位於：

```text
docs/validation/2026-07-26-launchdaemon-feasibility-spike.md
docs/superpowers/reviews/2026-07-26-launchdaemon-feasibility-spike-final-review.md
```

最終 disposition：feasibility tooling 保留作歷史驗證；production daemon 已完成設計、實作、實機驗收、正式安裝與持久啟用。未來若重新安裝或更換 payload，仍必須從 `disabled` 開始，重新完成 identity-bound acceptance 後才能 `activate`。
