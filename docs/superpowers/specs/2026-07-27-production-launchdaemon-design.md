# Production LaunchDaemon Design Specification

Status: Implemented and accepted on the validated M1 Pro; final system state uninstalled
Baseline: `589dc7a`

## 1. Problem

The feasibility phase proved that a root system LaunchDaemon can monitor the validated M1 Pro lid HID before login, observe system power transitions, and request sleep. It did not provide the controls, compatibility gates, lifecycle management, observability, or rollback guarantees required for long-term production use.

## 2. Goal

Deliver a production LaunchDaemon that can safely monitor an explicitly approved lid sensor profile and, only in `enabled` mode, request macOS sleep according to the calibrated policy while remaining fail-open under uncertainty or failure.

## 3. Scope

- new production daemon executable and composition root;
- fixed-path validated configuration with `disabled`, `dry-run`, and `enabled` modes;
- exact approved hardware profile and decoder binding;
- single root authority and foreground conflict checks;
- structured logging, health/status, bounded diagnostics, and log maintenance;
- safe install, upgrade, rollback, disable, bootout, and uninstall;
- bounded unexpected-exit recovery without restart storms;
- failure injection, packaging validation, clean validation, and approved hardware acceptance;
- operator and architecture documentation.

## 4. Non-goals

- generic support for all MacBook models;
- conversion of sensor values to geometric hinge angles;
- LaunchAgent or per-user authority;
- automatic hardware calibration;
- network telemetry, cloud control, or remote command execution;
- automatic retry of failed sleep requests;
- installation of the sleep probe;
- modification of persistent macOS power settings or NVRAM.

## 5. Safety invariants

1. Unknown hardware, unknown report format, decoder ambiguity, missing configuration, invalid ownership, stale sensor data, or sleep API failure never causes sleep.
2. `disabled` and `dry-run` can never construct `MacOSSleepRequester`.
3. A wake epoch can produce at most one recovery resleep request.
4. A failed sleep request is not retried and disarms until a fresh `>= reopenThreshold` sample.
5. No LaunchAgent exists and at most one real-sleep authority may run.
6. No installation, bootstrap, real sleep, logout, reboot, or `/Library` mutation is performed without explicit approval.

## 6. Components

### 6.1 `ProductionDaemonApplication`

Owns startup sequencing, dependency composition, health state, termination reason, and orderly shutdown. It does not contain hardware-specific constants.

Startup order:

1. load and securely validate configuration;
2. validate package manifest and fixed-path ownership/modes;
3. resolve the exact hardware profile;
4. enforce authority conflict checks;
5. if disabled, publish healthy-disabled and wait for termination;
6. enumerate and exact-match the HID device;
7. select the profile-bound decoder;
8. construct dry-run or real requester according to validated mode;
9. start power observation and HID stream;
10. publish monitoring/armed health as state transitions occur.

### 6.2 Configuration

`ProductionConfiguration` is decoded from the fixed root-owned plist and contains:

```text
schemaVersion: 1
mode: disabled | dry-run | enabled
hardwareProfile: String
policy:
  sleepThreshold: Int
  reopenThreshold: Int
  closeDebounceSeconds: Double
  startupCooldownSeconds: Double
  wakeRecoverySeconds: Double
  sensorFreshnessSeconds: Double
```

Validation rules:

- schema must be supported;
- all fields must be present;
- `sleepThreshold < reopenThreshold`;
- thresholds must be within the profile's accepted decoded range;
- debounce, wake recovery, and sensor freshness must be positive; startup cooldown non-negative;
- enabled mode requires an approved profile and exact package/config permissions;
- no environment variable or command-line override is permitted in production.

### 6.3 Hardware profiles

`LidHardwareProfile` binds exact HID identity, expected transport, report contract, accepted value range, decoder, and validated policy envelope. The first and only enabled profile is the accepted M1 Pro profile described in the audit.

Heuristic candidate ranking remains available to diagnostics but is not an authorization source.

### 6.4 Freshness and request guard

Every decoded sample carries its receipt timestamp. The state machine/coordinator must prove that:

- close debounce uses a sample no older than the configured freshness limit;
- wake recovery considers only samples after `has-powered-on`;
- invalid or stale data cancels a close candidate and produces no request;
- a monotonic wake/request epoch guard prevents duplicate requests from duplicate callbacks or timers.

### 6.5 Health model

Externally observable states:

```text
starting
disabled
monitoring-disarmed
monitoring-armed
dry-run
incompatible-hardware
degraded-fail-open
stopping
```

Status output must include version, mode, profile, PID, launchd state, health state, last transition time, last valid sample age, and last stable error code. It must not expose raw reports.

### 6.6 Exit and restart model

Exit dispositions:

- `0`: deliberate clean stop or disabled shutdown;
- configuration/hardware incompatibility: remain alive in fail-open health where practical, otherwise exit with a documented non-retry disposition;
- unexpected internal failure: non-zero crash-class exit.

The launchd plist may restart unexpected exits with `ThrottleInterval`, but must not unconditionally restart clean exits. A persistent crash budget records bounded failures in the application-support directory. Exceeding the budget enters failed-open/circuit-open state until an operator runs an explicit recovery command.

### 6.7 Logging and privacy

Production event taxonomy includes lifecycle, configuration validation, profile match, HID/power registration, policy transitions, sleep request outcome, health changes, and shutdown.

- no per-report logging;
- no raw HID bytes;
- sensor values only on state-changing evidence and optionally in an explicitly requested bounded diagnostic capture;
- log files root-owned and not group/world-writable;
- management command rotates by bounded size and retained generations;
- diagnostics are redacted by default.

### 6.8 Package manager

One production management script provides explicit subcommands:

```text
prepare verify install upgrade rollback enable-dry-run enable disable
bootstrap status health logs diagnostics stop bootout uninstall
```

Mutating commands require root and must reject symlinked managed paths. `prepare` and repository validation remain non-root and never write `/Library`.

Upgrade is transactional: stage, validate, bootout, atomically activate, bootstrap, verify health, commit manifest. Failure automatically restores the previous binary/plist/config and verifies rollback health.

## 7. Single source of truth

- build/product version: package-generated version metadata;
- runtime behavior: validated production config plist;
- hardware compatibility: checked-in profile registry;
- installation state: root-owned manifest;
- calibrated defaults: profile-defined defaults copied into config only by package tooling and printed during verification.

Scripts must not duplicate policy constants.

## 8. Acceptance criteria

### Automated

- configuration validation and mode composition tests;
- exact profile matching and unknown hardware fail-open tests;
- stale data and wake epoch duplicate-request tests;
- sleep failure no-retry tests;
- signal, health, logging redaction, rotation, manifest, transaction, rollback, and residual-state tests;
- full unit/integration suite and release build.

### Packaging

- plist lint, script syntax, shellcheck, fixed-path and permission checks;
- install/upgrade/rollback/uninstall tested in a controlled approved environment;
- no feasibility product enters the production package;
- clean checkout can reproduce release artifacts.

### Hardware

- dry-run boot/loginwindow/report continuity;
- dry-run close/reopen and wake recovery;
- explicitly approved enabled-mode single sleep;
- explicitly approved enabled-mode recovery resleep;
- injected sleep API failure remains awake and disarmed;
- reboot auto-start and rollback acceptance;
- final uninstall leaves no managed process, job, binary, plist, config, manifest, rollback, or log artifact.

## 9. Documentation requirements

README and operator documentation must clearly distinguish sensor values from physical angles, foreground and daemon authority, all modes, approval gates, emergency disable, install/upgrade/rollback/uninstall, compatibility limits, diagnostics privacy, and current residual system state.

## 10. Completion definition

The production daemon is complete only after all planned tasks, per-task reviews, small-stage reviews, fresh full validation, approved hardware acceptance, residual-state validation, and holistic final review pass. Feasibility evidence alone cannot satisfy production completion.
