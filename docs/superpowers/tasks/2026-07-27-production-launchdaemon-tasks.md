# Production LaunchDaemon Task Register

Status: Implementation in progress; Tasks 1–11 and Stage C complete; Task 12 logged-in dry-run acceptance complete. Loginwindow/logout, real sleep/wake, and reboot remain behind separate approval gates.

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
| 9 | install/control lifecycle — complete | script/docs/harness | controlled disabled acceptance | approved and completed | disable, stop, bootout, uninstall staged artifacts |
| 10 | upgrade/rollback — complete | script/fixtures/evidence | injected failure + rollback acceptance | approved and completed | automatic restore previous set |
| 11 | logs/diagnostics/uninstall — complete | script/docs/tests | rotation/privacy/residual-state | approved and completed | bootout and scoped removal |
| C | Packaging stage review — complete | reviews/evidence | clean checkout + residual state | completed with zero installed residual | explicit uninstall |
| 12 | Production dry-run acceptance — complete | validation evidence | logged-in, loginwindow, and real sleep/wake dry-run acceptance complete | completed; separate reboot approval remains for Task 14 | automatic disable/bootout/bootstrap cleanup |
| 13 | Enabled bounded acceptance — corrected enabled retry ready | validation evidence | dry-run path complete; enabled acceptance now uses pre-call attempt plus wake/PID evidence | enabled retry approved; recovery resleep still requires separate approval | automatic disable/bootout/bootstrap cleanup |
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
