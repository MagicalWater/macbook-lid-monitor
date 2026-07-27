## Task 12 — Logged-in dry-run system acceptance

### Evidence

- Pre-install production residual state was clean.
- Release version `7d056a175fe5` was prepared and verified.
- Dry-run started under the system LaunchDaemon with exactly one resident process.
- Redacted diagnostics reported matching installed and manifest checksums.
- Production error log remained empty.
- Root-only log permissions were enforced before shutdown.
- Emergency disable returned the package to `disabled`, process count zero, and launchd last exit code zero.
- Independent re-review found no GUI-domain duplicate authority.

### Disposition

**Task 12 logged-in scope approved and complete.** Loginwindow/logout, real sleep/wake, and reboot
remain blocked behind their separate approval gates.

## Task 12 — Logged-in dry-run acceptance command

### Implementation

- Added explicit `dry-run` mode activation for the installed production configuration.
- Added `accept-task12-logged-in` as the single root entry point for the non-disruptive logged-in portion of Task 12.
- The command requires zero production residual state, prepares as the invoking non-root user, installs disabled, activates dry-run, verifies one system-domain daemon and dry-run startup evidence, captures redacted diagnostics, enforces log bounds, and returns the job to loaded/disabled.
- Logout/loginwindow, real sleep/wake, and reboot are intentionally excluded and remain separate approval gates.

### TDD evidence

- RED: no Task 12 lifecycle command or sandbox acceptance existed.
- GREEN: sandbox acceptance proves install → dry-run → disabled final state, and contract tests prove explicit invocation without password handling.

### Immediate review finding

#### P0 — Mid-acceptance failure could leave dry-run active

The first implementation only disabled the daemon on the success path.

**Resolution:** Added an EXIT cleanup trap that, whenever a managed config exists, best-effort disables, bootouts, and re-bootstraps the job before process exit. The trap is cleared only after the normal disabled final state is established.

### Re-review

- Starts only from verified zero production residual state: pass.
- Initial install remains disabled: pass.
- Dry-run activation performs no real sleep request construction: covered by existing production composition tests.
- Real-system verification requires exactly one production daemon PID and dry-run startup evidence: pass by implementation review.
- Failure path returns to disabled through EXIT cleanup: pass.
- Success path returns to loaded/disabled and emits diagnostics: pass.
- No logout, sleep, reboot, or enabled-mode mutation is included: pass.
- No password reading, `sudo -S`, or embedded credentials: pass.

### Fresh verification

- Focused management tests: 27 tests, 0 failures.
- Full suite: 171 tests, 0 failures.
- `bash -n`: passed.
- `shellcheck`: passed.
- Release production daemon: passed.
- `git diff --check`: passed.

### Disposition

**Task 12 logged-in acceptance command approved.** Real root execution is pending the user's already-granted Task 12 approval. Loginwindow/logout and real sleep/wake remain blocked by separate explicit gates.

# Production LaunchDaemon Implementation Task Reviews

## Task 1 — Typed configuration and modes

### Implementation

- Added a typed `disabled / dry-run / enabled` production mode model.
- Added strict schema-v1 plist decoding with an allowlist of supported keys.
- Reused `LidSleepPolicy` validation as the single policy authority.
- Added a fixed-path loader for `/Library/Application Support/MacBookLidMonitor/config.plist`.
- Added injectable file metadata/read seams so ownership and permissions are testable without
  touching `/Library`.

### TDD evidence

- RED: focused tests failed because the production configuration types did not exist.
- GREEN: seven focused tests pass after minimal implementation.

### Immediate review findings

#### P1 — Group ownership was not validated

Root ownership alone would permit a non-wheel group. The production packaging contract requires
`root:wheel`.

**Resolution:** Added a failing regression test and required group ID `0`.

#### P1 — Blank hardware profile IDs were accepted

A whitespace-only identifier could pass decoding but could never authorize a hardware profile.

**Resolution:** Added a failing regression test and stable `invalid-hardware-profile-id` error.

### Re-review

- Unknown keys and unsupported schema/modes fail closed: pass.
- Invalid policy cannot produce enabled configuration: pass.
- Configuration path is fixed and not caller-overridable: pass.
- Symlink, non-root owner/group, and group/world-writable file fail closed: pass.
- No production runtime or system path is mutated: pass.

### Verification

- Focused: 7 tests, 0 failures.
- Full: 118 tests, 0 failures.
- Release build: passed.
- `git diff --check`: passed.
- Residual system state: unchanged; no `/Library` write or launchd operation.

### Disposition

**Task 1 approved and complete.**

## Task 2 — Exact hardware profile registry

### Implementation

- Added one production hardware profile for the verified M1 Pro HID identity.
- Bound that profile directly to the verified report-ID-1, 3-byte decoder.
- Added exact-match resolution that rejects zero matches and duplicate matches.
- Kept `CandidateRanker` available for diagnostics but outside production authorization.

### TDD evidence

- RED: focused tests failed because no production profile registry existed.
- GREEN: five focused tests pass after minimal registry and decoder binding.

### Immediate review findings

No blocking implementation defect was found. Re-review specifically checked that profile matching
includes vendor, product, usage page, usage, transport, and non-input-device class, and that the
profile-bound decoder rejects every unknown report shape rather than falling back to the exploratory
two-byte decoder.

### Re-review

- Diagnostic score cannot authorize production monitoring: pass.
- Unknown profile and transport mismatch fail open: pass.
- Multiple exact devices fail open as ambiguous: pass.
- Generic/composite decoder is not returned by the production registry: pass.
- No runtime composition or system mutation was introduced: pass.

### Verification

- Focused: 5 tests, 0 failures.
- Full: 123 tests, 0 failures.
- Release build: passed.
- `git diff --check`: passed.
- Residual system state: unchanged.

### Disposition

**Task 2 approved and complete.**

## Pre-Task 3 Spec/Plan deviation review

### Finding — configured freshness had no schema field

The approved Spec required a configured sensor freshness limit, while schema version 1 and the
Task 1 implementation listed no field capable of carrying that value. Implementing Task 3 without
first correcting the authority documents would create undocumented runtime behavior.

### Resolution

- Added required positive `SensorFreshnessSeconds` to schema version 1.
- Updated Task 3 to extend configuration under TDD before state-machine changes.
- Kept schema version at 1 because production packaging has not yet shipped or been accepted; no
  installed consumer exists to migrate.

### Re-review

- Spec freshness invariant now has an explicit configuration source: pass.
- Plan orders schema coverage before freshness behavior: pass.
- No implementation was changed before this review: pass.

### Disposition

**Spec/Plan adjustment approved; Task 3 may proceed.**

## Task 3 — Fresh sensor and request epoch safety

### Implementation

- Added required positive `SensorFreshnessSeconds` to production configuration.
- Added sample timestamps and configurable maximum age to `LidSleepStateMachine`.
- Stale close samples now cancel the candidate and return to open without a request.
- Stale wake-recovery samples fail open into disarmed.
- Duplicate or out-of-order wake callbacks no longer replace the active recovery epoch.
- Added a coordinator injection seam while preserving existing CLI behavior with an infinite default.

### TDD evidence

- RED: configuration and state-machine tests failed on missing freshness fields and constructor seam.
- GREEN: focused configuration/state-machine/coordinator suite passes after minimal changes.

### Immediate review findings

#### P1 — Freshness did not cross the coordinator boundary

The first implementation added state-machine freshness but no production composition seam.

**Resolution:** Added `maximumSampleAge` to `LidSleepCoordinator` and forwarded it into the state
machine. Nonpositive direct values clamp to zero, which is fail-open.

### Re-review

- Stale close and recovery data cannot request sleep: pass.
- Wake clears pre-wake data and rejects duplicate callbacks: pass.
- Duplicate timer delivery remains idempotent through state transitions: pass.
- Existing calibrated behavior remains unchanged with the compatibility default: pass.
- Configuration is the production single source for finite freshness: pass.

### Verification

- Focused: 35 tests, 0 failures.
- Full: 127 tests, 0 failures.
- Release build: passed.
- `git diff --check`: passed.
- Residual system state: unchanged.

### Disposition

**Task 3 approved and complete.**

## Task 4 — Production events and health

### Implementation

- Added production-only lifecycle, health, transition, degradation, and stopping events.
- Added stable line formatting and a lock-serialized output sink.
- Added a health model with version/mode/profile, transition time, sample age, and stable error.
- Raw reports are not representable by the production event model.

### TDD evidence

- RED: focused tests failed because production event/health types did not exist.
- GREEN: four focused tests pass after minimal implementation.

### Immediate review findings

#### P1 — Health initializer was inaccessible

Private stored properties caused Swift's synthesized initializer to become private.

**Resolution:** Added an explicit internal initializer and repeated focused/full verification.

### Re-review

- Stable lifecycle/error taxonomy: pass.
- One complete line per event: pass.
- Raw bytes cannot be logged: pass.
- Sensor values are limited to explicit transition events: pass.
- Health snapshot exposes age and stable code without raw data: pass.

### Verification

- Focused: 4 tests, 0 failures.
- Full: 131 tests, 0 failures.
- Release build: passed.
- `git diff --check`: passed.

### Disposition

**Task 4 approved and complete.**

## Task 5 — Production daemon composition

### Implementation

- Added a new `macbook-lid-monitor-daemon` executable and dedicated production entry point.
- Added a production application composition root; spike/probe entry points are not reused.
- Disabled mode exits before HID enumeration or requester construction.
- Dry-run and enabled requester construction occurs only after exact profile resolution.
- Injected production freshness, policy, event sink, stream, scheduler, wake observer, and requester.
- Added idempotent signal-driven session shutdown.

### TDD evidence

- RED: focused tests failed because production application/dependency/result types did not exist.
- GREEN: three focused composition tests pass after minimal implementation.

### Immediate review findings

#### P1 — Dependency container incorrectly conformed to `Sendable`

The first compile exposed that the existing `HIDDeviceEnumerating` protocol is not Sendable.
Marking the dependency container Sendable would have claimed a concurrency guarantee not provided
by the injected enumerator.

**Resolution:** Removed the unnecessary Sendable conformance rather than weakening the compiler
check or adding an unsafe annotation.

### Re-review

- Disabled mode cannot open HID or construct any sleep requester: pass.
- Dry-run cannot construct the native real-sleep requester: pass.
- Enabled mode resolves the exact hardware profile before requester construction: pass.
- No command-line or environment production override exists: pass.
- Signal shutdown is idempotent: pass.
- Production target builds independently; spike/probe products remain separate: pass.

### Verification

- Focused: 3 tests, 0 failures.
- Full: 134 tests, 0 failures.
- Release product `macbook-lid-monitor-daemon`: passed.
- `git diff --check`: passed.
- Residual system state: unchanged; no service or `/Library` mutation.

### Disposition

**Task 5 approved and complete.**

## Task 6 — Bounded crash budget and circuit breaker

### Implementation

- Added rolling-window unexpected-exit accounting with persistent JSON state.
- Added atomic file replacement, explicit reset, clean-exit exclusion, and corrupt-state fail-open.
- Added startup circuit gating before configuration, HID enumeration, or requester construction.
- Added unexpected startup failure accounting and clean session-stop recording.

### TDD evidence

- RED: focused tests failed because crash budget/storage/circuit result types did not exist.
- GREEN: budget and composition focused tests pass after implementation.

### Immediate review findings

#### P0 — Initial implementation only read circuit state

Without consuming budget on unexpected startup failure, repeated launchd starts could never open
the circuit.

**Resolution:** Added injected unexpected/clean-exit recorders. Enumeration, stream construction,
and coordinator startup failures consume budget; expected configuration/hardware incompatibility
does not. Clean signal stop does not consume budget.

### Re-review

- Rolling window and threshold behavior: pass.
- Corrupt persistent state fails open without rewriting evidence: pass.
- Circuit-open path starts no HID/requester: pass.
- Unexpected startup failures consume budget: pass.
- Clean stop is excluded and reset is explicit: pass.
- Persistence uses atomic replacement: pass.

### Verification

- Focused: 10 tests, 0 failures.
- Full: 141 tests, 0 failures.
- Release production daemon: passed.
- `git diff --check`: passed.
- No crash file or other `/Library` artifact was created during tests.

### Disposition

**Task 6 approved and complete.**

## Task 7 — Production plist, config, and manifest

### Implementation

- Added a fixed system LaunchDaemon plist for the production executable.
- Added a schema-v1 disabled configuration template.
- Added a version/checksum manifest template with fixed managed paths.
- Added contract tests and plist lint validation.

### TDD evidence

- RED: all three packaging tests failed because templates did not exist.
- GREEN: templates decode and lint successfully after implementation.

### Immediate review findings

#### P1 — Plist did not request bounded unexpected-exit recovery

`ThrottleInterval` alone does not restart an unexpected non-zero exit, making the crash budget
ineffective for controlled recovery.

**Resolution:** Added conditional `KeepAlive.SuccessfulExit=false`. Clean/disabled exits remain
non-restarting; only non-zero exits are eligible, with launchd throttle plus application circuit.

### Re-review

- Fixed production label/product/path consistency: pass.
- No feasibility executable or LaunchAgent path: pass.
- Initial config is disabled and fully schema-valid: pass.
- Clean exits do not restart; unexpected exits are throttled: pass.
- Manifest covers binary/plist/config/crash state and checksum slot: pass.

### Verification

- Focused: 3 tests, 0 failures.
- Full: 144 tests, 0 failures.
- All three plists: lint passed.
- Release production daemon: passed.
- `git diff --check`: passed.

### Disposition

**Task 7 approved and complete.**


## Task 8 — Non-mutating prepare and verify

### Implementation

- Added `scripts/manage-production-daemon.sh` with only `prepare` and `verify` commands.
- Added shared packaging helpers with one fixed repository-local staging directory.
- `prepare` builds the production release product, rejects symlink sources, copies only allowlisted
  package inputs, applies staging modes, and writes version/checksum values into the staged manifest.
- `verify` checks regular files, executable mode, plist validity, binary checksum, and manifest
  version consistency.
- No root escalation, launchctl command, or `/Library` destination exists in the Task 8 scripts.

### TDD evidence

- RED: focused tests failed because both production management scripts were absent.
- GREEN: three focused tests pass after the non-mutating commands and validation contracts were
  implemented.

### Immediate review findings

#### P1 — XCTest child process could block while building

The first integration-style test launched `prepare` from inside the active SwiftPM test process.
The nested release build could contend with the parent build and the initial pipe handling could
also block on buffered output.

**Resolution:** Kept XCTest focused on static command/safety contracts and moved actual
`prepare`/`verify` execution to the Task verification command after the test build completes.

#### P2 — shellcheck treated sourced constants as unused

The common library constants are consumed by the sourcing management script, but standalone
shellcheck reported SC2034 warnings.

**Resolution:** Exported the shared path constants, preserving one authority while producing a
clean standalone shellcheck result.

### Re-review

- Command surface contains only `prepare` and `verify`: pass.
- Source symlinks and missing sources are rejected: pass.
- Staging location is fixed under `.build/production-package`: pass.
- Prepared binary checksum matches the staged manifest: pass.
- Staged manifest version matches the current Git commit: pass.
- Plist/config/manifest lint successfully: pass.
- No `sudo`, launchctl invocation, or `/Library` write exists or occurred: pass.

### Verification

- Focused management-script tests: 3 tests, 0 failures.
- `bash -n`: passed.
- `shellcheck`: passed with zero warnings/errors.
- Real non-root `prepare`: passed.
- Real non-root `verify`: passed; checksum and version matched.
- Full suite: 147 tests, 0 failures.
- Release production daemon: passed.
- `git diff --check`: passed.
- Production `/Library` binary, plist, and application-support directory: all absent.

### Disposition

**Task 8 approved and complete. Approval Gate C1 is now active.** Task 9 may be designed and
reviewed further without mutation, but no install, bootstrap, `/Library` write, or launchd mutation
may occur until the user explicitly approves that gate.

## Task 9 — Install and control lifecycle

### Implementation

- Added explicit `install`, `bootstrap`, `status`, `disable`, `stop`, and `bootout` commands.
- Added a sandbox-only system-root seam constrained to the repository `.build` directory.
- Added `accept-task9`, a single sudo command that prepares as the invoking non-root user and then
  performs the complete disabled install/control acceptance sequence.
- Installation refuses symlinked managed paths, preserves unrelated files, verifies staging, and
  requires the initial config mode to be exactly `disabled`.

### TDD evidence

- RED: lifecycle tests initially failed because commands and system-root seam did not exist.
- GREEN: sandbox install/control and complete `accept-task9` lifecycle tests pass.

### Immediate review findings

#### P1 — Test root was initially unrestricted

An arbitrary absolute `MLM_TEST_ROOT` could have redirected supposedly sandboxed mutation outside
the repository.

**Resolution:** Restricted the seam to `$REPO_ROOT/.build/*` and added a regression test.

#### P1 — Initial install did not re-assert disabled mode

Relying only on the template could allow a modified staging config to install dry-run/enabled.

**Resolution:** Installation now reads staging `Mode` and rejects every value except `disabled`.

#### P1 — Single-command acceptance could create root-owned build artifacts

Running prepare directly under sudo would contaminate repository build ownership.

**Resolution:** `accept-task9` performs prepare through `sudo -u "$SUDO_USER"`, then resumes root-only
system mutation. It contains no password handling.

### Re-review

- Managed paths and parents reject symlinks: pass.
- Sandbox root cannot escape repository `.build`: pass.
- Initial install is forced disabled: pass.
- Unrelated files are preserved: pass.
- Bootstrap/status/disable/stop/bootout command flow: pass.
- One-command root acceptance has no password pipe or embedded credential handling: pass.

### Verification before real mutation

- Focused management tests: 12 tests, 0 failures.
- Full suite: 156 tests, 0 failures.
- `bash -n`: passed.
- `shellcheck`: passed.
- Release production daemon: passed.
- `git diff --check`: passed.

### Controlled system acceptance evidence

- Pre-state: production binary/plist/config/manifest and system job absent.
- Installed package version: `25693f158874`.
- Installed binary checksum equals manifest checksum.
- Binary owner/mode: `root:wheel`, `0755`.
- Plist/config/manifest owner/mode: `root:wheel`, `0644`.
- Initial and final config mode: `disabled`.
- System LaunchDaemon loaded; disabled process exits cleanly with `last exit code = 0`.
- No resident daemon PID remains in disabled mode.
- No duplicate GUI-domain authority exists.
- Production log contains only `started` and `health-changed state=disabled` events.
- Production error log is empty.
- Crash budget state is absent.

### Disposition

**Task 9 approved and complete.** The installed system remains loaded in `disabled` mode with no
resident process and no sleep authority.

## Task 10 — Upgrade and rollback implementation

### Implementation

- Added one rollback slot under the managed application-support directory.
- Added installed-set checksum preflight before any upgrade mutation.
- Added atomic activation for binary, plist, config, and manifest.
- Added automatic restore when activation or bootstrap fails.
- Added explicit rollback command and post-restore checksum verification.
- Added fail-open behavior when rollback restore/bootstrap itself fails.

### TDD evidence

- RED: upgrade/rollback tests failed because commands and rollback slot did not exist.
- GREEN: successful upgrade, injected activation failure, corrupt-installed preflight, and rollback
  failure tests pass in the constrained sandbox root.

### Immediate review findings

#### P0 — Initial rollback implementation did not validate the installed set

Backing up an already-corrupt installed set would create an unusable rollback authority.

**Resolution:** Added `verify_managed_set` before backup and a corrupt-manifest regression test.

#### P0 — Restored rollback set was not integrity-checked

A copy operation alone did not prove the previous set was usable.

**Resolution:** Restore now verifies binary checksum against the restored manifest before any
bootstrap.

#### P0 — Rollback failure could attempt to continue

If restore or rollback bootstrap fails, continuing would risk an unknown active authority.

**Resolution:** The command returns a distinct failure and leaves the job booted out/fail-open.

#### P1 — First success fixture accidentally violated preflight

The test changed an installed binary without updating its manifest, so the new preflight correctly
rejected it before exercising upgrade.

**Resolution:** Fixed fixtures to model a valid previous version, proving activation and rollback
paths rather than only preflight rejection.

### Re-review

- Current installed set must be checksum-valid before backup: pass.
- Exactly one rollback slot is retained: pass.
- New set activation uses temporary files and rename: pass.
- Activation/bootstrap failure restores the previous set: pass.
- Restored set checksum is verified before bootstrap: pass.
- Rollback failure leaves service fail-open and returns failure: pass.
- No real installed-version mutation occurred during implementation verification: pass.

### Verification

- Focused management tests: 16 tests, 0 failures.
- Full suite: 160 tests, 0 failures.
- `bash -n`: passed.
- `shellcheck`: passed.
- Release production daemon: passed.
- `git diff --check`: passed.

### Disposition

**Task 10 implementation approved.** Controlled mutation of the installed Task 9 version remains
blocked pending the explicit installed-version approval gate.

## Task 10 — Controlled system acceptance

### Evidence

- Prepared candidate version `ffdec68d54e5`.
- Injected post-activation failure restored version `25693f158874` and matching checksum.
- Normal upgrade activated and verified candidate version/checksum.
- Explicit rollback restored the original version/checksum.
- Final mode is `disabled`; system job is loaded but not running.
- No resident PID, GUI-domain duplicate, error log entry, or crash-budget state exists.
- One rollback slot remains and matches the final installed version.

### Disposition

**Task 10 approved and complete.**

## Task 11 — Logs, diagnostics, and uninstall implementation

### Implementation

- Added fixed 1 MiB log rotation with three retained generations.
- Added root-only log directory/file modes (`0700`/`0600`).
- Added redacted diagnostics that report state, version, checksum, process count, and log metadata
  without printing raw log contents or sensor reports.
- Added scoped uninstall for the production binary, plist, config, manifest, crash state, rollback
  slot, and managed log generations.
- Uninstall preserves unrelated files and refuses symlinked managed paths before any mutation.

### TDD evidence

- RED: lifecycle tests failed before rotation, diagnostics, and uninstall commands existed.
- GREEN: bounded rotation, redacted diagnostics, scoped uninstall, unrelated-file preservation, and
  symlink refusal tests pass in the repository sandbox.

### Immediate review findings

#### P0 — Uninstall checked symlinks after attempting disable

That ordering could allow a symlinked config path to be touched before refusal.

**Resolution:** All managed paths, including rollback, are now checked before disable/bootout or
file deletion.

#### P0 — Rollback directory was not covered by symlink refusal

Recursive removal of a substituted rollback path was outside the intended trust boundary.

**Resolution:** Added rollback-directory symlink preflight and a regression test proving no managed
binary mutation occurs after refusal.

#### P1 — Rotated log generations were not removed

Uninstall originally removed only active log files, leaving `.1`–`.3` residual artifacts.

**Resolution:** Scoped removal now covers all retained generations for both production logs.

#### P1 — Existing logs were not forced root-only

Rotation applied secure mode only to newly created active files.

**Resolution:** Rotation now enforces `0700` on the log directory and `0600` on existing active
logs before size handling.

### Re-review

- Rotation is bounded to 1 MiB and three generations: pass.
- Log directory/file modes are root-only: pass.
- Diagnostics do not print log contents or raw sensor values: pass.
- Uninstall refuses symlinks before mutation: pass.
- Rollback slot and all log generations are scoped for removal: pass.
- Unrelated files remain untouched: pass.
- No real installed-state mutation occurred during implementation verification: pass.

### Verification

- Focused management tests: 23 tests, 0 failures.
- Full suite: 167 tests, 0 failures.
- `bash -n`: passed.
- `shellcheck`: passed.
- Release production daemon: passed.
- `git diff --check`: passed.

### Disposition

**Task 11 implementation approved.** Real diagnostics/rotation are non-destructive, but controlled
uninstall and zero-residual validation remain blocked pending explicit installed-state approval.

## Task 11 — Controlled acceptance command

### Implementation

- Added `accept-task11` as the single approved root entry point.
- The command emits redacted diagnostics before mutation, enforces bounded log rotation and
  permissions, emits post-rotation diagnostics, performs scoped uninstall, and verifies zero
  managed residual state.
- Residual verification covers the system job, daemon process, binary, plist, config, manifest,
  crash state, rollback slot, active logs, and all three rotated generations.

### TDD evidence

- RED: no single Task 11 acceptance entry point or post-uninstall verifier existed.
- GREEN: the sandbox acceptance test installs a managed set, creates oversized logs, runs the
  complete command, and proves every managed path is absent.

### Immediate review

No new P0/P1 issue was found after the Task 11 implementation review fixes. The acceptance wrapper
uses the already-reviewed diagnostics, rotation, uninstall, and symlink protections rather than
duplicating mutation logic.

### Re-review

- Root is required for real-system execution: pass.
- Diagnostics never print log contents or raw reports: pass.
- Rotation precedes uninstall and retains bounded permissions: pass.
- Uninstall is scoped to managed paths: pass.
- Post-uninstall verification checks job/process and every managed artifact: pass.
- No password reading, `sudo -S`, or embedded credential handling: pass.
- Sandbox execution does not touch real `/Library` or launchd state: pass.

### Fresh verification

- Focused management tests: 25 tests, 0 failures.
- Full suite: 169 tests, 0 failures.
- `bash -n`: passed.
- `shellcheck`: passed.
- Release production daemon: passed.
- `git diff --check`: passed.

### Disposition

**Task 11 controlled acceptance command approved.** The user approved the installed-state mutation;
real execution remains pending the one explicit sudo command.

### Real acceptance retry finding

The first real `accept-task11` execution stopped immediately after the pre-diagnostics heading.
No rotation or uninstall mutation had occurred. Root cause was `pgrep` returning status 1 when the
disabled daemon correctly had zero resident processes; with `set -euo pipefail`, that normal absent
state terminated diagnostics.

**Resolution:** The process-count pipeline now explicitly treats `pgrep` no-match as an empty result
and still counts it as zero. Added a regression contract for the no-process handling.

### Retry verification

- Focused management tests: 25 tests, 0 failures.
- Full suite: 169 tests, 0 failures.
- `bash -n`: passed.
- `shellcheck`: passed.
- Release production daemon: passed.
- `git diff --check`: passed.

The failed attempt left the production package installed, loaded, and disabled; Task 11 uninstall
acceptance remains pending a retry of the same approved command.

## Task 10 — Controlled acceptance command

### Implementation

- Added one explicit `accept-task10` root command.
- Records pre/post managed state and installed version/checksum.
- Prepares the candidate as the invoking non-root user.
- Injects a post-activation failure and proves automatic restoration of the original version.
- Performs a successful upgrade and verifies candidate version/checksum.
- Performs an explicit rollback and verifies the original version/checksum.
- Reasserts `disabled`, reboots the launchd job into the disabled clean-exit state, and prints final
  residual state.

### TDD evidence

- RED: acceptance tests failed before the command existed.
- GREEN: complete sandbox acceptance and password-handling contract tests pass.

### Immediate review

- Final state intentionally returns to the original Task 9 installed version, proving rollback
  without leaving an unreviewed candidate active.
- The command never reads or pipes passwords and reuses the approved non-root prepare boundary.
- Injected failure must return failure; unexpected success aborts acceptance.

### Re-review

- Original version/checksum captured before mutation: pass.
- Injected failure automatically restores and verifies original set: pass.
- Successful upgrade verifies candidate manifest and binary checksum: pass.
- Explicit rollback verifies original manifest and checksum: pass.
- Final config is disabled and launchd authority is loaded without sleep authority: pass.
- Sandbox test root remains constrained under repository `.build`: pass.

### Fresh verification

- Focused management tests: 18 tests, 0 failures.
- Full suite: 162 tests, 0 failures.
- `bash -n`: passed.
- `shellcheck`: passed.
- Release production daemon: passed.
- `git diff --check`: passed.

### Disposition

**Task 10 controlled acceptance command approved.** Real execution is authorized by the user's
installed-version mutation approval and requires one visible sudo invocation.

## Task 9 — Install and control lifecycle (pre-acceptance review)

### Implementation

- Added explicit `install`, `bootstrap`, `status`, `disable`, `stop`, and `bootout` commands.
- Added sandbox-root lifecycle tests that never touch `/Library` or real launchd state.
- Added a single `accept-task9` command that records pre/post state, prepares as the invoking
  non-root user, verifies staging, installs disabled configuration, exercises bootstrap/control,
  and leaves the system job loaded with mode disabled.
- Added root:wheel/mode handling, managed-path symlink refusal, duplicate authority refusal, and
  unrelated-file preservation.

### TDD and debugging evidence

- Initial lifecycle tests failed before command implementation.
- Test compilation failure was traced to a missing `LidMonitorCore` import and corrected.
- Child-process stalls were traced to nested release builds and buffered subprocess output.
- Sandbox acceptance now uses seeded staging; the real acceptance path still forces a fresh
  non-root release prepare through `sudo -u "$SUDO_USER"`.

### Immediate review findings

#### P0 — Test root could target arbitrary absolute paths

**Resolution:** `MLM_TEST_ROOT` is restricted to the repository `.build` subtree.

#### P0 — Install did not reassert disabled initial mode

**Resolution:** Install rejects staged configuration unless `Mode=disabled`.

#### P1 — One-command root acceptance could create root-owned build artifacts

**Resolution:** `accept-task9` requires sudo invocation but performs `prepare` as the original
non-root user before returning to root-only installation operations.

### Re-review

- Sandbox lifecycle and single-command acceptance: pass.
- Managed path symlink and non-disabled staging rejection: pass.
- No password reading, `sudo -S`, or embedded credential handling: pass.
- Unrelated files remain untouched: pass.
- Final sandbox configuration remains disabled: pass.

### Fresh verification

- Focused management tests: 12 tests, 0 failures.
- Full suite: 156 tests, 0 failures.
- `bash -n`: passed.
- `shellcheck`: passed.
- Release production daemon: passed.
- `git diff --check`: passed.

### Disposition

**Implementation approved.** Task 9 remains open until the separately approved root
`accept-task9` command completes and its real system evidence is reviewed.

## Task 11 — Controlled system acceptance

### Evidence

- Pre-diagnostics reported loaded, disabled version `25693f158874`, matching checksum, and zero resident processes.
- Existing production logs were `0644`; rotation enforcement changed both active logs to `0600` and the directory to `0700`.
- No rotation was needed because active logs were below the 1 MiB threshold.
- Disable and bootout completed before file removal.
- Scoped uninstall removed the system job, process authority, binary, plist, config, manifest, crash state, rollback slot, active logs, and all retained generations.
- Independent post-command review found no managed residual path and no remaining production log directory.

### Re-review

- System launchd job: absent.
- Resident daemon process: absent.
- Managed binary/plist/config/manifest: absent.
- Crash budget and rollback slot: absent.
- Active and rotated production logs: absent.
- Unrelated residual content: none observed; empty production log directory removed.

### Disposition

**Task 11 approved and complete.** The real system is now uninstalled with zero production managed residual state.

## Stage C — Packaging holistic review

### Review

- Reviewed every install, upgrade, rollback, diagnostics, rotation, and uninstall mutation path.
- Confirmed symlink refusal occurs before mutation and unrelated files remain outside removal scope.
- Confirmed upgrade/rollback integrity verification and fail-open behavior.
- Confirmed diagnostics privacy and bounded root-only log handling.

### Fresh clean-checkout verification

- Commit: `b6414ea00f53`.
- Full suite: 169 tests, 0 failures.
- Release production daemon: passed.
- `bash -n` and `shellcheck`: passed.
- Packaging plist lint: passed.
- Non-root prepare/verify: passed.
- Clean status after verification: passed.

### Residual state

- System job/process: absent.
- All production managed files/state/log generations: absent.
- Production log directory: absent.

### Disposition

**Stage C approved and complete.** Stage D acceptance remains gated.


## Task 12 — Loginwindow dry-run acceptance commands

### Implementation

- Added explicit `accept-task12-loginwindow-start` and `accept-task12-loginwindow-finish` commands.
- Start requires the installed daemon to be disabled, switches to dry-run, verifies one system-domain process, launches a detached root-only observer, and performs a controlled GUI-domain bootout for the invoking user.
- The observer records console owner, system job state, and daemon process count while no user GUI session is active.
- Finish validates that evidence, restores disabled mode, bootouts/rebootstraps the system job, emits diagnostics, and deletes the temporary evidence.

### Immediate review

A single foreground shell cannot safely span logout because its Terminal session is destroyed. The implementation therefore uses an explicit two-phase boundary and a short-lived detached observer rather than pretending one shell can survive logout.

### Re-review

- Real start requires root and a non-root `SUDO_USER`: pass.
- System job remains the only production authority: pass.
- Observer writes only bounded state metadata, not sensor data or log contents: pass.
- Observer script is root-owned mode `0700` and self-removes: pass.
- Finish refuses missing or invalid loginwindow evidence: pass.
- Final state returns to installed/loaded/disabled with no resident process: pass in sandbox.
- No password reading, `sudo -S`, or embedded credentials: pass.

### Fresh verification

- Focused management tests: 29 tests, 0 failures.
- Full suite: 173 tests, 0 failures.
- `bash -n`: passed.
- `shellcheck`: passed.
- Release production daemon: passed.
- `git diff --check`: passed.

### Disposition

**Loginwindow acceptance commands approved for the separately authorized logout test.** Real system evidence remains pending start/logout/login/finish execution.
