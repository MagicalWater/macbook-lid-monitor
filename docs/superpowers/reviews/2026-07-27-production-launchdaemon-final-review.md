# Production LaunchDaemon Holistic Final Review

Date: 2026-07-27

## Scope

Holistic review of the production LaunchDaemon implementation, packaging, governance traceability, real-system acceptance, tooling disposition, and final residual state.

## Governance traceability

- Spec gate: reviewed, revised, re-reviewed, and closed.
- Plan gate: reviewed, revised, re-reviewed, and closed.
- Task gate: reviewed, revised, re-reviewed, and closed.
- Tasks 1–15: each implemented or documented with immediate review, findings disposition, fresh verification, and an independent commit.
- Stage A/B/C reviews: complete.
- Separate approvals were retained for install, loginwindow, real sleep, recovery resleep, reboot, rollback, and uninstall.

## Architecture and safety review

1. **Single authority:** production uses one system LaunchDaemon and no LaunchAgent.
2. **Mode isolation:** `disabled` and `dry-run` cannot construct a real sleep requester.
3. **Exact hardware authorization:** production requires the validated M1 Pro profile and profile-bound decoder; diagnostic ranking is not authority.
4. **Fail-open input handling:** unknown hardware/report/configuration, stale data, and invalid recovery data do not request sleep.
5. **Bounded requests:** normal close is exactly once per request epoch; recovery resleep is bounded to one request per wake epoch.
6. **Failure behavior:** sleep-request failure is observable, disarms, and does not retry.
7. **Restart protection:** crash budget prevents restart storms and fails open on corrupt state.
8. **Lifecycle safety:** install begins disabled; upgrade has one verified rollback slot; stop, disable, bootout, rollback, diagnostics, and uninstall are explicit operations.
9. **Filesystem safety:** fixed paths, root ownership/modes, symlink refusal, checksum manifest, and unrelated-file preservation are tested.
10. **Privacy and observability:** logs are root-only, bounded, structured, and exclude raw HID reports from production events.

## Real-system acceptance

- Logged-in production dry-run: accepted.
- Loginwindow/pre-login dry-run: accepted.
- Real sleep/wake dry-run continuity: accepted.
- Full sensor/debounce/request dry-run chain: accepted.
- First enabled sensor-driven sleep: accepted with one request and stable PID.
- Recovery resleep: accepted with two request attempts, one recovery transition, two wake boundaries, and stable PID.
- Injected sleep-request failure: accepted with one failure, disarm, zero retry, stable PID, and no real sleep.
- Reboot startup: accepted in loaded/disabled/no-PID state.
- Rollback: accepted to version `20c369b823d1`.
- Uninstall: accepted with independently verified zero residual managed state.

## Tooling disposition

- `macbook-lid-monitor-daemon` is the production executable.
- `macbook-lid-monitor-daemon-spike` and `macbook-lid-monitor-sleep-probe` are retained as historical feasibility/regression tools.
- Experimental products are excluded from the production manifest, LaunchDaemon plist, install set, and production composition.
- No tooling removal is required for safety because the final installed system state is empty.

## Final system state

```text
production LaunchDaemon job: absent
production daemon process: absent
managed binary/plist/support/log directories: absent
repository checkout: detached HEAD pending explicit merge/push authorization
```

## Verification results

The current checkout and an independent clean snapshot both passed:

- 188 XCTest tests with zero failures;
- release builds for all four package products;
- `bash -n` and `shellcheck -x` for all scripts;
- plist/config/manifest lint;
- production package `prepare` and `verify`;
- `git diff --check`.

The clean snapshot was copied without `.git` and `.build`, initialized as a new repository, and
validated from a fresh build graph. Its tracked working tree remained clean after verification.

## Decision

**Approved.** The production LaunchDaemon architecture, implementation, lifecycle tooling, and validated M1 Pro behavior meet the closed Spec and Plan. The final acceptance state is intentionally uninstalled. Future deployment must begin disabled and repeat hardware-appropriate dry-run validation before enabled use.
