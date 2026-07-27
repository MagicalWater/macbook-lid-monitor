# Milestone 16 Production Deployment and Long-term Operation Audit

Date: 2026-07-27
Repository baseline: `e2b8afeac0bf8f7560d6a9d60b4da328d9650bd3`
Scope: Current-state inventory and deployment-readiness review only; no production installation or enablement

## 1. Verified starting state

The formal checkout at `/Users/water/Developer/projects/macbook-lid-monitor` was verified before
creating the Milestone 16 worktree:

```text
branch=main
HEAD=e2b8afeac0bf8f7560d6a9d60b4da328d9650bd3
origin/main=e2b8afeac0bf8f7560d6a9d60b4da328d9650bd3
working-tree=clean
old-worktree=/Users/water/.devspace/worktrees/macbook-lid-monitor-d3aeb5a9 absent
```

The new DevSpace-managed isolated worktree is:

```text
/Users/water/.devspace/worktrees/macbook-lid-monitor-7bf2a52a
base=e2b8afeac0bf8f7560d6a9d60b4da328d9650bd3
state=detached managed worktree
```

Read-only system inspection found the managed production state absent:

```text
LaunchDaemon job=absent
resident production daemon=absent
/Library/PrivilegedHelperTools/macbook-lid-monitor-daemon=absent
/Library/LaunchDaemons/com.crazydennies.macbook-lid-monitor.plist=absent
/Library/Application Support/MacBookLidMonitor=absent
/Library/Logs/MacBookLidMonitor=absent
sleep-authority lease path=absent
```

One user-owned historical test log remains outside the managed package boundary:

```text
/private/tmp/macbook-lid-monitor-task15-final-test.log
owner=water:wheel
mode=0644
```

This does not represent a loaded daemon or installed package, but a broad claim of “no project
residual anywhere on the system” is not yet true. It must be dispositioned explicitly before the
deployment preflight is closed; it must not be silently deleted during this audit.

## 2. Fresh non-mutating baseline verification

The Milestone 16 worktree passed:

- 198 XCTest tests with zero failures;
- release build of `macbook-lid-monitor-daemon`;
- Bash syntax validation for production management scripts;
- plist/config/manifest lint;
- `git diff --check`;
- clean tracked working tree before this audit was written.

These results prove the accepted Milestone 1–15 baseline remains reproducible. They do not prove
that the current lifecycle is sufficient for permanent enabled deployment.

## 3. Capabilities already available

The accepted baseline already provides:

- a system-domain LaunchDaemon that can start before login;
- exact HID identity/profile resolution for the validated M1 Pro sensor;
- strict `disabled`, `dry-run`, and `enabled` runtime composition;
- stale-sample, wake-epoch, duplicate-request, and no-retry protections;
- a persistent crash budget with circuit-open fail-open behavior;
- transactional install, upgrade, rollback, disable, bootout, and uninstall mechanics;
- structured transition logging without raw HID reports;
- bounded one-shot enabled sleep and recovery-resleep acceptance commands;
- prior real-system logged-in, loginwindow, sleep/wake, enabled, recovery, reboot, rollback, and
  uninstall evidence;
- zero managed production artifacts after the prior acceptance closure.

Milestone 16 therefore does not need to redesign lid policy or repeat feasibility work. It must
convert an acceptance-oriented lifecycle into a defensible persistent deployment lifecycle.

## 4. Deployment-blocking findings

### P0 — Sleep-authority inode can be replaced in the current `/tmp` design

`POSIXSleepAuthorityLease` opens a world-writable lock file at:

```text
/tmp/com.crazydennies.macbook-lid-monitor.sleep-authority.lock
```

The implementation rejects symlinks and uses `flock`, but it does not require a root-owned,
non-replaceable parent or owner. If a regular user creates the file first, the daemon can later
lock that user-owned inode. The owner can then unlink and recreate the pathname while the daemon
still holds the old inode, allowing another process to lock the replacement inode. Two real-sleep
authorities can then exist under the same pathname.

**Disposition:** Persistent enabled deployment is blocked until production uses an
installer-created root-owned lease file inside a root-owned non-user-writable directory, validates
owner/mode/type/link count, and has regression coverage for unlink/replacement and unsafe-owner
cases.

### P0 — No production command may intentionally leave the service enabled

`set_enabled_mode` is internal. The only enabled entry points are Task 13 acceptance commands, and
their cleanup traps deliberately restore `disabled`. This was correct for bounded acceptance but
cannot represent the requested final state.

Adding a raw public `enable` command would bypass dry-run evidence, enabled acceptance,
recovery-resleep acceptance, installed artifact integrity, and explicit final approval.

**Disposition:** Add a deployment-specific acceptance record and a final `activate` gate. The
acceptance commands must remain fail-safe and return to `disabled`; only `activate`, after all
required evidence matches the current package identity, may leave the service `enabled`.

### P1 — Production runtime still honors an acceptance-only environment override

The production composition checks `MLM_SLEEP_OPERATION=injected-failure`. The Task 13 script
temporarily writes this value into the managed launchd plist. The acceptance command removes it,
and prior evidence confirmed removal, but a long-term production executable should not contain an
undocumented environment-controlled requester substitution.

**Disposition:** Remove the environment override from the deployable production composition.
Sleep-failure behavior remains covered through dependency-injected tests and historical Task 13
evidence; any future real-system injection must use a separately governed non-production artifact.

### P1 — Installed package integrity is incomplete

The manifest contains only `BinarySHA256`. It does not checksum the launchd plist or config
template. `verify_managed_set` checks only the binary. The runtime does not read or verify the
manifest despite the original design startup sequence requiring package validation. Mode-changing
functions do not call a complete installed-set verifier.

**Disposition:** Extend manifest and installed-set validation to cover binary, launchd plist, and
the normalized config policy. Every bootstrap, dry-run transition, acceptance operation,
activation, upgrade, rollback, status, and reboot finish must verify the current installed identity.

### P1 — Operational health/status contract is not connected to the running daemon

`DaemonHealth` exists only as a tested standalone value. The production application does not own
or publish it. `status` prints raw `launchctl` output, while `diagnostics` reports only mode,
manifest version, current binary checksum, process count, and log sizes. The required operational
baseline cannot currently report expected-vs-actual checksums, crash-budget state, authority
metadata, stable health, CPU, memory, or deterministic path permissions.

**Disposition:** Provide stable machine-readable `status`, expanded redacted `diagnostics`, and an
`operational-baseline` command. Connect runtime events to a bounded health snapshot or equivalent
stable derived health evidence.

### P1 — Enabled upgrade and rollback semantics are ambiguous

Upgrade stages the disabled config template, but rollback restores the previous config verbatim.
Once a persistent deployment exists, an explicit rollback slot may contain `enabled`; a later
rollback can therefore reactivate real sleep without repeating the deployment approval gate.

**Disposition:** Package changes must force a safe disabled state and invalidate deployment
acceptance. Explicit rollback must restore artifacts in `disabled`; reactivation requires the
deployment gate. Automatic rollback may restore only an exact previously accepted artifact set,
and must still fail safe if acceptance identity cannot be proven.

### P1 — Online log rotation does not preserve the active inode

`rotate_one_log` renames the active log to `.1` and creates a new file. launchd and the running
daemon retain the old open file descriptor, so subsequent output continues into `.1`. The newly
created primary log remains empty and the archived file can continue growing.

**Disposition:** Use copy-and-truncate or another inode-preserving strategy while the daemon is
running. Verify that post-rotation events reach the primary log and that generation/permission
bounds remain correct.

### P1 — Required long-term operator runbook is absent

The previous Plan listed `docs/operations/production-daemon.md`, but no `docs/operations`
document exists in the repository. README command snippets are not a complete status,
diagnostics, disable, crash-budget recovery, upgrade, rollback, and uninstall runbook.

**Disposition:** Milestone 16 must create and validate the dedicated runbook before activation.

### P2 — “Exact hardware profile” currently means exact HID identity, not exact Mac model

The registry matches vendor/product/usage/transport and report contract. It does not include the
Mac model identifier. The deployment target is currently `MacBookPro18,1` with Apple M1 Pro.

**Disposition:** Keep HID identity as runtime authorization, but deployment evidence must also
record and compare `MacBookPro18,1`. Do not store serial number, hardware UUID, provisioning UDID,
or other unnecessary device identifiers.

### P2 — Managed directory and state-file permissions need deterministic verification

Installation changes ownership but does not explicitly set every support/log directory mode.
Crash-budget state creation relies on default file-creation behavior. Prior acceptance observed a
safe system, but long-term deployment needs deterministic owner/mode checks rather than umask
assumptions.

**Disposition:** Specify and test exact modes for support, logs, lock, acceptance state,
crash-budget state, manifest, config, binary, and plist.

## 5. Considered approaches

### Approach A — Manual deployment runbook only

Install disabled, run existing dry-run and Task 13 commands, then edit the config to enabled and
bootstrap manually.

**Rejected:** It bypasses a durable approval gate, does not correct the authority inode issue,
does not prove installed-set integrity, and cannot produce the required operational baseline.

### Approach B — Expose the existing internal `set_enabled_mode`

Add an `enable` command and reuse the previous acceptance commands.

**Rejected:** It creates a permanent unsafe shortcut. The command has no acceptance-state binding,
complete checksum verification, model binding, or long-term reboot/operations closure.

### Approach C — Dedicated deployment lifecycle with evidence-bound activation

Harden shared safety primitives first; install disabled; perform fresh deployment dry-run and
bounded real-sleep acceptance; record evidence against the exact installed identity; activate only
after explicit approval; verify enabled boot/pre-login operation; capture an operational baseline;
and leave the system installed, loaded, enabled, and running.

**Recommended:** This preserves the accepted fail-open design while creating a deliberate,
auditable distinction between temporary acceptance and permanent operation.

## 6. Audit decision

Milestone 16 is justified and must include implementation work before system deployment.
Installation or activation from the current `e2b8afe` baseline is **not approved**. The accompanying
Spec must close every P0/P1 design finding before an implementation Plan may be written.

