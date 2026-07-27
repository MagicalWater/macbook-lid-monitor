# Milestone 16 — Production Deployment and Long-term Operation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Harden the accepted production LaunchDaemon for indefinite enabled operation, add an
evidence-bound deployment lifecycle, and deploy it on the validated Mac while preserving
installed/loaded/enabled/running state at closure.

**Architecture:** Shared Swift filesystem/integrity primitives enforce the same managed artifact
and sleep-authority contract inside the daemon and foreground real-sleep CLI. Focused shell
libraries own package verification, deployment acceptance, activation, observability, and
transactions. Bounded acceptance commands always restore disabled; only a fully evidenced
`activate` command and enabled reboot finish may preserve enabled state.

**Tech Stack:** Swift 6, Swift Package Manager, XCTest, Darwin/POSIX file and lock APIs, IOKit,
launchd, Bash, plist tooling, `shellcheck`, `shasum`, macOS process tools.

---

## Execution and governance rules

1. Execute one implementation Task at a time.
2. For every Task: write failing tests, prove RED, implement minimally, prove focused GREEN, run
   required full checks, perform immediate review, fix findings, re-review, document evidence, and
   commit independently.
3. Run a stage implementation review after Tasks 1–5, Tasks 6–13, and Tasks 14–21.
4. Do not use historical Task 12–14 system evidence as current deployment evidence.
5. Tasks 1–14 do not mutate `/Library`, launchd, sleep state, or reboot state.
6. Task 15 requires explicit merge/push authorization before formal-main integration.
7. Task 16 requires explicit install/bootstrap approval.
8. Task 17 requires explicit dry-run mode/acceptance approval because it mutates managed config and
   launchd state even though it cannot request real sleep.
9. Tasks 18, 19, and 20 require independent approvals for one real sleep, recovery resleep, and
   persistent activation.
10. Task 21 requires explicit reboot preparation approval; the user manually restarts the Mac.
10. No successful closure may call `disable`, `bootout`, rollback, or `uninstall` after final
    activation except as emergency failure cleanup followed by a complete redeployment.

## File responsibility map

### Swift production core

- `Sources/LidMonitorCore/Production/ProductionFileSystem.swift`
  - shared metadata, regular-file, link-count, owner/group/mode, and safe-parent inspection.
- `Sources/LidMonitorCore/SleepAuthorityLease.swift`
  - secure managed lease acquisition only; no deployment detection policy.
- `Sources/LidMonitorCore/Production/SleepAuthorityPathResolver.swift`
  - selects managed or foreground-only fallback path based on production markers.
- `Sources/LidMonitorCore/Production/ProductionInstalledSetVerifier.swift`
  - manifest parsing, checksums, normalized config, metadata, prohibited plist environment, and
    enabled runtime authorization.
- `Sources/LidMonitorCore/Production/ProductionHealthStore.swift`
  - bounded root-owned runtime health snapshot persistence.
- `Sources/LidMonitorCore/Production/ProductionDaemonApplication.swift`
  - composition only; no production requester environment override.
- `Sources/LidMonitorCore/CLI.swift`
  - foreground real-sleep uses the same resolver and lease as installed production.

### Packaging and operator tooling

- `scripts/manage-production-daemon.sh`
  - command dispatch and short orchestration functions.
- `scripts/lib/production-package-common.sh`
  - immutable paths, source package preparation, generic hashing, root/test-root seams.
- `scripts/lib/production-installed-set.sh`
  - installed metadata, manifest, checksum, normalized config, and prohibited-entry verification.
- `scripts/lib/production-deployment-state.sh`
  - target model evidence, acceptance/reboot plist state, invalidation, and identity comparison.
- `scripts/lib/production-observability.sh`
  - status, diagnostics, crash snapshot, process metrics, health snapshot, log metadata, baseline.
- `packaging/manifest/manifest.plist.example`
  - complete artifact and deployment schema.
- `docs/operations/production-daemon.md`
  - long-term operator runbook.

### Tests

- `Tests/LidMonitorTests/ProductionFileSystemTests.swift`
- `Tests/LidMonitorTests/SleepAuthorityLeaseTests.swift`
- `Tests/LidMonitorTests/AutoSleepIntegrationTests.swift`
- `Tests/LidMonitorTests/ProductionDaemonCompositionTests.swift`
- `Tests/LidMonitorTests/ProductionInstalledSetVerifierTests.swift`
- `Tests/LidMonitorTests/ProductionHealthStoreTests.swift`
- `Tests/LidMonitorTests/ProductionPackagingTests.swift`
- `Tests/LidMonitorTests/ProductionManagementScriptTests.swift`

## Stage A — Runtime authority and installed identity

### Task 1: Shared secure filesystem metadata and managed lease primitive

**Purpose:** Make owner/group/mode/type/link-count/parent safety reusable and prevent a replaceable
or hard-linked sleep-authority inode.

**Files:**

- Create: `Sources/LidMonitorCore/Production/ProductionFileSystem.swift`
- Modify: `Sources/LidMonitorCore/Production/ProductionConfigurationLoader.swift`
- Modify: `Sources/LidMonitorCore/SleepAuthorityLease.swift`
- Create: `Tests/LidMonitorTests/ProductionFileSystemTests.swift`
- Modify: `Tests/LidMonitorTests/SleepAuthorityLeaseTests.swift`

- [x] **Step 1: Add failing metadata and lease tests**

Add tests named:

```swift
func testManagedLeaseRejectsUserWritableParent()
func testManagedLeaseRejectsUnexpectedOwnerGroupModeAndLinkCount()
func testManagedLeaseCannotSplitAuthorityAcrossReplacementInodes()
func testManagedLeaseAcceptsOneRootOwnedRegularInode()
func testConfigurationLoaderUsesSharedMetadataContract()
```

The replacement test must acquire inode A, unlink/recreate the path where permissions allow, and
prove the managed policy rejects the unsafe setup rather than allowing a second independent lock.

- [x] **Step 2: Prove RED**

Run:

```bash
swift test --filter 'ProductionFileSystemTests|SleepAuthorityLeaseTests|ProductionConfigurationTests'
```

Expected: FAIL because shared metadata and managed policy do not exist and current `/tmp` behavior
does not enforce the required owner/parent/link contract.

- [x] **Step 3: Introduce shared metadata types**

Implement the following stable shape:

```swift
struct ProductionFileMetadata: Equatable, Sendable {
    let ownerID: UInt32
    let groupID: UInt32
    let permissions: UInt16
    let fileType: ProductionFileType
    let linkCount: UInt64
}

enum ProductionFileType: Equatable, Sendable {
    case regularFile
    case directory
    case symbolicLink
    case other
}

protocol ProductionFileSystemInspecting: Sendable {
    func metadata(at path: String, followSymbolicLink: Bool) throws -> ProductionFileMetadata
}
```

Use `lstat` for path identity and `fstat` after open. Configuration loading must preserve its
existing stable errors while using the shared metadata representation.

- [x] **Step 4: Harden lease acquisition**

`POSIXSleepAuthorityLease` must accept an explicit policy containing expected owner/group,
permissions, link count, and parent-directory requirements. Managed acquisition must:

```text
lstat parent and path
→ reject symlink/unsafe parent
→ open O_RDWR|O_NOFOLLOW without O_CREAT
→ fstat opened inode
→ verify same required metadata and link-count=1
→ acquire LOCK_EX|LOCK_NB
```

Creation of the managed lease belongs to installation, not daemon startup.

- [x] **Step 5: Prove focused GREEN and full regression**

Run:

```bash
swift test --filter 'ProductionFileSystemTests|SleepAuthorityLeaseTests|ProductionConfigurationTests'
swift test
```

Expected: all focused tests and the complete suite pass.

- [x] **Step 6: Immediate Task 1 review and commit**

Review TOCTOU boundaries, test-root seams, existing configuration errors, and absence of `/Library`
mutation. Record review in the Milestone implementation review log, fix/re-review, then commit:

```bash
git add Sources/LidMonitorCore/Production/ProductionFileSystem.swift \
  Sources/LidMonitorCore/Production/ProductionConfigurationLoader.swift \
  Sources/LidMonitorCore/SleepAuthorityLease.swift \
  Tests/LidMonitorTests/ProductionFileSystemTests.swift \
  Tests/LidMonitorTests/SleepAuthorityLeaseTests.swift
git commit -m "fix: harden production sleep authority inode"
```

### Task 2: Shared authority path resolution for daemon and foreground CLI — complete

**Purpose:** Ensure installed production and foreground `--execute-sleep` can never use different
authority paths.

**Files:**

- Create: `Sources/LidMonitorCore/Production/SleepAuthorityPathResolver.swift`
- Modify: `Sources/LidMonitorCore/Production/ProductionDaemonApplication.swift`
- Modify: `Sources/LidMonitorCore/CLI.swift`
- Modify: `Tests/LidMonitorTests/AutoSleepIntegrationTests.swift`
- Modify: `Tests/LidMonitorTests/ProductionDaemonCompositionTests.swift`
- Modify: `Tests/LidMonitorTests/SleepAuthorityLeaseTests.swift`

- [x] **Step 1: Add failing resolver/composition tests**

Cover:

```swift
func testInstalledProductionAndForegroundResolveSameManagedLease()
func testForegroundFallbackRequiresAllProductionMarkersAbsent()
func testLoadedProductionJobMarkerProhibitsFallback()
func testMissingOrUnsafeManagedLeaseFailsOpenWhenProductionInstalled()
func testDryRunDoesNotResolveOrAcquireRealSleepAuthority()
```

- [x] **Step 2: Prove RED**

```bash
swift test --filter 'AutoSleepIntegrationTests|ProductionDaemonCompositionTests|SleepAuthorityLeaseTests'
```

- [x] **Step 3: Implement resolver**

Use a testable marker contract:

```swift
struct ProductionInstallationMarkers: Sendable {
    let binaryExists: Bool
    let plistExists: Bool
    let manifestExists: Bool
    let jobRegistered: Bool
}

enum SleepAuthorityPathResolution: Equatable, Sendable {
    case managed(String)
    case foregroundFallback(String)
    case unsafeInstalledState
}
```

Any production marker selects managed-or-fail-open; fallback is allowed only when every marker is
absent.

- [x] **Step 4: Wire both real-sleep compositions**

Production enabled and foreground execute-sleep use the resolver plus the same managed policy.
Diagnostic and dry-run paths remain lease-free.

- [x] **Step 5: Run focused/full verification, review, and commit**

```bash
swift test --filter 'AutoSleepIntegrationTests|ProductionDaemonCompositionTests|SleepAuthorityLeaseTests'
swift test
git add Sources/LidMonitorCore/Production/SleepAuthorityPathResolver.swift \
  Sources/LidMonitorCore/Production/ProductionDaemonApplication.swift \
  Sources/LidMonitorCore/CLI.swift \
  Tests/LidMonitorTests/AutoSleepIntegrationTests.swift \
  Tests/LidMonitorTests/ProductionDaemonCompositionTests.swift \
  Tests/LidMonitorTests/SleepAuthorityLeaseTests.swift
git commit -m "fix: unify production sleep authority resolution"
```

### Task 3: Remove deployable requester environment injection — complete

**Purpose:** Make the production executable always compose the real requester in enabled mode while
retaining dependency-injected failure tests.

**Files:**

- Modify: `Sources/LidMonitorCore/Production/ProductionDaemonApplication.swift`
- Modify: `Tests/LidMonitorTests/ProductionDaemonCompositionTests.swift`
- Modify: `Tests/LidMonitorTests/ProductionManagementScriptTests.swift`
- Modify: `scripts/manage-production-daemon.sh`

- [x] **Step 1: Add failing source/package tests**

```swift
func testDeployableProductionSourceContainsNoSleepOperationEnvironmentOverride()
func testProductionPlistAndManagedPlistRejectEnvironmentVariables()
func testInjectedRequesterFailureRemainsCoveredThroughDependencies()
```

- [x] **Step 2: Prove RED**

```bash
swift test --filter 'ProductionDaemonCompositionTests|ProductionManagementScriptTests'
```

- [x] **Step 3: Remove `ProcessInfo` requester selection**

Enabled composition becomes equivalent to:

```swift
return MacOSSleepRequester(
    operation: IOKitSystemSleepOperation(),
    onEvent: productionSleepEventHandler
)
```

Keep injected-failure coverage at the `requesterFactory` dependency seam. Remove or retire the
old system-level acceptance command that edits LaunchDaemon `EnvironmentVariables`; do not replace
it with another deployable override.

- [x] **Step 4: Verify and commit**

```bash
swift test --filter 'ProductionDaemonCompositionTests|ProductionManagementScriptTests'
swift test
git add Sources/LidMonitorCore/Production/ProductionDaemonApplication.swift \
  Tests/LidMonitorTests/ProductionDaemonCompositionTests.swift \
  Tests/LidMonitorTests/ProductionManagementScriptTests.swift \
  scripts/manage-production-daemon.sh
git commit -m "fix: remove production sleep requester override"
```

### Task 4: Complete package manifest and source preparation integrity — complete

**Purpose:** Record binary, plist, normalized disabled config, source commit, profile, and managed
paths in one reproducible package identity.

**Files:**

- Modify: `packaging/manifest/manifest.plist.example`
- Modify: `scripts/lib/production-package-common.sh`
- Modify: `scripts/manage-production-daemon.sh`
- Modify: `Tests/LidMonitorTests/ProductionPackagingTests.swift`
- Modify: `Tests/LidMonitorTests/ProductionManagementScriptTests.swift`

- [x] **Step 1: Add failing schema and checksum tests**

Require manifest keys:

```text
SchemaVersion
Product
SourceCommit
Version
BinaryPath / BinarySHA256
PlistPath / PlistSHA256
ConfigPath / DisabledConfigSHA256
HardwareProfileID
CrashBudgetPath
SleepAuthorityPath
AcceptanceStatePath
HealthStatePath
```

- [x] **Step 2: Prove RED**

```bash
swift test --filter 'ProductionPackagingTests|ProductionManagementScriptTests'
```

- [x] **Step 3: Implement deterministic preparation**

`prepare` must build, copy, chmod, lint, calculate all hashes, and write the exact full source
commit. `verify` must recompute every staged hash and reject `EnvironmentVariables` in the staged
plist.

- [x] **Step 4: Verify package reproduction**

```bash
rm -rf .build/production-package
./scripts/manage-production-daemon.sh prepare
./scripts/manage-production-daemon.sh verify
plutil -lint .build/production-package/*.plist
swift test --filter 'ProductionPackagingTests|ProductionManagementScriptTests'
```

- [x] **Step 5: Review and commit**

Review mutable-mode normalization boundaries and source-commit accuracy, then commit:

```bash
git add packaging/manifest/manifest.plist.example \
  scripts/lib/production-package-common.sh \
  scripts/manage-production-daemon.sh \
  Tests/LidMonitorTests/ProductionPackagingTests.swift \
  Tests/LidMonitorTests/ProductionManagementScriptTests.swift
git commit -m "feat: complete production package identity"
```

### Task 5: Runtime installed-set verification — complete

**Purpose:** Prevent enabled requester construction when installed binary/plist/config/manifest or
metadata no longer matches the accepted package.

**Files:**

- Create: `Sources/LidMonitorCore/Production/ProductionInstalledSetVerifier.swift`
- Modify: `Sources/LidMonitorCore/Production/ProductionDaemonApplication.swift`
- Create: `Tests/LidMonitorTests/ProductionInstalledSetVerifierTests.swift`
- Modify: `Tests/LidMonitorTests/ProductionDaemonCompositionTests.swift`

- [x] **Step 1: Add failing verifier tests**

Test valid set plus binary/plist/config mismatch, non-mode config drift, mode-only normalization,
manifest schema/path mismatch, unsafe metadata, hard links, and prohibited environment entries.

- [x] **Step 2: Prove RED**

```bash
swift test --filter 'ProductionInstalledSetVerifierTests|ProductionDaemonCompositionTests'
```

- [x] **Step 3: Implement verifier API**

```swift
protocol ProductionInstalledSetVerifying: Sendable {
    func verify(mode: ProductionMode) throws -> ProductionInstalledSetIdentity
}

struct ProductionInstalledSetIdentity: Equatable, Sendable {
    let sourceCommit: String
    let manifestSHA256: String
    let binarySHA256: String
    let plistSHA256: String
    let normalizedConfigSHA256: String
    let currentConfigSHA256: String
    let hardwareProfileID: String
}
```

Use injected readers/hashers in tests. Enabled startup verifies before acquiring authority or
constructing `MacOSSleepRequester`. Failure emits stable `installed-set-invalid-*` evidence and
exits fail-open without restart storm semantics changing.

- [x] **Step 4: Verify, review, and commit**

```bash
swift test --filter 'ProductionInstalledSetVerifierTests|ProductionDaemonCompositionTests'
swift test
swift build -c release --product macbook-lid-monitor-daemon
git add Sources/LidMonitorCore/Production/ProductionInstalledSetVerifier.swift \
  Sources/LidMonitorCore/Production/ProductionDaemonApplication.swift \
  Tests/LidMonitorTests/ProductionInstalledSetVerifierTests.swift \
  Tests/LidMonitorTests/ProductionDaemonCompositionTests.swift
git commit -m "feat: verify installed set before enabled runtime"
```

### Stage A implementation review

- [x] Independently review Tasks 1–5 for TOCTOU, inode identity, fallback ambiguity, requester
  composition, checksum normalization, stable errors, and fail-open exit behavior.
- [x] Run full tests, release builds for all products, package prepare/verify, Bash syntax,
  shellcheck, plist lint, and `git diff --check`.
- [x] Fix/re-review every finding and commit Stage A closure.

## Stage B — Deployment lifecycle and operations

### Task 6: Shell installed-set verifier, managed metadata, and lifecycle guard

**Purpose:** Give every mutating command one shared integrity preflight and serialize lifecycle
mutation rather than duplicating partial checks or relying on operator timing.

**Files:**

- Create: `scripts/lib/production-installed-set.sh`
- Modify: `scripts/lib/production-package-common.sh`
- Modify: `scripts/manage-production-daemon.sh`
- Modify: `Tests/LidMonitorTests/ProductionManagementScriptTests.swift`

- [x] Write sandbox tests for expected/actual checksums, normalized config, owner/group/mode/type,
  link count, unsafe ancestors, prohibited plist environment, and stable key-value output.
- [x] Add a concurrent sandbox test proving a second install/upgrade/rollback/uninstall lifecycle
  mutation fails before changing files while the first operation holds the guard.
- [x] Prove RED with `swift test --filter ProductionManagementScriptTests`.
- [x] Implement and source these stable shell interfaces:

```bash
verify_managed_metadata PATH EXPECTED_TYPE EXPECTED_OWNER EXPECTED_GROUP EXPECTED_MODE EXPECTED_LINKS
normalized_config_sha256 CONFIG_PATH
verify_installed_set
installed_identity_lines
with_lifecycle_guard COMMAND [ARGUMENTS...]
```

`verify_installed_set` returns non-zero on any mismatch and emits stable error keys without changing
mode, job state, or files. `with_lifecycle_guard` uses an atomic transient lock directory below the
root-owned support directory, rejects symlink/unsafe ancestors, records no password/token, cleans up
on normal/signal exit, and returns a stable busy error for concurrent mutation.
- [x] Require verification before bootstrap, dry-run, bounded acceptance, activation, baseline,
  upgrade, rollback, and reboot finish.
- [x] Require the lifecycle guard around install, upgrade, rollback, uninstall, and any future
  whole-set replacement; mode-only operations use installed verification but not the whole-set
  lifecycle guard.
- [x] Run focused/full/static checks, immediate review, and commit
  `feat: add shared installed set verification`.

### Task 7: Target preflight and atomic deployment acceptance state

**Purpose:** Bind fresh dry-run and real-sleep evidence to one installed artifact identity and the
validated non-unique hardware compatibility fields.

**Files:**

- Create: `scripts/lib/production-deployment-state.sh`
- Modify: `scripts/manage-production-daemon.sh`
- Modify: `scripts/lib/production-package-common.sh`
- Modify: `Tests/LidMonitorTests/ProductionManagementScriptTests.swift`

- [ ] Add failing tests for model/chip mismatch, missing/partial/stale acceptance, atomic writes,
  checksum mismatch, install/upgrade/rollback invalidation, and privacy exclusions.
- [ ] Implement these state interfaces with root-owned `0600` temp+rename writes:

```bash
target_hardware_identity_lines
deployment_identity_lines
record_deployment_acceptance STAGE RESULT
verify_deployment_acceptance REQUIRED_STAGES...
invalidate_deployment_acceptance REASON
write_deployment_reboot_state BOOT_EPOCH
verify_deployment_reboot_state
```

- [ ] Store only source/artifact checksums, profile, `MacBookPro18,1`, Apple M1 Pro, timestamps, and
  pass/fail state; never store serial/UUID/UDID/raw reports.
- [ ] Add `invalidate_deployment_acceptance` to install, upgrade, rollback, and non-mode config
  changes.
- [ ] Verify, review, and commit `feat: add deployment acceptance identity`.

### Task 8: Bounded deployment acceptance commands and persistent activation

**Purpose:** Replace historical Task-specific commands with stable deployment commands and one
evidence-bound persistent activation path.

**Files:**

- Modify: `scripts/manage-production-daemon.sh`
- Modify: `scripts/lib/production-deployment-state.sh`
- Modify: `scripts/lib/production-installed-set.sh`
- Modify: `Tests/LidMonitorTests/ProductionManagementScriptTests.swift`

- [ ] Add sandbox tests for `deployment-dry-run`, `deployment-enabled-once`,
  `deployment-recovery-resleep`, and `activate`.
- [ ] Prove all bounded commands return disabled on success, timeout, signal, malformed evidence,
  and injected script failure.
- [ ] Prove `activate` rejects partial/mismatched acceptance and leaves enabled only with complete
  matching evidence.
- [ ] Implement one atomic mode editor and the command contracts:

```bash
set_managed_mode disabled|dry-run|enabled
deployment_dry_run
deployment_enabled_once
deployment_recovery_resleep
activate_deployment
```

Bounded commands wrap the editor with mandatory cleanup traps,
  while `activate` intentionally has no disable cleanup after final verification succeeds.
- [ ] Verify no unrestricted `enable` dispatcher entry exists.
- [ ] Focused/full review and commit `feat: add evidence-bound production activation`.

### Task 9: Bounded runtime health persistence

**Purpose:** Connect production health state to a root-owned, low-write snapshot consumed by status
and diagnostics.

**Files:**

- Create: `Sources/LidMonitorCore/Production/ProductionHealthStore.swift`
- Modify: `Sources/LidMonitorCore/Production/DaemonHealth.swift`
- Modify: `Sources/LidMonitorCore/Production/ProductionDaemonApplication.swift`
- Create: `Tests/LidMonitorTests/ProductionHealthStoreTests.swift`
- Modify: `Tests/LidMonitorTests/ProductionDaemonCompositionTests.swift`

- [ ] Add failing atomicity, metadata, state-transition, throttling, stale/corrupt, and redaction
  tests.
- [ ] Implement a plist/JSON snapshot containing version, mode, profile, state, PID, transition
  timestamp, last-valid-sample timestamp, and last stable error code.
- [ ] Write only on state/error transitions and a bounded sample heartbeat, never every HID report.
- [ ] Ensure health-store failure degrades observability but cannot create sleep authority.
- [ ] Focused/full/release verification, review, and commit `feat: persist bounded daemon health`.

### Task 10: Stable status, diagnostics, and operational baseline

**Purpose:** Expose all required long-term operational evidence without printing log contents or
unique identifiers.

**Files:**

- Create: `scripts/lib/production-observability.sh`
- Modify: `scripts/manage-production-daemon.sh`
- Modify: `Tests/LidMonitorTests/ProductionManagementScriptTests.swift`

- [ ] Add parser-friendly output tests for installed/version/commit/mode/job/PID/health/hardware,
  installed integrity, crash state, lease metadata/lock probe, acceptance state, checksums, process
  elapsed/CPU/RSS/VSZ, and logs.
- [ ] Add corrupt/missing state tests and verify stable `unavailable`/`corrupt` values.
- [ ] Implement read-only stable interfaces:

```bash
status_job
diagnostics
crash_budget_status_lines
process_metric_lines PID
health_status_lines
log_status_lines
operational_baseline
```

Diagnostics must not `cat` or `tail` logs.
- [ ] Implement `operational-baseline` as a strict verifier that requires enabled, loaded, exactly
  one PID, healthy monitoring evidence, matching acceptance, and valid installed identity.
- [ ] Verify, review, and commit `feat: add production operational baseline`.

### Task 11: Online-safe log rotation

**Purpose:** Bound logs without moving the inode currently held by launchd and the daemon.

**Files:**

- Modify: `scripts/lib/production-observability.sh`
- Modify: `scripts/manage-production-daemon.sh`
- Modify: `Tests/LidMonitorTests/ProductionManagementScriptTests.swift`

- [ ] Create a running-writer regression fixture that records primary inode, rotates, writes again,
  and proves the new event appears in the primary path.
- [ ] Prove RED against the current move-based implementation.
- [ ] Implement generation shift by copy, copy active log to `.1`, then truncate the active file in
  place while preserving owner/mode and active inode.
- [ ] Keep the public interface exact:

```bash
rotate_one_log_preserving_inode PATH 1048576 3
rotate_logs
```

- [ ] Retain at most three generations and rotate only above 1 MiB.
- [ ] Run focused/full/static checks, review, and commit `fix: preserve active production log inode`.

### Task 12: Disabled upgrade, rollback, and complete uninstall semantics

**Purpose:** Ensure maintenance never silently restores enabled authority or leaves new state
behind.

**Files:**

- Modify: `scripts/manage-production-daemon.sh`
- Modify: `scripts/lib/production-installed-set.sh`
- Modify: `scripts/lib/production-deployment-state.sh`
- Modify: `Tests/LidMonitorTests/ProductionManagementScriptTests.swift`

- [ ] Add tests proving upgrade and explicit/automatic rollback require/force disabled,
  nonresident state and finish disabled.
- [ ] Prove acceptance invalidation on artifact/policy change and safe preservation only for
  evidence-only repository commits that do not change installed identity.
- [ ] Extend uninstall tests to lease, acceptance, reboot state, health state, crash state, logs,
  and rollback while preserving unrelated files.
- [ ] Prove rollback failure leaves the job booted out and returns failure.
- [ ] Preserve these explicit transaction boundaries:

```bash
prepare_maintenance_disabled_state
backup_current_set
activate_staged_set_disabled
restore_rollback_set_disabled
upgrade_package
rollback_upgrade
uninstall_package
```

- [ ] Verify, review, and commit `fix: make production maintenance activation-safe`.

### Task 13: Long-term operator runbook and repository synchronization

**Purpose:** Make routine and emergency operation reproducible after Milestone closure.

**Files:**

- Create: `docs/operations/production-daemon.md`
- Modify: `README.md`
- Modify: relevant architecture/spec/plan/task status sections after implementation evidence exists
- Modify: `Tests/LidMonitorTests/ProductionManagementScriptTests.swift`

- [ ] Document status, diagnostics, disable, crash-budget reset, log rotation, upgrade, rollback,
  uninstall, foreground real-sleep conflict, circuit-open recovery, integrity failure, and emergency
  bootout.
- [ ] State which commands leave enabled and which force disabled.
- [ ] Include exact expected state checks and warnings for real sleep/reboot.
- [ ] Add a test or static review that every documented management command exists and no
  unrestricted enable command is documented.
- [ ] Review docs against actual dispatcher/output and commit `docs: add production daemon runbook`.

### Stage B implementation review

- [ ] Review all root mutation and state-transition code independently from Task reviews.
- [ ] Trace every management command through installed verifier, authority state, acceptance
  invalidation, safe cleanup, and final mode.
- [ ] Run full test/build/static/package/clean-snapshot validation.
- [ ] Fix/re-review and commit Stage B closure.

## Stage C — Release and real deployment

### Task 14: Full automated and clean-checkout release gate

**Purpose:** Establish an implementation-complete release candidate before any system mutation.

**Files:**

- Create: `docs/superpowers/reviews/2026-07-27-production-deployment-long-term-operation-implementation-review.md`
- Create: `docs/validation/2026-07-27-production-deployment-automated-gate.md`
- Update: Milestone Task review/status documents

- [ ] Run all  Swift tests with exact count and zero failures.
- [ ] Build all four release products.
- [ ] Run `bash -n`, `shellcheck -x`, plist lint, package prepare/verify, and `git diff --check`.
- [ ] Validate an independent clean snapshot excluding `.git` and `.build`.
- [ ] Verify no `/Library`/launchd/sleep/reboot mutation occurred and production remains uninstalled.
- [ ] Perform holistic implementation review, fix/re-review all findings, and commit the release
  candidate closure.

### Task 15: Formal-main integration and package provenance gate

**Approval:** Explicit user authorization is required before merge, push, or worktree cleanup.

**Purpose:** Ensure the real package is built from the exact approved formal-main release commit.

- [ ] Present release candidate commit range, tests, findings disposition, and merge strategy.
- [ ] After approval, integrate to formal `main` without rewriting unrelated history.
- [ ] Verify formal `main == origin/main`, both clean, and exact release commit recorded.
- [ ] Reopen/create the deployment worktree at the approved formal-main release commit if needed.
- [ ] Run package `prepare` and `verify` from that exact commit.
- [ ] Do not install in this Task.

### Task 16: Disabled production installation

**Approval:** Explain exact `/Library` paths and launchd effects, then obtain explicit approval.

**Purpose:** Install the approved release in its safest persistent state and verify artifact/job
identity before any monitoring mode is started.

- [ ] Capture broad pre-install residual inventory and explicitly dispose of the historical
  user-owned `/private/tmp/macbook-lid-monitor-task15-final-test.log` only with user approval.
- [ ] Install root-owned artifacts in disabled mode, create the managed lease, bootstrap the job,
  and verify loaded/disabled/zero PID plus every checksum and permission.
- [ ] Verify acceptance state is absent/invalidated, health state is absent or disabled, crash state
  is valid, and no foreground real-sleep process or duplicate authority exists.
- [ ] Record disabled-install evidence and immediate review. Leave loaded/disabled/zero PID.

### Task 17: Fresh installed dry-run acceptance

**Approval:** Explain that managed config and the system job will change to dry-run, but no real
sleep requester can be constructed; obtain explicit approval before the mutation.

**Purpose:** Prove the complete installed sensor/power path without granting real-sleep authority.

- [ ] Run logged-in installed dry-run close/debounce/would-sleep/reopen/rearm acceptance.
- [ ] Run installed dry-run sleep/wake continuity acceptance without sensor-driven real sleep.
- [ ] Verify one PID in dry-run, no duplicate authority, crash state, health, logs, and emergency
  disable; return loaded/disabled/zero PID.
- [ ] Record matching dry-run acceptance identity and immediate review; do not perform real sleep or
  activation.

### Task 18: Bounded one-sleep acceptance

**Approval:** Explain that closing the lid will issue one real sleep request and obtain explicit
approval immediately before the command.

**Purpose:** Produce fresh exactly-once sensor-driven sleep evidence while retaining fail-safe
cleanup to disabled.

- [ ] Run one bounded sensor-driven sleep; prove exactly one attempt, stable PID, wake evidence,
  and automatic return to disabled.
- [ ] Bind the pass result to the exact installed acceptance identity.
- [ ] Perform immediate review and leave loaded/disabled/zero PID.

### Task 19: Bounded recovery-resleep acceptance

**Approval:** Explain that the Mac will sleep, wake while still below threshold, then issue one
recovery resleep request; obtain separate explicit approval.

**Purpose:** Produce fresh bounded recovery evidence without granting persistent authority.

- [ ] Run one bounded recovery-resleep cycle; prove exactly two attempts, one recovery transition,
  no third request, stable PID, and automatic return to disabled.
- [ ] Bind the pass result to the exact installed acceptance identity.
- [ ] Perform immediate review and leave loaded/disabled/zero PID.

### Task 20: Persistent production activation

**Approval:** Review the complete dry-run, one-sleep, and recovery-resleep identity; explain that the
daemon will remain capable of real sleep after the command exits; obtain explicit approval.

**Purpose:** Deliberately enter and preserve the validated long-term enabled state.

- [ ] Re-verify installed identity, target compatibility, crash state, managed authority metadata,
  and all required acceptance stages.
- [ ] Run `activate` and verify installed/enabled/loaded,
  exactly one running PID, managed authority held, healthy monitoring, and no cleanup to disabled.
- [ ] Record activation evidence and leave enabled.

### Task 21: Enabled reboot, pre-login operation, baseline, and holistic closure

**Approval:** Obtain explicit approval before preparing reboot evidence. The script never reboots;
the user restarts manually.

**Purpose:** Prove the final state survives boot and close the Milestone without uninstalling.

- [ ] Prepare enabled reboot state and temporary pre-login observer evidence without changing mode.
- [ ] User manually reboots and remains at loginwindow for the documented observation window.
- [ ] Finish reboot proof: changed boot epoch, enabled retained, job auto-loaded, one PID, exact
  profile/model, pre-login health, no duplicate authority, temporary observer removed.
- [ ] Verify wake monitoring after reboot and capture strict operational baseline.
- [ ] Run current-checkout/formal-main/clean verification and final holistic review.
- [ ] Fix any finding through a safely redeployed release if required; otherwise record final state:

```text
package=installed
job=loaded
mode=enabled
process-count=1
daemon=running
boot-auto-start=verified
pre-login=verified
single-authority=verified
```

- [ ] Commit evidence-only closure. Do not disable, bootout, rollback, uninstall, push, merge, or
  clean the worktree without separate authorization.

### Stage C implementation review

- [ ] Independently review formal-main provenance, every real-system evidence document, approval
  records, enabled reboot proof, operational baseline, repository cleanliness, and final live
  system state.
- [ ] Confirm temporary acceptance/observer artifacts are removed while the production package,
  managed lease, health, acceptance, manifest, config, plist, logs, and daemon remain present.
- [ ] Fix/redeploy/re-review any finding; successful Stage C closure must still be enabled and
  running.

## Plan completion rule

The implementation Plan is complete only when Tasks 1–21 and all stage/holistic reviews pass. A
Task may be marked complete only with its own fresh review and verification evidence. System Tasks
cannot be pre-approved by Plan closure. The final system state is part of the product result, not
temporary acceptance scaffolding.
