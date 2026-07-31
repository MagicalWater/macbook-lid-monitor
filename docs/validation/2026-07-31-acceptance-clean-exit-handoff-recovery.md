# Task 6R2 — Acceptance clean-exit handoff recovery validation

日期：2026-07-31
Repository base：`93d9881ecddb0256c8cce97a360e55187902b4cb`
Implementation candidate：`04b35acf94c2e2a098112d889295f1e1a9603906`
執行環境：isolated managed worktree
`/Users/water/.devspace/worktrees/macbook-lid-monitor-0d5e8167`

## Incident reproduced from production evidence

Milestone 17 `deployment-dry-run` 對 identity `93d9881ecddb` 完成 exactly-one dry-run path，並
恢復 loaded／disabled／zero PID；但 cleanup 同一秒出現：

```text
PID 9182 event=stopping reason=signal
PID 9725 event=started mode=disabled
crash_count=1
crash_circuit=closed
crash_run_active=false
```

Unexpected-exit timestamp `1785469472.31077` 落在舊 PID stop 與新 disabled PID start 的交接
區間。Source trace 確認：舊 daemon 在 signal handler 的
`ProductionDaemonSession.stop()` 寫入 clean exit；新 daemon 的 `beginRun()` 若先執行，會把
仍 active 的舊 run 計入 unexpected exit。

## Governance authority

```text
Spec:
docs/superpowers/specs/2026-07-31-acceptance-clean-exit-handoff-recovery-design.md

Spec review:
docs/superpowers/reviews/2026-07-31-acceptance-clean-exit-handoff-recovery-spec-review.md

Implementation Plan:
docs/superpowers/plans/2026-07-31-acceptance-clean-exit-handoff-recovery.md

Plan review:
docs/superpowers/reviews/2026-07-31-acceptance-clean-exit-handoff-recovery-plan-review.md
```

Commits：

```text
a5b6f6d docs: design acceptance clean-exit handoff recovery
b1b9f08 docs: plan acceptance clean-exit handoff recovery
e0d08b7 test: define acceptance clean-exit handoff contract
04b35ac fix: wait for acceptance clean-exit handoff
```

## Baseline

在任何 Task 6R2 code mutation 前：

```text
ProductionManagementScriptTests: 93 tests, 0 failures
worktree HEAD: 93d9881ecddb0256c8cce97a360e55187902b4cb
working tree: clean
live production mutation: none
```

## RED evidence

四條新 contract 均在 production code mutation 前執行並失敗：

1. Delayed clean exit：找不到 `daemon-exit-wait`／`clean-exit-wait` ordered evidence。
2. Clean-state timeout：現有 command 錯誤地 return 0、bootstrap 並 record acceptance。
3. Failure trap：原始 injected failure 保留，但 trap 沒有 clean-exit handoff evidence。
4. Shared helper contract：四個 helper 與三個 shared Task 13 trap 均不存在。

Unrelated failure = 0；live production mutation = none。

## Implemented boundary

Task 13 dry-run、enabled-once、recovery-resleep 的 success 與 EXIT cleanup 現在共用：

```text
set mode disabled
→ SIGTERM old daemon
→ bootout job
→ wait_for_managed_daemon_exit
→ wait_for_crash_budget_clean_exit
→ bootstrap disabled job
```

新增 interfaces：

```text
crash_budget_clean_exit_persisted
wait_for_crash_budget_clean_exit
restore_disabled_job_after_acceptance
cleanup_acceptance_to_disabled
```

`ACCEPTANCE_HANDOFF_STATE=idle|waiting|complete|failed` 防止成功路徑 failure 後 EXIT trap 第二次
bootstrap。Resident 與 clean-state wait 各自最多 50 × 100 ms；timeout return 70，不 reset、
不強殺、不 bootstrap。

## Focused GREEN evidence

```text
new clean-exit contracts: 4 tests, 0 failures
Task 13 focused suite: 9 tests, 0 failures
bounded deployment regression: 2 tests, 0 failures
Task 6R resident-exit regression: 1 test, 0 failures
bash -n: pass
shellcheck -x: pass
git diff --check: pass
```

Verified behaviors：

- active probes 2 次後，第三次 clean-exit probe 才允許 bootstrap；
- crash-budget file bytes 在 successful sandbox cleanup 中完全不變；
- 51 active probes return 70；timeout 後沒有 bootstrap 或 acceptance record；
- injected failure trap 使用相同 bounded handoff 並保留原始 failure；
- Task 12／Task 17 cleanup 未改；
- SIGKILL／kill -9 = 0；新增 reset invocation = 0。

## Holistic repository gate

```text
ProductionManagementScriptTests:
97 tests, 0 failures

Swift full suite:
296 tests, 0 failures

release macbook-lid-monitor:
pass

release macbook-lid-monitor-daemon:
pass

bash -n scripts/manage-production-daemon.sh scripts/lib/*.sh:
pass

shellcheck -x scripts/manage-production-daemon.sh scripts/lib/*.sh:
pass

git diff --check:
pass
```

## Candidate package gate

Worktree candidate package self-verification：

```text
Version: 04b35acf94c2
SourceCommit: 04b35acf94c2e2a098112d889295f1e1a9603906
BinarySHA256: 079fde769a069129f27c3084440f9ae994bd4b4f6864cf0a6463fa29f717df20
PlistSHA256: 02ed783137c406d5baad9b07ec20ac60283b0bad8a1b2b29fa07d02d4689c24b
DisabledConfigSHA256: 201d3fae2c0d6266df417ce65374721b5793415d8bf4e2a9c479fe63790f77bf
```

這只是 pre-closure worktree candidate。Local-main integration 後必須從 final main fresh tree
重新 `prepare`／`verify`；本 identity 不可直接視為 final deployment authority。

## Live production read-only gate

Task 6R2 repository execution後：

```text
installed_version=93d9881ecddb
installed_commit=93d9881ecddb0256c8cce97a360e55187902b4cb
mode=disabled
job=loaded
job_state=not running
process_count=0
crash_count=1
crash_circuit=closed
crash_run_active=false
unexpected_exit_times=1785469472.31077
acceptance owner=root:wheel mode=600 size=1103 mtime=1785469473
main HEAD=93d9881ecddb0256c8cce97a360e55187902b4cb
main working tree=clean
```

沒有 reset crash budget、重跑 dry-run、enabled-once、真實睡眠、upgrade、activate、reboot、
rollback、push 或任何 `/Library` mutation。

## Holistic review

- Changed production file only：`scripts/manage-production-daemon.sh`。
- Required helper interfaces present：4/4。
- Task 13 shared EXIT traps：3/3。
- Task 12 original cleanup traps：unchanged。
- Task 17 original cleanup trap：unchanged。
- Prohibited scope scan：no `pmset`、SIGKILL、kill -9、reset、activation 或 reboot additions。
- Open P0 = 0。
- Open P1 without disposition = 0。

沒有可用 reviewer subagent；因此以獨立 requirement checklist、full diff review、focused
behavior tests、full suites 與 static/package gates完成第二層 holistic review。

## Deployment re-entry boundary

Task 6R2 repository candidate通過不等於 production 已修復。後續必須分開取得批准：

1. 使用 final-main verified package upgrade，結束於 loaded／disabled／zero PID；
2. reset 這次已確認由舊 cleanup race 誤增的 crash budget；
3. 對新 identity 重新執行 deployment-dry-run，並確認 crash count 不增加；
4. 之後才可另行批准 enabled-once。

在上述 gate 完成前，Task 6 enabled-once 維持 blocked。

## Local-main integration

Reviewed worktree closure `a0ddb32e20a01f678c29a81e3b86a58e4ff76642` 已從 base
`93d9881ecddb0256c8cce97a360e55187902b4cb` 以 `git merge --ff-only` 整合到本機 `main`。
整合無 conflict、working tree clean；未 push、未修改 production。Final-main fresh test與 package
evidence 必須在 integration-authority commit 上重新建立。

