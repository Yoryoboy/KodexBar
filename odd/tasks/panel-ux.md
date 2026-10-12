# Panel UX: tooltip, usage colour, mouse shortcuts, accessibility

## Intent and scope

User approved items 4–7 of the UI/UX sweep after the refresh-reliability work:

4. Compact tooltip with real context (account, per-window usage and reset, freshness).
5. Compact label coloured by usage with configurable warning/critical thresholds (reused later by notifications).
6. Mouse shortcuts on the panel: middle-click refreshes, wheel cycles accounts.
7. Accessibility and keyboard: accessible names, keyboard activation of the panel, card focus/selection/menu from the keyboard.

Non-goals: notifications (next PR), aliases, provider list unification.

## Design

- Thresholds: `warningUsedPercent` (default 80) and `criticalUsedPercent` (default 95), plus `colorPanelByUsage` (default true). Level = highest used % among the compact entry's windows; warning → `neutralTextColor`, critical → `negativeTextColor`; unknown/error → default colour.
- Tooltip: main text = provider + account (respects `showEmailInWidget`? no — tooltip is on hover, shows email); sub text = one line per window (`<title>: <used>% used · resets <when>`), stale/cached note, `Checked <time>` / refreshing / error banner.
- Middle-click → explicit refresh. Wheel → pin next/previous visible usable account (accumulate angleDelta to 120 per step, wrap around).
- Accessibility: compact `Accessible.role/name/description`, Enter/Space toggles popup; cards focusable with Tab/arrow-free simple Tab order, Enter/Space select+pin, Menu key / Shift+F10 opens the hide menu, visible focus border; Refresh button has a tooltip and accessible name.

## Execution

- Branch: `feat/panel-ux` stacked on `feat/refresh-reliability` (`835f636`, not yet merged).
- Route: delegated writer per task; parent commits each task; independent verifier; native review.
- Tests: `bash tests/test-wrapper.sh` (offscreen qmltestrunner on extracted pure functions + structural asserts); test-first.

## Tasks

- [x] **PX-1 — Usage thresholds setting and coloured compact label** — `619cb02`
  - `colorPanelByUsage`/`warningUsedPercent`/`criticalUsedPercent`; `maxUsedPercent`, `usageLevel`, `compactLabelColor`; stale keeps last-known colour; inverted critical raised to warning. RED 11 qmltests; GREEN.
- [x] **PX-2 — Informative compact tooltip** — `b8f4d3d`
  - Main text provider + account (email shown on hover regardless of popup setting); per-window used + reset, stale/cached, errors, refresh state. RED 5 qmltests; GREEN. Countdown text updates on re-evaluation (refresh), not every second.
- [x] **PX-3 — Middle-click refresh and wheel account cycling** — `0a9c3b1`
  - Middle-click refresh guarded while loading; `cycledEntryKey` with wrap, 120-unit steps, reversal resets; positive wheel = next. RED (helper missing); GREEN 9 cases.
- [x] **PX-4 — Accessible names and keyboard navigation** — `3323698`
  - Compact button role/name/description/press action, Enter/Space; cards Tab-focusable, focus border, Enter/Space pin, Menu/Shift+F10 menu; Refresh tooltip/name. Arrow keys skipped. RED (`cardAccessibleName` missing); GREEN.

## Evidence

- Independent verifier: `bash tests/test-wrapper.sh` exit 0 (qmltestrunner ran), `git diff --check 835f636..HEAD` exit 0, `qmllint` only `[unqualified]`, `xmllint` valid, all 14 cfg_ settings match `main.xml`; Keys handlers accept only handled events (Tab untouched); ids in scope; no obvious binding loops.
- Not verified: live Plasma hover/keyboard/screen-reader behaviour.
