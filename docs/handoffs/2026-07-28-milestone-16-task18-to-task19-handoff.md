# Milestone 16 Cross-conversation Handoff — Task 18 to Task 19

Date: 2026-07-28

## Authority and scope

This file is the cross-conversation continuation authority for Milestone 16 after Task 18. The
repository, Git history, tests, production evidence, and review documents remain authoritative;
chat summaries are not.

Repository:

```text
/Users/water/Developer/projects/macbook-lid-monitor
```

Branch and Git content baseline before this handoff document's closure commit:

```text
branch: main
last completed Task 18 closure commit: 4d00ad1cc9fe92a1f481ea8651d0ca081208368f
working tree before handoff synchronization: clean
local main ahead of origin/main before handoff synchronization: 9 commits
local main behind origin/main: 0 commits
origin/main: 412fcc207b447d42ffdf58e9e35bd545d1b04ad4
push status: not pushed; the handoff synchronization commit will add one further local commit;
explicit user approval is still required
```

## Installed production identity and live state

```text
installed source commit: 0885d54dbf133fdd8620d4a38379a8ed64819430
installed version: 0885d54dbf13
integrity: valid
hardware model: MacBookPro18,1
chip: Apple M1 Pro
profile: m1-pro-0x8104-report-id-1-v1
mode: disabled
launchd job: loaded, not running
process-count: 0
last exit code: 0
```

Managed sleep authority:

```text
path: /Library/Application Support/MacBookLidMonitor/sleep-authority.lock
owner: root:wheel
mode: 0600
type: regular file
link count: 1
size: 0
```

The Mac is safe to leave in this state indefinitely. Persistent production behavior is not yet
enabled.

## Completed governance and acceptance

- Spec, Plan, Task register, Stage A review, and Stage B review: complete.
- Tasks 1–15: complete.
- Task 16: complete after managed lease creation, provenance, privileged Git trust, and runtime
  `0600` permission remediation.
- Task 17: complete on installed identity `0885d54...`.
- Task 18: complete on installed identity `0885d54...`.

Task 17 final dry-run evidence:

```text
daemon PID: 87847
monitoring-armed: observed
candidate-started: observed
debounce-elapsed: observed
sleep-request-attempted: exactly 1
would-sleep: exactly 1
deployment-dry-run acceptance: pass
cleanup: disabled, loaded, zero PID
```

Task 18 final sensor-driven real-sleep evidence:

```text
daemon PID: 93950
monitoring-armed: observed
candidate-started: observed
debounce-elapsed: observed
sleep-request-attempted: exactly 1
sleep-requested: exactly 1
wake evidence: true
PID stable across sleep/wake: true
deployment-enabled-once acceptance: pass
cleanup: disabled, loaded, zero PID
```

No open P0 or undispositioned P1 finding remains for Tasks 16–18.

## Important remediations already closed

1. Installer now creates and repairs the managed sleep-authority lease.
2. Full no-op upgrade requires payload and provenance identity equality.
3. Privileged package provenance uses per-command `safe.directory` and does not mutate global Git
   configuration.
4. Task 17 readiness waits for PID-specific `monitoring-armed` before starting the manual window.
5. Managed production runtime lease policy expects `0600`, matching the installed secure lease.

Relevant evidence:

```text
docs/validation/2026-07-28-managed-sleep-authority-remediation.md
docs/validation/2026-07-28-production-deployment-dry-run-acceptance.md
docs/superpowers/reviews/2026-07-27-production-deployment-long-term-operation-implementation-task-reviews.md
docs/superpowers/tasks/2026-07-27-production-deployment-long-term-operation-tasks.md
```

Latest verification associated with the runtime permission remediation:

```text
SleepAuthorityLeaseTests: 12 tests, 0 failures
ProductionDaemonCompositionTests: 11 tests, 0 failures
ProductionManagementScriptTests: 84 tests, 0 failures
full suite: 270 tests, 0 failures
bash -n: pass
shellcheck -x: pass
git diff --check: pass
```

## Remaining Milestone 16 work

### Task 19 — Bounded recovery-resleep acceptance

Goal: verify the installed daemon handles wake while the lid remains below the reopen threshold by
issuing one bounded recovery resleep, with exactly two total sleep attempts, one recovery
transition, no third attempt, PID continuity, and cleanup back to disabled.

This task requires a new explicit user approval because it performs real power-state changes. Do
not reuse Task 18 approval.

### Task 20 — Persistent production activation

Goal: activate the accepted installed identity for long-term enabled operation and verify one PID,
managed authority, healthy enabled state, and complete acceptance identity.

This task requires a separate explicit persistent-activation approval. Until it is completed, the
user's final goal of long-term automatic lid-angle sleep handling is not active.

### Task 21 — Enabled reboot, pre-login, baseline, and final closure

Goal: reboot the Mac manually after preparation and verify auto-load before login, enabled mode,
single PID, hardware/profile identity, managed authority, operational baseline, and final closure.

This task requires explicit reboot preparation approval; the user performs the restart manually.

### Stage C and holistic final review

After Tasks 19–21, perform the independent Stage C review and Milestone 16 holistic final review.
Final closure requires the live daemon to remain enabled/running and all repository authority files
to agree.

## Required workflow in the next conversation

1. Open the repository checkout, not a new worktree, unless repository evidence requires otherwise.
2. Read this handoff, the Task register, the implementation review, and relevant validation files.
3. Perform a read-only cross-conversation baseline audit before any mutation.
4. Confirm branch, HEAD, clean tree, origin divergence, installed identity, disabled/zero-PID state,
   lease metadata, and Task 18 acceptance evidence.
5. Synchronize any authority discrepancy before entering Task 19.
6. Apply the mandatory per-Task double-layer governance workflow.
7. Obtain a fresh explicit approval before Task 19 real power-state mutation.

## Non-obvious operational notes

- The product uses the Apple lid-angle HID sensor, not the broken legacy clamshell switch.
- The sleep threshold is `<=68°` with a two-second debounce.
- A non-root `status` command may label root-only health/acceptance files as `corrupt` after a
  permission denial. Root acceptance evidence and direct installed-state verification are the
  authority; do not infer actual corruption solely from the non-root status label.
- Do not push local main, enable persistent production, reboot, or run Task 19 without the required
  separate user approval.
- The correct safe stopping state for the current handoff is loaded/disabled/zero PID.
