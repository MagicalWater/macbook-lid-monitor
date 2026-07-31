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
- Task 5 full-suite, release, package and clean-snapshot evidence is recorded below. Production
  Tasks 6–7 still require separate explicit approvals.

## Task 5 holistic verification

### Current checkout

```text
source commit: 3d47ddd29ba4cb9773dc4db016f4dd6f6ca86b72
Swift XCTest: 289 tests, 0 failures
ProductionManagementScriptTests: 90 tests, 0 failures
macbook-lid-monitor release build: pass
macbook-lid-monitor-daemon release build: pass
bash -n / shellcheck -x / git diff --check: pass
package prepare/verify: pass
```

The current-checkout prepared daemon package recorded binary SHA-256
`a1b0dc2bf052e0fa525fb1c3416b8eb48d24ac5a2c796e2adc8616199d87347e`.

### Independent clean clone

The first clone under `/private/tmp` was rejected by management tests because the parent directory
group did not match the expected user sandbox group. This correctly exercised the managed lease
group verifier and was not accepted as a valid clean environment.

The valid clean clone was recreated under the user-owned `water:staff` directory:

```text
/Users/water/.devspace/clean-snapshots/macbook-lid-monitor-m17.2MFprP
```

Results:

```text
source commit: 3d47ddd29ba4cb9773dc4db016f4dd6f6ca86b72
Swift XCTest: 289 tests, 0 failures
release builds: pass
bash -n / shellcheck -x / git diff --check: pass
package prepare/verify: pass
tracked working tree: clean
```

Its independently linked daemon SHA-256 was
`1fc70045cb339fe0df720b2e9a9e3547de59ab55c9b0a1263bcfff4945ac2fb4`.
The cross-build hash difference was traced to different Mach-O `LC_UUID` values and corresponding
linker-generated ad-hoc signatures. Each package manifest verified its own exact binary. The final
production deployment must prepare and retain one package from the final main commit; packages from
different builds must never be mixed.

### Live production read-only state

```text
installed source commit: 0885d54dbf133fdd8620d4a38379a8ed64819430
installed version: 0885d54dbf13
mode: enabled
launchd state: running
PID: 288
process count: 1
```

No production mutation occurred. The repository candidate is complete, but the installed daemon
still has the old startup-disarmed behavior until Tasks 6–7 are approved and completed.

## Repository decision

Tasks 1–5 are repository-complete with Open P0 = 0 and Open P1 without disposition = 0. Production
upgrade, real-sleep acceptance, persistent activation, and low-angle reboot/loginwindow acceptance
remain open and independently approval-gated.
