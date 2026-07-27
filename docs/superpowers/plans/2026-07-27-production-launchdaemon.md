# Production LaunchDaemon Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Build and validate a fail-open production system LaunchDaemon around the proven lid-monitoring core, with exact hardware authorization and transactional lifecycle management.

**Architecture:** A new thin production executable loads one fixed-path validated configuration, resolves an exact hardware profile, and composes the existing event-driven coordinator with dry-run or real sleep requesters. Separate package tooling owns fixed paths, manifest, health verification, upgrade, rollback, logs, and uninstall; spike/probe products remain excluded.

**Tech Stack:** Swift 6, Swift Package Manager, IOKit HID and power-management APIs, launchd plist, Bash packaging tooling, XCTest.

---

## Stage A — Shared-core production contracts

### Task 1: Configuration and mode model

**Purpose:** Introduce typed production configuration, secure fixed-path loading, and exhaustive validation without changing runtime composition.

**Files:**
- Create: `Sources/LidMonitorCore/Production/ProductionConfiguration.swift`
- Create: `Sources/LidMonitorCore/Production/ProductionConfigurationLoader.swift`
- Create: `Tests/LidMonitorTests/ProductionConfigurationTests.swift`

**Steps:**
- [x] Write tests for all three modes, schema rejection, policy ordering/ranges, missing fields, unsupported overrides, ownership/mode validation seams, and stable errors.
- [x] Run focused tests and confirm RED.
- [x] Implement minimal typed decoding and validation.
- [x] Run focused and full tests.
- [x] Update spec/task status and record Task 1 review.
- [x] Commit Task 1 independently.

**Completion:** Invalid or unsafe configuration cannot produce an enabled runtime configuration.

### Task 2: Exact hardware profile registry

**Purpose:** Separate diagnostic ranking from production authorization.

**Files:**
- Create: `Sources/LidMonitorCore/Production/LidHardwareProfile.swift`
- Create: `Sources/LidMonitorCore/Production/LidHardwareProfileRegistry.swift`
- Modify: `Sources/LidMonitorCore/LidSensorDiscovery.swift`
- Test: `Tests/LidMonitorTests/ProductionHardwareProfileTests.swift`

**Steps:**
- [x] Write exact-match, transport mismatch, duplicate device, unknown format, and diagnostic-ranking-not-authoritative tests.
- [x] Confirm RED, implement the single accepted M1 Pro profile and profile-bound decoder factory.
- [x] Verify no generic/composite decoder can authorize enabled mode.
- [x] Run focused/full tests, review, document, and commit.

**Completion:** Only the exact accepted profile can enter monitoring; all unknowns fail open.

### Task 3: Fresh sensor and request epoch safety

**Purpose:** Prevent stale or duplicate sensor/power events from issuing sleep.

**Files:**
- Modify: `Sources/LidMonitorCore/LidSleepStateMachine.swift`
- Modify: `Sources/LidMonitorCore/LidSleepCoordinator.swift`
- Modify: `Sources/LidMonitorCore/DiagnosticModels.swift` or add a focused freshness type.
- Test: `Tests/LidMonitorTests/LidSleepStateMachineTests.swift`
- Test: `Tests/LidMonitorTests/LidSleepCoordinatorTests.swift`

**Steps:**
- [x] Extend schema-v1 configuration with required positive `SensorFreshnessSeconds` and regression coverage.
- [x] Add failing tests for stale close sample, stale recovery sample, pre-wake sample rejection, duplicate wake callback, duplicate timer callback, and exactly-one request per epoch.
- [x] Implement minimal freshness/epoch state.
- [x] Prove existing calibrated behavior remains unchanged for fresh data.
- [x] Run focused/full tests, review, document, and commit.

**Completion:** Unfresh or duplicate events cannot request sleep.

### Stage A review

- [x] Review all shared-core changes against safety invariants.
- [x] Run clean full tests and release build.
- [x] Confirm no package or system path changes.
- [x] Commit Stage A closure.

## Stage B — Production daemon composition and observability

### Task 4: Production event, health, and exit contracts

**Purpose:** Replace spike evidence semantics with stable production observability.

**Files:**
- Create: `Sources/LidMonitorCore/Production/ProductionEvent.swift`
- Create: `Sources/LidMonitorCore/Production/DaemonHealth.swift`
- Create: `Sources/LidMonitorCore/Production/ProductionEventSink.swift`
- Test: `Tests/LidMonitorTests/ProductionEventTests.swift`
- Test: `Tests/LidMonitorTests/DaemonHealthTests.swift`

**Steps:**
- [x] Test lifecycle/error taxonomy, stable formatting, line atomicity, redaction, and prohibited raw report output.
- [x] Implement bounded transition logging and health snapshots.
- [x] Verify sensor values appear only in allowed transition events.
- [x] Run tests, review, document, and commit.

### Task 5: Production application composition

**Purpose:** Add the real production application without reusing the spike entry point.

**Files:**
- Create: `Sources/LidMonitorCore/Production/ProductionDaemonApplication.swift`
- Create: `Sources/LidMonitorDaemon/main.swift`
- Modify: `Package.swift`
- Test: `Tests/LidMonitorTests/ProductionDaemonCompositionTests.swift`

**Steps:**
- [x] Test disabled mode does not open HID; dry-run cannot construct real requester; enabled requires exact profile; startup failures become health/exit dispositions; signal shutdown is idempotent.
- [x] Confirm RED and implement the thin composition root.
- [x] Verify no CLI/environment production override.
- [x] Run focused/full tests and release build, review, document, and commit.

### Task 6: Crash budget and bounded recovery

**Purpose:** Prevent launchd restart storms while preserving bounded unexpected-exit recovery.

**Files:**
- Create: `Sources/LidMonitorCore/Production/CrashBudget.swift`
- Modify: `Sources/LidMonitorCore/Production/ProductionDaemonApplication.swift`
- Test: `Tests/LidMonitorTests/CrashBudgetTests.swift`

**Steps:**
- [x] Test rolling-window accounting, clean-exit exclusion, circuit open, explicit reset, corrupt state fail-open, and atomic persistence.
- [x] Implement with injectable storage/time.
- [x] Verify circuit-open mode never starts sensor-driven sleep.
- [x] Run tests, review, document, and commit.

### Stage B review

- [x] Review composition, privacy, exit, and restart boundaries.
- [x] Run clean full tests and all release products.
- [x] Confirm spike/probe behavior remains unchanged and excluded from production composition.
- [x] Commit Stage B closure.

## Stage C — Packaging and operator lifecycle

### Task 7: Production plist and package manifest

**Purpose:** Define fixed paths, versioned manifest, permissions, and bounded restart semantics.

**Files:**
- Create: `packaging/launchd/com.crazydennies.macbook-lid-monitor.plist`
- Create: `packaging/config/config.plist.example`
- Create: `packaging/manifest/manifest.plist.example`
- Create: `Tests/LidMonitorTests/ProductionPackagingTests.swift`

**Steps:**
- [x] Test label/path/product consistency, no LaunchAgent, no feasibility product, no unconditional KeepAlive, required throttle/restart fields, and file modes.
- [x] Add package templates and lint validation.
- [x] Run tests/plutil, review, document, and commit.

### Task 8: Non-mutating prepare and verify commands

**Purpose:** Reproducibly build and verify production artifacts without root or `/Library` writes.

**Files:**
- Create: `scripts/manage-production-daemon.sh`
- Create: `scripts/lib/production-package-common.sh`
- Test: `Tests/LidMonitorTests/ProductionManagementScriptTests.swift`

**Steps:**
- [x] Add tests for `prepare`/`verify`, source symlink rejection, checksum manifest, version consistency, script syntax, and zero `/Library` mutation.
- [x] Implement non-mutating commands only.
- [x] Run XCTest, `bash -n`, shellcheck, plist lint, review, and commit.

### Approval Gate C1

Explicit approval is required before Task 9 performs any `/Library` write or launchd mutation.

### Task 9: Install, bootstrap, status, stop, bootout, disable

**Purpose:** Add first-install and emergency-control operations with residual-state checks.

**Files:**
- Modify: `scripts/manage-production-daemon.sh`
- Modify: `scripts/lib/production-package-common.sh`
- Add integration harness under `Tests/PackagingFixtures/` if needed.
- Create: `docs/operations/production-daemon.md`

**Steps:**
- [x] Implement tests/harness for staged atomic install, ownership/modes, symlink refusal, duplicate authority refusal, disabled default, bootstrap health verification, idempotent stop/bootout, and emergency disable.
- [x] After explicit approval, perform controlled install in `disabled`, then dry-run only.
- [x] Capture residual state before and after every mutation.
- [x] Review, fresh verification, evidence document, and commit.

### Task 10: Upgrade and automatic rollback

**Purpose:** Make version transitions transactional and recoverable.

**Files:**
- Modify: `scripts/manage-production-daemon.sh`
- Modify: `scripts/lib/production-package-common.sh`
- Test: packaging transaction fixtures/tests.
- Create: `docs/validation/<date>-production-upgrade-rollback.md`

**Steps:**
- [x] Test successful upgrade, failed preflight, failed bootstrap, failed health check, automatic rollback, rollback checksum/version verification, and rollback failure fail-open.
- [x] Implement one rollback slot and atomic activation.
- [x] After explicit approval, run controlled dry-run upgrade/rollback acceptance.
- [x] Review, verify, document, and commit.

### Task 11: Logs, rotation, diagnostics, and uninstall

**Purpose:** Complete bounded operational support and full removal.

**Files:**
- Modify: `scripts/manage-production-daemon.sh`
- Modify: `docs/operations/production-daemon.md`
- Test: logging/diagnostic/uninstall fixtures.

**Steps:**
- [x] Test log size rotation/retention, root-only permissions, redacted diagnostics, bounded sensor capture, uninstall scope, process/job checks, and unrelated-file preservation.
- [x] Implement commands and failure-safe cleanup.
- [x] After explicit approval, validate uninstall and zero managed residual state.
- [x] Review, verify, document, and commit.

### Stage C review

- [x] Holistically review every root mutation and rollback path.
- [x] Run package/script/static validations from a clean checkout.
- [x] Record current system residual state.
- [x] Commit Stage C closure.

## Stage D — Hardware acceptance and closure

### Approval Gate D1

Separate explicit approvals are required for loginwindow/logout, real sensor-driven sleep, recovery resleep, reboot, and final uninstall.

### Task 12: Production dry-run acceptance

Validate installed dry-run under logged-in, loginwindow, sleep/wake, close/reopen, unknown/stale-data injection where practical, single PID/authority, log bounds, and emergency disable.

### Task 13: Enabled-mode bounded acceptance

Perform one approved sensor-driven sleep, one separately approved recovery-resleep cycle, and injected sleep-request failure. Prove exactly-once requests, fail-open disarm, no retry loop, and immediate disable/bootout.

### Task 14: Reboot, upgrade/rollback, and uninstall acceptance

Perform separately approved reboot auto-start in dry-run, production upgrade/rollback, and final uninstall. Prove pre-login operation, one authority, rollback health, and zero residual managed artifacts.

### Task 15: Documentation, spike disposition, and holistic final review

**Files:**
- Modify: `README.md`
- Modify: `Package.swift` if experimental products are archived/removed.
- Move or remove feasibility tooling only after production acceptance.
- Create final task reviews, validation evidence, and holistic review.

**Completion:** All spec criteria have fresh evidence; documentation matches actual state; final disposition explicitly states installed/disabled/uninstalled state and supported hardware profile.

### Task 15 closure

- [x] Synchronize README production usage, safety boundaries, supported profile, and uninstall state.
- [x] Retain spike/probe products as historical feasibility and regression tooling; keep them excluded from production packaging and launchd composition.
- [x] Synchronize Spec, Plan, Task, architecture audit, acceptance evidence, and system residual state.
- [x] Run fresh full tests, release builds for all products, Bash/static/plist/package validation, and clean-checkout validation.
- [x] Perform holistic traceability review against every Spec safety invariant and planned acceptance gate.
- [x] Record final disposition and commit Task 15 independently.
