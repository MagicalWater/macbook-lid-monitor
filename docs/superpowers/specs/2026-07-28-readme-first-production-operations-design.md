# README 優先的 Production 操作資訊架構設計

日期：2026-07-28
狀態：已核准執行

## 背景

Milestone 16 已完成 production daemon 的正式部署、持久啟用、重新開機與登入前驗收。後續兩次文件修改補齊生命週期操作並將正式操作手冊翻譯為繁體中文，但未重新建立完整雙層治理證據。此外，README 將最重要的 production 使用方式放在較後段，第一眼多為前景診斷工具細節，不符合已部署產品的主要使用情境。

## 目標

1. README 第一屏直接回答：產品用途、目前正式部署狀態、日常如何使用、如何檢查、如何停用、如何完整移除。
2. 在 README 前段提供醒目的正式操作手冊連結。
3. 保留前景 CLI、架構、歷史與驗收內容，但下移為進階資訊。
4. 補正 commits `6c3f445` 與 `5c774a6` 的雙層治理證據。
5. 不修改任何 daemon、管理腳本、production package 或 live system state。

## README 資訊優先順序

README 開頭依序為：

1. 專案一句話定位。
2. 「目前正式狀態」：已安裝、enabled、system-domain LaunchDaemon、開機與登入前自動運行。
3. 「日常使用」：無須開啟 Terminal/App，闔蓋角度與 recovery-resleep 的使用概念。
4. 「最常用命令」：status、diagnostics、operational-baseline、disable、uninstall。
5. 「完整操作手冊」連結：`docs/operations/production-daemon.md`。
6. 系統需求與前景 CLI 使用。
7. 深入安全邊界、實作、歷史與驗收資料。

## 邊界

- README 不應複製整份 runbook；只放第一線操作與導覽。
- 命令、固定狀態欄位、路徑與 launchd label 必須逐字正確。
- 不可宣稱支援未驗證硬體。
- 不可暗示 `activate` 是一般 enable 捷徑。
- 不可改寫歷史 validation evidence 的當時狀態。
- 中文正文使用繁體中文；必要技術識別字可保留原文。

## 驗證標準

- README 前 100 行內必須包含正式狀態、日常使用、常用命令、停用、卸載與 runbook 連結。
- 文件契約測試必須驗證上述入口存在且位於前景 CLI 詳細說明之前。
- 正式 runbook 中文契約測試通過。
- `bash -n`、`shellcheck`、`git diff --check` 通過。
- live production 保持 `enabled`、單一 PID、running。
- Task-level review 與 holistic review 均無未處置 P0/P1 finding。

## 安全停止

任何文件或測試 finding 都只修改 repository 文件／測試。不得 disable、bootout、upgrade、rollback、uninstall 或重啟 production。
