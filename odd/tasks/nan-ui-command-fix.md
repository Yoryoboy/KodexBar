# NaN UI command fix

## Goal and evidence
Restore all providers and enable NaN in the live widget. The previous configuration change exposed a QML bug: candidateList recognizes legacy codexbar-multi but not bundled kodexbar-multi; it discards the aggregate candidate and stops on usable Codex data. The live command has been rolled back to the legacy wrapper pending this fix.

## Scope and constraints
- Accept both exact wrapper basenames in contents/ui/main.qml.
- Add a focused regression in tests/test-wrapper.sh; preserve upstream CLI fallback.
- Deploy only after checks; verify configured command, not a different executable.
- No commits, pushes, or unrelated refactors without explicit user authorization.
- TDD: not configured (existing project feature records); ordinary functional checks.
- Checks: bash -n bin/kodexbar-multi install.sh tests/test-wrapper.sh; bash tests/test-wrapper.sh; /usr/lib/qt6/bin/qmllint contents/ui/main.qml.
- Route: delegated writer (QML + regression test); delegated deployment/verification. RDD enabled, candidate review before completion.
- Forecast: under 60 authored source/test lines; delivery strategy ask-on-risk.

## Tasks
- [x] T1: Correct aggregate-name detection and add regression coverage. Checks passed; native review approved and acknowledged.
- [ ] T2 (paused): Corrected QML deployed and runtime wrapper verified; Plasma reload, bundled command selection, and visual confirmation remain pending.

## Evidence and next step
Writer changed contents/ui/main.qml (+3/-1) and tests/test-wrapper.sh (+72). Bash syntax, full wrapper suite with behavioral qmltestrunner tests, and qmllint passed (unqualified-access warnings remain). Negative control with old condition fails: 31 candidates versus expected 1. Native review review-2ede3a7ce02c3753 approved all four lenses and acknowledgement burned authority; five informational findings about test heredoc and structural fallback remain separate follow-ups. First consent expired with no lineage; fresh consent succeeded. User authorized preserving this fix in a commit at session close (no push). Deployment via bash install.sh succeeded; independent wrapper tests and installed-QML cmp passed. Runtime aggregate returned six entries (3 Codex, OpenCode Go, DeepSeek, NaN) both normally and with the plasmashell environment. Verifier incorrectly described the legitimate nan provider identifier as an anomaly; it is the intended provider key, not numeric NaN. Live widget remains configured to legacy codexbar-multi after rollback. User deferred further work; next session reload Plasma with authorization, select kodexbar-multi, then confirm UI visually. Commit identity is recorded in the session memory after committing.
