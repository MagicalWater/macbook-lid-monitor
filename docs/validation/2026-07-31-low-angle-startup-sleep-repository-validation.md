# Milestone 17 — 低角度啟動睡眠恢復 Repository Validation

日期：2026-07-31
範圍：Tasks 1–4 repository candidate；尚未進行 production upgrade 或真實睡眠驗收。

## 已確認根因

舊 state machine 在 startup cooldown 結束時，只允許 `>=reopenThreshold` 進入 open；其餘角度
一律 disarmed。進入 disarmed 後，低角度資料被忽略直到上蓋先重新打開。2026-07-31 live log
顯示 daemon 與 HID 正常，但啟動序列為 startup-cooldown → monitoring-disarmed，與 source/test
authority 一致。

## Candidate behavior

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

所有 auto-sleep composition 共用同一 state machine；pure diagnostic modes 不適用。

## TDD evidence

### RED

Missing `LidSleepState.startupClosedCandidate` and startup transition events caused the new focused
tests to fail exactly at the intended contract. README/runbook tests also failed before the new
candidate/deployment wording was added.

### GREEN focused results

```text
LidSleepStateMachineTests: 22 tests, 0 failures
LidSleepCoordinatorTests: 14 tests, 0 failures
OutputFormatterTests: 7 tests, 0 failures
AutoSleepIntegrationTests: 11 tests, 0 failures
ProductionDaemonCompositionTests: 13 tests, 0 failures
Diagnostic-focused suites: 6 tests, 0 failures
ProductionEventTests: 3 tests, 0 failures
Production runbook contract: 1 test, 0 failures
README-first contract: 1 test, 0 failures
```

## Safety and deployment status

- Work occurred only in isolated worktree `/Users/water/.devspace/worktrees/macbook-lid-monitor-fb7c8f05`.
- No `/Library` mutation, launchd mutation, sleep request, reboot, upgrade, rollback or uninstall occurred.
- Current installed production remains the previous identity and previous startup behavior.
- README/runbook explicitly identify Milestone 17 as a repository candidate not yet deployed.
- Task 5 full-suite, release, package and clean-snapshot evidence is still required before any
  production approval may be requested.
