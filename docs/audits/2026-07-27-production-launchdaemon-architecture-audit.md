# Production LaunchDaemon Architecture Audit

Date: 2026-07-27  
Baseline: `589dc7a docs: close launchdaemon feasibility spike`

## Audit scope

This audit originally evaluated whether the completed feasibility implementation could become a long-lived system LaunchDaemon. The production phase subsequently implemented and accepted that architecture. Installation, `/Library` mutation, bootstrap, reboot, logout, and real sensor-driven sleep remained separately approved throughout execution.

The requested `AGENTS.md` is not present at baseline `589dc7a`. The repository-level rules available for this audit are therefore the user's explicit instructions, the existing superpowers documents, and the checked-in source and validation evidence.

## Current inventory

### Existing products

- `macbook-lid-monitor`: foreground diagnostic and explicitly enabled foreground auto-sleep CLI.
- `macbook-lid-monitor-daemon-spike`: fixed dry-run feasibility executable.
- `macbook-lid-monitor-sleep-probe`: independent one-shot root-context sleep API probe.

### Verified platform capabilities

- system-domain root execution and launch-at-boot;
- pre-login HID discovery, open, and continuous report delivery;
- single root process without a LaunchAgent;
- ordered IOKit sleep/wake callbacks;
- wake-recovery open and low-value branches;
- one-shot `IOPMSleepSystem` success in root context;
- clean stop, bootout, bootstrap, reboot auto-start, and uninstall;
- no observed retry loop, duplicate authority, or restart storm.

### Current calibrated policy

The policy remains machine-specific sensor data, not geometric hinge angle:

```text
sleepThreshold=68
reopenThreshold=75
closeDebounce=2
startupCooldown=5
wakeRecovery=15
```

## Promotion assessment

### Shared core suitable for promotion

The following components have production-shaped responsibilities and test seams. They should remain shared core, with targeted hardening rather than duplication:

| Component | Disposition | Required hardening |
| --- | --- | --- |
| `LidSleepStateMachine` | Promote | Add explicit freshness semantics and duplicate-request guard evidence. |
| `LidSleepCoordinator` | Promote | Separate lifecycle result/exit classification, make configuration injected, expose health snapshots. |
| `IOHIDReportStream` | Promote | Add startup timeout/failure classification and explicit stale-report handling above the stream. |
| `IOHIDDeviceEnumerator` / `CandidateRanker` | Promote partially | Ranking may remain diagnostic; production selection must require an approved hardware profile, not score alone. |
| `ReportID1DegreesDecoder` | Promote only behind profile | It is valid for the accepted M1 Pro profile; generic fallback decoding must not authorize sleep. |
| `IOKitSystemPowerObserver` | Promote | Preserve ordered acknowledgement tests; add lifecycle health and bounded registration failure disposition. |
| `MacOSSleepRequester` / `IOKitSystemSleepOperation` | Promote | Exactly-once per state transition, fail-open, no automatic retry. |
| `ProcessSignalController` | Promote | Production naming, termination reason, and clean shutdown timeout evidence. |
| scheduler abstractions | Promote | Continue one-shot scheduling; do not add polling. |

### Must not become the production entry point

| Existing item | Reason |
| --- | --- |
| `DaemonSpikeApplication` | Hard-codes dry-run, calibrated default, composite exploratory decoder, spike naming, and evidence-only composition. |
| `DaemonSpikeEvidence` | Logs raw machine identity and sensor values without a production privacy/retention contract. |
| `LidMonitorDaemonSpike/main.swift` | Experimental product and exit mapping; no configuration or compatibility gate. |
| `SleepProbeApplication` and sleep-probe product | Deliberately bypasses sensor policy; retain only as an approval-gated engineering tool. |
| feasibility plist | Temporary label/path/log policy; no production mode/config/health contract. |
| `manage-feasibility-daemon.sh` | Install-only experiment flow; no transactional upgrade, rollback, version verification, or production state model. |

## Production readiness gaps

### P0 safety gaps

1. **No production hardware authorization gate.** Candidate score plus composite decoding can select an unvalidated device/report format. Production sleep must require an exact approved profile and decoder.
2. **No formal daemon mode model.** Dry-run is hard-coded in the spike; enabled and disabled states are not represented as validated configuration.
3. **No persistent single source of truth.** Policy, hardware profile, mode, schema version, and package version are not assembled into one validated configuration document.
4. **No stale-data contract.** Unknown format fails open, but production must also reject old sensor samples during close debounce and wake recovery.
5. **No upgrade/rollback transaction.** The feasibility installer refuses replacement but cannot safely stage, validate, activate, and revert a version.

### P1 operational gaps

1. Startup failures are mapped to process exit codes but not classified into permanent versus transient outcomes for launchd.
2. There is no bounded restart budget or administrative crash-loop circuit breaker.
3. Logging has no rotation, size cap, event taxonomy, redaction policy, or diagnostic bundle command.
4. There is no health/status contract distinguishing loaded, running, monitoring, armed, disabled, incompatible, degraded, and failed-open.
5. There is no emergency disable workflow independent of rebuilding or deleting the binary.
6. The installed package has no manifest, version stamp, checksum record, or rollback slot.
7. Ownership and permissions are checked during install but not comprehensively revalidated before bootstrap or upgrade.

### P2 maintainability gaps

1. Spike-specific names are mixed into reusable evidence concepts.
2. README documents feasibility but no production operator lifecycle.
3. Acceptance evidence has no matrix tying each requirement to automated, packaging, and hardware proof.
4. `AGENTS.md` is referenced by the workflow but absent from this baseline.

## Recommended architecture

### Production executable

Add a new product and target:

```text
macbook-lid-monitor-daemon
Sources/LidMonitorDaemon/
Sources/LidMonitorCore/Production/
```

The executable is a thin composition root. It reads one fixed-path configuration, validates it, resolves an approved hardware profile, constructs the shared coordinator, publishes structured operational events, and terminates with a classified exit disposition.

### Configuration and modes

Use a root-owned plist at a fixed path:

```text
/Library/Application Support/MacBookLidMonitor/config.plist
```

Required fields:

- configuration schema version;
- operating mode: `disabled`, `dry-run`, or `enabled`;
- approved hardware profile identifier;
- complete policy values;
- package-generated installation identifier and product version.

`disabled` keeps the job loadable but does not open HID or register sleep policy. `dry-run` runs the full sensor path but uses `DryRunSleepRequester`. `enabled` is accepted only when the hardware profile, decoder, policy, file ownership, and configuration schema are valid. Any invalid or unknown value fails open.

### Hardware compatibility

Production must not use heuristic ranking as authorization. It may use ranking for diagnostics, but sleep enablement requires an exact profile match. The first profile is:

```text
profile: m1-pro-05ac-8104-0020-008a-spu-report-id-1-u16
vendorID: 0x05AC
productID: 0x8104
usagePage: 0x0020
usage: 0x008A
transport: SPU
report format: report ID 1, three-byte report, unsigned little-endian payload
```

Unknown model, transport, identity, report length, report ID, decoder ambiguity, non-fresh data, or out-of-range value places the daemon in an incompatible/degraded fail-open state and never requests sleep.

### Single authority

- One system LaunchDaemon label: `com.crazydennies.macbook-lid-monitor`.
- No LaunchAgent.
- Production installation must reject a loaded feasibility job, foreground real-sleep process, or another production instance.
- Foreground CLI real-sleep documentation must require the production daemon to be disabled/booted out first.

### Sleep safety

- One request per transition to `triggered`.
- No retry after sleep API failure.
- Failure transitions to `disarmed` and requires a fresh reopen sample before rearming.
- Wake recovery uses only samples received after `has-powered-on`.
- Recovery may issue at most one resleep request per wake epoch.
- Missing/stale/invalid sensor data fails open.

### Restart policy

The plist should use `RunAtLoad=true` and a bounded launchd restart policy for unexpected exits only. It must not use unconditional `KeepAlive=true`. The daemon should classify configuration incompatibility and deliberate disable as clean, non-restarting states. Repeated crashes must trip an installer-managed or daemon-managed circuit breaker that leaves the service failed-open and requires an explicit operator action to clear.

### Packaging lifecycle

Use fixed paths and a transactional package layout:

```text
/Library/PrivilegedHelperTools/macbook-lid-monitor-daemon
/Library/LaunchDaemons/com.crazydennies.macbook-lid-monitor.plist
/Library/Application Support/MacBookLidMonitor/config.plist
/Library/Application Support/MacBookLidMonitor/manifest.plist
/Library/Application Support/MacBookLidMonitor/rollback/
/Library/Logs/MacBookLidMonitor/
```

Install and upgrade stage files to root-owned temporary files, validate syntax/checksums/version compatibility, boot out the old job, atomically activate the new set, bootstrap, verify health, and automatically restore the previous set if activation fails. Uninstall must boot out first, verify process exit, remove all managed artifacts, and leave unrelated files untouched.

### Logging and diagnostics

- Structured single-line events with timestamp, event name, daemon version, mode, profile, and stable error code.
- Do not log raw HID bytes in production.
- Sensor values may be logged only for bounded diagnostic mode or low-frequency state transitions, not every report.
- stdout/stderr files must have an explicit size/rotation strategy implemented by the management tool; launchd alone does not rotate them.
- Diagnostic bundle generation must default to redacted output and never mutate service state.

## Spike/probe disposition

- Keep spike and probe source temporarily under clearly marked experimental products until production acceptance is complete.
- Exclude both from production package preparation.
- Keep their tests as regression evidence where they test shared core behavior.
- After production hardware acceptance, archive feasibility scripts/plist under `tools/feasibility/` or remove them in a dedicated cleanup task; preserve validation documents permanently.
- Never install the sleep probe as a service and never invoke it from production scripts.

## Audit conclusion

The platform feasibility blocker is genuinely cleared, but the spike is not a safe production composition. The recommended path is a new production executable around promoted shared core, exact hardware-profile authorization, a validated fixed-path configuration, fail-open health states, bounded restart behavior, and transactional package management. Production implementation should proceed only after the accompanying spec, plan, and task decomposition pass review and the user approves each system mutation gate.
