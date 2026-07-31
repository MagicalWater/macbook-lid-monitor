# Task 7R — README Deployment-state Contract Recovery

Date: 2026-07-31

## Scope

This recovery repaired one stale README contract test exposed by the first Milestone 17 Task 7 Step 5
full-suite run. It did not change README wording, runtime source, production scripts, packaging or the
live production service.

## Initial failure

```text
test: ProductionManagementScriptTests/testReadmePresentsProductionQuickStartBeforeForegroundDetails
focused result: 1 test, 2 failures
full-suite result: 299 tests, 1 skip, 2 failures
```

The stale requirements were:

```text
Milestone 17 候選版本
尚未部署到目前正式常駐服務
```

Those strings were correct before production deployment, but contradicted the completed activation and
low-angle reboot/loginwindow evidence already recorded in README.

## Minimal change

Only this file changed for the functional repair:

```text
Tests/LidMonitorTests/ProductionManagementScriptTests.swift
```

The test now requires the existing README to state:

```text
Milestone 17 identity 7bf98ff6ceae completed upgrade
identity-bound acceptance and evidence-gated persistent activation
reboot/loginwindow real-machine acceptance completed
only repository holistic closure and unapproved push remain
```

## Verification

```text
focused RED: 1 test, 2 expected failures
focused GREEN: 1 test, 0 failures
full Swift suite: 299 tests, 1 child-only skip, 0 failures
ProductionManagementScriptTests: 98 tests, 0 failures
```

## Safety boundary

```text
README modified: false
runtime source modified: false
production scripts modified: false
packaging modified: false
production mutation: false
reboot: false
disable: false
rollback: false
push: false
```

Task 7R completes only the contract recovery. Task 7 Step 5 holistic closure remains open and must be
rerun from the beginning.
