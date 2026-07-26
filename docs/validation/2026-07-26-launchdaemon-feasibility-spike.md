# LaunchDaemon 可行性驗證 — 2026-07-26

## 範圍

本文件記錄 Phase 1 LaunchDaemon feasibility spike 的驗證證據。此階段的核心目標是確認系統層 daemon 在登入前後是否能開啟 M1 Pro 上蓋角度 HID、持續收到 report，以及接收 IOKit sleep／wake notification。

目前只完成安裝前的前景 dry-run 驗證。尚未安裝 LaunchDaemon，也未執行登出、睡眠、真實 sleep probe 或重新開機驗收。

## 安全邊界

- daemon spike 永遠建構 `DryRunSleepRequester`。
- daemon spike 不接受命令列參數。
- 暫時 plist 不含 `KeepAlive` 與任何 sleep 參數。
- one-shot sleep probe 是獨立 executable，不存在於 plist。
- 本輪未使用 sudo，未修改 `/Library`。

## 自動化 baseline

2026-07-26 最終 clean validation：

```text
swift package clean: passed
swift test: 110 tests, 0 failures
swift build -c release: passed
plutil -lint: passed
bash -n: passed
shellcheck: passed
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

尚未批准／尚未執行。

## Loginwindow

尚未批准／尚未執行。

## Power notification 與睡眠／喚醒

尚未批准／尚未執行。

## One-shot sleep probe

只有 `--dry-run` 已列入安裝前驗證；真實 `--execute-once` 尚未批准／尚未執行。

## 重新開機

尚未批准／尚未執行。

## Cleanup

前景程序停止後確認下列路徑均不存在：

```text
/Library/PrivilegedHelperTools/macbook-lid-monitor-daemon-spike
/Library/LaunchDaemons/com.crazydennies.macbook-lid-monitor.feasibility.plist
/Library/Logs/MacBookLidMonitor/Feasibility
```

沒有 system-domain job 被安裝或 bootstrap。

## Findings

### P1 — power observer registration 缺少直接 evidence

初次前景驗證只能由 daemon startup 成功間接推論 IOKit power observer 已註冊，無法在 loginwindow 驗收時單獨辨識 registration 成功或失敗。

**Resolution：** 新增 `power-observer-registered` 與 `power-observer-registration-failed` evidence。成功訊號只會在 `SystemPowerObserving.start` 返回後發出。

### P1 — daemon policy transition 未寫入共用 evidence sink

初版 daemon composition 使用空 closure，導致 startup cooldown、rearmed 與 dry-run policy transition 無法被 launchd stdout log 保存。

**Resolution：** daemon 現在使用既有 `OutputFormatter`，並透過同一個鎖定 writer 輸出 policy line，避免與 HID／power evidence 交錯破壞完整行。

## 目前結論

Task 7 的安裝前前景 spike 驗證通過：

- IOKit power observer 可在一般前景 process 註冊；
- M1 Pro lid HID 可被辨識、開啟並收到有效 report；
- calibrated startup cooldown 與 rearm 行為可被觀察；
- SIGTERM cleanup 正常；
- 沒有安裝或留下任何 system artifact。

這只代表 **Task 7 通過**，不代表 LaunchDaemon、loginwindow、睡眠／喚醒、daemon-context 真實睡眠或重開機可行性已通過。下一步仍受 Task 8 的獨立安裝批准 gate 約束。
