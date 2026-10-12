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

- [ ] **RR-1 — All-hidden empty state with settings shortcut**
- [ ] **RR-2 — Bound each wrapper provider query with a timeout**
- [ ] **RR-3 — Refresh guard, watchdog, error backoff, keep last good data**
- [ ] **RR-4 — Carry forward missing entries as stale; refresh indicator; footer wording**
