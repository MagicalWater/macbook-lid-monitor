# Production LaunchDaemon Task Register

Status: Implementation in progress; Tasks 1–8 complete; Task 9 implementation verified and awaiting controlled root acceptance.

| Task | Purpose | Primary files | Verification | Approval gate | Rollback/safe stop |
| ---: | --- | --- | --- | --- | --- |
| 1 | Typed config and modes — complete | `ProductionConfiguration*`, tests | focused + full tests | none | revert commit |
| 2 | Exact hardware profile — complete | `LidHardwareProfile*`, discovery, tests | profile/fail-open tests | none | revert commit |
| 3 | Freshness/request epochs, including required config freshness — complete | configuration/state machine/coordinator/tests | stale/duplicate regression | none | revert commit |
| A | Shared-core stage review | reviews only | clean test/build | none | no system state |
| 4 | Events and health — complete | production event/health/sink/tests | privacy/format tests | none | revert commit |
| 5 | Production executable — complete | application, target, Package.swift, tests | composition/full/release | none | revert commit |
| 6 | Crash budget — complete | crash budget/application/tests | circuit/no-restart tests | none | revert commit |
| B | Composition stage review | reviews only | clean test/build/products | none | no system state |
| 7 | plist/config/manifest templates — complete | packaging files/tests | XCTest + plutil | none | revert commit |
| 8 | prepare/verify scripts — complete | management script/lib/tests | XCTest/bash/shellcheck | none; must not write `/Library` | delete build artifacts |
| 9 | install/control lifecycle — implementation ready | script/docs/harness | controlled disabled acceptance pending | **C1 approved; root acceptance pending** | disable, stop, bootout, uninstall staged artifacts |
| 10 | upgrade/rollback | script/fixtures/evidence | injected failure + rollback acceptance | **required before installed-version mutation** | automatic restore previous set |
| 11 | logs/diagnostics/uninstall | script/docs/tests | rotation/privacy/residual-state | **required before installed-state mutation** | bootout and scoped removal |
| C | Packaging stage review | reviews/evidence | clean checkout + residual state | approval for any cleanup mutation | explicit uninstall |
| 12 | Production dry-run acceptance | validation evidence | loginwindow/power/HID/single authority | logout/sleep/reboot approvals as applicable | disable/bootout |
| 13 | Enabled bounded acceptance | validation evidence | one sleep, one recovery, injected failure | **separate approval per real sleep cycle** | disable/bootout/uninstall |
| 14 | Reboot/rollback/uninstall acceptance | validation evidence | boot, rollback, zero residual | **separate reboot and uninstall approvals** | rollback then uninstall |
| 15 | Docs, tooling disposition, final review | README/docs/tool moves | full clean validation + holistic review | approval if cleanup touches installed state | restore archived tooling from git |

## Per-task mandatory workflow

```text
implement one task
→ immediate review and findings
→ fix and re-review
→ focused verification
→ full verification
→ document evidence and residual state
→ commit
```

No task may borrow an earlier task's test result for its completion claim.
