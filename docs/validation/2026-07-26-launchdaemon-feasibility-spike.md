# LaunchDaemon 可行性驗證 — 2026-07-26

## 範圍

本文件記錄 Phase 1 LaunchDaemon feasibility spike 的驗證證據。此階段的核心目標是確認系統層 daemon 在登入前後是否能開啟 M1 Pro 上蓋角度 HID、持續收到 report，以及接收 IOKit sleep／wake notification。

目前已完成安裝前的前景 dry-run 驗證、使用者登入狀態下的 system-domain LaunchDaemon dry-run 驗收，以及 loginwindow HID/report continuity 驗收。尚未執行睡眠／喚醒、真實 sleep probe 或重新開機驗收。

## 安全邊界

- daemon spike 永遠建構 `DryRunSleepRequester`。
- daemon spike 不接受命令列參數。
- 暫時 plist 不含 `KeepAlive` 與任何 sleep 參數。
- one-shot sleep probe 是獨立 executable，不存在於 plist。
- Task 8 已使用管理員授權安裝暫時 binary／plist 並 bootstrap system job；未執行真實睡眠。

## 自動化 baseline

Task 7 clean validation：

```text
swift package clean: passed
swift test: 110 tests, 0 failures
swift build -c release: passed
plutil -lint: passed
bash -n: passed
shellcheck: passed
git diff --check: passed
```

Task 8 P1 修正後 fresh validation：

```text
DaemonSpikeCompositionTests regression: passed
swift test: 111 tests, 0 failures
swift build -c release: passed
plutil -lint: passed
git diff --check: passed
```

## 前景 daemon spike

最後一次前景 dry-run 於 `2026-07-26T14:23:01Z` 啟動：

```text
PID: 12790
UID: 501
GID: 20
Architecture: arm64
macOS: 26.5.2
```

選中的 HID candidate：

```text
registryID=4294968644
score=45
vendorID=0x05AC
productID=0x8104
usagePage=0x0020
usage=0x008A
transport=SPU
```

前景 evidence：

```text
event=power-observer-registered
auto-sleep: startup-cooldown
event=hid-opened
event=first-valid-report angle=161 count=1
auto-sleep: rearmed
event=stopping reason=signal
```

以 `SIGTERM` 停止後 exit code 為 `0`，沒有殘留的 `macbook-lid-monitor-daemon-spike` process。

本 Task 沒有刻意把上蓋移到觸發門檻以下，因此沒有產生 `would-sleep`。Dry-run sleep path 已由既有 integration tests 與 daemon composition review 證明；Task 8 的已登入 LaunchDaemon 驗收才會另外驗證 system-domain 下的 `would-sleep` evidence。

## 登入狀態 LaunchDaemon

使用者明確批准 Task 8 後，先在未 bootstrap 狀態安裝：

```text
binary: /Library/PrivilegedHelperTools/macbook-lid-monitor-daemon-spike
binary owner/group/mode: root:wheel 0755
plist: /Library/LaunchDaemons/com.crazydennies.macbook-lid-monitor.feasibility.plist
plist owner/group/mode: root:wheel 0644
initial binary SHA-256: 5dca7d7e91a6e53cef6cc751805a46717999eb8801e94eb2ef2528cdf5e4c750
plist SHA-256: 14798aa8cdfd6978e8a522a0a6731c895b897f68d9046975cfdafe8b61fbc5cc
bootstrap 前 process: none
bootstrap 前 system job: absent
```

首次 bootstrap 後：

```text
PID: 41768
UID/GID: 0/0
job domain: system
active count: 1
process count: 1
power observer: registered
HID: opened
first valid report: angle=161 count=1
stderr: empty
```

第一次實際壓低上蓋後，日誌出現 `candidate-started` 與 `triggered`，但沒有 `would-sleep`。這暴露出 Task 8 P1：daemon 的 `DryRunSleepRequester` callback 被設成空操作。

bootout 後以 TDD 修正，重新 build、uninstall、install 並 bootstrap。新 binary：

```text
SHA-256: 4a9fd2ed6c585f26954bd5316fb63253821425e78b67f6970ddedc2fd9a6e853
PID: 47660
UID/GID: 0/0
active count: 1
process count: 1
first valid report: angle=159 count=1
stderr: empty
```

使用者將上蓋壓低至感測器值約 60 並停留約 3 秒後，單次 close cycle evidence：

```text
auto-sleep: candidate-started = 1
auto-sleep: triggered = 1
auto-sleep: would-sleep = 1
auto-sleep: sleep-requested = 0
actual macOS sleep: none
```

接著執行 stop 與 bootout：

```text
stopping evidence: emitted
process after stop/bootout: none
system job after bootout: absent
wait 5 seconds: no automatic restart
```

最後手動 re-bootstrap：

```text
new PID: 52638
UID/GID: 0/0
active count: 1
process count: 1
power observer: registered
HID: reopened
first valid report: angle=159 count=1
stderr: empty
```

## Loginwindow

使用者明確批准 Task 9 後，於 `2026-07-26T15:44:18Z` 建立登出前基線：

```text
daemon PID: 52638
UID/GID: 0/0
job state: running
latest report milestone: angle=159 count=300 at 2026-07-26T15:43:27Z
stderr: empty
user LaunchAgent: absent
```

系統登入紀錄顯示：

```text
console logout: 2026-07-26 23:52 +0800
console login:  2026-07-26 23:55 +0800
```

使用者在 loginwindow 期間將上蓋兩次壓低至接近闔上，再重新打開。重新登入後回收的 daemon evidence：

```text
PID remained: 52638
launchd runs: 1
process count: 1
UID/GID: 0/0

candidate-started: 2
triggered: 2
would-sleep: 2
sleep-requested: 0
rearmed: 2

2026-07-26T15:53:27Z report-milestone angle=58 count=900
2026-07-26T15:55:07Z report-milestone angle=160 count=1000
stderr: empty
user LaunchAgent: absent
```

`15:53:27Z` 位於 console logout 與重新 login 之間，且感測器值 `58` 對應本機校準的完全／近乎完全闔上區域。這證明 system LaunchDaemon 在沒有任何使用者登入時仍持續接收有效 HID report、執行 dry-run policy，並於重新打開後恢復到 `160`。

Task 9 操作過程亦重新確認：這些數值是 machine-specific decoded sensor values，不是一般幾何鉸鏈角度。核心 runtime 一直直接比較 `68 / 75` 感測器門檻，未進行錯誤的物理角度換算。

## Power notification 與睡眠／喚醒

Task 10 經三次分別批准的 bounded manual sleep/wake cycle 完成 dry-run 驗收。三次測試均由使用者透過 macOS UI 手動要求睡眠；未執行 one-shot sleep probe，daemon 仍只使用 `DryRunSleepRequester`。

第一次 cycle 驗證正常重新開啟分支：

```text
pre-sleep: 2026-07-26T16:01:32Z
PID: 52638
latest report: angle=160 count=1300

2026-07-26T16:02:27Z power=will-sleep
2026-07-26T16:02:55Z power=will-power-on
2026-07-26T16:02:55Z power=has-powered-on
auto-sleep: wake-recovery
auto-sleep: rearmed
2026-07-26T16:03:48Z report-milestone angle=160 count=1500
```

macOS power log 獨立記錄 `2026-07-27 00:02:32 +0800` 的 Software Sleep，以及 `00:02:55 +0800` 的 HID Activity wake。相同 PID、`runs=1`、單一 root process 與空 stderr 均保持不變。

第二次 cycle 嘗試低值 recovery 分支，但喚醒後第一批 report 先達到 `>=75`，因此正確走入 `wake-recovery → rearmed`，之後壓低上蓋才走一般 `candidate-started → triggered → would-sleep`。此 cycle 證明一般 close path 正常，但不作為 `recovery-resleep` acceptance。

第三次 cycle 在睡眠前即將上蓋維持於低 sensor value，並於喚醒後保持低位超過 15 秒 recovery window：

```text
pre-sleep: 2026-07-26T16:14:18Z
PID: 52638
latest report: angle=159 count=2100

auto-sleep: candidate-started
2026-07-26T16:14:41Z power=will-sleep
auto-sleep: triggered
auto-sleep: would-sleep
2026-07-26T16:15:13Z power=will-power-on
2026-07-26T16:15:14Z power=has-powered-on
auto-sleep: wake-recovery
auto-sleep: recovery-resleep
auto-sleep: would-sleep
auto-sleep: rearmed
```

macOS power log 獨立記錄 `2026-07-27 00:14:46 +0800` 的 Software Sleep，以及 `00:15:13 +0800` 的 HID Activity wake。`recovery-resleep` 後只出現 `would-sleep`，沒有 `sleep-requested`，因此 daemon 沒有自行造成第二次真實睡眠；重新打開後成功 `rearmed`。

IOKit acknowledgement 的 exact-call ordering 由 `IOKitSystemPowerObserverTests` 驗證：`canSleep` 與 `willSleep` 均先呼叫 `IOAllowPowerChange` 再 forward event；runtime 的完整 sleep progression 亦證明 acknowledgement 沒有阻塞系統睡眠。

## One-shot sleep probe

只有 `--dry-run` 已列入安裝前驗證；真實 `--execute-once` 尚未批准／尚未執行。

## 重新開機

尚未批准／尚未執行。

## Cleanup

Task 7 前景程序停止後，下列路徑均不存在。Task 8 經批准後已安裝暫時 artifact，且目前為了後續 Task 9 驗收保留：

```text
/Library/PrivilegedHelperTools/macbook-lid-monitor-daemon-spike: present
/Library/LaunchDaemons/com.crazydennies.macbook-lid-monitor.feasibility.plist: present
/Library/Logs/MacBookLidMonitor/Feasibility: present
```

目前 system-domain job 已載入，單一 root PID 為 `52638`。Task 10 已通過；Task 11 真實 one-shot sleep probe 尚未批准。

## Findings

### P1 — power observer registration 缺少直接 evidence

初次前景驗證只能由 daemon startup 成功間接推論 IOKit power observer 已註冊，無法在 loginwindow 驗收時單獨辨識 registration 成功或失敗。

**Resolution：** 新增 `power-observer-registered` 與 `power-observer-registration-failed` evidence。成功訊號只會在 `SystemPowerObserving.start` 返回後發出。

### P1 — daemon policy transition 未寫入共用 evidence sink

初版 daemon composition 使用空 closure，導致 startup cooldown、rearmed 與 dry-run policy transition 無法被 launchd stdout log 保存。

**Resolution：** daemon 現在使用既有 `OutputFormatter`，並透過同一個鎖定 writer 輸出 policy line，避免與 HID／power evidence 交錯破壞完整行。

### P1 — DryRunSleepRequester 沒有輸出 would-sleep evidence

首次 logged-in LaunchDaemon close cycle 已產生 `candidate-started` 與 `triggered`，但沒有 `would-sleep`。根因是 daemon composition 建構 `DryRunSleepRequester` 時使用空 callback；coordinator 的 operational callback 只接收 requester 之外的失敗事件，無法補上這筆證據。

**Resolution：** 先 bootout system job，新增 regression test 並確認 RED，再讓 `DryRunSleepRequester` 直接透過共用 formatter/evidence sink 輸出 `auto-sleep: would-sleep`。111 tests 全數通過後，使用新 SHA-256 binary 完成 uninstall／install／bootstrap 與實機 re-acceptance。

### P2 — Task 9 操作說明一度把 sensor value 誤稱為物理角度

Task 9 執行前的口頭操作說明曾錯誤套用 `0° = 闔上、90° = 垂直、180° = 打開` 的一般幾何模型。這與本專案既有校準資料不符；本機完全闔上約為感測器值 `59`，實體約 90° 開啟時則約為 `148`。

**Impact：** 錯誤只存在於臨時操作說明。核心 decoder、policy、state machine、測試與已安裝 daemon 都直接使用 machine-specific sensor values，現行門檻仍為 `sleepThreshold=68`、`reopenThreshold=75`，沒有進行物理角度換算。

**Resolution：** 中止登出步驟、重新審查 decoder／policy／歷史校準 evidence，作廢錯誤說明，並改以「正常打開／接近闔上」描述人工作業；驗收與文件均以實際 sensor value 判定。

## 目前結論

Task 7、Task 8、Task 9 與 Task 10 驗證均通過：

- IOKit power observer 可在一般前景 process 註冊；
- M1 Pro lid HID 可被辨識、開啟並收到有效 report；
- calibrated startup cooldown 與 rearm 行為可被觀察；
- SIGTERM cleanup 正常；
- 沒有安裝或留下任何 system artifact。
- system-domain LaunchDaemon 可在使用者登入狀態下以 root 單一實例啟動；
- root daemon 可註冊 IOKit power observer、開啟同一 HID 並持續收到 report；
- 實際壓低上蓋可依序產生 `candidate-started`、`triggered`、`would-sleep`，且不會真的睡眠；
- stop／bootout 後不會因 `KeepAlive` 自動重啟；
- 手動 re-bootstrap 可用新 PID 乾淨重啟並重新開啟 HID。
- 登出至 loginwindow 後，同一 root PID 與同一 launchd run 持續存在；
- loginwindow 時段內有 timestamped report evidence，包含感測器值 `58` 與兩次完整 dry-run close cycle；
- 重新登入後 report 持續至 `count=1000`、感測器值回升至 `160`，且沒有 duplicate process、user LaunchAgent 或 stderr。
- system-domain daemon 在三次手動 sleep/wake 中均收到 ordered `will-sleep → will-power-on → has-powered-on` callback；
- 正常重新開啟分支在 fresh `>=75` report 後取消 recovery 並 `rearmed`；
- 低值分支在 recovery 到期後輸出一次 `recovery-resleep` 與一次 `would-sleep`，且沒有真實再次睡眠；
- 三次 cycle 前後 PID 均為 `52638`、`runs=1`、單一 root process、stderr 為空。

這代表 **Task 10 通過**，但不代表 daemon-context 真實 `IOPMSleepSystem` 或重開機自動啟動可行性已通過。下一步 Task 11 必須先 bootout dry-run daemon，再另行取得一次真實 one-shot sleep probe 的明確批准。
