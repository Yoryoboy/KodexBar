# Provider Data Runtime

## Goal
Restore mixed-provider runtime data and remove residual popup height after the spacing checkpoint.

## Tasks
- [x] Trace the configured wrapper output through candidate selection and QML normalization.
- [x] Ensure aggregate Codex, OpenCode Go, DeepSeek balance, reset credits, confidence, and nested pace data reach the UI.
- [x] Constrain the popup to natural content height despite persisted Plasma popup dimensions.
- [x] Verify, deploy, and inspect post-restart runtime behavior.

## Evidence
- The wrapper returns five entries in both shell and systemd user environments: 3 Codex, 1 OpenCode Go, and 1 DeepSeek.
- Sanitized checks confirmed Codex reset credits/confidence, all three OpenCode windows with nested pace, structured DeepSeek credits, and Codex history data.
- `codexbar-multi` detect mode now remains aggregate-only instead of silently falling back to partial `codex/cli` data.
- Nested pace semantics are rendered without exposing internal stage names.
- The active KodexBar applet's persisted popup geometry keys were removed; other applets retain their own geometry.
- Installed `main.qml` byte-matches source, Plasma is active, recent logs are clean, `git diff --check` passed, and exactly one refresh icon remains.
- Native review was declined; independent verification completed the risk-gated path.
- Runtime/data fix remains uncommitted pending visual confirmation.
