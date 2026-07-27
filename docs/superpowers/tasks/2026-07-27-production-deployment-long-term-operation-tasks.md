# Milestone 16 Production Deployment and Long-term Operation Task Register

Status: Tasks 1–5 complete and reviewed; Stage A review is next. Tasks 15–21 remain approval-gated.

## Mandatory per-Task workflow

```text
implement exactly one Task
→ immediate review
→ record findings
→ fix
→ re-review
→ focused verification
→ full verification required by that Task
→ document evidence and residual state
→ independent commit
→ only then enter the next Task
```

No Task may borrow test results or approval from another Task. A stage review is independent from
all Task reviews. Historical Milestone 1–15 evidence is context, not Milestone 16 completion proof.

## Task register

| Task | Purpose | Primary files | Focused verification | Approval | Safe stop / rollback |
| ---: | --- | --- | --- | --- | --- |
| 1 | Shared filesystem metadata and non-replaceable managed lease primitive — complete | `ProductionFileSystem.swift`, `ProductionConfigurationLoader.swift`, `SleepAuthorityLease.swift`, filesystem/lease tests | 21 focused tests; 209 full tests; daemon release build | none | revert Task 1 commit; no system state |
| 2 | Shared authority path resolution for daemon and foreground CLI — complete | `SleepAuthorityPathResolver.swift`, daemon/CLI composition, integration tests | 33 focused tests; 215 full tests; daemon release build | none | revert commit; no system state |
| 3 | Remove deployable requester environment override — complete | daemon composition, management script/tests | 52 focused tests; 215 full tests; Bash syntax | none | revert commit; no system state |
| 4 | Complete package manifest and staged identity — complete | manifest template, package common, package tests | 46 focused tests; 215 full tests; package prepare/verify; plist/Bash/diff checks | none | delete staging; revert commit |
| 5 | Runtime installed-set verification — complete | `ProductionInstalledSetVerifier.swift`, daemon composition/tests | 16 focused tests; 221 full tests; package prepare/verify; release build | none | revert commit; no system state |
| A | Stage A implementation review | review/evidence only | full tests, all release builds, static/plist/package checks | none | no system state |
| 6 | Shell installed verifier, metadata, and lifecycle guard | `production-installed-set.sh`, package common, manager/tests | expected/actual checks, normalization, metadata, concurrent mutation guard | none | revert commit; test-root only |
| 7 | Target preflight and deployment acceptance state | `production-deployment-state.sh`, manager/tests | model/chip, atomic state, privacy, mismatch/invalidation | none | revert commit; test-root only |
| 8 | Bounded deployment commands and evidence-bound activation | manager, deployment/installed libs, tests | bounded cleanup, partial acceptance rejection, sandbox enabled final state | none | revert commit; test-root only |
| 9 | Bounded runtime health persistence | `ProductionHealthStore.swift`, daemon health/composition/tests | atomic metadata, transitions, throttle, stale/corrupt/redaction | none | revert commit; no system state |
| 10 | Stable status, diagnostics, and baseline | `production-observability.sh`, manager/tests | stable fields, corrupt/missing states, metrics, strict baseline | none | revert commit; test-root only |
| 11 | Online-safe log rotation | observability lib, manager/tests | active inode retained, post-rotation primary write, 1 MiB/3 generations | none | revert commit; test-root only |
| 12 | Disabled upgrade/rollback and complete uninstall | manager, installed/deployment libs/tests | forced disabled, invalidation, rollback failure, complete scoped removal | none | revert commit; test-root only |
| 13 | Long-term operator runbook and docs synchronization | runbook, README, command/static tests | command/doc parity and state semantics | none | revert commit; no system state |
| B | Stage B implementation review | review/evidence only | root mutation trace, full/static/package/clean snapshot | none | no system state |
| 14 | Full automated clean-checkout release gate | implementation review and automated validation evidence | complete suite/build/static/package/clean snapshot/residual proof | none | no system state; production remains uninstalled |
| 15 | Formal-main integration and package provenance | Git and package evidence | formal main/origin equality, clean checkouts, exact release package | explicit merge/push approval | no install; abort before integration or revert approved merge |
| 16 | Disabled production installation | manager and install evidence | exact artifacts, root metadata, loaded/disabled/zero PID, no acceptance | explicit `/Library` and bootstrap approval | disable/bootout/uninstall if install acceptance fails |
| 17 | Fresh installed dry-run acceptance | deployment dry-run evidence | close/debounce/would-sleep, reopen, sleep/wake continuity, return disabled | explicit managed config/launchd mutation approval | cleanup trap to loaded/disabled/zero PID |
| 18 | Bounded one-sleep acceptance | enabled-once evidence | one attempt, wake, PID stable, exact identity, return disabled | separate real-sleep approval | cleanup trap to loaded/disabled/zero PID |
| 19 | Bounded recovery-resleep acceptance | recovery evidence | two attempts, one recovery transition, no third, return disabled | separate recovery-resleep approval | cleanup trap to loaded/disabled/zero PID |
| 20 | Persistent production activation | activation evidence | complete acceptance identity, one PID, managed authority, healthy enabled | separate persistent activation approval | emergency disable/bootout; Milestone becomes incomplete until redeployed |
| 21 | Enabled reboot, pre-login, baseline, and final closure | reboot/pre-login/baseline/final reviews | changed boot, auto-load, enabled one PID, profile/model, authority, final baseline | explicit reboot preparation; user restarts manually | emergency disable/bootout; safely redeploy before closure |
| C | Stage C implementation review | system/repository holistic review | approvals, evidence chain, temporary cleanup, final live state | no new mutation; findings may require new approvals | final state must remain or be restored enabled/running |

## Stage entry gates

### Stage A

May begin after Spec, Plan, and Task governance close. No system mutation is permitted.

### Stage B

May begin only after Stage A review passes. All management-command tests use the repository
`.build` test root; no real `/Library` path or launchd domain may be changed.

### Stage C

Task 14 is non-mutating. Task 15 and every following system/power operation retain their own
explicit approval. A previous approval cannot be reused for a later Task.

## Completion rule

Task governance closes when the register itself has no open sizing, dependency, verification,
approval, or safe-stop finding. Implementation completion is separate and requires Tasks 1–21,
Stage A/B/C reviews, and final holistic review to pass with the live daemon still enabled.
