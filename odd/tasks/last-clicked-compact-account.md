# Keep the last clicked account in the compact panel

## Intent and scope

User confirmed the compact panel should follow the last account/provider card clicked (for example Claude), not an individual limit window. Explicit runtime pinning overrides newer activity while the account stays visible/usable. Popup close/open and refresh/reordering preserve the pin; widget restart resets it. Hidden/removed pins cannot win and clear on entry refresh; unusable pins safely fall back and recover. No fetching or persistent configuration changes.

## Execution

- Route: delegated direct writer; multi-file trigger in `contents/ui/main.qml`, `tests/test-wrapper.sh`, `README.md`.
- TDD: not configured, per repository evidence and prior ODD records. Ordinary checks via `bash tests/test-wrapper.sh`.
- Delivery: `ask-on-risk`; forecast under 250 authored lines, observed 205 (200 additions, 5 deletions). Starting boundary `8d339b0` on clean `main`.
- User explicitly authorized “commit y push to main”. Behavior, tests and README committed on `main` as `9f8f0a0a8cdfd37f8bc722b1512030be22295157` (`fix(ui): keep the last clicked account in the compact panel`).
- Pre-delivery `git fetch origin main`: local/remote divergence `0 0`. Fresh verifier reran `bash tests/test-wrapper.sh` and `git diff --check`: both exit 0, no blockers.
- Push target: `origin/main` only; no upstream mutation or force push authorized.

## Tasks

- [x] **LC-1 — Implement, document and verify explicit compact account selection**
  - Added runtime `pinnedEntryKey`, `clickEntry()`, `pinnedEntry()`, `clearMissingPin()`, compact priority and actual card click wiring.
  - Seven offscreen QML regression cases and structural wiring guards; README documents lifecycle/fallbacks.
  - Writer `deepseek-v4-flash`, effort not exposed; independent verifier found no functional blocker.
  - `bash tests/test-wrapper.sh` and `git diff --check`: passed in writer and independent spot check; helper suites executed without fallback warning. Writer reported 25 display tests; verifier output suppresses counts.
  - Regressions cover manual override identity/percentages, subsequent clicks, no-click activity default, refresh/reordering, hidden/removed and unusable recovery. Exact Claude/OpenCode pair not a fixture; provider-independent logic covers it.
  - Native review `review-961e5b97ca5553ef`: high tier, four lenses, approved; exact acknowledgement burned authority for target `sha256:31af22f88d2c221900b38a3de82653e0b9f551495cf4acdc8a596fce17c13402`.
  - Non-blocking advisories R2-001, R2-002, R2-003, R3-001 retained for separate follow-up, not scope authorization. Initial assessment unavailable due to undeclared task file; native inspect excluded bookkeeping-only untracked file, independent checks executed.
- [x] **LC-2 — Install and reload the reviewed widget**
  - User authorized install with “hazlo”; delegated existing `./install.sh`: upgrade exit 0.
  - Package-show and installed/source QML `cmp`: exit 0; installed `~/.local/share/plasma/plasmoids/org.kde.plasma.kodexbar/contents/ui/main.qml` byte-identical with new pin wiring.
  - `/usr/lib/qt6/bin/qmllint contents/ui/main.qml`: explicit exit 0, unqualified-access warnings only; independent baseline comparison not performed.
  - User then reported old behavior and requested reload. Read-only DBus probe did not establish safe applet-only reload.
  - User explicitly selected “Reiniciar Plasma” after being informed all panels/desktop disappear briefly while applications remain open.
  - `systemctl --user restart plasma-plasmashell.service`: successful; active/running, MainPID changed from 1733 to 108856. No configuration edits or source mutations during deployment/reload.

## Limits and rollback

Installed bytes and service restart are verified. User confirmed the live post-restart selection behavior with “listo funciona bien”; no automated full-shell interaction test was performed. Rollback surface is pin state/helpers/priority, card wiring and entry-refresh hook in main.qml plus associated tests/docs. No new native review needed for unchanged source.

## Next step

Behavior is complete, user-validated and committed. Push the behavior commit and this passive progress record to `origin/main` with an ordinary fast-forward push; verify the remote commit identity afterward.
