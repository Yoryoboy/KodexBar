# Hide accounts from the widget without code changes

## Intent and scope

User cancelled one Codex account and wants to hide it (and any future dead account) from the widget without editing source code. Hiding is a persistent, display-only widget preference: the wrapper still queries and returns every entry. Accounts are hidden from a right-click action on their popup card and restored from widget settings. No automatic hiding of failing accounts (a transient error must never hide a working account).

## Design

- Persistent setting `hiddenAccounts` (StringList) in `contents/config/main.xml`.
- Stable hide key per card: `provider|account` (lowercased provider), independent of source and payload order.
- `visibleEntries()` drops user-hidden entries in both aggregate and explicit provider views; pin/selection already fall back when a card disappears.
- Card right-click opens a menu with "Hide account"; left click keeps the existing pin behavior.
- Settings page lists hidden accounts with a per-account "Show" action.

## Execution

- Branch: `feat/hide-accounts` from `main` at `88f0119`.
- Route: delegated writer (multi-file trigger: `main.xml`, `main.qml`, `configGeneral.qml`, `tests/test-wrapper.sh`, `README.md`); independent verifier for checks.
- Tests: `bash tests/test-wrapper.sh` extracts pure `main.qml` functions into offscreen qmltestrunner cases; hide logic is test-first through those cases.

## Tasks

- [x] **HA-1 — Persistent hidden-accounts setting and filtering logic**
  - `hiddenAccounts` entry, `hiddenAccountKey()`, `isHiddenEntry()`, list helpers, `visibleEntries()` filtering; RED/GREEN qmltest cases.
- [x] **HA-2 — "Hide account" action on popup cards**
  - Right-click menu on each card writes the key to `Plasmoid.configuration.hiddenAccounts`; left click unchanged.
- [x] **HA-3 — Restore hidden accounts from settings, document**
  - Settings list with per-account "Show"; README Settings/Usage docs.

## Evidence

- Writer (`gentle-ai-worker`) implemented HA-1 → HA-3 in order, test-first. RED: HA-1 seven qmltest failures (helpers undefined, hidden entries still visible, stale pin); HA-2/HA-3 structural asserts failed before wiring. GREEN: `bash tests/test-wrapper.sh` exit 0 after each task.
- Deviation: the writer does not commit, so HA-1..HA-3 share one work-unit commit `7d398f6` (`feat(ui): hide user-selected accounts from the popup`); splitting interleaved hunks in `main.qml` and tests would be artificial.
- Independent verifier: `bash tests/test-wrapper.sh` exit 0 (qmltestrunner ran, no fallback), `git diff --check` exit 0, `qmllint` exit 0 with only `[unqualified]` warnings (no new categories). Menu/settings wiring inspected: left click pins, right click only opens menu; Show assigns a new array.
- Not verified: live Plasma interaction (context menu, settings restore). Requires install + plasmashell reload, user-authorized.

- Native review `review-49170ab6be060824`: high tier, four lenses, approved; acknowledgement burned authority for target `sha256:59e9ce5bf4bf80d68e1b2bc503a1ac20ffcf6b6bb6f9d7d7ff2cd62222173f97`. Non-blocking advisory R3-001 (reliability, `tests/test-wrapper.sh:554-562`) kept as separate follow-up.

## Next step

Install (`./install.sh`) and reload Plasma to validate live; push/merge remain the user's decision.
