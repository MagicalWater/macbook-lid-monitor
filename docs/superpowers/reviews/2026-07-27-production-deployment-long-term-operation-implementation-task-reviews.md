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
