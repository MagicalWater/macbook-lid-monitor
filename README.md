# macbook-lid-monitor

`macbook-lid-monitor` 是一個 macOS 上蓋感測器診斷工具，也提供一個需要明確啟用的前景自動睡眠原型，用於處理原生闔蓋睡眠偵測不可靠的情況。

診斷模式只會讀取資料。自動睡眠必須明確選擇，且預設為只輸出 `would-sleep` 的 dry-run 模式；真正要求 macOS 睡眠時，還必須額外傳入 `--execute-sleep`。一般前景 CLI 不會修改持久電源設定、不會修改 NVRAM、不會安裝 LaunchAgent、不會要求系統管理員權限，也不會寫入 HID report。倉庫另保留一組已完成驗證、但不屬於正式部署的 LaunchDaemon feasibility tooling；只有明確執行管理腳本時才會使用管理員權限與 `/Library` 暫時路徑。

## 系統需求

- Apple Silicon MacBook
- macOS 13.0 或更新版本
- 透過 Xcode Command Line Tools 提供的 Swift 6.x

第一台完成驗證的設備是搭載 M1 Pro、執行 macOS 26.5.2 的 MacBook。

## 使用方式

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

- 程式啟動後先等待 5 秒，且不會因啟動時已處於低角度就立即睡眠。
- 啟動等待結束時，如果沒有取得新的 `>=75` 角度，程式會保持 `disarmed`，直到上蓋重新打開。
- 真實睡眠後收到喚醒通知時，程式會清除睡眠前的舊角度資料，並進入 15 秒 `wake-recovery`。
- recovery 到期時，若最新有效角度仍 `<75`，代表上蓋尚未真正重新打開，程式會再次要求睡眠。
- `69...74` 屬於遲滯區間，不視為重新開蓋。
- recovery 期間只要取得新的 `>=75` 角度，就會立即取消待執行的再次睡眠並重新啟用自動睡眠。
- recovery 期間若沒有新的有效資料，或資料格式無效，程式會採用 fail-open：不要求睡眠並進入 `disarmed`。

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

真實睡眠始終需要操作者明確執行 `--auto-sleep --execute-sleep`。本專案目前沒有建立任何背景或持久部署。

驗收結果與感測器格式具有硬體相依性。其他 MacBook 型號或其他 report 格式，在使用真實睡眠功能前必須重新完成校準與 dry-run 驗證。

## 移除方式

先停止正在執行的程序，再刪除專案目錄：

```text
~/Developer/projects/macbook-lid-monitor
```

診斷與前景自動睡眠流程不會安裝系統服務，也不會修改任何持久系統設定，因此不需要額外解除安裝步驟。

## LaunchDaemon 可行性驗證

正式可用的功能目前仍是前景 CLI。系統層 `LaunchDaemon` feasibility phase 已完成，證明 M1 Pro 上的 system-domain daemon 可於登入前啟動、讀取 lid HID、接收 IOKit power notification，且 root/system context 可透過獨立 one-shot probe 成功呼叫 `IOPMSleepSystem`。

這不等於正式 production daemon 已完成或已安裝。Task 13 已移除所有暫時 system artifacts，目前沒有載入的 job、daemon process、installed binary、plist 或 feasibility log directory。

`macbook-lid-monitor-daemon-spike` 仍具有以下實驗限制：

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

最終 disposition：production daemon architecture 已解除可行性阻塞，可以進入正式設計；但 production packaging、持久 logging、升級／回滾與真實 sensor-driven sleep enablement 仍必須另立正式階段實作與驗收。
