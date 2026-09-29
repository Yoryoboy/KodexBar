# Claude Code Usage in Aggregate Widget

## Objective
Show Claude Code subscription rate-limit windows alongside existing providers in the default KodexBar aggregate, using the already installed upstream CodexBar CLI rather than direct credential access.

## Evidence and rationale
- The current aggregate queries Codex, NaN, OpenCode Go, and DeepSeek, but not Claude (`bin/kodexbar-multi`). The QML already supports `usage.primary` and `usage.secondary` with percentage and reset information.
- A sanitized local probe of `codexbar usage --provider claude --source cli --format json --json-only` succeeded with primary and secondary windows containing `usedPercent`, `windowMinutes`, `resetsAt`, and `resetDescription`. The default/auto probe timed out after 35 seconds. CLI help says auto prefers the claude.ai API and falls back to CLI only when cookies are absent. Explicit CLI source therefore matches the requested Claude Code subscription and avoids that observed auto path.
- Append Claude after DeepSeek to preserve the existing relative order. Keep the existing Weekly label and silent omission on provider failure; no QML changes unless tests disprove compatibility.

## Scope and constraints
- Edit `bin/kodexbar-multi`, `tests/test-wrapper.sh`, `tests/fixtures/claude.json`, and `README.md` only for the behavior unit. Do not read Claude credentials or local session files, add a new auth mechanism, install the widget, push, or open a PR.
- Feature branch: `feature/claude-code-usage`, branched from `82a8ffc`.
- TDD mode: not configured in project/session; ordinary fixture-based functional checks, per existing feature records. Exact runner: `bash tests/test-wrapper.sh`. Supplement with `bash -n bin/kodexbar-multi` and sanitized structural/live CLI checks as applicable.
- Review workload: initial forecast approximately 90 authored changed lines; expanded fixture coverage and Claude payload validation brought the pre-commit count to approximately 220 authored lines. `ask-on-risk` delivery strategy, no chain needed below ~400 lines. Track actual authored changed lines at commit.

## Acceptance criteria
1. Default `kodexbar-multi usage` includes Claude after existing providers when the upstream CLI returns a valid Claude entry; the invocation uses `--provider claude --source cli`.
2. A failed, malformed, or off-shape Claude query is omitted without dropping other providers; a valid single-window response is accepted and all-provider failure still fails.
3. Fixtures and wrapper tests assert provider order, Claude rate-window shape, source flags, and failure isolation without live credentials/network.
4. README documents Claude Code subscription usage, source choice, and prerequisite login; existing QML renders both primary and secondary windows without modification.
5. Functional checks pass and the work unit is captured by a local Conventional Commit with docs/tests alongside behavior.

## Tasks
- [ ] C1 (in progress) — Add Claude to the aggregate with fixture-based coverage and README guidance. Route: delegated `gentle-ai-worker` (four non-trivial files), after parent read-only mapping. Checks: `bash tests/test-wrapper.sh`; `bash -n bin/kodexbar-multi`; sanitized live Claude CLI schema probe (already observed before writes, repeat only if necessary). Commit: pending. Review assessment: pending.

## Progress and verification
- Mapped current wrapper/UI/tests and validated Claude CLI schema read-only. Implemented wrapper integration, synthetic fixture, ordered/failure/shape tests, README guidance, and isolated a pre-existing NaN helper PATH test leak.
- `bash tests/test-wrapper.sh`: passed after test isolation; `bash -n bin/kodexbar-multi`: exit 0; `jq -e . tests/fixtures/claude.json`: exit 0; `git diff --check`: exit 0. Independent verifier found no candidate-caused blockers after corrections. Live Plasma rendering was not tested.
- Config incident resolved separately: explorer model restored to `nan/mimo-v2.6-flash` in global Pi config, with a successful subsequent mapping.
- User authorized a local feature-branch commit after verification; push and PR remain unapproved.

## Next step
Commit the verified work unit locally, assess its native review tier, and close C1 when commit/review evidence is recorded.
