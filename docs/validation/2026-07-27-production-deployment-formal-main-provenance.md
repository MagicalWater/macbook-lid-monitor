# Milestone 16 Task 15 — Formal-main provenance gate

## Scope

This record covers repository integration only. It does not authorize or perform installation,
launchd mutation, real sleep, reboot, or persistent activation.

## Approved release candidate

```text
release-candidate=f16ae1d81a17f8acbe6e09862b2bcec716a18195
base-main=e2b8afeac0bf8f7560d6a9d60b4da328d9650bd3
merge-strategy=fast-forward-only
history-rewrite=false
```

## Independent integration evidence

```text
release-candidate working tree: clean
pre-integration full XCTest: 264 tests, 0 failures
formal main before integration: clean
formal main before integration: equal to origin/main
formal main ahead/behind before integration: 0/0
merged-result full XCTest: 264 tests, 0 failures
```

## Exact release identity rule

The commit containing this document is the formal release commit. After committing this record,
the production package must be prepared and verified from that exact `HEAD`; its manifest
`SourceCommit` must equal that exact full commit hash. Only then may the commit be pushed, followed
by a fresh fetch proving `main == origin/main` and both clean.

## Safety state

```text
/Library installation: not performed
production launchd mutation: not performed
real sleep: not performed
reboot: not performed
persistent activation: not performed
```
