# README 優先的 Production 操作資訊架構 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 讓 README 成為 production 使用者的第一入口，並補齊 Milestone 16 closure 後兩次文件修改的雙層治理證據。

**Architecture:** README 提供第一線狀態、日常使用、常用命令與 runbook 導覽；`docs/operations/production-daemon.md` 保持完整生命週期 authority。Swift 文件契約測試驗證 README 入口順序與 runbook 中文語意，不修改 runtime。

**Tech Stack:** Markdown、Swift XCTest、Bash、ShellCheck、Git。

## Global Constraints

- 不修改 daemon、管理腳本、package 或 production system state。
- README 前 100 行內必須包含正式狀態、日常使用、常用命令、停用、卸載與 runbook 連結。
- README 不得把 `activate` 描述為一般 enable 捷徑。
- 正文使用繁體中文；命令、固定欄位與識別字保留原文。
- 每個 Task 完成 focused verification、immediate review 與獨立 commit。

---

### Task 1: 補正 post-closure 文件治理 authority

**Files:**
- Create: `docs/superpowers/tasks/2026-07-28-readme-first-production-operations-tasks.md`
- Create: `docs/superpowers/reviews/2026-07-28-readme-first-production-operations-task-reviews.md`

- [ ] 記錄 commits `6c3f445` 與 `5c774a6` 的 scope、驗證與治理缺口。
- [ ] 定義本 remediation 的三個 Task、review gate 與 safe stop。
- [ ] 執行 placeholder、矛盾與 `git diff --check` 檢查。
- [ ] 完成 Task 1 immediate review 並 commit。

### Task 2: 將 README 重構為第一入口

**Files:**
- Modify: `README.md`
- Modify: `Tests/LidMonitorTests/ProductionManagementScriptTests.swift`

- [ ] 先擴充文件契約測試，要求 README production 快速入口位於詳細前景 CLI 之前。
- [ ] 執行 focused test，確認舊 README 不符合新契約。
- [ ] 在 README 前段新增目前正式狀態、日常使用、常用命令與完整 runbook 連結。
- [ ] 將後段重複 production 內容改為深入說明，避免互相矛盾。
- [ ] 執行 focused test、Bash、ShellCheck、diff 與 stale-state scan。
- [ ] 完成 Task 2 immediate review 並 commit。

### Task 3: Holistic review 與 closure

**Files:**
- Create: `docs/validation/2026-07-28-readme-first-production-operations.md`
- Modify: `docs/superpowers/reviews/2026-07-28-readme-first-production-operations-task-reviews.md`
- Modify: `docs/superpowers/tasks/2026-07-28-readme-first-production-operations-tasks.md`

- [ ] 核對 README 首 100 行、runbook 中文、命令與狀態語意。
- [ ] 執行 focused 文件測試與完整 `ProductionManagementScriptTests`。
- [ ] 執行 `bash -n`、`shellcheck -x`、`git diff --check`。
- [ ] 核對 live production 仍 enabled、running、單一 PID。
- [ ] 記錄 Task-level re-review、holistic review、P0/P1 disposition 與 validation evidence。
- [ ] 建立 closure commit 並 push main。
