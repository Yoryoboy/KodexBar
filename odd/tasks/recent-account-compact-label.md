# Recent Account Compact Label

## Objective

Show a reduced Plasma panel label for the most recently active local Codex or single OpenCode Go account, including both the rolling 5-hour and weekly used percentages.

## Problem

The compact panel currently follows the selected/first usable entry, displays only the primary percentage, and can show an unlabeled zero-credit value. The upstream quota payloads do not identify the most recently used account, while both Codex and OpenCode keep sufficient timestamp metadata locally.

## Why

A compact `A# · 46% / 31%` label makes the active account and both meaningful quota windows visible without account rotation or expanding the panel.

## Scope

- Add best-effort local activity metadata to bundled wrapper entries.
- Attribute Codex activity per account from its scoped local Codex home.
- Attribute one OpenCode Go account from its local SQLite session metadata.
- Select the newest usable entry in the compact representation.
- Render a stable reduced account/provider label plus 5-hour and weekly used percentages.
- Preserve existing popup account selection and detail behavior.
- Document local-only attribution, privacy boundaries, and fallbacks.

## Constraints

- Support only one OpenCode Go account for activity attribution.
- Never read, emit, or display prompt/message content, project names, session titles, credentials, or local paths.
- Activity enrichment is best-effort and must never break quota aggregation.
- Missing or ambiguous activity must fall back to the existing selected/first-usable behavior.
- Codex account numbering must remain deterministic and independent of activity order.
- Technical artifacts remain in English.
- No commit will be created until the user explicitly authorizes committing.

## Delivery Strategy

- Strategy: `ask-on-risk`
- Forecast: below 400 authored changed lines.
- Route: delegated direct writer; multi-file write trigger fired (`bin/kodexbar-multi`, `tests/test-wrapper.sh`, `contents/ui/main.qml`, `README.md`).
- TDD mode: not configured; use focused fixture-based functional checks and structural QML checks.

## Tasks

- [x] **RA-1 — Enrich wrapper activity metadata**
  - Added safe automatic Codex per-account discovery plus explicit mapping overrides.
  - Added exactly-one-entry OpenCode Go SQLite activity attribution.
  - Added fixture-driven success, ambiguity, mixed-config, and graceful-fallback coverage.
  - Checks: `bash -n bin/kodexbar-multi` passed; `bash tests/test-wrapper.sh` passed.

- [x] **RA-2 — Render the most recently active compact entry**
  - Normalized activity metadata in QML.
  - Selected the newest usable activity entry with the existing behavior as fallback.
  - Rendered deterministic identity plus 5-hour and weekly used percentages while preserving compact settings.
  - Preserved popup selection semantics and suppressed unavailable/zero credits.
  - Checks: structural verification passed; `git diff --check` passed; `qmllint` unavailable.

- [x] **RA-3 — Document and verify the behavior**
  - Documented local sources, single-account OpenCode limitation, fallbacks, and privacy boundary.
  - Independent verification passed after two bounded correction rounds.
  - Native review consent was declined for this candidate; no lineage was created.
  - Commit identity pending explicit user authorization.

## Acceptance Criteria

- A Codex entry can carry a per-account local last-activity timestamp without exposing session content.
- The single OpenCode Go entry can carry its latest local session timestamp from SQLite.
- Missing SQLite, missing Codex logs, schema differences, or ambiguous account attribution do not fail usage output.
- The compact panel selects the newest usable timestamp and otherwise keeps the prior fallback.
- The reduced label displays deterministic account/provider identity and both 5-hour and weekly used percentages when available.
- The popup remains manually selectable and behaviorally unchanged.
- Focused tests pass and documentation matches the implementation.

## Progress and Evidence

- Exploration confirmed OpenCode stores session timestamps, provider/model, and token totals in `~/.local/share/opencode/opencode.db` without requiring message content reads.
- The current upstream quota payload `usage.updatedAt` is query time, not last activity, and is not used for recency.
- `bash -n bin/kodexbar-multi`: passed.
- `bash tests/test-wrapper.sh`: passed (`test-wrapper.sh: all tests passed`; expected temporary-wrapper warning only).
- `git diff --check`: passed.
- Independent verification: PASS; no blockers. `qmllint` remains unavailable.
- Native review: candidate-scoped consent declined; no lineage or receipt created.
- Work-unit commit: `231772a` (`feat: show most recently active usage account`), pushed to `origin/main`.

## Next Step

Monitor runtime account switching; if Codex activity remains unattributed, diagnose its scoped home identity mapping in a follow-up work unit.
