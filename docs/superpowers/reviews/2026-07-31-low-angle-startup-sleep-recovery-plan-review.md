# Milestone 17 — 低角度啟動睡眠恢復 Plan／Task Review

日期：2026-07-31

## Task-level Plan review

- RED tests 與 implementation 分離，能證明原漏洞：通過。
- State machine、coordinator、composition、docs 與 deployment responsibilities 分離：通過。
- 每個 Task 具有 focused verification、review 與 safe stop：通過。
- Repository Tasks 不修改 live production：通過。
- New identity upgrade 與三階段 acceptance 明確：通過。
- Activate 與 reboot acceptance 未被合併成單一批准：通過。

## Findings

### S17-PLAN-P1-1 — Startup candidate 不能新增第四個 timer

若另建 startup-specific scheduler，stop/wake/invalid cancellation 將產生雙重 timer ownership。

**Disposition：** Plan 要求沿用現有 close debounce task，並以 tests 鎖定。Finding closed。

### S17-PLAN-P1-2 — Repository complete 不可等同 production complete

僅 full suite 通過不能證明低角度 loginwindow 情境，且 binary identity 改變會使舊 acceptance
失效。

**Disposition：** Tasks 5、6、7 分離；Task register completion rule 要求重新 acceptance 與真實
reboot evidence。Finding closed。

### S17-PLAN-P1-3 — 低角度 reboot 必須驗證一次而非無界 resleep

若觀察流程沒有 exactly-once 邊界，關閉上蓋可能形成難以驗收的重複睡眠循環。

**Disposition：** Task 7 要求 bounded observer、一次 startup sleep request、reopen recovery 與
temporary cleanup。Finding closed。

Open P0 = 0。
Open P1 without disposition = 0。

## Holistic Plan review

Plan 從 pure state-machine contract 一路追蹤到真實 loginwindow evidence，並把 repository、package、
acceptance、activation 與 reboot 的 authority 分層。沒有省略 identity invalidation、safe stop、
clean snapshot 或 operator documentation。

## Decision

**Plan and Task register approved.** Tasks 1–5 可在 isolated worktree 開始；Tasks 6–7 仍需各自
production approval。
