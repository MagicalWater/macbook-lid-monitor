# README 優先的 Production 操作資訊架構 Validation

日期：2026-07-28

## Scope

本 validation 補正 commits `6c3f445`、`5c774a6` 的 post-closure 治理缺口，並驗證 README 已成為 production 使用者的第一入口。未修改任何 runtime、package 或 live production state。

## Information architecture evidence

README 前 100 行目前直接包含：

- 專案作為 system-domain 常駐服務的定位；
- 目前已正式安裝並啟用；
- 開機與登入前自動運行；
- 平常不需要開啟 Terminal、App、專案或 ChatGPT；
- status、diagnostics、operational-baseline、disable、uninstall；
- `docs/operations/production-daemon.md` 正式中文操作手冊連結；
- `activate` 不是一般 enable 捷徑的安全警告。

前景診斷與測試工具保留於後續獨立章節，不再占據第一入口。

## Governance evidence

```text
Spec + Task-level/holistic Spec review: passed
Plan + Task-level/holistic Plan review: passed
Task register: Tasks 1–3 complete
Task 1 immediate review: passed
Task 2 RED/GREEN + immediate review + re-review: passed
Task 3 finding fix + re-review: passed
Holistic review: passed
Open P0: 0
Open P1 without disposition: 0
```

## Verification evidence

```text
README focused contract: 1 test, 0 failures
Chinese runbook contract: 1 test, 0 failures
ProductionManagementScriptTests final rerun: 90 tests, 0 failures
README first 100 lines gate: pass
bash -n: pass
shellcheck -x: pass
git diff --check: pass
```

## Live state evidence

```text
mode=enabled
process-count=1
PID=283
launchd state=running
```

## Decision

**Accepted.** README 現為第一眼可用的 production 操作入口，完整中文 runbook 則作為深入生命週期 authority。先前兩次文件修改已納入完整雙層治理 closure，production 保持 enabled/running。
