# Claude Multi-Account Support

## Objective
Show one Claude card per configured Claude Code account, mirroring the Codex multi-account experience (identity, activity attribution, compact label, pin).

## Evidence and rationale
- Codex multi-account is owned by upstream: `codexProfileHomePaths` in `~/.config/codexbar/config.json` plus `--all-accounts`. The wrapper only attributes local activity (`codex_activity_map`), and QML labels cards `A<n>` (`contents/ui/main.qml:218`).
- Upstream `codexbar` 0.60.4 has no Claude equivalent but honors `CLAUDE_CONFIG_DIR` (verified: an empty dir yields `No available fetch strategy for claude`; the default yields usage).
- The Claude usage payload carries no identity (`account`/`accountEmail` null; `usage.identity` is only `{providerID}`). Identity lives in local `.claude.json` `oauthAccount.emailAddress`/`accountUuid`. For the default dir the file is `~/.claude.json` (outside `~/.claude`); for a custom `CLAUDE_CONFIG_DIR` it is `$dir/.claude.json`.
- `entryKey` is `provider|account|source`, so without an injected account multiple Claude cards would collide and the click pin could not distinguish them.

## Decisions
- Extra dirs come from `KODEXBAR_CLAUDE_CONFIG_DIRS` (semicolon-separated, `~` expanded), mirroring `KODEXBAR_CODEX_ACCOUNT_HOMES`. The default dir (`${CLAUDE_CONFIG_DIR:-~/.claude}`) is always first; with no extras, behavior is unchanged. A widget settings field is deferred.
- Auto-discovery of `~/.claude-*` is rejected (picks up stale/backup dirs).
- Only the email and timestamps are emitted; never credentials, paths, or session contents.

## Scope and constraints
- Branch `feature/claude-multi-account` from `278e781`.
- Test-first with the existing runner `bash tests/test-wrapper.sh` and a stubbed `codexbar`; no live credentials or network in tests.
- Push and PR are not authorized.

## Tasks
- [x] T1 — Wrapper: query each Claude config dir with `CLAUDE_CONFIG_DIR`, inject `account` from that dir's `.claude.json`, dedupe by `accountUuid`, keep failure isolation and aggregate order. Tests + README. Route: delegated `gentle-ai-worker`. RED observed (two-account ordering assertion failed), GREEN `bash tests/test-wrapper.sh` exit 0, `bash -n` and `git diff --check` exit 0. Commit `02231b7` (`feat(claude): query each configured Claude account in aggregate`), 138 changed lines. Native review `review-fa150fa5e70b39b1` approved by four lenses and acknowledged (authority burned). Non-blocking follow-ups: upstream call inside the `while read` loop can consume loop stdin (R3), sequential per-dir latency (R4), dedupe only after querying (R4), readability of the inline loop (R2).
- [ ] T2 — Wrapper: attach per-dir local activity (newest mtime under `$dir/projects`) to each Claude entry. Tests + README.
- [ ] T3 — QML: compact label `C<n>` for Claude accounts in deterministic order; README.

## Progress and verification
