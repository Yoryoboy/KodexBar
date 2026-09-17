# Compact Popup Spacing

## Goal
Correct the deployed popup layout shown in the annotated screenshot.

## Tasks
- [x] Increase account-card content height so labels and percentages never overlap.
- [x] Remove the large blank region between account cards and selected-account details.
- [x] Remove the large blank region above the footer and remove the Settings action.
- [x] Deploy and verify the corrected popup at runtime.

## Evidence
- `git diff --check` passed.
- Independent verification confirmed natural popup sizing, no fill-height detail scroll, no Settings action, and exactly one refresh icon.
- Installed `main.qml` byte-matches the repository source.
- `plasma-plasmashell.service` is active.
- Three old TypeErrors appeared before restart; no KodexBar/QML syntax, type, or assignment errors appeared after restart.
- Native review was declined for this candidate; independent verification completed the risk-gated path.
- The spacing fix remains uncommitted pending visual confirmation.
