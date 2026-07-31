# Milestone 17 跨對話交接 — Task 5 至 Task 6

日期：2026-07-31

## Authority 與範圍

本文件是 Milestone 17 在 Tasks 1–5 repository closure 後，跨對話進入 Task 6 的正式交接 authority。
Repository 文件、Git 歷史、tests、production evidence 與 review evidence 才是正式 authority；聊天摘要不是。

Repository：

```text
/Users/water/Developer/projects/macbook-lid-monitor
```

本次交接處理的是新的大階段：

```text
Milestone 17 — 低角度啟動睡眠恢復
```

目標是修復：Mac 在上蓋 `<=68°` 或完全蓋上時，從關機／重新開機進入 loginwindow 後，舊 daemon 因 startup safety 進入 `disarmed`，不會自動再次睡眠。

## Git baseline

在本 handoff closure commit 建立前：

```text
branch: main
repository candidate closure: 73015cac8bce121b2ea3137c3b616f3b91eb4a03
origin/main: cf9f26eccf16bd15ba60cfe47a33720ddfc4a11e
local main ahead of origin/main: 7 commits
local main behind origin/main: 0 commits
working tree: only this handoff synchronization remains before closure commit
push status: not pushed
```

Tasks 1–5 的候選 commits 已由 detached worktree fast-forward 整合回本機 `main`：

```text
31c9b80 test: define low-angle startup sleep contract
6631b0b fix: sleep after closed low-angle startup
8454a8d test: verify shared startup sleep composition
3d47ddd docs: document low-angle startup sleep recovery
73015ca docs: close low-angle startup repository candidate
```

原 managed worktree：

```text
/Users/water/.devspace/worktrees/macbook-lid-monitor-fb7c8f05
```

它是 bridge／DevSpace 管理的 detached worktree，不再是 authority。下一個對話應開啟 main checkout，不應從該 worktree繼續 production deployment。

## 雙層治理狀態

以下均已完成：

```text
Milestone 17 Spec
→ Task-level Spec review
→ holistic Spec review

Milestone 17 Implementation Plan
→ Task-level Plan review
→ holistic Plan review

Task register
→ sizing / dependency / approval / safe-stop review

Task 1 RED contract
→ RED evidence
→ immediate review
→ commit

Task 2 shared state machine
→ GREEN evidence
→ immediate review
→ finding disposition / re-review
→ commit

Task 3 composition equivalence
→ focused verification
→ immediate review
→ commit

Task 4 docs / event authority
→ RED / GREEN evidence
→ immediate review
→ commit

Task 5 repository holistic gate
→ current checkout full gate
→ independent valid clean clone gate
→ live production read-only gate
→ holistic review
→ closure commit
```

目前：

```text
Stage A: complete
Stage B: complete
Tasks 1–5: complete
Stage C: open
Tasks 6–7: open
Open P0: 0
Open P1 without disposition: 0
Milestone 17 overall: not complete
```

## Repository candidate 行為

所有 auto-sleep composition 現在共用同一 startup policy：

```text
fresh startup angle >=75
→ open / monitoring-armed

fresh startup angle <=68
→ startup-closed-candidate
→ 2-second close debounce
→ fresh and still <=68
→ exactly one sleep effect

startup angle 69...74, missing, invalid, or stale
→ disarmed / fail-open
```

適用：

- foreground auto-sleep dry-run
- foreground execute-sleep
- production dry-run
- production enabled

不適用：

- `--list`
- `--watch`
- `--watch --raw`
- 其他純診斷路徑

## Repository verification evidence

Current checkout：

```text
Swift XCTest: 289 tests, 0 failures
ProductionManagementScriptTests: 90 tests, 0 failures
release macbook-lid-monitor: pass
release macbook-lid-monitor-daemon: pass
bash -n: pass
shellcheck -x: pass
package prepare / verify: pass
git diff --check: pass
```

Valid independent clean clone：

```text
owner/group: water:staff
Swift XCTest: 289 tests, 0 failures
release builds: pass
bash -n / shellcheck -x / git diff --check: pass
package prepare / verify: pass
tracked working tree: clean
```

第一次放在 `/private/tmp` 的 clone 因 parent group 不符合 managed lease 安全政策而被正確拒絕；不能把該次視為 candidate failure。有效 clean clone 已在使用者擁有的 `water:staff` 目錄重新完整通過。

同一 source commit 的兩次 Swift release build 可能因不同 Mach-O `LC_UUID` 與 linker ad-hoc signature 產生不同 binary SHA。正式 deployment 必須從 final main commit 執行一次 `prepare`／`verify`，鎖定單一 package；不得混用不同 build 的 manifest 與 binary。

## 目前 installed production 狀態

```text
installed source commit: 0885d54dbf133fdd8620d4a38379a8ed64819430
installed version: 0885d54dbf13
mode: enabled
launchd state: running
PID: 288
process count: 1
```

目前 installed daemon 仍是 Milestone 16 舊 identity，因此**低角度開機漏洞仍存在於 live production**。Repository 已修復不等於 production 已修復。

在 Task 6 upgrade 前的暫時操作方式：

```text
重新開機後先把上蓋打開到 >=75°
→ 等待 monitoring-armed
→ 再降低到 <=68°
```

不得宣稱目前 installed production 已包含 `startupClosedCandidate`。

## 正式 authority 文件

下一個對話開始前必須先只讀：

```text
docs/handoffs/2026-07-31-milestone-17-task5-to-task6-handoff.md

docs/superpowers/specs/2026-07-31-low-angle-startup-sleep-recovery-design.md

docs/superpowers/plans/2026-07-31-low-angle-startup-sleep-recovery.md

docs/superpowers/tasks/2026-07-31-low-angle-startup-sleep-recovery-tasks.md

docs/superpowers/reviews/2026-07-31-low-angle-startup-sleep-recovery-spec-review.md

docs/superpowers/reviews/2026-07-31-low-angle-startup-sleep-recovery-plan-review.md

docs/superpowers/reviews/2026-07-31-low-angle-startup-sleep-recovery-task-reviews.md

docs/validation/2026-07-31-low-angle-startup-sleep-repository-validation.md

docs/operations/production-daemon.md
```

## 下一個安全起點

從：

```text
Task 6 — 新 identity production upgrade 與 bounded acceptance
```

開始。

在任何 mutation 前，先執行跨對話只讀 baseline audit：

1. 確認 branch=`main`、HEAD、working tree clean、origin divergence。
2. 確認 Tasks 1–5 commits 均已在 main。
3. 確認 installed identity 仍是 `0885d54...`。
4. 確認 mode=`enabled`、launchd running、single PID。
5. 確認目前 installed daemon 尚未包含 Milestone 17 behavior。
6. 確認 Task 6 尚未開始，沒有沿用任何舊 mutation approval。

## Task 6 必須遵守的 approval gates

Task 6 不是單一批准。以下每一步都必須取得新的明確批准：

1. 從 final main commit 執行 repository-only `prepare`／`verify`。
2. Production `upgrade`：結束於 loaded／disabled／zero PID，舊 acceptance 失效。
3. `deployment-dry-run`：低角度 startup candidate、debounce、exactly one `would-sleep`，最後 disabled。
4. `deployment-enabled-once`：真實睡眠 exactly once，最後 disabled。
5. `deployment-recovery-resleep`：維持 exactly-two-attempt boundary，最後 disabled。
6. Task 6 immediate review 與 acceptance identity review。

不能因使用者同意修復設計，就視為已批准 upgrade 或真實睡眠。

## Task 7 後續邊界

Task 7 仍需另外批准：

```text
persistent activate
→ low-angle reboot observer arm
→ 使用者保持 <=68° 手動 reboot
→ loginwindow observation
→ deployment reboot finish
→ final baseline
→ Stage C / Milestone holistic closure
→ push approval
```

Reboot 必須由使用者手動執行；不得自動重啟。Observer 必須 one-shot、root-owned、bounded，完成後清除。

## 不可遺失的非文件口頭資訊

沒有必要依賴口頭交接才能繼續的技術決策。所有重要需求、根因、設計、測試、findings、production 狀態與批准邊界均已落檔。

唯一需注意的操作事實是：目前 bridge 連線已恢復，production PID 在本次交接只讀核對時為 `288`；PID 可能因後續 sleep、reboot 或 launchd restart 改變，因此新對話必須重新讀取，不能把 `288` 當成永久常數。
