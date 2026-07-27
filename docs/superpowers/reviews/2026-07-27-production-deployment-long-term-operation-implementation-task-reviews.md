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

## Task 9 — Bounded runtime health persistence

### RED evidence

The focused test target failed to compile because `ProductionHealthStore`,
`ProductionHealthRecord`, the health reader result, and the persisting event sink did not exist.

### Implemented

- Added a root-owned production health snapshot at the manifest-bound `health.plist` path using
  JSON content with schema, installed version, mode, profile, state, PID, transition time,
  last-valid-sample time, last stable error code, and update time.
- Reused `DaemonHealth` as the single in-memory state model rather than introducing a second state
  machine.
- Added same-directory random temporary writes, mode `0600`, and POSIX atomic rename replacement.
- Added bounded valid-sample heartbeat persistence while retaining every valid sample time only in
  memory between writes.
- Added missing/corrupt/stale/current read classification with one ISO-8601 serialization contract.
- Wrapped the production event sink so state/error transitions persist while every original log
  event is still forwarded.
- Added a coordinator callback that records only successfully decoded finite integer samples.
- Store failures are swallowed at the observability boundary and cannot construct or acquire sleep
  authority.

### Immediate review findings

#### T9-P1 — Writer and reader used different date encodings

The first writer encoded ISO-8601 dates while the reader used the default decoder strategy, which
would classify a valid production snapshot as corrupt.

**Resolution:** use ISO-8601 for both encoding and decoding and add current/stale fixtures using the
same contract.

#### T9-P1 — Replacement briefly removed the health snapshot

The first GREEN implementation removed the existing destination before moving the temporary file,
creating a missing-file observation window.

**Resolution:** replace with one same-filesystem POSIX `rename`, retain deferred temporary cleanup,
and prove no temporary health file remains.

#### T9-P1 — No valid-sample heartbeat source existed

The existing event stream exposed state transitions but not every valid decoded sample. Persisting
only transition events could make a healthy steady-state daemon appear stale.

**Resolution:** add a defaulted coordinator `onValidSample` callback. Every valid sample updates the
store's in-memory timestamp, but disk writes occur only when the bounded heartbeat is due. Malformed
reports do not refresh health.

#### T9-P2 — Runtime path and state ownership diverged from existing contracts

The initial store used `health.json`, while the manifest defines `health.plist`, and initially kept
state fields independently from `DaemonHealth`.

**Resolution:** use the manifest-bound path and extend `DaemonHealthSnapshot` with the absolute last
sample time so persistence derives from the existing health model.

### Re-review

- Snapshot contains only bounded operational health fields: pass.
- Snapshot and temporary file metadata are mode `0600`: pass.
- Replacement is atomic and leaves no temporary file: pass.
- State and new error transitions write immediately: pass.
- Duplicate state/error events do not write repeatedly: pass.
- Valid sample heartbeats are bounded and malformed reports do not refresh them: pass.
- Missing, corrupt, stale, and current snapshots are distinguishable: pass.
- Installed version reads only the manifest version field: pass.
- Persistence failure forwards events and cannot affect authority/startup: pass.
- No `/Library`, launchd, sleep, reboot, merge, push, or worktree cleanup occurred: pass.

### Verification

```text
RED: focused compile failed because health persistence interfaces were absent
focused: 29 tests, 0 failures
full XCTest: 249 tests, 0 failures
release daemon build: passed
git diff --check: passed
```

### Decision

**Task 9 approved.** No Critical/P0/P1 finding remains. Task 10 may begin after the independent Task 9
commit.

## Task 10 — Stable status, diagnostics, and operational baseline

### RED evidence

Four focused tests failed because the observability library, parser-friendly fields, stable
missing/corrupt classification, process metrics, and strict operational baseline did not exist.

### Implemented

- Added read-only `production-observability.sh` with stable status, diagnostics, crash-budget,
  health, process metric, log metadata, and operational baseline interfaces.
- Status reports installed identity, mode, launchd state, process count, health, target hardware,
  integrity, crash state, acceptance state, and lease state as parser-friendly key/value fields.
- Diagnostics adds PID elapsed/CPU/RSS/VSZ and log metadata without reading log contents.
- Missing state reports `unavailable`; malformed or unsafe state reports `corrupt`.
- Operational baseline requires a valid installed set, enabled mode, loaded job, exactly one PID,
  fresh root-owned `0600` monitoring health matching that PID, and complete matching acceptance.
- Sandbox process/job/metric hooks are rejected outside `MLM_TEST_ROOT`.

### Immediate review findings

#### T10-P1 — Baseline accepted stale or unsafe health evidence

The first GREEN implementation checked the health state but not freshness or managed metadata.

**Resolution:** health parsing now rejects unsafe metadata and classifies snapshots older than 180
seconds as stale. Regression tests cover stale and mode `0666` health files.

#### T10-P2 — Status compatibility and redaction static test drift

The extracted library initially made `status` succeed while uninstalled, and a historical static
test only inspected the manager file.

**Resolution:** preserve nonzero uninstalled `status`, keep diagnostics tolerant through
`status_job || true`, and update the static assertion to inspect the new library boundary.

### Re-review

- Status and diagnostics fields are stable and parser-friendly: pass.
- Missing/corrupt health and crash state degrade deterministically: pass.
- Diagnostics does not cat or tail logs: pass.
- Process metrics are reported only for discovered PIDs: pass.
- Health freshness, metadata, mode, state, and PID matching are enforced: pass.
- Operational baseline rejects partial acceptance and unhealthy evidence: pass.
- Production cannot enable observability test hooks: pass.
- Existing uninstalled status behavior remains nonzero: pass.
- No `/Library`, production launchd, sleep, reboot, merge, push, or worktree cleanup occurred: pass.

### Verification

```text
RED: 4 focused tests failed because observability interfaces were absent
focused Task 10: 5 tests, 0 failures
management suite: 69 tests, 0 failures
full XCTest: 254 tests, 0 failures
bash -n: manager and sourced libraries passed
shellcheck: passed with zero findings
release daemon build: passed
package prepare/verify: passed
git diff --check: passed
```

### Decision

**Task 10 approved.** No Critical/P0/P1 finding remains. Task 11 may begin after the independent
Task 10 commit.

## Task 11 — Online-safe production log rotation

### RED evidence

The running-writer fixture failed because move-based rotation replaced the primary inode. A writer
holding the original file descriptor appended its post-rotation event to `.1`, while the new
primary path remained empty. The required observability interfaces were also absent.

### Implemented

- Added `rotate_one_log_preserving_inode PATH 1048576 3` and moved `rotate_logs` into the
  observability library.
- Shifted generations by copying through same-directory random temporary files and atomic rename.
- Copied the active log to `.1`, then truncated the active file in place so launchd/daemon file
  descriptors continue to target the primary inode.
- Retained the existing threshold of greater than 1 MiB and at most three generations.
- Preserved active log owner and mode while keeping the log directory mode `0700`.

### Immediate review findings

#### T11-P1 — Generation destinations could follow symlinks

The first GREEN implementation copied directly to generation paths and used a predictable `.tmp`
name, allowing an existing generation symlink to redirect writes.

**Resolution:** preflight every generation path before mutation, reject symlinks/non-regular
destinations, and copy through random same-directory temporary files before rename. A regression
proves the outside target and active log remain unchanged on rejection.

### Re-review

- Primary inode is identical before and after rotation: pass.
- A writer opened before rotation writes its next event into the primary path: pass.
- `.1` contains the pre-rotation snapshot: pass.
- Rotation occurs only above 1 MiB: pass.
- At most three generations remain: pass.
- Generation symlinks are rejected before mutation: pass.
- Bash syntax and ShellCheck are clean: pass.
- No `/Library`, production launchd, sleep, reboot, merge, push, or worktree cleanup occurred: pass.

### Verification

```text
RED: running writer retained old inode and post-rotation event missed primary path
focused Task 11: 4 tests, 0 failures
management suite: 72 tests, 0 failures
full XCTest: 257 tests, 0 failures
bash -n: manager and sourced libraries passed
shellcheck: passed with zero findings
release daemon build: passed
package prepare/verify: passed
git diff --check: passed
```

### Decision

**Task 11 approved.** No Critical/P0/P1 finding remains. Task 12 may begin after the independent
Task 11 commit.

## Task 12 — Disabled upgrade, rollback, and complete uninstall semantics

### RED evidence

The initial Task 12 tests failed because the manager lacked explicit disabled maintenance
transaction boundaries, evidence-only upgrades still attempted provenance replacement, and
uninstall left lease, acceptance, reboot, and health state behind.

### Implemented

- Added explicit `prepare_maintenance_disabled_state`, `activate_staged_set_disabled`, and
  `restore_rollback_set_disabled` transaction boundaries.
- Upgrade and explicit/automatic rollback now enter disabled, booted-out, nonresident state before
  replacing payloads and finish disabled after success.
- Rollback failure returns nonzero and intentionally leaves the job booted out.
- Added installed payload identity comparison that ignores repository-only version/source-commit
  changes when binary, plist, normalized disabled config, and hardware policy are unchanged.
- Evidence-only upgrades preserve the installed identity and matching deployment acceptance;
  artifact or policy replacement invalidates acceptance and reboot evidence.
- Added complete rollback-slot metadata, checksum, disabled-config, and plist-policy verification.
- Uninstall now preflights and removes the authority lease, acceptance, reboot state, health state,
  crash budget, Task 14 state, logs and generations, rollback slot, and core installed artifacts
  while preserving unrelated files.

### Immediate review findings

#### T12-P1 — Unsafe rollback and uninstall paths were discovered after maintenance mutation

The first GREEN implementation entered disabled/booted-out maintenance state before validating a
rollback slot or every uninstall path. A tampered rollback slot could therefore modify the current
set before checksum failure, and a rollback-directory symlink could change mode before rejection.

**Resolution:** move complete rollback-slot verification and uninstall symlink preflight before any
mode, process, launchd, or filesystem mutation. Regression tests prove rejection preserves the
original enabled configuration and current payload.

#### T12-P2 — Historical acceptance fixtures used repository-only identity drift

Three historical tests changed only manifest version or reused an identical staged payload. Under
the new identity contract these are correctly classified as evidence-only no-ops, so no rollback
slot is created.

**Resolution:** update those fixtures to use genuinely different installed binary payloads before
testing upgrade, rollback, and reboot acceptance behavior.

### Re-review

- Upgrade forces disabled, booted-out, nonresident state before replacement: pass.
- Successful upgrade leaves the new installed set disabled: pass.
- Automatic rollback restores the previous set disabled: pass.
- Explicit rollback restores the previous set disabled and invalidates acceptance: pass.
- Tampered rollback state is rejected before maintenance mutation: pass.
- Rollback restore failure returns failure and remains booted out: pass.
- Evidence-only repository changes preserve installed identity and acceptance: pass.
- Payload or policy replacement invalidates acceptance and reboot state: pass.
- Uninstall removes every managed runtime/deployment state and preserves unrelated files: pass.
- Uninstall symlink hazards are rejected before mode or filesystem mutation: pass.
- No `/Library`, production launchd, sleep, reboot, merge, push, or worktree cleanup occurred: pass.

### Verification

```text
RED: 5 focused tests produced 11 failures because transaction/no-op/cleanup semantics were absent
focused Task 12: 12 tests, 0 failures
management suite: 77 tests, 0 failures
full XCTest: 262 tests, 0 failures
bash -n: manager and sourced libraries passed
shellcheck: passed with zero findings
release daemon build: passed
package prepare/verify: passed
git diff --check: passed
```

### Decision

**Task 12 approved.** No Critical/P0/P1 finding remains. Task 13 may begin after the independent
Task 12 commit.

## Task 13 — Long-term operator runbook and repository synchronization

### RED evidence

The command/document parity test failed because `docs/operations/production-daemon.md` did not
exist.

### Implemented

- Added the supported production operator runbook and linked it from `README.md`.
- Documented routine status, diagnostics, operational baseline, disable, emergency bootout,
  crash-circuit recovery, online-safe rotation, upgrade, rollback, integrity failure, foreground
  real-sleep lease conflict, uninstall, real-sleep warning, and reboot warning.
- Recorded exact healthy/disabled/booted-out/residual expectations and which commands preserve the
  current mode versus force disabled maintenance state.
- Added a static parity regression proving every documented management command exists in the
  dispatcher and no unrestricted enable command is documented.

### Immediate review findings

#### T13-P2 — Negative enable wording matched the prohibited command assertion

The first runbook explicitly wrote the nonexistent unrestricted command inside a sentence saying it
did not exist. The parity test correctly treated the literal command line as documentation of that
interface.

**Resolution:** describe the absence as “no unrestricted enable dispatcher” without presenting a
copyable nonexistent command.

### Re-review

- Every runbook command has a matching dispatcher entry: pass.
- No unrestricted enable command is documented: pass.
- Routine and emergency paths include expected final state checks: pass.
- Upgrade, rollback, and uninstall semantics match Task 12 implementation: pass.
- Real-sleep and reboot operations carry explicit warnings: pass.
- README links to the canonical runbook: pass.
- No `/Library`, production launchd, sleep, reboot, merge, push, or worktree cleanup occurred: pass.

### Verification

```text
RED: focused test failed because the production runbook was absent
focused Task 13: 1 test, 0 failures
management suite: 78 tests, 0 failures
full XCTest: 263 tests, 0 failures
git diff --check: passed
```

### Decision

**Task 13 approved.** No Critical/P0/P1 finding remains. Stage B implementation review may begin
after the independent Task 13 commit.

## Stage B — Deployment lifecycle and operations implementation review

### Independent review scope

- Traced every root-mutating and launchd-mutating dispatcher path independently from Task 6–13
  reviews.
- Verified install, mode changes, bounded acceptance, persistent activation, crash reset, log
  rotation, upgrade, rollback, and uninstall against installed-set verification, acceptance state,
  authority boundaries, cleanup ordering, and final mode.
- Re-ran the complete automated, release, static, package, and independent clean-snapshot gates.

### Finding

#### SB-P1 — Persistent activation could retain enabled config after bootstrap failure

`activate_deployment` changed the managed config to `enabled` before bootout/bootstrap. If bootstrap
failed, the command returned with no resident daemon but left enabled authority on disk. A later
manual bootstrap could therefore start real sleep authority without re-running the evidence-bound
activation gate.

**Resolution:** activation now treats bootout/bootstrap as one fail-safe transaction. Any bootstrap
failure atomically restores `disabled`, performs bootout, emits
`error: activation failed; restored disabled`, and returns failure. The deterministic failure hook is
sandbox-only and a regression proves both the final mode and failure result.

### Re-review

- Install starts disabled and rejects loaded/duplicate authority: pass.
- All mode edits verify the installed set and use atomic config replacement: pass.
- Bounded deployment stages return disabled and identity-bound acceptance is ordered: pass.
- Persistent activation is the only path that intentionally leaves enabled: pass.
- Activation bootstrap failure restores disabled and booted-out state: pass.
- Crash reset requires disabled/nonresident state: pass.
- Upgrade and rollback preflight before mutation and finish disabled: pass.
- Rollback failure remains booted out: pass.
- Uninstall preflights all managed paths and removes all managed state only: pass.
- Online log rotation preserves the active writer inode: pass.
- Test hooks cannot be enabled outside `MLM_TEST_ROOT`: pass.
- No real `/Library`, production launchd, sleep, reboot, merge, push, or worktree cleanup occurred:
  pass.

### Verification

```text
Stage B finding RED: activation bootstrap-failure regression failed and left mode=enabled
focused fix: 1 test, 0 failures
main working tree full XCTest: 264 tests, 0 failures
four release products: passed
bash -n: manager and all sourced libraries passed
shellcheck -x: passed with zero findings
plist lint: three production templates passed
package prepare/verify: passed
git diff --check: passed
independent clean snapshot: 264 tests, 0 failures
independent clean snapshot: four release products passed
independent clean snapshot: bash/shellcheck/plist/package/diff/status passed
```

### Decision

**Stage B approved.** No Critical/P0/P1 finding remains. Task 14 may begin after the independent
Stage B closure commit.

## Task 16 — Disabled production installation

### Approval and execution

The user explicitly approved `/Library` installation and system-domain bootstrap while preserving
disabled mode. The reviewed formal-main release commit was
`412fcc207b447d42ffdf58e9e35bd545d1b04ad4`.

### Immediate review finding

#### T16-P2 — Non-root status misclassified a root-only health snapshot as corrupt

The first post-install status invocation ran without root privileges. Installed-set and launchd
state were readable, but the root-owned `0600` health snapshot raised `PermissionError`; the
read-only observability wrapper consequently printed `health_state=corrupt`.

**Resolution:** no production mutation was needed. Root evidence proved the snapshot was valid,
schema 1, identity-bound, and disabled. The root status correctly classified it as `stale`, which is
expected because a disabled daemon exits and no longer refreshes health. Future production
acceptance uses root status/diagnostics for root-only state.

### Re-review

- Formal release, origin/main, package manifest, and installed manifest identity match: pass.
- Binary, launchd plist, config, and manifest checksums match the prepared package: pass.
- Managed files/directories have fixed root:wheel metadata and no unsafe links: pass.
- Installed config is disabled: pass.
- System job is loaded, not running, last exit code zero, and process count zero: pass.
- Deployment acceptance, reboot state, lease, lifecycle guard, and GUI duplicate job are absent:
  pass.
- Root-only health snapshot is valid disabled evidence; stale is expected and not corrupt: pass.
- Crash circuit is closed with zero unexpected exits and no active run: pass.
- Historical unrelated temp log was preserved because deletion was not separately approved: pass.
- No dry-run, real sleep, persistent activation, or reboot occurred: pass.

### Evidence

See `docs/validation/2026-07-27-production-deployment-disabled-install.md`.

### Decision

**Task 16 approved.** No Critical/P0/P1 finding remains. The production job remains
loaded/disabled with zero resident PID. Task 17 requires a new explicit approval before changing
managed mode or launchd runtime behavior.

## Task 15 — Formal-main integration and package provenance

### Approval and integration scope

- The user explicitly approved merge to formal `main`, push to `origin/main`, and worktree handling.
- The approved release candidate was `f16ae1d81a17f8acbe6e09862b2bcec716a18195`.
- Formal `main` and `origin/main` both started at
  `e2b8afeac0bf8f7560d6a9d60b4da328d9650bd3`, with clean working trees and zero divergence.
- The release candidate was a direct descendant of formal `main`, so integration used a
  non-rewriting fast-forward merge.

### Immediate review

- Confirmed the detached implementation worktree was clean before integration.
- Re-ran the complete suite before integration rather than borrowing Task 14 evidence.
- Verified the formal repository was on `main`, clean, fetched, and equal to `origin/main` before
  merge.
- Verified `main` was an ancestor of the release candidate and rejected any history rewrite or
  force-push path.
- Re-ran the complete suite on the merged formal-main result before provenance closure.

No Critical/P0/P1 finding was discovered during integration review.

### Verification

```text
pre-integration release-candidate XCTest: 264 tests, 0 failures
formal preflight: main == origin/main == e2b8afeac0bf8f7560d6a9d60b4da328d9650bd3
formal preflight: clean status and ahead/behind 0/0
integration: fast-forward only, no rewritten history
merged formal-main XCTest: 264 tests, 0 failures
exact formal release package prepare/verify: closure post-commit gate
push and main/origin equality: closure post-commit gate
production installation or launchd mutation: none
```

### Decision

**Task 15 approved.** The closure commit containing this review is the formal release commit. Its
post-commit gate must package that exact `HEAD`, push it without history rewriting, and prove
`main == origin/main` before Task 16 may begin.

## Task 17 — Fresh installed dry-run acceptance

### Approval and execution

The user explicitly approved managed dry-run mutation, one bounded `pmset sleepnow` continuity
check, and the final installed sensor reopen gate. All runs used the installed release identity
`412fcc207b447d42ffdf58e9e35bd545d1b04ad4`; persistent enabled mode was never entered.

### Findings

#### T17-P1 — Partial acceptance was misclassified as corrupt

`acceptance_status_value` treated every state lacking all three deployment stages as `corrupt`, even
when `deployment-dry-run` was valid and identity-bound.

**Resolution:** observability now reports `partial` after a valid first-stage acceptance, reserves
`complete` for all three stages, and keeps `corrupt` for invalid metadata, identity, or content. A
RED/GREEN regression covers the distinction.

#### T17-P1 — Ad-hoc privileged wrapper omitted management functions

The first approved sleep/wake orchestration sourced only library files, so manager-local functions
such as `set_dry_run_mode` were unavailable. The Mac slept once, but the daemon never entered the
intended acceptance mode and the result was rejected.

**Resolution:** added the stable `deployment-dry-run-sleep-wake` command, which verifies current
installed acceptance and reuses the reviewed fail-safe sleep/wake path without package prepare or
upgrade. The corrected run passed with PID stability and returned disabled.

#### T17-P2 — Same-cycle reopen capture timed out

The final bounded sensor gate did not produce a second `would-sleep` event before timeout. It did
prove the installed daemon moved from monitoring-disarmed to monitoring-armed after the lid was
reopened, while the earlier accepted dry-run proved candidate/debounce/request/would-sleep.

**Disposition:** accepted as split installed evidence, not as a same-cycle claim. The same installed
release identity was used throughout; automated integration coverage proves the complete same-cycle
state-machine behavior. No further manual lid repetition is required for Task 17.

### Re-review

- Installed identity, checksums, target model/chip, and dry-run acceptance identity match: pass.
- Close candidate, debounce, one attempted request, and one `would-sleep` were observed: pass.
- Reopen returned an installed dry-run daemon from disarmed to monitoring-armed: pass.
- Sleep/wake continuity kept PID `14049`, emitted monitoring-disarmed, and re-armed after wake: pass.
- No sensor-driven real sleep authority was constructed: pass.
- The only real sleep was separately approved and initiated by bounded `pmset sleepnow`: pass.
- Crash circuit remained closed; health returned disabled; no managed lease remained: pass.
- Every cleanup path returned loaded/disabled/zero PID with last exit code zero: pass.
- Acceptance remains valid `partial`, which is expected before Tasks 18 and 19: pass.

### Verification

```text
partial observability RED: failed as acceptance_state=corrupt
partial observability GREEN: passed
stable sleep/wake command RED: usage failure
stable sleep/wake command GREEN: passed
stable reopen command RED: usage failure
stable reopen command GREEN: passed
management suite after sleep/wake command: 81 tests, 0 failures
final full suite: 267 tests, 0 failures
bash -n / shellcheck -x / git diff --check: passed
live final state: loaded, disabled, zero PID, last exit code 0
```

### Evidence

See `docs/validation/2026-07-28-production-deployment-dry-run-acceptance.md`.

### Decision

**Task 17 approved.** Open P0 = 0 and Open P1 without disposition = 0. Production remains
loaded/disabled with zero resident PID. Task 18 requires separate approval because it grants one
bounded sensor-driven real-sleep request.
