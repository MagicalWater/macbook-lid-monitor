# Managed Sleep-Authority Remediation

Date: 2026-07-28

## Incident

The first Task 18 enabled-once attempt never reached lid-angle monitoring. The installed daemon
started in enabled mode, emitted `sleep-authority-unavailable`, entered degraded fail-open state,
and exited. Cleanup restored loaded/disabled/zero PID. No sensor-driven sleep occurred.

## Root cause

The managed lease path declared by the manifest was absent:

```text
/Library/Application Support/MacBookLidMonitor/sleep-authority.lock
```

The daemon intentionally does not create this authority file. The Plan assigns creation to
installation, but the shell install implementation omitted it and the Task 16 review incorrectly
accepted `lease_state=missing`.

## Repository remediation

- Install creates an empty regular managed lease with mode `0600` and link count 1.
- Production ownership is `root:wheel`; sandbox tests use the sandbox expected owner/group.
- Existing safe lease inodes are preserved.
- Unsafe existing files, symlinks, metadata, or hard links are rejected.
- Legacy identity-equal upgrade repairs a missing lease before returning no-op.
- A payload-identical package with a newer valid Version/SourceCommit is not treated as a full
  identity no-op: the staged manifest is installed transactionally and prior acceptance is
  invalidated.
- Staged upgrade and rollback ensure the same lease contract.
- Uninstall removes the lease as a managed artifact.

## Verification

```text
install regression RED: file missing
install regression GREEN: passed
legacy no-op upgrade repair RED: file missing
legacy no-op upgrade repair GREEN: passed
provenance-only upgrade RED: old manifest and acceptance were preserved
provenance-only upgrade GREEN: staged Version/SourceCommit installed; acceptance invalidated
root package verification RED: Git rejected repository ownership under privileged upgrade
root package verification GREEN: repository trust scoped to each provenance command only
management suite: 84 tests, 0 failures
full suite: 269 tests, 0 failures
```

## Deployment gate

The repository fix does not close the incident by itself. Closure requires:

1. Commit the reviewed remediation.
2. Prepare and verify a package from that exact commit.
3. Upgrade the real installation while disabled.
4. Verify the lease is root-owned, `0600`, regular, link count 1, and not held.
5. Verify loaded/disabled/zero PID and valid installed identity.
6. Rerun Task 17 against the new identity before Task 18.

## Privileged provenance follow-up

The first real provenance-only upgrade was rejected before mutation because root Git did not trust
the user-owned checkout. The fix uses `git -c safe.directory="$REPO_ROOT"` only on the package
version and source-commit reads. It does not modify global or system Git configuration. The failed
attempt left the old installed manifest, partial acceptance, secure lease, disabled mode, and zero
resident PID unchanged.
