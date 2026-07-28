# Enabled Reboot Acceptance Remediation

Date: 2026-07-28

## Trigger

Task 21 reboot preparation was approved while production was enabled/running. Read-only command
review found that the only existing reboot commands were the historical
`accept-task14-reboot-start/finish` flow. That flow requires disabled mode, upgrades, creates a
rollback slot, rolls back after reboot, and uninstalls the package. It contradicted the Milestone 16
Task 21 authority, which requires enabled reboot/pre-login proof and a final enabled/running state.
No reboot preparation or production mutation was attempted with the historical commands.

## Governance remediation

The user approved a focused remediation design. The following authority was added and independently
committed before implementation:

```text
4958715 docs: design enabled reboot acceptance remediation
9efb79c docs: plan enabled reboot acceptance remediation
3798d88 test: define enabled reboot acceptance contract
608c36a feat: add enabled reboot acceptance commands
```

## Implemented contract

New stable commands:

```text
deployment-reboot-start
deployment-reboot-finish
```

`deployment-reboot-start` verifies the installed set, target, complete deployment acceptance,
enabled mode, loaded job, exactly one PID, fresh armed health matching that PID, closed crash
circuit, and secure managed lease. It writes identity-bound reboot state and installs a temporary
one-shot system observer. It does not reboot, disable, upgrade, rollback, uninstall, or replace the
installed payload.

`deployment-reboot-finish` verifies changed boot epoch, unchanged identity, pre-login observer
evidence, one new daemon PID, enabled mode, armed health, complete acceptance, secure authority,
and strict operational baseline. It removes only temporary observer/reboot artifacts and leaves
production enabled/running.

The historical Task 14 commands remain unchanged and are not routed from Task 21.

## TDD and review evidence

Initial RED:

```text
new dispatcher entries: absent
new start/finish functions: absent
sandbox commands: usage exit 64
```

Review findings resolved during GREEN:

1. The first implementation referenced a nonexistent `crash_status_lines` interface. It was
   corrected to the existing `crash_budget_status_lines` production interface.
2. Sandbox lacked a crash-budget fixture. A sandbox-only closed/open hook was added while production
   rejects the hook and continues to use root crash state.
3. The successful reboot fixture initially reused the pre-reboot PID. It was corrected to require a
   distinct post-reboot PID and matching health evidence.
4. A static observer test initially prohibited the word `reboot`, conflicting with legitimate file
   names. It was narrowed to prohibit actual reboot/shutdown/pmset commands.

Final focused evidence:

```text
Task 21 focused tests: 6 tests, 0 failures
same-boot rejection: pass, enabled preserved
logged-in-only observer rejection: pass, enabled preserved
successful start/finish: pass, temporary artifacts removed, enabled preserved
historical destructive-flow isolation: pass
one-shot observer fixed-path/static contract: pass
```

## Full verification

```text
ProductionManagementScriptTests: 89 tests, 0 failures
full XCTest: 275 tests, 0 failures
bash -n: pass
shellcheck -x: pass
observer plist lint: pass
git diff --check: pass
```

## Live production non-regression

The remediation used repository files and `MLM_TEST_ROOT` only. Live production remained unchanged:

```text
installed identity: 0885d54dbf133fdd8620d4a38379a8ed64819430
mode: enabled
job: running
PID: 33458
monitoring-armed: observed before and after remediation
process-count: 1
lease: root:wheel 0600 regular file link count 1
reboot performed: no
observer installed on live system: no
push: no
```

## Decision

The Task 21 command-interface discrepancy is closed. No open P0 or undispositioned P1 finding
remains. Task 21 itself remains open and is now ready to execute the already approved real
`deployment-reboot-start` preparation, followed by a user-performed manual reboot and
`deployment-reboot-finish` verification.
