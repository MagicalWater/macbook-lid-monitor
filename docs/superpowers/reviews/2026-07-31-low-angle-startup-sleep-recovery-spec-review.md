# Milestone 17 — 低角度啟動睡眠恢復 Spec Review

日期：2026-07-31

## Task-level review

- 根因有 source、test、README 與 production log 交叉證據：通過。
- 新規則明確 supersede 舊 startup-disarmed authority：通過。
- 適用邊界按 auto-sleep／pure diagnostic 分類，而非 production／foreground 分叉：通過。
- 獨立 `startupClosedCandidate` 保留 hysteresis 安全語意：通過。
- freshness、invalid-data、request-failure fail-open 邊界完整：通過。
- Coordinator 不新增輪詢或第四個 timer：通過。
- 新 payload 的 acceptance invalidation 與重新部署 gates 明確：通過。
- 真實睡眠、upgrade、activate、reboot 保留獨立批准：通過。

## Findings

### S17-SPEC-P1-1 — 不能直接重用普通 close candidate

普通 `.closingCandidate` 在角度離開 sleep threshold 時回到 `.open`。若 startup 只升至
`69...74` 也回到 `.open`，會錯誤視為已重新打開並允許後續 close flow。

**Disposition：** Spec 已要求獨立 `.startupClosedCandidate`，其 hysteresis cancellation 必須
回到 `.disarmed`。Finding closed。

### S17-SPEC-P1-2 — 不能只修 production composition

若 production 與 foreground auto-sleep 使用不同 startup policy，dry-run 將無法可靠預測
enabled 行為，並產生第二真相來源。

**Disposition：** Spec 已要求所有 auto-sleep composition 共用 state machine，只讓 requester
effect 不同。Finding closed。

Open P0 = 0。
Open P1 without disposition = 0。

## Holistic review

設計在不降低 fresh-data 與 hysteresis 安全邊界的前提下，修正「啟動時已關閉」無法履行
auto-sleep policy 的產品缺口。狀態、timer、composition 與 deployment authority 彼此一致，
沒有引入 production-only 特例、輪詢或未受控重試。

## Decision

**Spec approved.** 可進入 implementation plan 與 Task governance；production mutation 仍需後續
獨立批准。
