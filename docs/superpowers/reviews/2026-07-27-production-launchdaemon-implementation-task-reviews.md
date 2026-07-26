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
