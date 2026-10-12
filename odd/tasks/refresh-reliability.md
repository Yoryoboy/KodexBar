# Refresh reliability and visible data freshness

## Intent and scope

User approved items 1–3 of the UI/UX sweep as one reliability PR:

1. All-hidden empty state: when every account is hidden, explain it and offer a settings shortcut instead of a blank popup.
2. Robust refresh: no overlapping refreshes, bounded provider queries, error backoff, and a failed refresh never wipes the last good data.
3. Visible state: refresh-in-progress indicator while data is shown, entries missing from a refresh (partial provider failure) kept and marked as not updated, and honest footer wording for fetch time.

Non-goals: notifications, tooltip/colour/shortcut UX (later PRs), provider list unification, changing the aggregate JSON contract.

## Design

- Empty state derives from `visibleEntries()`, distinguishing "no data" from "all hidden"; the shortcut triggers Plasma's configure action.
- Wrapper bounds each upstream provider query with `timeout` when available (`KODEXBAR_PROVIDER_TIMEOUT`, default 60 s, `0` disables); a timed-out provider is omitted like any failed provider.
- UI: timer refreshes skip while a refresh is running; explicit/config refreshes restart. A watchdog aborts a refresh that exceeds a bound. Consecutive failures back off the timer interval (×2, ×4, ×8, capped at 30 min, never below the configured interval) and reset on success. A failed refresh keeps previous entries and shows the error as a banner.
- Carry-forward: an entry present in the previous successful refresh but missing now is kept, flagged stale with its last-updated time, until it reappears, is hidden, or is older than 24 h. Configuration changes clear carry-forward.

## Execution

- Branch: `feat/refresh-reliability` from `main` at `4efde5d`.
- Route: delegated writer per task (`main.qml` + tests + wrapper + README); parent commits each task; independent verifier.
- Tests: `bash tests/test-wrapper.sh` (offscreen qmltestrunner on extracted pure functions, fake-upstream wrapper cases); test-first.

## Tasks

- [x] **RR-1 — All-hidden empty state with settings shortcut** — `8749d64`
  - `allEntriesHidden()`; display checks use `visibleEntries()`; "All accounts are hidden." + configure-action shortcut. RED: 3 qmltests (`allEntriesHidden is not defined`); GREEN suite exit 0.
- [x] **RR-2 — Bound each wrapper provider query with a timeout** — `0216a32`
  - `run_bounded` via `timeout --kill-after=5`, `KODEXBAR_PROVIDER_TIMEOUT` (60 s default, 0 disables, invalid → 60); aggregate upstream, Codex identity and NaN calls; passthrough unbounded. RED: unbounded 8 s query; GREEN exit 0. Suite runtime +~9 s.
- [x] **RR-3 — Refresh guard, watchdog, error backoff, keep last good data** — `55b3a73`
  - Periodic `refresh(false)` skips while loading; 5-min watchdog; backoff ×2/×4/×8 capped 1800 s; failed refresh keeps usable cards with error banner above. Behavior change: an unusable last-candidate result is now a failed refresh. RED: backoff/guard functions undefined; GREEN exit 0.
- [x] **RR-4 — Carry forward missing entries as stale; refresh indicator; footer wording** — `7d785b4`
  - `carryForwardEntries()` with `fetchedAt`/`staleSince`, 24 h bound; dimmed "Not updated since" cards; compact prefers fresh; BusyIndicator; footer "Checked %1" + not-updated provider count; config changes clear entries. Known trade-off: an account removed from codexbar config lingers as stale up to 24 h. RED: carry-forward/compact tests; GREEN exit 0.

## Evidence

- Independent verifier: qmltestrunner ran (no fallback); `qmllint` only pre-existing `[unqualified]` categories; structural inspection found no terminal path leaving `loading` true. Parent re-run: `bash tests/test-wrapper.sh` exit 0 (18 s), `git diff --check 4efde5d..HEAD` exit 0, `bash -n bin/kodexbar-multi` exit 0.
- Not verified: live Plasma behaviour (stale cards, banner, spinner, configure shortcut). Late-result guard has no generation id (non-blocking).
