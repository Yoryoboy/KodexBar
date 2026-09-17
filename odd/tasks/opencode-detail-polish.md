# OpenCode Detail Polish

## Goal
Improve only the OpenCode/OpenCode Go detail panels so titles, percentages, and reset times remain readable in three columns.

## Tasks
- [x] Give OpenCode usage panels a compact vertical hierarchy suited to three columns.
- [x] Preserve Codex, DeepSeek, cards, provider data, and popup sizing unchanged.
- [x] Verify, deploy, and inspect runtime logs.

## Evidence
- The OpenCode-specific branch renders full title, used percentage, progress, and muted reset text vertically.
- Provider detection lives on the outer usage grid, before row-model shadowing.
- Independent verification confirmed Codex retains its prior horizontal layout and no other subsystem changed.
- `git diff --check` passed.
- Installed source byte-matches the repository, Plasma is active, and post-restart logs contain no KodexBar/QML errors.
- Native review was declined; independent verification completed the risk-gated path.
- Visual confirmation at the live popup width remains recommended before commit.
