# Dynamic Popup Resize

## Goal
Make the open popup resize correctly when selection changes between providers with different detail heights.

## Tasks
- [x] Propagate selected-detail implicit height changes to the Plasma popup in both shrink and grow directions.
- [ ] Verify switching DeepSeek → Codex/OpenCode no longer clips detail content (visual confirmation required).
- [x] Deploy and inspect runtime logs.

## Evidence
- `Layout.minimumHeight`, `Layout.preferredHeight`, and `Layout.maximumHeight` now track the capped selected-content `naturalPopupHeight`.
- `git diff --check` passed and independent structural verification found no blocker.
- Initial runtime exposed two boolean bindings receiving `undefined`; both were made explicitly boolean-safe.
- Installed source matches the repository, Plasma is active, and the post-restart journal contains no KodexBar/QML assignment, type, or binding-loop errors.
- Native review was declined; independent verification completed the risk-gated path.
