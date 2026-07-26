# Lid Angle Auto-Sleep Plan Review

## Review Scope

Review the implementation plan task-by-task against the approved design, with emphasis on executable interfaces, deterministic tests, macOS lifecycle integration, real-sleep containment, and the two-layer Task governance contract.

## Initial Findings

### P1-1 — Wake cooldown requirement had no implementation Task

The initial plan mentioned wake cooldown globally but Task 3 only described angle events, scheduling, and sleep requests. No lifecycle port or production notification adapter existed.

**Resolution:** Added `SystemWakeObserving`, `SystemWakeObserver.swift`, fake wake-observer tests, `.systemDidWake`, coordinator routing, and explicit `NSWorkspace.didWakeNotification` behavior.

### P1-2 — Cooldown state could produce incompatible implementations

The state-machine tests only said cooldown blocks closing until elapsed. They did not specify whether a lid already below `70` becomes armed when cooldown ends.

**Resolution:** Added deterministic tests and interfaces for the `disarmed` outcome. Cooldown completion below `70` stays disarmed until a later `>=70` report.

### P1-3 — `SleepRequesting` ownership was inconsistent

Task 3 claimed to produce `SleepRequesting`, while the file intended to own that interface was only created in Task 4. An implementer following Task 3 alone would lack an exact file location.

**Resolution:** Task 3 now creates `SleepRequester.swift` with the port; Task 4 modifies that file to add dry-run and production adapters.

### P1-4 — Production sleep operation remained an implementation placeholder

The initial wording asked for the “narrowest available mechanism,” which was not an executable instruction and could lead to `pmset`, shell execution, or retries.

**Resolution:** Fixed the implementation to one `IOPMSleepSystem` call using an `IOPMCopySystemPowerConnection()` connection, typed `IOReturn` handling, connection cleanup, no retries, and a safety scan rejecting `pmset`.

### P1-5 — AppKit dependency was absent from the file/task map

The new `NSWorkspace` wake adapter requires AppKit, but the package manifest was not scheduled for modification.

**Resolution:** Added `Package.swift` to Task 3 and required explicit AppKit linkage.

### P2-1 — Main-loop behavior was underspecified

“Keep the process alive without a high-frequency loop” did not give an exact implementation choice.

**Resolution:** Task 5 now requires `RunLoop.main.run()`.

### P2-2 — Startup cooldown acceptance did not define the safe post-cooldown result

The original hardware acceptance asked only to document what happened after five seconds.

**Resolution:** Task 6 now requires the process to remain disarmed below `70`, then rearm only after opening to `>=70` before a new close can trigger.

## Re-Review

- Every produced protocol has one exact owning file and a later consuming Task.
- State-machine, coordinator, lifecycle, and system-operation boundaries are independently testable.
- The production path contains no implicit real-sleep mode.
- Dry-run hardware acceptance and energy review remain mandatory gates before real sleep.
- Task 8 still requires a new explicit user approval and creates no LaunchAgent.
- Each Task has RED, GREEN, review, correction, Open P0/P1 gate, and commit instructions.
- Placeholder scan and interface-name scan show no unresolved implementation choice material to safety.

## Final Disposition

- Open P0: 0
- Open P1: 0
- Open P2: 0
- Plan status: approved for holistic Spec+Plan consistency review
