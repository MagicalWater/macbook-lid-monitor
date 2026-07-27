# Milestone 16 Implementation Task Reviews

Date: 2026-07-27

## Task 1 — Shared secure filesystem metadata and managed lease primitive

### Implemented

- Added `ProductionFileSystem.swift` with shared file type, owner, group, permissions, link count,
  device, and inode metadata plus native `fstatat` inspection.
- Preserved the existing configuration-reader metadata contract through a compatibility initializer
  while moving native inspection to the shared implementation.
- Added explicit foreground-fallback and managed-production lease policies.
- Managed production policy requires an existing root:wheel regular file, mode `0666`, one link,
  root:wheel immediate parent, and no group/world-writable parent.
- Managed acquisition opens without `O_CREAT`, rejects symlinks and unsafe metadata, compares
  pre-open and opened device/inode identity, then acquires a non-blocking exclusive lock.
- Foreground fallback retains explicit creation behavior and existing same-inode exclusivity.

### TDD evidence

Initial RED:

```text
missing NativeProductionFileSystemInspector
missing SleepAuthorityLeasePolicy
missing unsafeParent / unsafeMetadata
extra policy argument rejected
```

Focused branch RED was separately demonstrated for:

- unexpected file owner;
- unexpected file group;
- unexpected parent owner;
- unexpected parent group;
- pre-open/opened inode mismatch.

Each branch failed because the corresponding production check was temporarily absent, then passed
after the minimal check was restored.

### Immediate review findings

#### T1-P1 — Owner and group checks lacked independent failing tests

The first GREEN implementation contained file owner/group checks, but the original RED suite only
proved mode, hard-link, and parent-writability behavior.

**Resolution:** withdraw the owner/group branches, add precise tests, observe two expected failures,
restore minimal checks, and re-run the focused suite.

#### T1-P1 — Parent identity and path-open identity lacked independent proof

The first re-review found no direct test for parent owner/group mismatch or the pre-open/opened
inode comparison.

**Resolution:** withdraw those branches, add three focused tests, observe three expected failures,
restore minimal checks, and re-run the focused suite.

#### T1-P2 — Swift `stat` function/type name conflict blocked compilation

`Darwin.stat(path, &info)` resolved to the `stat` structure initializer under this toolchain.

**Resolution:** use `fstatat(AT_FDCWD, ..., AT_SYMLINK_NOFOLLOW)` for one native metadata path that
supports both follow and no-follow behavior. This was a compile-only correction and did not alter
the security contract.

### Re-review

- Managed policy cannot create a missing lease: pass by `createIfMissing=false` and open flags.
- Managed policy hard-codes root/wheel/0666/single-link/safe-parent expectations: pass.
- Symlink, non-regular, mode, hard-link, owner, group, parent, replacement, and already-held paths
  are covered: pass.
- Configuration errors and existing fake-reader tests remain stable: pass.
- No daemon/CLI composition path is changed yet; Task 2 remains responsible for managed path
  selection: pass.
- No `/Library`, launchd, sleep, reboot, merge, push, or worktree cleanup occurred: pass.

### Verification

```text
focused: 21 tests, 0 failures
full XCTest: 209 tests, 0 failures
release build: macbook-lid-monitor-daemon passed
git diff --check: passed
```

### Decision

**Task 1 approved.** No Critical/P0/P1 finding remains. Task 2 may begin after the Task 1 commit.

## Task 2 — Shared authority path resolution for daemon and foreground CLI

### Implemented

- Added `SleepAuthorityPathResolver` and explicit production marker/result contracts.
- Any production artifact, registered system job, or managed lease marker selects managed-or-fail-open.
- Foreground fallback is available only when all production markers are absent.
- Both foreground execute-sleep and production enabled composition use the resolver; dry-run remains lease-free.
- Native marker collection checks binary, plist, manifest, managed lease, and the system launchd label.

### TDD evidence

The initial focused build failed because the resolver, marker, and result types did not exist. After
the minimal resolver was added, resolver and composition tests passed.

### Immediate review finding

#### T2-P1 — Native marker collection initially omitted loaded-job detection

The first GREEN implementation defaulted `jobRegistered=false`, which could have allowed fallback
after artifacts were removed while the launchd job remained registered.

**Resolution:** add a bounded `/bin/launchctl print system/com.crazydennies.macbook-lid-monitor`
probe and a testable override. A loaded-job-without-files test now resolves to unsafe installed state.

### Re-review

- Installed daemon and foreground resolve the same managed path: pass.
- Missing managed lease with any production marker fails open: pass.
- Loaded job alone prohibits fallback: pass.
- Dry-run does not resolve or acquire authority: pass.
- Existing injected leasing tests remain valid: pass.
- No system mutation occurred: pass.

### Verification

```text
focused: 33 tests, 0 failures
full XCTest: 215 tests, 0 failures
release build: macbook-lid-monitor-daemon passed
```

### Decision

**Task 2 approved.** No Critical/P0/P1 finding remains. Task 3 may begin.

## Task 3 — Remove deployable requester environment injection

### Implemented

- Production enabled composition now always constructs `IOKitSystemSleepOperation`.
- Removed `MLM_SLEEP_OPERATION` inspection from deployable Swift source.
- Removed the management command that modified LaunchDaemon `EnvironmentVariables`.
- Removed the dispatcher and usage entry for the retired injected-failure acceptance path.
- Retained sleep failure coverage through existing dependency-injected requester tests.

### Immediate review

- Deployable source contains no environment requester override: pass.
- Management script contains no `MLM_SLEEP_OPERATION` or `EnvironmentVariables`: pass.
- Production plist is no longer mutated for failure injection: pass.
- Existing requester failure/non-retry behavior remains covered at the dependency seam: pass.
- No system mutation occurred: pass.

### Verification

```text
focused: 52 tests, 0 failures
full XCTest: 215 tests, 0 failures
bash -n: passed
```

### Decision

**Task 3 approved.** No Critical/P0/P1 finding remains. Task 4 may begin.

## Task 4 — Complete package manifest and source preparation integrity

### Implemented

- Manifest now records full source commit, binary/plist/disabled-config hashes, hardware profile,
  managed authority path, deployment acceptance path, and health path.
- `prepare` writes the exact full Git commit and all staged artifact checksums.
- `verify` recomputes binary/plist/config checksums, checks exact source commit and version, lints
  every plist, and rejects staged LaunchDaemon environment variables.
- Sandbox staging fixtures now produce the same complete manifest identity as production staging.

### TDD evidence

The initial focused run produced ten expected failures for missing manifest keys and missing package
preparation assignments. After implementation, lifecycle sandbox tests initially failed before
mutation because their fixture still emitted the legacy one-checksum manifest.

### Immediate review finding

#### T4-P1 — Sandbox fixture did not implement the new package contract

The first GREEN package implementation was correct, but `seedStaging()` omitted source, plist, and
config identity. This caused `verify_package` to reject fixtures and generated secondary cleanup
noise.

**Resolution:** update the fixture to calculate the same complete identity and narrow the source
override assertion to actual Add/Delete environment mutations. Production verification remained
strict.

### Re-review

- Full source commit is recorded and verified: pass.
- Binary, plist, and disabled-template config hashes are reproducible: pass.
- Staged environment variables are rejected: pass.
- Hardware/profile and managed state paths are fixed in the manifest: pass.
- Package preparation performs no `/Library` or launchd mutation: pass.

### Verification

```text
focused: 46 tests, 0 failures
full XCTest: 215 tests, 0 failures
prepare/verify: passed
plist lint: passed
bash -n: passed
git diff --check: passed
```

### Decision

**Task 4 approved.** No Critical/P0/P1 finding remains. Task 5 may begin.

## Task 5 — Runtime installed-set verification

### Implemented

- Added native and injectable installed-set readers, SHA-256 hashing, fixed managed paths, identity,
  and verifier contracts.
- Verifier checks owner/group/mode/type/link-count for binary, plist, config, and manifest.
- Manifest paths, schema, binary/plist hashes, hardware profile, and prohibited environment entries
  are validated.
- Config identity uses sorted-key canonical JSON after normalizing only `Mode=disabled`, allowing
  mode transitions while rejecting every other policy drift.
- Enabled daemon startup verifies the installed set before HID enumeration, sleep authority, or
  requester construction and fails open with stable evidence.
- Package preparation/verification now produces the identical canonical config hash.

### TDD and review findings

- RED proved all verifier types and behavior were absent.
- Binary-plist normalization was nondeterministic because dictionary serialization order is
  unspecified. Replaced with sorted-key canonical JSON.
- The first fixture generated expected identity from already-mutated config. Expected template and
  current config were separated, proving non-Mode drift rejection.
- Shell package hashing initially remained raw bytes. It now uses the same canonical semantic hash.

### Re-review

- Valid set and mode-only change: pass.
- Binary/plist/config/path/metadata/hard-link/environment mismatch: fail-open pass.
- Invalid installed set precedes authority/requester construction: pass.
- Package/runtime canonical hash equality: pass.
- No system mutation occurred: pass.

### Verification

```text
focused verifier/composition: 16 tests, 0 failures
focused package/verifier: 52 tests, 0 failures
full XCTest: 221 tests, 0 failures
package prepare/verify: passed
release daemon build: passed
git diff --check: passed
```

### Decision

**Task 5 approved.** No Critical/P0/P1 finding remains. Stage A review may begin.

## Task 6 — Shell installed-set verifier, managed metadata, and lifecycle guard

### RED evidence

The first focused run failed because `scripts/lib/production-installed-set.sh` did not exist. The
new tests therefore proved the shared verifier and lifecycle interfaces were absent before any
production implementation was added.

### Implemented

- Added one shared shell verifier for metadata, fixed manifest identity, binary/plist/config
  checksums, canonical disabled-config hashing, prohibited LaunchDaemon environment entries, and
  stable installed identity output.
- Added root/test-root expected ownership, exact type/mode/link-count checks, symlink rejection,
  and safe ancestor validation.
- Added one atomic lifecycle guard below the managed support directory. Install, upgrade, rollback,
  and uninstall share that guard; mode-only commands verify integrity without taking it.
- Added verification before bootstrap, mode transitions, reset, upgrade, rollback, uninstall, and
  reboot finish. Historical bounded acceptance paths inherit the same preflight through these
  shared operations.
- Added a sandbox-only deterministic guard-hold hook, with static protection preventing production
  use.

### Immediate review findings

#### T6-P1 — Shell canonical JSON initially added a newline

The initial implementation used Python `print`, producing a different hash from Swift's canonical
JSON bytes.

**Resolution:** write canonical JSON with `sys.stdout.write` and no trailing newline. Mode-only
config changes now match the Swift runtime policy exactly.

#### T6-P1 — Verifier failures could emit an error and continue

The initial helper returned nonzero, but callers did not always return immediately. This allowed a
corrupt manifest to reach later upgrade code under some shell execution contexts.

**Resolution:** make every verifier branch explicitly return on failure and add a regression proving
corrupt installed identity blocks upgrade before activation.

#### T6-P1 — Lifecycle guard temporarily disabled errexit

The first status-capture implementation used `set +e`, weakening nested integrity checks.

**Resolution:** preserve `errexit`, rely on the EXIT trap for failure cleanup, and retain explicit
status cleanup for conditional-call contexts.

#### T6-P2 — Guard cleanup could leave an empty support directory after uninstall

The guard directory existed while uninstall attempted to remove the support directory.

**Resolution:** guard cleanup now removes the lock first and then removes the support directory only
when empty.

#### T6-P2 — Signal cleanup did not explicitly terminate

The original signal trap only removed the guard.

**Resolution:** dedicated HUP/INT/TERM handlers remove the guard, clear traps, and exit with stable
signal-derived status. A deterministic sandbox test proves no managed binary is written.

### Re-review

- Verifier performs no state mutation: pass.
- Busy guard fails before managed file replacement with `error=lifecycle-busy`: pass.
- Normal and signal exits remove the guard: pass.
- Metadata verifies type, owner, group, mode, link count, symlink, and ancestors: pass.
- Shell and Swift normalized config hashes are identical: pass.
- Prohibited `EnvironmentVariables` remains rejected: pass.
- Mode-only operations do not take the whole-set guard: pass.
- Production cannot enable the test hold hook: pass.
- Install/upgrade/rollback/uninstall share one lifecycle guard: pass.
- Package prepare/verify behavior remains stable: pass.
- No `/Library`, launchd, sleep, reboot, merge, push, or worktree cleanup occurred: pass.

### Verification

```text
RED: missing production-installed-set.sh, expected focused failure
focused: 52 tests, 0 failures
full XCTest: 231 tests, 0 failures
bash -n: manager, package common, installed-set library passed
shellcheck: passed with zero findings
package prepare/verify: passed
release daemon build during prepare: passed
git diff --check: passed
```

### Remaining risk

Shell verification cannot eliminate every possible cross-process TOCTOU between final verification
and later command mutation. The lifecycle guard serializes supported whole-set mutations, while the
Swift daemon independently re-verifies the installed set at enabled startup.

### Decision

**Task 6 approved.** No Critical/P0/P1 finding remains. Task 7 may begin after the independent Task 6
commit.

## Task 7 — Target preflight and atomic deployment acceptance state

### RED evidence

Five focused tests failed because `production-deployment-state.sh` and all target, acceptance,
invalidation, and reboot-state interfaces were absent.

### Implemented

- Added exact target preflight for `MacBookPro18,1` and `Apple M1 Pro` with sandbox-only overrides.
- Added stable deployment identity combining installed artifact identity, hardware profile, model,
  and chip.
- Added atomic root-owned/test-root `0600` acceptance and reboot state writes using same-directory
  temporary files plus rename.
- Acceptance records named stages and timestamps and verifies every required stage against the
  current installed identity.
- Install, upgrade, and rollback invalidate acceptance and reboot evidence.
- State contains no machine-unique identifiers or raw sensor evidence.

### Immediate review findings

#### T7-P1 — Legacy reboot test hooks were not sandbox-restricted

The historical Task 14 helpers accepted boot and state-time overrides outside `MLM_TEST_ROOT`.

**Resolution:** both overrides now fail with `error=test-hook-production-disabled` outside the
sandbox. Target model/chip and new reboot hooks follow the same rule.

#### T7-P2 — Install invalidation lacked direct proof

Upgrade and rollback invalidation were covered first, but initial install invalidation was only
visible in implementation.

**Resolution:** add a stale pre-install acceptance/reboot fixture and prove install removes both.

#### T7-P2 — Atomic cleanup helper triggered an indirect-call ShellCheck finding

**Resolution:** add one precise `SC2329` suppression documenting the RETURN-trap invocation.

### Re-review

- Model/chip mismatch fails before state recording: pass.
- Partial, failed, stale, or identity-mismatched acceptance is rejected: pass.
- Writes are atomic, mode `0600`, and leave no fixed temp file: pass.
- Install/upgrade/rollback invalidate acceptance and reboot evidence: pass.
- Reboot proof requires changed boot epoch and matching identity: pass.
- Production test hooks are disabled: pass.
- Privacy exclusions are statically enforced: pass.
- No `/Library`, launchd, sleep, reboot, merge, push, or worktree cleanup occurred: pass.

### Verification

```text
RED: 5 focused tests failed because deployment state interfaces were absent
focused: 59 tests, 0 failures
full XCTest: 238 tests, 0 failures
bash -n: manager and all sourced libraries passed
shellcheck: passed with zero findings
package prepare/verify: passed
release daemon build during prepare: passed
git diff --check: passed
```

### Decision

**Task 7 approved.** No Critical/P0/P1 finding remains. Task 8 may begin after the independent Task 7
commit.

## Task 8 — Bounded deployment acceptance commands and persistent activation

### RED evidence

Five focused tests failed because the stable deployment dispatcher, atomic mode editor, bounded
cleanup contract, and evidence-bound activation path did not exist.

### Implemented

- Added one atomic `set_managed_mode disabled|dry-run|enabled` editor using a same-directory
  temporary plist plus rename.
- Added stable `deployment-dry-run`, `deployment-enabled-once`,
  `deployment-recovery-resleep`, and `activate` commands.
- Every bounded command verifies the installed set and prior stage requirements, records matching
  acceptance only after success, and restores disabled mode on normal failure, injected failure,
  timeout, or signal.
- Persistent activation requires all three matching acceptance stages and intentionally has no
  post-success disable cleanup.
- Removed any unrestricted `enable` dispatcher path.
- Added sandbox-only deterministic hold/failure hooks for cleanup testing.

### Immediate review findings

#### T8-P1 — Sandbox evidence counting reused earlier stage log entries

The first GREEN implementation counted from byte offset zero for every bounded sandbox stage, so
the second stage could count the first stage's sleep-attempt evidence.

**Resolution:** each bounded stage now records the current log size before emitting its fixture and
counts only newly appended evidence.

#### T8-P2 — Existing static tests were coupled to direct plist mutation

Historical tests searched for literal `PlistBuddy Set :Mode` statements inside the mode wrappers.
The atomic editor correctly moved that responsibility into one shared function.

**Resolution:** update the tests to prove wrappers call the shared atomic editor and retain
installed-set verification without taking the whole-set lifecycle guard.

### Re-review

- Bounded dry-run, enabled-once, and recovery-resleep finish disabled on success: pass.
- Injected failure and TERM cleanup restore disabled: pass.
- Partial, corrupt, failed, and identity-mismatched acceptance cannot activate: pass.
- Complete matching three-stage acceptance leaves enabled only through `activate`: pass.
- Mode edits are atomic and preserve managed metadata: pass.
- No unrestricted `enable` dispatcher entry exists: pass.
- Sandbox-only hooks cannot be enabled in production: pass.
- Historical acceptance commands remain behaviorally compatible: pass.
- No `/Library`, production launchd, sleep, reboot, merge, push, or worktree cleanup occurred: pass.

### Verification

```text
RED: 5 focused tests failed because stable deployment commands were absent
focused: 64 tests, 0 failures
full XCTest: 243 tests, 0 failures
bash -n: manager and sourced libraries passed
shellcheck: passed with zero findings
release daemon build: passed
package prepare/verify: passed
git diff --check: passed
```

### Decision

**Task 8 approved.** No Critical/P0/P1 finding remains. Task 9 may begin after the independent Task 8
commit.
