# Breeze Usage Dashboard

## Goal
Redesign the Plasma popup as a compact, provider-aware Breeze-style usage dashboard while preserving the existing CLI integration and panel representation.

## Acceptance criteria
- Horizontal, scrollable account cards show every account/provider and select one detail view.
- Codex, OpenCode/OpenCode Go, and DeepSeek receive provider-aware summaries and details.
- Primary windows use compact progress panels; optional metadata, pace, insights, and extra windows hide when unavailable.
- Account identifiers continue honoring `showEmailInWidget`.
- Exactly one refresh action appears in the footer beside the CLI refresh timestamp.
- The result remains compatible with Plasma 6 QML and uses Kirigami/Breeze theme roles.

## Tasks
- [x] Normalize provider-specific fields needed by the dashboard and add stable account selection.
- [x] Replace the popup with the compact Breeze account selector and selected-account details.
- [x] Verify QML syntax/static behavior and inspect the final diff.
- [x] Deploy the source package to the installed Plasma applet and verify the runtime.

## Evidence
- `git diff --check` passed.
- Independent read-only verification confirmed the provider-aware card/detail hierarchy and exactly one refresh icon.
- Installed `main.qml` byte-matches the repository source by SHA-256.
- `plasma-plasmashell.service` is active with no recent KodexBar/QML syntax, type, or assignment errors.
- `qmllint`/`qmlscene` were unavailable.
- Native RDD review could not start because the provider returned `schema-incompatible`; no lineage was created.
- No commit was created.
