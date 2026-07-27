# Task 10 System Evidence — Upgrade and Rollback

Date: 2026-07-27

## Controlled acceptance

- Candidate package version: `ffdec68d54e5`.
- Original installed version: `25693f158874`.
- Injected failure occurred after activation.
- Automatic rollback restored the original version and checksum.
- Normal upgrade activated and verified the candidate version/checksum.
- Explicit rollback restored the original version/checksum.
- Final configuration mode is `disabled`.
- Final system LaunchDaemon is loaded and exits cleanly with no resident PID.

## Post-acceptance re-review

- Installed version: `25693f158874`.
- Installed binary checksum equals manifest checksum.
- Rollback slot contains exactly binary, plist, config, and manifest.
- Rollback manifest version is `25693f158874`.
- No GUI-domain duplicate authority exists.
- Production error log is empty.
- Crash-budget state is absent.

## Disposition

Task 10 is approved and complete. The production system remains loaded in `disabled` mode with no
resident process and no sleep authority.
