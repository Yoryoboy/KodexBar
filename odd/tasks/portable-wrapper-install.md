# Portable Wrapper Install

## Goal
Make a fresh clone of the fork reproduce the current multi-provider setup with one installation command.

## Tasks
- [x] Add a repository-owned portable `kodexbar-multi` wrapper without hardcoded user paths.
- [x] Add fixture-backed wrapper tests for aggregation, pass-through, and DeepSeek normalization.
- [x] Add an idempotent installer that validates dependencies, installs the wrapper, and installs or updates the Plasma applet.
- [x] Make new installations default to the bundled aggregate command without overriding existing user configuration.
- [x] Document install, update, dependencies, behavior, rollback, and uninstall.
- [x] Verify a staged clean-home installation and repository checks.

## Evidence
- `bash -n bin/kodexbar-multi install.sh tests/test-wrapper.sh` passed.
- `tests/test-wrapper.sh` passed aggregation, partial/all failure, account selection, cost pass-through, DeepSeek normalization/unmatched preservation, and uninstall protection.
- Independent staged install verified fresh install, update, timestamped backup, recognized-wrapper uninstall, unknown-wrapper preservation, mode `0755`, and credential/Plasma-config preservation without touching real user paths.
- Independent re-verification found no blockers or warnings.
- `git diff --check` passed; changed executable files have mode `0755`; no hardcoded `/home/yoryo`, unsafe `eval`, or credential values were found.
- Real installer run upgraded the applet and installed the repository wrapper; installed wrapper and config match repository files.
- Sanitized live wrapper check returned 3 Codex, 1 OpenCode Go, and 1 DeepSeek with structured DeepSeek credits.
- Native review was declined; independent verification completed the risk-gated path.
- Feature remains uncommitted pending user confirmation.
