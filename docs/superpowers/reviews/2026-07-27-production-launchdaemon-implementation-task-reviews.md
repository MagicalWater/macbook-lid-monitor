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
