# Card Order and Popup Width

## Goal
Two presentation fixes requested by the user after the NaN provider landed:
1. Move the NaN account card so it is the 4th card, right after the three Codex accounts and before OpenCode Go and DeepSeek.
2. Stop the horizontal scrollbar in the popup: size the popup width to the account-card row so every card fits.

## Acceptance criteria
- A no-provider `kodexbar-multi usage` aggregate orders entries exactly: `codex` (all accounts), `nan`, `opencode`, `deepseek`. Order is a tested, documented wrapper contract.
- The popup opens wide enough to show every account card without a horizontal scrollbar for the current provider set (6 cards).
- A width floor keeps the selected-detail pane readable when there are few cards, and a width ceiling keeps the popup on-screen; the horizontal scrollbar is never rendered.
- The card viewport preserves the full shared card height without the scrollbar consuming or covering the last row.
- Changing the entry count re-evaluates the popup width (reactive binding), in both grow and shrink directions.
- No regression to the existing height behaviour documented in `dynamic-popup-resize.md`.
- `bash tests/test-wrapper.sh` and `qmllint contents/ui/main.qml` both pass.

## Non-goals
- No change to the NaN card's content (windows, token rows, allTime, freshness) — explicitly deferred by the user.
- No vertical-layout or card-wrapping redesign; the card row stays horizontal.
- No change to the wrapper's provider set or its retry behaviour.
- No `popupWidth`/`popupHeight` edits in `appletsrc` by hand.

## Design notes
- Ordering is implemented in the wrapper, not the QML: the aggregate array already carries a deliberate provider priority and the wrapper has the only automated test suite. The QML renders in array order and is untested, so adding a sort there would add untested logic. Moving `run_provider nan` before the OpenCode/DeepSeek calls is the minimal change; wall-clock refresh time is unchanged because NaN's single retry sleep is already unconditional on failure.
- Width: extract the inline card width (`Kirigami.Units.gridUnit * 6.2`) into a readonly property, derive the row width from `entries.length`, and drive `Layout.minimumWidth`/`preferredWidth` (and a maximum) from it, mirroring the existing `naturalPopupHeight` pattern. Keep a floor equal to the current `gridUnit * 30` minimum so the detail pane stays readable. The live screenshot showed that an `AsNeeded` horizontal scrollbar can still appear from fractional rounding and consume the bottom of the fixed-height viewport, so its visual policy is `AlwaysOff`; pointer/touch scrolling remains available if an extreme provider set overflows.

## Tasks
- [x] Reorder the aggregate so NaN is the 4th entry: move the `nan` provider run before OpenCode Go and DeepSeek in `bin/kodexbar-multi`.
- [x] Add a wrapper test asserting the aggregate provider order end to end.
- [x] Derive the popup width from the account-card row in `contents/ui/main.qml` so no horizontal scrollbar appears.
- [x] Document the aggregate ordering contract in `README.md`.
- [x] Run `bash tests/test-wrapper.sh`, `bash -n bin/kodexbar-multi`, and `/usr/lib/qt6/bin/qmllint contents/ui/main.qml`.
- [x] Deploy with `install.sh` and visually confirm NaN is 4th and all six cards fit.
- [x] Hide the card-row scrollbar so it cannot consume card height or clip the final row.
- [x] Re-run focused verification, deploy, and visually confirm the card contents are fully visible.

## Evidence
- Diff: 4 files, 17 insertions, 5 deletions (`README.md`, `bin/kodexbar-multi`, `contents/ui/main.qml`, `tests/test-wrapper.sh`). Written by a scoped `gentle-ai-worker` that did not commit.
- Real-environment order, repo wrapper, `./bin/kodexbar-multi usage --format json --json-only`:
  1 codex 93jads@gmail.com, 2 codex 93jadsarg@gmail.com, 3 codex 93jadsusa@gmail.com, 4 **nan** 93jads@gmail.com, 5 opencodego, 6 deepseek. NaN is 4th as requested.
- Independent verification (`gentle-ai-verify`, read-only) verdicts: the new assertion is a true exact-sequence check (jq ordered array equality), and it was **falsified**: reverting the nan move in a throwaway copy made the suite fail (exit 1). Fixture produces 2 Codex entries vs 3 in the real environment; the test is self-contained so the real count cannot make it flaky.
- Wrapper change is order-only: `successes` accounting, `outputs` append order, the `jq -s` flatten step, and the nan failure path are unchanged; providers were already sequential, so wall-clock is unchanged.
- QML arithmetic: inner content width equals `cardRowWidth` exactly because the card row's `spacing` matches the `smallSpacing` used in the formula and `anchors.margins: popupMargin` cancels `popupMargin * 2`. For 6 entries `naturalPopupWidth = 37.2g + 5s + 4L`, inside the `[30g, 44g]` clamp, so the AsNeeded scrollbar does not trigger. The card `ScrollView` is the only child of its `RowLayout`, so no sibling width is unaccounted for.
- Static checks: `bash -n bin/kodexbar-multi` exit 0; `bash tests/test-wrapper.sh` "all tests passed"; `/usr/lib/qt6/bin/qmllint contents/ui/main.qml` exit 0; `git diff --check` exit 0.
- qmllint warning count: 252 on HEAD vs 256 on the working tree. The 4 new ones are all `Unqualified access [unqualified]` on the touched lines, the same class as ~250 pre-existing warnings in the file; no error-level diagnostics.
- ASSESS returned `risk: unassessable` (native assess unavailable: Gentle AI v3.4.0 binary missing at the package path), and its plan required an independent verifier, which ran.
- Live screenshot confirmed NaN is 4th and all six cards fit, but also falsified the scrollbar assumption: a horizontal bar appeared and consumed the bottom of the fixed-height card viewport, clipping card content.
- Root cause: `accountCardHeight` correctly uses the maximum row count (OpenCode Go has three rows; NaN does not enlarge it), but the `AsNeeded` scrollbar reduces/overlays the available viewport height. The visual scrollbar must be disabled rather than adding extra card height.
- Known residual risk (low): the exact-order assertion covers only the all-providers-succeed path; the failure-path cases assert membership only. No current code path regresses order under failure.

## Runtime confirmation
- User confirmed the final deployed popup: NaN is fourth, all cards fit, the horizontal scrollbar is gone, and card contents are fully visible.

## Open questions
- None. User authorized commit and push to `origin` after visual confirmation.

## Related
- `odd/tasks/dynamic-popup-resize.md` — height resizing on selection change (same Layout min/preferred/max pattern).
- `odd/tasks/compact-popup-spacing.md` — earlier popup spacing corrections.
- `odd/tasks/nan-provider-support.md` — NaN provider origin and its open popup-visibility issue (now root-caused as a stale widget command name).
