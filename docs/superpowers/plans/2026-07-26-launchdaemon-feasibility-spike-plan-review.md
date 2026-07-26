# LaunchDaemon Feasibility Spike Plan Review

## Review Scope

Review `2026-07-26-launchdaemon-feasibility-spike.md` against the approved spike
specification, the existing project structure, the two-layer Task governance
requirements, and the user's explicit safety gates for installation, logout,
sleep, reboot, shutdown, and real sleep requests.

## Initial Findings

### P1-1 — Sharing code between three executables needed an exact boundary

A second executable cannot safely copy the existing state machine, HID stream,
or policy, while moving directly to the final production target layout would
over-expand the spike.

**Resolution:** Task 1 extracts one internal `LidMonitorCore` module and retains
tiny executable wrappers. Daemon and probe applications are implemented inside
the core module so implementation types do not need broad public access. The
final production module layout remains a later design decision.

### P1-2 — A real sleep probe could accidentally become part of the daemon

Building the probe in the same package creates a risk that its execution mode
or sleep operation is reused by the installed daemon composition.

**Resolution:** Tasks 3 and 5 enforce separate entry points and dependency
graphs. The daemon exposes no execution-mode argument and always constructs a
dry-run requester. The probe initializes no HID, scheduler, coordinator, or
power observer and is absent from the plist. Tests cover both invariants.

### P1-3 — Installation and bootstrap were initially one operational step

Combining copy and bootstrap would make ownership/path inspection impossible
before root execution and would weaken the user's installation approval gate.

**Resolution:** Task 6 requires separate `install` and `bootstrap` subcommands.
Task 8 installs first, verifies hashes and ownership, and only then bootstraps.

### P1-4 — Sleep/wake acknowledgement could not be proven solely by hardware

A successful manual sleep shows that the daemon did not block sleep, but does
not prove exactly which notification IDs were acknowledged.

**Resolution:** Task 2 adds injectable unit tests for exact
`IOAllowPowerChange` calls. Task 10 combines those automated results with runtime
event ordering and successful sleep/wake evidence.

### P1-5 — Reboot acceptance needed an early-boot sensor race disposition

If the sensor appears after launchd starts the process, treating the first
enumeration failure as a permission failure would produce a false negative.

**Resolution:** Tasks 9 and 12 require timestamped evidence and explicitly route
an observed publication race into a new reviewed event-driven IOHID matching
subtask. Fixed-interval polling remains prohibited.

### P1-6 — `KeepAlive` testing was not required to answer the primary spike

Testing restart policy before API feasibility would add risk and could create a
restart loop. The final product needs restart behavior, but this spike first
needs reliable boot and cleanup evidence.

**Resolution:** The plist omits `KeepAlive` throughout this plan. Reboot with
`RunAtLoad` validates boot auto-start. Production crash-restart policy remains a
separate production-daemon design concern.

### P1-7 — Phase completion could incorrectly pass with unapproved disruptive stages

The user may approve implementation but defer logout, sleep, probe, or reboot.
A single phase status would obscure which claims were actually tested.

**Resolution:** Task 13 requires a matrix that marks each stage pass, fail, or
not approved. Production architecture and production execute-sleep have separate
unlock decisions.

### P1-8 — Avoiding NSWorkspace calls was weaker than removing AppKit dependency

Leaving the existing workspace observer in the shared core would cause the
daemon spike to link AppKit even when its composition selected the IOKit
observer. That would preserve an unnecessary login-session framework dependency
in the exact binary being tested before login.

**Resolution:** Task 2 now replaces the foreground CLI wake path with the IOKit
observer as well, deletes the workspace notification implementation, removes the
AppKit linker setting, and verifies the daemon binary with `otool -L`.

### P2-1 — Binary string scanning is not authoritative in a shared library build

The daemon executable may contain linked strings from shared core CLI code even
when its composition cannot reach execute-sleep.

**Resolution:** Task 3 labels the string scan supplementary. Injectable
composition tests, absence of a daemon execution-mode parameter, plist review,
and source review are the authoritative no-sleep proof.

### P2-2 — Loginwindow logs must be bounded without losing evidence

Per-report logging would prove continuity but violate the event-driven low-noise
design and create log growth risk.

**Resolution:** Task 4 uses report-driven milestones at count 1 and every 100
valid reports. It adds no logging timer and records no raw bytes.

## Re-Review

- Every spec goal maps to at least one implementation or acceptance Task.
- The existing CLI remains available and retains its explicit foreground sleep
  gate.
- One shared module prevents duplicated state-machine, decoder, coordinator, and
  policy authority.
- The daemon spike is permanently dry-run by API shape, tests, source review,
  and plist contract.
- The one-shot sleep probe is separate, explicit, exactly once, and approval
  gated.
- IOKit message mapping, acknowledgements, cleanup, and failure behavior have
  focused unit tests before hardware validation.
- The final spike binaries do not link AppKit and have no `NSWorkspace` wake
  dependency.
- Packaging uses fixed temporary paths, install/bootstrap separation, root-owned
  modes, no first-stage `KeepAlive`, and allowlisted uninstall.
- Foreground validation precedes all system installation.
- Installation, logout, manual sleep, one-shot real sleep, and reboot each have
  distinct approval gates.
- Loginwindow acceptance requires evidence from inside the logged-out interval.
- Reboot acceptance distinguishes permission failure from device-publication
  timing.
- Every Task includes review, findings, P0/P1 closure, validation, and commit.
- Whole-phase review and final acceptance require system artifact removal.
- README/operator documentation remains Traditional Chinese.

## Validation

### Spec coverage

| Spec requirement | Plan coverage |
| --- | --- |
| pre-login HID enumerate/open | Tasks 8, 9, 12 |
| pre-login report continuity | Tasks 4, 9, 12 |
| system sleep/wake notification | Tasks 2, 10 |
| daemon-context `IOPMSleepSystem` | Tasks 5, 11 |
| root versus other identity | Task 8 proves root only; final review defers least privilege to production |
| core reuse and change scope | Task 1 |
| two executable roles plus isolated probe | Tasks 1, 3, 5 |
| traditional LaunchDaemon packaging | Task 6 |
| fixed paths | Task 6 |
| status/logs/stop/uninstall | Tasks 6, 8, 13 |
| duplicate/restart/disable safety | Tasks 3, 6, 8, 13 |
| login, sleep, reboot acceptance | Tasks 9, 10, 12 |

### Placeholder scan

No `TBD`, `TODO`, `implement later`, `fill in details`, or "similar to another
Task" instruction remains. Deferred production concerns have explicit phase
ownership and blocking rules.

### Type and command consistency

- Product and target names are consistent throughout.
- Fixed label and `/Library` paths are identical in spec, plan, plist contract,
  scripts, tests, and acceptance commands.
- The daemon has no command arguments; the probe command and approval token are
  exact throughout.
- `kIOMessageSystemHasPoweredOn` remains the sole wake-recovery trigger.
- `RunAtLoad`, omitted `KeepAlive`, `ProcessType=Background`, and
  `ThrottleInterval>=30` remain consistent.

## Final Disposition

- Open P0: 0
- Open P1: 0
- Open P2: 0
- Plan status: approved for user implementation decision
- Implementation status: blocked pending explicit user approval
- Installation and disruptive-test Tasks: retain independent approval gates
