# NaN Cloud quota from local Chrome

## Objective
Show NaN per-model quota in KodexBar using the user's existing Chrome session, without another login or exposing session secrets.

## Scope and constraints
- Worktree: `/home/yoryo/apps/KodexBar-nan-cloud-quota`, branch `feature/nan-cloud-quota`; do not modify the main or sibling worktrees.
- Linux Google Chrome Default profile and unlocked KDE KWallet are the verified starting environment. Fail closed for absent, expired, inaccessible, or differently encrypted cookies; preserve existing NaN CLI fallback.
- Read only the `.nan.builders` `nan_session` record from Chrome's cookie DB and `Chrome Safe Storage` from KWallet. Keep the decrypted cookie and key in process memory; never print, persist, place in argv/environment, or include in diagnostics. Restrict outbound requests to the fixed HTTPS NaN quota endpoint, with bounded timeout and sanitized errors. No DevTools or browser extension required.
- TDD: not configured in existing feature records. Ordinary focused functional checks via `bash tests/test-wrapper.sh` and helper unit tests; QML lint when QML changes. No live cookie values in tests.
- Delivery strategy: ask-on-risk, user selected `stacked-to-main` on review-size risk. Forecast revised from ~300 to >1000 authored changed lines after T1; T1 reader and T2 widget integration are separate review slices/commits. User expressly accepted `size:exception` for T1's 1053 authored lines (396 helper, 637 tests, 20 task record), keeping the behavior and tests together. Every completed task closes with a work-unit commit. No push/PR without user instruction.

## Evidence and tasks
- Live read-only probe: Chrome Default cookie metadata `.nan.builders` / `nan_session` (`v11`, HttpOnly, Secure); `Chrome Keys` / `Chrome Safe Storage` in `kdewallet`. In-memory KWallet decryption plus fixed-endpoint HTTP GET with dashboard-origin headers returned HTTP 200 and six models. Bare GET returned 403. No cookie values emitted or stored.
- [x] T1 — Add a narrowly scoped local quota helper with deterministic mocked tests. Route: delegated direct writer (new helper + tests); initial hyphenated Python test path prevented unittest discovery, parent corrected it to `tests/test_nan_cloud_quota.py`. Independent verifier: 51 mocked tests passed, py_compile passed, sanitized live helper exited 0 and returned six models with expected fields and no stderr. Security readback found extra-field/non-finite risks; writer whitelisted schema and reran checks. Rollback boundary: `bin/nan-cloud-quota`, `tests/test_nan_cloud_quota.py`, this T1 record. Commit identity: pending this commit. Review slice 1.
- [ ] T2 — Prefer cloud quota in NaN aggregate and render per-model quota in popup, retaining CLI fallback. Route: delegated direct writer (wrapper, UI, tests, README, installer if necessary). Check: wrapper regression suite, helper tests, QML lint, runtime aggregate boundary. Commit identity: pending. Review slice 2 stacked on slice 1.

## Progress
- Current: T1 implementation and checks complete; commit pending. Next: close T1 commit and native risk assessment, then T2.
- Review outcomes: pending. Failed/skipped checks: none after correcting initial unittest-discovery path. Running authored line count: pending committed count.
