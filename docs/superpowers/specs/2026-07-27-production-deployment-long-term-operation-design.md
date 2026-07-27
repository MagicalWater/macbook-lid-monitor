# Milestone 16 — Production Deployment and Long-term Operation Design Specification

Status: Approved and closed under dual-layer Spec governance; Plan and system mutation remain prohibited
Baseline: `e2b8afeac0bf8f7560d6a9d60b4da328d9650bd3`
Target machine: `MacBookPro18,1` (Apple M1 Pro)

## 1. Problem

Milestones 1–15 produced and accepted a fail-open production LaunchDaemon, then intentionally
rolled it back and uninstalled it. The accepted lifecycle is optimized for bounded acceptance: it
can temporarily enter `enabled`, but every real-sleep command returns to `disabled`, reboot proof
expects disabled/no resident process, and final closure removes all managed artifacts.

The requested product state is different. This Mac must retain an installed, loaded, persistently
enabled system daemon that starts before login, monitors continuously across wake cycles, and
remains operational after reboot. That state must not be reached by bypassing the existing safety
gates or by treating historical acceptance as current deployment evidence.

## 2. Goal

Deliver a governed deployment lifecycle whose successful final state is:

```text
production package=installed
LaunchDaemon=loaded
mode=enabled
daemon process count=1
daemon=running
boot auto-start=verified
pre-login operation=verified
lid close sleep=verified
wake monitoring=verified
recovery resleep=verified
duplicate sleep authority=absent
operational baseline=captured
```

Milestone closure must preserve this state. Closure must not call `disable`, `bootout`, rollback, or
`uninstall` unless a failure requires emergency fail-open recovery; any such recovery prevents a
successful Milestone closure until the deployment is repeated and the final state is restored.

## 3. Scope

- verify source provenance from formal `main` and `origin/main`;
- maintain all development and governance changes in the isolated DevSpace worktree;
- correct deployment-blocking authority, environment-override, integrity, log-rotation, and
  operational-observability findings;
- add an evidence-bound persistent activation lifecycle;
- install the final package in `disabled` only after explicit approval;
- perform fresh installed dry-run, enabled sleep, recovery-resleep, enabled reboot, and pre-login
  acceptance with separate approval gates;
- create stable status, diagnostics, operational baseline, emergency response, upgrade, rollback,
  and uninstall workflows;
- capture repository evidence and complete Task, stage, and holistic reviews;
- finish installed, loaded, enabled, and running.

## 4. Non-goals

- generic support for unvalidated MacBook models;
- cloud control, remote activation, telemetry, or automatic updates;
- modification of NVRAM or persistent macOS power settings;
- removal of fail-open, crash-budget, freshness, wake-epoch, or no-retry protections;
- permanent installation of feasibility spike or sleep-probe products;
- automatic reboot or password handling;
- storing serial number, hardware UUID, provisioning UDID, or unrelated personal/device data;
- treating the previous Task 12–14 evidence as a substitute for this installed deployment.

## 5. Source and Git provenance

1. All Milestone 16 edits, tests, reviews, and evidence are created in the DevSpace worktree.
2. No merge, push, or worktree cleanup occurs without explicit user approval.
3. Before any package preparation intended for real installation:
   - formal `main` must equal `origin/main`;
   - the deployment worktree HEAD must equal the approved formal-main release commit;
   - both tracked working trees must be clean;
   - the package version and evidence must record that exact commit.
4. A package built from an unmerged implementation commit may be used only in sandbox tests, not
   for final system installation.
5. Evidence-only commits created after installation may advance the worktree without changing the
   installed package identity; the evidence must continue to name the installed release commit.

## 6. Safety invariants

1. Unknown hardware, report format, policy, package identity, configuration, ownership, mode,
   acceptance state, crash state, or authority state never causes sleep.
2. `disabled` and `dry-run` cannot construct a real sleep requester.
3. Persistent `enabled` can be reached only through the deployment `activate` gate.
4. Dry-run, one-sleep, and recovery-resleep evidence must match the exact currently installed
   artifact set and target model/profile.
5. Acceptance commands that perform real sleep always restore `disabled` on success, error,
   timeout, interruption, or failed evidence collection.
6. Only final activation and enabled reboot verification are allowed to leave the daemon enabled.
7. Production and foreground real-sleep flows cannot hold different replaceable lease inodes.
8. A wake epoch produces at most one recovery-resleep request; a failed sleep request is not
   retried and remains disarmed until a fresh reopen sample.
9. Crash-circuit-open, corrupt crash state, or unsafe reset state remains fail-open.
10. No script invokes reboot, reads a password, stores a password, or uses `sudo -S`.
11. Upgrade, rollback, and package/config changes cannot silently preserve or restore enabled mode
    without a matching deployment acceptance identity.
12. Final closure does not uninstall or intentionally return the system to disabled.

## 7. Deployment architecture

### 7.1 Managed artifact set

The installed set remains rooted in the existing fixed paths and adds deployment state and a safe
authority file:

```text
/Library/PrivilegedHelperTools/macbook-lid-monitor-daemon
/Library/LaunchDaemons/com.crazydennies.macbook-lid-monitor.plist
/Library/Application Support/MacBookLidMonitor/config.plist
/Library/Application Support/MacBookLidMonitor/manifest.plist
/Library/Application Support/MacBookLidMonitor/sleep-authority.lock
/Library/Application Support/MacBookLidMonitor/deployment-acceptance.plist
/Library/Application Support/MacBookLidMonitor/deployment-reboot-state.plist
/Library/Application Support/MacBookLidMonitor/crash-budget.json
/Library/Application Support/MacBookLidMonitor/rollback/
/Library/Logs/MacBookLidMonitor/
```

Exact required metadata:

```text
binary                       root:wheel 0755 regular
LaunchDaemon plist           root:wheel 0644 regular
support directory            root:wheel 0755 directory, not user-writable
config                       root:wheel 0644 regular
manifest                     root:wheel 0644 regular
sleep-authority.lock         root:wheel 0666 regular, link-count=1, parent not user-writable
deployment acceptance state  root:wheel 0600 regular
deployment reboot state      root:wheel 0600 regular
crash-budget state           root:wheel 0600 regular when present
log directory                root:wheel 0700 directory
production logs              root:wheel 0600 regular when present
rollback directory           root:wheel 0700 directory when present
```

Every managed path operation rejects symlinks and unsafe ancestors. Security-sensitive regular
files also reject unexpected hard-link counts.

### 7.2 Non-replaceable sleep authority

The production daemon never uses the current `/tmp` lease. Installation creates the managed
root-owned lease file before the job can be bootstrapped. The production daemon opens it without
following links, validates type, owner, group, permissions, link count, and parent safety, then
uses a non-blocking exclusive advisory lock.

When the production package is installed, foreground `--execute-sleep` must use the same managed
lease file. Unsafe or missing managed lease state fails open. A foreground-only fallback may exist
only when all production package/job markers are absent; it cannot authorize a foreground process
while production is installed.

Installation, upgrade, rollback, and uninstall must serialize lifecycle mutation and must reject a
resident foreground real-sleep process. Uninstall removes the managed lease only after the daemon
is stopped and the job is booted out.

### 7.3 Production requester composition

The deployable production daemon must not inspect `MLM_SLEEP_OPERATION` or any environment variable
to choose a sleep requester. `enabled` always composes the real IOKit requester after validated
configuration, installed package, hardware profile, crash budget, and sleep authority gates pass.

Sleep-failure behavior remains testable through injected dependencies. Any future system-level
failure-injection executable or package must be separate from the production manifest and must be
governed as its own acceptance artifact.

### 7.4 Manifest and installed-set integrity

The manifest schema must cover at least:

```text
schema version
product
source/release commit
binary path and SHA-256
LaunchDaemon plist path and SHA-256
config path and disabled-template SHA-256
hardware profile ID
crash-budget path
sleep-authority path
```

Because `Mode` is intentionally mutable, installed config verification normalizes only `Mode` back
to `disabled` before comparison with the manifest template checksum. Every other config key and
value must match the package template exactly. The current unnormalized config checksum is also
reported for operational evidence.

A shared installed-set verifier validates file identity, owner, group, mode, symlink/hard-link
safety, manifest schema, expected-vs-actual checksums, normalized config policy, and prohibited
LaunchDaemon environment variables. It is required before bootstrap, mode changes, acceptance,
activation, baseline capture, upgrade, rollback, and reboot completion.

The production runtime repeats the installed-set checks that are required to decide whether it may
construct a real requester. Failure emits a stable fail-open error and cannot start enabled
monitoring.

### 7.5 Target hardware binding

Runtime authority remains the checked-in exact HID profile:

```text
profile=m1-pro-0x8104-report-id-1-v1
vendor=0x05AC
product=0x8104
usage-page=0x0020
usage=0x008A
transport=SPU
report=ID 1, three bytes, profile-bound decoder
```

Deployment preflight and acceptance additionally require:

```text
Mac model identifier=MacBookPro18,1
chip family=Apple M1 Pro
```

The deployment record stores only these non-unique compatibility fields. A mismatch invalidates
acceptance and fails open.

### 7.6 Deployment acceptance state

`deployment-acceptance.plist` is an atomic root-owned record bound to:

- source/release commit;
- manifest checksum;
- binary/plist/template/current-config checksums;
- hardware profile ID;
- Mac model identifier;
- dry-run acceptance timestamp/result;
- one-sleep acceptance timestamp/result;
- recovery-resleep acceptance timestamp/result.

Install, upgrade, rollback, policy change, manifest change, hardware mismatch, or acceptance
failure invalidates the record. The record is evidence and a gate, not a substitute for tests or
review. It contains no password, token with reusable authority, raw HID bytes, or unique device ID.

### 7.7 Management commands

The management surface must provide stable, explicit commands equivalent to:

```text
prepare
verify
verify-installed
install
bootstrap
status
diagnostics
disable
dry-run
deployment-dry-run
deployment-enabled-once
deployment-recovery-resleep
activate
deployment-reboot-start
deployment-reboot-finish
operational-baseline
reset-crash-budget
rotate-logs
upgrade
rollback
uninstall
```

There is no unrestricted `enable` alias. `activate` requires a complete matching acceptance record
and an explicit invocation after user approval. It verifies the installed set, removes any
prohibited acceptance environment entry, sets mode to enabled atomically, restarts the job, and
verifies one stable resident daemon plus expected startup/profile/health evidence.

### 7.8 Status, diagnostics, and baseline

`status` emits a concise stable key-value summary suitable for operators and tests:

```text
installed
version/source commit
mode
job loaded state
resident process count and PID
runtime health
hardware profile/model match
installed-set integrity
crash circuit state
sleep-authority metadata/held state
acceptance state
```

`diagnostics` is read-only and redacted. It additionally emits:

- manifest checksum;
- expected and actual binary/plist/normalized-config checksums;
- current config checksum;
- owner/mode/type/link count for managed paths;
- crash-budget count, circuit state, and active-run state, or stable corrupt/unavailable status;
- process elapsed time, CPU percentage, RSS, and VSZ;
- log owner/mode/size and retained-generation sizes;
- last stable lifecycle, health, and error metadata without raw reports or unrelated log contents.

`operational-baseline` runs only after enabled activation or reboot finish and fails unless the
required final state is present. Its output is copied into a repository validation document and
includes installed version, manifest/config checksums, launchd state, PID, crash-budget state, log
permissions/sizes, CPU/memory values, hardware/profile match, and acceptance identity.

### 7.9 Runtime health

The currently unused `DaemonHealth` contract must be connected to production composition or
replaced by an equally stable tested mechanism. Health evidence must cover startup, disabled,
dry-run, monitoring-disarmed, monitoring-armed, incompatible, degraded-fail-open, and stopping.

Disk-backed health updates must be bounded. If a health snapshot stores sample time, it records a
timestamp at a throttled interval or state transition rather than writing on every HID report.
Status computes age from the stored timestamp and marks unavailable/stale evidence explicitly.

### 7.10 Log maintenance

Production logs remain low-frequency and raw-report-free. `rotate-logs` must preserve the active
inode while the daemon is running, rotate at a 1 MiB threshold, retain at most three generations,
and preserve root-only permissions. Post-rotation events must appear in the primary log, not the
archived inode.

Diagnostics never rotates logs implicitly. The operator runbook defines the inspection threshold
and explicit maintenance procedure. Automatic periodic maintenance is not added in Milestone 16
unless implementation review proves manual bounded maintenance is inadequate for the observed
event rate.

### 7.11 Upgrade and rollback

An upgrade verifies the current set, forces or requires disabled/nonresident state, stages the new
package, activates it transactionally, and finishes disabled. Any artifact/policy checksum change
invalidates deployment acceptance. A docs-only change with identical deployed artifact checksums
does not by itself invalidate hardware evidence.

Explicit and automatic rollback restore the selected artifact set but finish disabled. Neither may
reactivate enabled mode merely because the rollback config was previously enabled or previously
accepted. Failure to restore and verify a safe disabled set leaves the job booted out and returns an
error.

Re-entering persistent enabled after upgrade or rollback requires the applicable dry-run,
acceptance, and `activate` gates defined by the implementation Plan.

## 8. Approval gates and deployment flow

### Gate 0 — Documentation and implementation only

Audit, Spec, Plan, Tasks, tests, and worktree implementation may proceed without system mutation.
No `/Library` write, launchd mutation, real sleep, or reboot is authorized by this Spec.

### Gate 1 — Install disabled

After implementation and reviews pass and the release commit is approved on formal `main`, explain
the exact `/Library` paths and launchd effects. Explicit approval is required before package
preparation for real installation, install, or bootstrap.

Expected post-gate state:

```text
installed=true
mode=disabled
job=loaded
resident process count=0
```

### Gate 2 — Installed dry-run acceptance

Switch to dry-run only after installed-set verification. Verify exact profile/model, one daemon,
full close/debounce/would-sleep chain, reopen/rearm, sleep/wake continuity, authority metadata,
logs, crash budget, and emergency disable. This gate never performs sensor-driven real sleep.

On completion or failure, return to loaded/disabled and write matching dry-run acceptance evidence.

### Gate 3 — One enabled sleep

Explain that closing the lid will cause one real sleep request. After separate explicit approval,
run the bounded one-sleep acceptance with timeout, exact event counts, PID stability, wake evidence,
and fail-safe cleanup. Always return to disabled.

### Gate 4 — Recovery resleep

Explain that the Mac will sleep, wake while the lid remains below the close threshold, and request
one recovery resleep after the configured recovery period. After separate explicit approval, verify
exactly two request attempts, one recovery-resleep transition, bounded wake epochs, stable PID, and
no third request. Always return to disabled.

### Gate 5 — Persistent activation

After dry-run, one-sleep, and recovery-resleep evidence match the installed identity, explain that
`activate` will leave real sleep enabled after the command exits. Explicit approval is required.

Expected post-gate state:

```text
installed=true
mode=enabled
job=loaded
resident process count=1
daemon=running
```

### Gate 6 — Manual reboot and pre-login acceptance

The management script prepares reboot evidence but never invokes reboot. Explain that the user must
restart manually and remain at loginwindow long enough for the pre-login observer/evidence path to
record enabled startup, one PID, exact profile monitoring, and no duplicate authority. Explicit
approval is required before preparation, and the user performs the restart.

`deployment-reboot-finish` proves boot epoch changed, removes temporary observer artifacts, captures
operational evidence, and leaves the daemon enabled and running.

### Gate 7 — Emergency/maintenance mutations

Disable, crash-budget reset, upgrade, rollback, and uninstall remain explicit later operator
actions. They are documented but are not executed during successful Milestone 16 closure.

## 9. Automated verification requirements

- managed lease rejects symlink, unsafe owner/group/mode, hard links, user-writable parent, and
  replacement/inode-split scenarios;
- daemon and foreground use the same managed lease whenever production is installed;
- deployable production composition contains no environment requester override;
- manifest schema and binary/plist/normalized-config checksum validation;
- mode-only config normalization and rejection of every other config difference;
- activation rejection for missing, stale, mismatched, or partial acceptance state;
- acceptance-state atomic update and invalidation on install/upgrade/rollback/config change;
- persistent activation success leaves enabled in sandbox; all bounded acceptance failures return
  disabled;
- stable status/diagnostics/baseline output and redaction;
- crash-budget parsing, corrupt-state fail-open, and reset constraints;
- deterministic owner/mode/type/link-count verification seams;
- running-daemon copy-and-truncate rotation with post-rotation primary-log output;
- upgrade/rollback cannot silently restore enabled mode;
- reboot state requires a changed boot epoch and matching exact package identity;
- uninstall removes all new managed state while preserving unrelated files;
- full XCTest, all release products, Bash/static/plist/package checks, and clean-checkout validation.

## 10. Fresh real-system acceptance requirements

Historical Task 12–14 evidence informs expected behavior but does not close these checks:

1. formal-main source and package identity;
2. broad pre-install residual inventory and explicit disposition of project-owned temporary files;
3. disabled install ownership, modes, checksums, loaded state, and zero PID;
4. installed logged-in dry-run close/reopen chain;
5. installed sleep/wake dry-run continuity;
6. one approved sensor-driven enabled sleep;
7. separately approved recovery resleep;
8. persistent activation with one running PID;
9. manually initiated reboot with enabled mode retained;
10. pre-login enabled process/profile evidence;
11. no duplicate sleep authority;
12. wake monitoring after reboot;
13. operational baseline capture;
14. final status proving installed, enabled, loaded, running, and clean repository provenance.

## 11. Documentation and evidence

Milestone 16 must create:

- this Spec, Spec review, and Spec closure;
- governed implementation Plan, Plan review/re-review/closure;
- governed Task register and per-Task/stage/holistic reviews;
- `docs/operations/production-daemon.md` with status, diagnostics, disable,
  reset-crash-budget, upgrade, rollback, uninstall, and emergency guidance;
- deployment validation evidence for install/dry-run, enabled sleep, recovery resleep, activation,
  reboot/pre-login, and operational baseline;
- final review that names the exact installed version and proves the service remains enabled.

Evidence must not include passwords, raw HID reports, serial number, hardware UUID, or provisioning
UDID.

## 12. Completion definition

Milestone 16 is complete only when:

- Spec, Plan, Tasks, per-Task reviews, stage reviews, and holistic review are closed;
- all implementation findings are fixed and re-reviewed;
- final code/package identity is present on approved formal `main` and `origin/main`;
- all required system mutations and real sleep/reboot gates received separate explicit approval;
- fresh deployment evidence passes;
- operational documentation matches actual commands and state;
- repository verification is clean;
- the final live system remains installed, loaded, enabled, and running with one authority.

Any final `disabled`, booted-out, rolled-back, uninstalled, circuit-open, integrity-failed, or
duplicate-authority state is a failed/incomplete Milestone closure, not an acceptable alternate
success state.

