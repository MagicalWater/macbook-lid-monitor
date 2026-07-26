# LaunchDaemon Feasibility Spike Spec Review

## Review Scope

Review `2026-07-26-launchdaemon-feasibility-spike-design.md` against the user's
required pre-login LaunchDaemon feasibility questions, the existing foreground
auto-sleep safety model, the no-install/no-disruptive-test approval gates, and
the requirement that spec and plan each follow the two-layer Task governance
flow.

## Initial Findings

### P1-1 — A production target refactor could be mistaken for spike scope

The initial architecture direction called for Core + CLI + daemon targets, but a
full target migration before system-context feasibility is proven would create
large code movement without answering the primary loginwindow question.

**Resolution:** The spec now permits only a minimal temporary spike executable
and the smallest shared-code extraction needed to avoid duplication. The final
Core + CLI + daemon structure is explicitly deferred to the production phase.

### P1-2 — Dry-run alone did not answer daemon-context `IOPMSleepSystem`

A permanently dry-run LaunchDaemon safely validates HID and notifications, but
cannot prove that `IOPMSleepSystem` works from daemon context. Folding real sleep
into the installed spike would violate the user's safety gate.

**Resolution:** Added a separate one-shot sleep-operation probe. It is not
referenced by the installed plist, cannot be triggered by sensor reports, runs
once without retry, and requires explicit approval immediately before the real
sleep test.

### P1-3 — `KeepAlive` could mask failures and complicate emergency stop

Enabling `KeepAlive=true` in the first system installation could restart a
failing spike, obscure startup defects, and make a first-time service harder to
stop while the safety behavior is still unproven.

**Resolution:** The first plist must use `RunAtLoad` without `KeepAlive`. Basic
bootstrap, status, SIGTERM, bootout, and uninstall must pass before any bounded
restart-policy test is considered.

### P1-4 — Loginwindow acceptance needed proof from inside the logged-out interval

Seeing reports before logout and after login would not prove that callbacks
continued while the Mac was actually at loginwindow.

**Resolution:** Acceptance now requires timestamped report milestones or other
bounded evidence generated during the loginwindow interval, correlated with the
same launchd job and process lifecycle.

### P1-5 — The installed spike needed a mechanically enforceable no-sleep rule

Documentation saying "dry-run" is insufficient if the daemon target can still
construct `IOKitSystemSleepOperation` through an argument or composition branch.

**Resolution:** The daemon-spike executable must not accept execute-sleep and
must not construct a real sleep operation. Static source and plist scans plus
composition tests are mandatory before installation.

### P2-1 — Sensor availability may race launchd startup

The current stream resolves the selected registry ID once. During early boot,
the SPU sensor may be published after the job starts even if loginwindow access
is otherwise supported.

**Resolution:** The spec records this as a feasibility result to distinguish from
permission failure. The spike may add event-driven IOHID matching callbacks if
boot evidence requires them, but fixed-interval polling is prohibited.

### P2-2 — Root feasibility does not establish the production least privilege

Running the first spike as root removes permission variables but does not prove
that root is necessary or desirable for the final service.

**Resolution:** Root is explicitly limited to the initial feasibility identity.
The production phase must separately decide whether a dedicated service account
can satisfy HID, power notification, and sleep-operation requirements.

## Re-Review

- Scope is limited to system-context feasibility and does not claim production
  daemon readiness.
- The installed spike is mechanically dry-run and has no sensor-driven route to
  `IOPMSleepSystem`.
- HID enumeration, open, callback registration, first report, and report
  continuity are separately observable.
- IOKit power messages and required acknowledgements have exact semantics.
- `kIOMessageSystemHasPoweredOn` is the sole wake-recovery trigger.
- Initial deployment uses a visibly temporary label, binary, plist, and optional
  evidence directory.
- The first plist omits `KeepAlive`, reducing restart-loop and stop risks.
- Loginwindow evidence must be generated during the logged-out interval.
- Logout, sleep, reboot, shutdown, installation, and real sleep each remain
  separately approval-gated.
- A separately gated one-shot probe answers daemon-context `IOPMSleepSystem`
  without weakening the installed dry-run invariant.
- No LaunchAgent, UI, persistent state, power-setting mutation, HID write,
  polling loop, or self-installation entered scope.
- The spec defines exact phase pass/block criteria and preserves Open P0/P1 = 0
  as the implementation gate.

## Validation

- Placeholder scan: no `TBD`, `TODO`, or deferred ambiguous requirement remains.
- Internal consistency: temporary spike naming, dry-run invariant, deployment
  paths, approval gates, and acceptance stages agree throughout.
- Scope check: production target migration, installer hardening, least-privilege
  identity, and unattended execute-sleep remain outside this phase.
- Requirement coverage: all twelve requested feasibility and operational topics
  are either directly tested in this phase or explicitly deferred with a blocking
  gate to the production phase.

## Final Disposition

- Open P0: 0
- Open P1: 0
- Open P2: 0
- Accepted feasibility unknowns: loginwindow HID/report access, early-boot sensor
  publication timing, and daemon-context `IOPMSleepSystem`
- Spec status: approved for implementation-plan creation
