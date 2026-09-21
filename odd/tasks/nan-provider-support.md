# NaN Provider Support

## Goal
Add nan.builders (NaN) as a provider in the `kodexbar-multi` aggregate wrapper and the Plasma popup, showing subscription token usage per model from `nan metrics usage` (v0.1.19). NaN exposes token totals per window (24h, 30d, monthToDate, allTime) with a per-model breakdown; it has no rate-limit windows or credit balance.

## Acceptance criteria
- `kodexbar-multi usage` (no provider flag) includes a NaN entry when `nan` is installed and authenticated; NaN failure is silent and does not affect other providers.
- The wrapper supports `KODEXBAR_NAN_COMMAND` to override the `nan` binary for testing and custom paths.
- The wrapper transforms the NaN payload into a CodexBar-shaped entry (`provider: "nan"`) carrying the raw metrics nested for the QML.
- The popup renders NaN with token-based rows (30d/monthToDate totals plus per-model breakdown) instead of percentage rows; the compact label shows NaN identity without percentages or credits.
- `isUsableEntry` accepts a NaN entry with token data so it is not dropped.
- Wrapper tests cover the NaN aggregation path (happy path, missing binary, invalid JSON) with a fixture.
- README documents the NaN provider, its token-only semantics, and the override variable.

## Non-goals
- No credit/balance or cost display for NaN (cloud-api endpoints are not exposed by the CLI).
- No per-day time-series chart in the popup.
- No changes to the upstream `codexbar` CLI.

## Tasks
- [x] Add NaN provider to the aggregate query in `bin/kodexbar-multi` with payload transform and `KODEXBAR_NAN_COMMAND` override.
- [x] Add the NaN branch to `contents/ui/main.qml` normalization, cards, usability, and compact identity.
- [x] Extend `tests/test-wrapper.sh` with NaN fixtures and cases.
- [x] Add the `nan` provider icon mapping and `contents/icons/providers/nan.svg`.
- [x] Update `README.md` with the NaN provider row, semantics, and troubleshooting.
- [x] Run the full wrapper test suite and QML syntax checks; deploy with `install.sh` if verified.

## Evidence
- Native RDD review completed and approved: lineage `review-43b91be039b099c8`, target `sha256:80806bd1…`, 4 lenses (risk, resilience, readability, reliability) captured; acknowledgement burned (`gentle-ai.review-acknowledged/v1`). Findings: 7 advisory/non-blocking (4 SUGGESTION, 2 WARNING informational, 1 SUGGESTION) — no corrections opened. The readability lens relay initially failed repeatedly (non-JSON reviewer output) and succeeded after a relay fix.
- `bash tests/test-wrapper.sh`: all tests passed (pre-existing cases plus new NaN cases: aggregate includes nan entry, `nan me` failure omits account, missing/metrics-fail/invalid-JSON nan stays silent and other providers still aggregate).
- `bash -n bin/kodexbar-multi`: clean.
- `/usr/lib/qt6/bin/qmllint contents/ui/main.qml`: exit 0; no error-level diagnostics (pre-existing style warnings only).
- `contents/icons/providers/nan.svg`: valid XML; `"nan": "nan"` mapping present in `providerIconSource`.
- End-to-end fake harness: `KODEXBAR_NAN_COMMAND=<fake nan> KODEXBAR_CODEXBAR_COMMAND=/bin/false kodexbar-multi usage` returned a length-1 array with `provider == "nan"`, `source == "cli"`, `account == "nan@example.com"`, and `usage.nan.monthToDate.totalTokens == 930278`.
- Native review assess was unavailable (empty native output); risk treated as high, so an independent verifier was required. `gentle-ai-verify` failed twice at bootstrap (runtime defect, zero tool calls); verification was executed inline by the orchestrator as fallback with the same checks.

## Open issue (handoff to next session)
- [ ] User reports NaN card still NOT visible in the popup after plasmashell restart, despite: installed QML byte-identical to reviewed source, zero QML errors in journal, and the wrapper returning the nan entry in the plasmashell environment at verification time. The `nan` CLI fails in intermittent multi-minute streaks (proven), which omits the entry silently, but the user's persistent failure suggests something else may be involved. Next steps: inspect the actual widget rendering (screenshot), check refresh cadence/selection state, verify the widget's DataSource command line actually executed, consider nan CLI-side reporting to helmcode/nan-cli.

## Commits
- `243c935` feat: add NaN provider to aggregate usage wrapper (wrapper + tests + fixtures)
- `8b53247` feat: render NaN token usage in popup (QML + nan.svg icon)
- `b542b15` docs: document NaN provider support (README)
- `c083c2b` docs: record NaN provider support tasks (feature doc)
- `4362c29` fix: retry transient nan metrics failure once (retry + metrics-flaky test)

## Post-deploy findings
- The `nan` CLI fails intermittently in multi-minute streaks (server-side/network); direct invocations work before and after. During a streak the aggregate omits the NaN entry (silent by design); the retry added in `4362c29` absorbs short transient failures. KodexBar code is not implicated: wrapper, QML, and environment were verified (env -i with the systemd user PATH reproduces plasmashell's environment).
- Third native review (lineage `review-aad2ed68eee1cb36`, target `sha256:cfa0587c…`): approved and acknowledged; 9 advisory findings, all informational. Reviewer lenses intermittently produce schema-invalid output (unknown field "evidence", non-JSON bodies) — recovered by re-running the slot; rejected payloads preserved under `.git/gentle-ai/rejected-results/`.
