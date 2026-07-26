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
