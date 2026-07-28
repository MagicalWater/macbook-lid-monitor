# Milestone 16 Production Deployment and Long-term Operation Task Register

Status: Tasks 1–18 and Stage A/B reviews complete. Tasks 16–18 were reopened during live
acceptance, remediated, redeployed, rerun, and reclosed against installed identity
`0885d54dbf133fdd8620d4a38379a8ed64819430`. Production is intentionally loaded/disabled with
zero resident PID. Tasks 19–21 and Stage C remain open and retain separate approvals.

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
| A | Stage A implementation review — complete | review/evidence only | 221 full tests, release/package/static checks | none | no system state |
| 6 | Shell installed verifier, metadata, and lifecycle guard — complete | `production-installed-set.sh`, package common, manager/tests | 52 focused tests; 231 full tests; shellcheck/syntax/package/diff checks | none | revert commit; test-root only |
| 7 | Target preflight and deployment acceptance state — complete | `production-deployment-state.sh`, manager/tests | 59 focused tests; 238 full tests; atomic/privacy/static/package checks | none | revert commit; test-root only |
| 8 | Bounded deployment commands and evidence-bound activation — complete | manager, deployment/installed libs, tests | 64 focused tests; 243 full tests; bounded cleanup, activation identity, static/package checks | none | revert commit; test-root only |
| 9 | Bounded runtime health persistence — complete | `ProductionHealthStore.swift`, daemon health/composition/tests | 29 focused tests; 249 full tests; release daemon build and diff check | none | revert commit; no system state |
| 10 | Stable status, diagnostics, and baseline — complete | `production-observability.sh`, manager/tests | 69 focused tests; 254 full tests; static/package/release checks | none | revert commit; test-root only |
| 11 | Online-safe log rotation — complete | observability lib, manager/tests | 72 focused tests; 257 full tests; writer inode/symlink/static/package checks | none | revert commit; test-root only |
| 12 | Disabled upgrade/rollback and complete uninstall — complete | manager, installed/deployment libs/tests | 12 focused tests; 77 management tests; 262 full tests; static/package/release checks | none | revert commit; test-root only |
| 13 | Long-term operator runbook and docs synchronization — complete | runbook, README, command/static tests | 1 focused test; 78 management tests; 263 full tests; diff check | none | revert commit; no system state |
| B | Stage B implementation review — complete | review/evidence only | 264 full tests; four release products; static/package/clean-snapshot gate | none | no system state |
| 14 | Full automated clean-checkout release gate — complete | implementation review and automated validation evidence | 264 tests in main and clean snapshot; four release products; static/package/residual gates | none | no system state; production remains uninstalled |
| 15 | Formal-main integration and package provenance — complete | Git and package evidence | pre/post integration 264-test suites; fast-forward main; exact release package; main/origin equality | approved | no install occurred; release remains safely uninstalled |
| 16 | Disabled production installation — complete after remediation | manager, install/upgrade repair, deployment evidence | secure managed lease creation/repair; provenance-only upgrade semantics; privileged Git trust scoping; runtime lease policy aligned to `0600`; 270-test full suite; exact identity `0885d54...` installed | approved and completed | loaded/disabled/zero PID |
| 17 | Fresh installed dry-run acceptance — complete | deployment dry-run evidence | PID-bound readiness; candidate/debounce/one attempt/one `would-sleep`; acceptance recorded against `0885d54...`; cleanup disabled/zero PID | approved and completed | cleanup trap verified loaded/disabled/zero PID |
| 18 | Bounded one-sleep acceptance — complete | enabled-once evidence | one candidate, one debounce, exactly one real sleep request, wake evidence, PID stable, acceptance recorded against `0885d54...` | approved and completed | cleanup verified loaded/disabled/zero PID |
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
