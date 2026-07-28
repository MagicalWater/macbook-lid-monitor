# Enabled Reboot Acceptance Remediation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a fail-safe enabled reboot start/finish acceptance flow for Milestone 16 Task 21 while preserving the installed identity and leaving production enabled/running.

**Architecture:** Extend the existing production deployment state and management boundaries with one Task 21 reboot-state contract and one temporary LaunchDaemon observer. All automated behavior is exercised under `MLM_TEST_ROOT`; real-system commands only verify and record state, never reboot, upgrade, rollback, uninstall, or disable production.

**Tech Stack:** Bash 3.2-compatible shell, launchd plist, Python 3 for atomic plist/state helpers already used by the repository, Swift XCTest management-script integration tests.

## Global Constraints

- Live production must remain `enabled`, loaded, running, and single-PID throughout remediation.
- Installed source identity remains `0885d54dbf133fdd8620d4a38379a8ed64819430`.
- Task 21 commands must never call upgrade, rollback, uninstall, disable, or mutate deployment acceptance.
- The user manually reboots; no script may invoke reboot or shutdown.
- Temporary observer and reboot evidence are root-owned `0600` regular single-link files.
- Production test hooks are rejected outside `MLM_TEST_ROOT`.
- Historical `accept-task14-reboot-start/finish` behavior remains unchanged.

---

### Task 1: Define Task 21 sandbox contracts and RED tests

**Files:**
- Modify: `Tests/LidMonitorTests/ProductionManagementScriptTests.swift`
- Modify: `scripts/manage-production-daemon.sh`
- Modify: `scripts/lib/production-deployment-state.sh`

**Interfaces:**
- Consumes: existing `verify_installed_set`, `verify_target_hardware`, `verify_deployment_acceptance`, `operational_baseline`, `atomic_write_state`, `job_state_value`, `process_id_lines`, and `health_status_lines` shell interfaces.
- Produces: dispatcher names `deployment-reboot-start` and `deployment-reboot-finish`; state helpers `prepare_enabled_reboot_state`, `verify_enabled_reboot_state`, and `remove_enabled_reboot_artifacts`.

- [ ] **Step 1: Add failing static dispatcher and safety tests**

Add tests asserting both new dispatcher entries exist, neither routes to `accept_task14_reboot_*`, and their function bodies contain no calls to `upgrade_package`, `rollback_upgrade`, `uninstall_package`, `disable_job`, `pmset`, `shutdown`, or `reboot`.

- [ ] **Step 2: Add failing sandbox lifecycle tests**

Add one successful start/finish test and focused rejection tests for disabled mode, incomplete acceptance, duplicate PID, unsafe lease, stale health, unchanged boot epoch, identity mismatch, logged-in observer evidence, and observer health/PID mismatch. The successful test must assert enabled mode and one PID remain after both commands and all temporary artifacts are removed after finish.

- [ ] **Step 3: Run focused tests to prove RED**

Run:

```bash
swift test --filter ProductionManagementScriptTests/testDeploymentReboot
```

Expected: failures because the commands and helper contracts do not exist.

- [ ] **Step 4: Commit RED tests**

```bash
git add Tests/LidMonitorTests/ProductionManagementScriptTests.swift
git commit -m "test: define enabled reboot acceptance contract"
```

### Task 2: Implement atomic reboot state and observer artifacts

**Files:**
- Modify: `scripts/lib/production-deployment-state.sh`
- Create: `scripts/lib/production-reboot-observer.sh`
- Create: `packaging/com.crazydennies.macbook-lid-monitor.reboot-observer.plist`
- Modify: `Tests/LidMonitorTests/ProductionManagementScriptTests.swift`

**Interfaces:**
- Produces: fixed managed paths for reboot state, observer evidence, observer executable, and observer plist; atomic write/verify/remove helpers; one-shot observer output fields `schema`, `boot_epoch`, `observed_at`, `console_user`, `job_state`, `process_count`, `pid`, `mode`, `source_commit`, `version`, `hardware_profile`, `health_state`, and `health_pid`.

- [ ] **Step 1: Implement fixed paths and safe metadata verification**

Use the existing managed support directory and reject symlinks, non-regular files, wrong owner/group, mode other than `0600`, or link count other than one.

- [ ] **Step 2: Implement atomic reboot-state serialization**

Write schema 1, prepared boot epoch, installed version/source commit, pre-reboot PID, hardware model/chip/profile, and preparation timestamp using same-directory temporary file plus rename.

- [ ] **Step 3: Implement one-shot observer**

The observer must read only fixed production paths, write one atomic `0600` evidence record, and exit zero. Its plist must run in the system domain at load and must not keep alive or restart continuously.

- [ ] **Step 4: Run focused artifact tests**

Run:

```bash
swift test --filter ProductionManagementScriptTests/testDeploymentReboot
bash -n scripts/lib/production-deployment-state.sh scripts/lib/production-reboot-observer.sh
shellcheck -x scripts/lib/production-deployment-state.sh scripts/lib/production-reboot-observer.sh
plutil -lint packaging/com.crazydennies.macbook-lid-monitor.reboot-observer.plist
```

Expected: artifact and metadata tests pass; start/finish command tests may remain RED.

- [ ] **Step 5: Commit Task 2**

```bash
git add scripts/lib/production-deployment-state.sh scripts/lib/production-reboot-observer.sh packaging/com.crazydennies.macbook-lid-monitor.reboot-observer.plist Tests/LidMonitorTests/ProductionManagementScriptTests.swift
git commit -m "feat: add enabled reboot observer evidence"
```

### Task 3: Implement deployment reboot start and finish commands

**Files:**
- Modify: `scripts/manage-production-daemon.sh`
- Modify: `Tests/LidMonitorTests/ProductionManagementScriptTests.swift`

**Interfaces:**
- Produces: `deployment_reboot_start()` and `deployment_reboot_finish()`.

- [ ] **Step 1: Implement start preflight**

Require root, valid installed set, target hardware, complete acceptance, enabled mode, loaded job, exactly one PID, fresh `monitoring-armed` health matching that PID, closed crash circuit, and secure lease. Reject before artifact creation on any failure.

- [ ] **Step 2: Install and bootstrap temporary observer**

Create the state record, copy fixed observer executable/plist with root-safe metadata, boot out stale observer state if present, bootstrap the observer, and print a manual reboot instruction. Do not alter production mode or PID.

- [ ] **Step 3: Implement finish verification**

Verify state/evidence metadata, changed boot epoch, unchanged installed identity and hardware/profile, no graphical console user in observer evidence, enabled mode, auto-loaded job, exactly one post-reboot PID different from the prepared PID, armed health matching that PID, complete acceptance, and secure lease. Run `operational_baseline` before cleanup.

- [ ] **Step 4: Implement bounded cleanup**

Boot out and remove only the temporary observer plist/executable, observer evidence, and reboot state. Re-run the enabled one-PID/armed live checks after cleanup.

- [ ] **Step 5: Run focused tests to GREEN**

Run:

```bash
swift test --filter ProductionManagementScriptTests/testDeploymentReboot
```

Expected: all Task 21 focused tests pass.

- [ ] **Step 6: Commit Task 3**

```bash
git add scripts/manage-production-daemon.sh Tests/LidMonitorTests/ProductionManagementScriptTests.swift
git commit -m "feat: add enabled reboot acceptance commands"
```

### Task 4: Immediate review, remediation verification, and governance synchronization

**Files:**
- Modify: `docs/superpowers/reviews/2026-07-27-production-deployment-long-term-operation-implementation-task-reviews.md`
- Modify: `docs/superpowers/tasks/2026-07-27-production-deployment-long-term-operation-tasks.md`
- Create: `docs/validation/2026-07-28-enabled-reboot-acceptance-remediation.md`

**Interfaces:**
- Produces: review evidence that Task 21 is unblocked but still awaiting real reboot preparation execution.

- [ ] **Step 1: Perform immediate code and boundary review**

Trace both new commands and observer paths. Record any P0/P1 findings, fix them, and re-review. Explicitly prove historical Task 14 commands are unchanged and Task 21 paths cannot disable, replace, rollback, uninstall, or reboot production.

- [ ] **Step 2: Run focused and full verification**

Run:

```bash
swift test --filter ProductionManagementScriptTests
swift test
bash -n scripts/manage-production-daemon.sh scripts/lib/*.sh
shellcheck -x scripts/manage-production-daemon.sh scripts/lib/*.sh
git diff --check
```

Expected: 84-or-more management tests pass, full suite passes, and static checks are clean.

- [ ] **Step 3: Verify live production remained unchanged**

Read-only verify:

```text
mode=enabled
job=running
process-count=1
PID=33458 or a legitimate same-boot launchd replacement only if independently explained
health=monitoring-armed
acceptance=complete
lease=root:wheel 0600 regular single-link
```

- [ ] **Step 4: Synchronize authority**

Record the discrepancy, design/implementation remediation, verification, and residual enabled state. Keep Task 21 open but mark its command-interface prerequisite complete and ready for real reboot preparation.

- [ ] **Step 5: Commit remediation closure**

```bash
git add scripts packaging Tests docs
git commit -m "fix: add task 21 enabled reboot acceptance"
```
