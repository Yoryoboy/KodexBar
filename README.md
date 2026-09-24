# KodexBar

> AI provider usage in your KDE Plasma panel.

[![Plasma 6](https://img.shields.io/badge/KDE%20Plasma-6-1d99f3?style=flat-square)](https://kde.org/plasma-desktop/)
[![CodexBar CLI](https://img.shields.io/badge/powered%20by-CodexBar%20CLI-0a0a0c?style=flat-square)](https://github.com/steipete/CodexBar)
[![License: MIT](https://img.shields.io/badge/license-MIT-6e5aff?style=flat-square)](LICENSE)

KodexBar is a native KDE Plasma widget inspired by [CodexBar](https://github.com/steipete/CodexBar). It keeps Codex, Claude, OpenAI, Gemini, Copilot, OpenRouter, Bedrock, GroqCloud, and other CodexBar-supported provider limits visible from a Plasma panel popup. The bundled wrapper also surfaces [nan.builders](https://nan.builders) (NaN) subscription token usage, which is token-metered rather than rate-limited.

The widget intentionally uses the upstream `codexbar` CLI as its data source instead of reimplementing provider backends. CodexBar owns auth, provider config, API calls, local CLI probing, and `${XDG_CONFIG_HOME:-$HOME/.config}/codexbar/config.json`; KodexBar focuses on the Plasma panel and popup UI. The compact label also uses best-effort, local-only last-activity metadata for Codex accounts and the single OpenCode Go account.

![KodexBar widget screenshot](screenshot.png)

## Why

- **Panel visibility.** Show the active provider, used percent, and remaining credits directly in your KDE panel.
- **CodexBar-compatible data.** Reads the same JSON payloads as the upstream app and Linux CLI.
- **Local cost estimates.** Shows `codexbar cost` token and estimated-cost summaries when the upstream CLI can scan local logs.
- **Provider fallback.** `Best available` tries Linux-friendly source combinations before surfacing an error.
- **Plasma-native UI.** Built as a Plasma 6 applet with Kirigami styling, provider icons, compact panel text, and a scrollable popup.

## Requirements

- KDE Plasma 6
- Bash and `jq`
- `kpackagetool6`
- Upstream `codexbar` CLI on `PATH`, or a full executable path configured in the widget settings or `KODEXBAR_CODEXBAR_COMMAND`
- Optional: the `nan` CLI on `PATH` (or via `KODEXBAR_NAN_COMMAND`) with `nan auth login` done, to include NaN token usage in the aggregate
- Optional: Python 3 with the [`cryptography`](https://cryptography.io/) package, `kwallet-query` (KDE KWallet), and a Linux Google Chrome `Default` profile, to read NaN per-model cloud quota from your existing browser session instead of the CLI

The installer does not download dependencies. Install the upstream CLI with Homebrew on Linux:

```sh
brew install steipete/tap/codexbar
codexbar --version
codexbar usage --format json --pretty
```

Or download a Linux CLI tarball from the [CodexBar releases](https://github.com/steipete/CodexBar/releases/latest).

Make sure the provider CLIs or credentials you rely on are already configured. For example, sign in with `codex login`, `claude /login`, cloud/provider CLIs, or API keys supported by CodexBar.

## Install

Clone this repository and run the repository-owned installer:

```sh
git clone https://github.com/Yoryoboy/KodexBar.git
cd KodexBar
./install.sh
```

The installer validates Bash, `jq`, `kpackagetool6`, and the upstream CLI, then installs the executable `kodexbar-multi` and the optional `nan-cloud-quota` helper to `${XDG_BIN_HOME:-$HOME/.local/bin}` and installs or upgrades the Plasma applet. Add **KodexBar** to a Plasma panel. Existing widget configuration, including a stored custom command, is preserved; only new installations default the command to `kodexbar-multi`.

The `nan-cloud-quota` helper is optional and installed only as a byte-for-byte copy of the repository file. If a different `nan-cloud-quota` already exists at the target, the installer preserves it untouched and warns instead of replacing it, and an existing byte-identical copy is left as is. When Python 3 or `cryptography` is missing the installer warns but still succeeds, and the wrapper falls back to the `nan` CLI.

For development or manual package operations:

```sh
kpackagetool6 -t Plasma/Applet -i .
# Update an existing local package:
kpackagetool6 -t Plasma/Applet -u .
```

The installer does not edit `plasma-org.kde.plasma.desktop-appletsrc` or restart Plasma automatically.

## Bundled multi-provider wrapper

The bundled `kodexbar-multi` wrapper is the widget's portable aggregate command. A no-provider `usage` query asks Codex for `--all-accounts`, OpenCode Go for `--source auto`, DeepSeek for `--source api`, and NaN through its cloud quota helper or `nan` CLI, returning all successful JSON entries. Aggregate entry order is a tested contract: the Codex accounts first, then NaN, then OpenCode Go, then DeepSeek. Successful provider data is retained when another provider fails; failed provider output is omitted. The command fails only if all providers fail or the resulting JSON is invalid.

For the current DeepSeek payload shape, the wrapper defensively converts `usage.primary.resetDescription` such as `$2.05 (Paid: $2.05 / Granted: $0.00)` into structured `credits.remaining`, `paidBalance`, `grantedBalance`, and `currencyCode` fields. Unrecognized descriptions are left unchanged. Explicit Codex usage receives `--all-accounts` only when no account selector is present. Non-`usage` commands, including `cost`, pass through unchanged: usage is provider quota/balance data, while cost is a separate local/provider estimate scan.

NaN is not a CodexBar provider, so its runner never calls the upstream `codexbar` CLI. It first prefers the local **cloud quota helper**, which reads the existing Chrome session, and falls back to the `nan` CLI metrics when that helper is missing or fails.

The cloud quota helper resolves as `KODEXBAR_NAN_QUOTA_COMMAND` when set, then the `nan-cloud-quota` file beside the wrapper, then `nan-cloud-quota` on `PATH`, then `${XDG_BIN_HOME:-$HOME/.local/bin}/nan-cloud-quota`. `KODEXBAR_NAN_QUOTA_COMMAND` selects which executable runs; it does not configure an endpoint, and the bundled helper's HTTPS target is fixed and non-configurable. It is not a safety boundary: whatever executable you name runs with access to your Chrome session, so override it only with a helper you trust. The helper only supports a Linux Google Chrome `Default` profile with an unlocked KDE KWallet `Chrome Keys` / `Chrome Safe Storage` entry; it reads only the `.nan.builders` `nan_session` record, keeps the cookie and wallet password in process memory, performs one request to the fixed NaN endpoint, and fails closed with a sanitized message for a missing, expired, insecure, differently encrypted, or inaccessible cookie. The wrapper discards the helper's stderr, so no wallet or cookie diagnostics can reach the aggregate or the widget.

When the helper succeeds, the payload is nested under `usage.nanQuota` as `{periodStart, models[]}` with per-model `tokensUsed`, `cap`, `remaining`, `periodEnd`, and optional `updatedAt`, `fullWindowTokens`, and `windowHours`. The popup renders per-model used/remaining quota, the cap, the period end, and rolling-window details where reported. It never presents quota as spend or credits, and it labels the quota period explicitly instead of showing a reset countdown.

When no helper is available, the wrapper resolves the `nan` binary from `KODEXBAR_NAN_COMMAND` when set, then `nan` on `PATH`, then `${XDG_BIN_HOME:-$HOME/.local/bin}/nan`, and skips it silently when no executable is found. It runs `nan metrics usage`, validates the JSON, and optionally runs `nan me` to attach `.email` as the account; a failed `nan me` still emits the entry without an account. The raw metrics are nested under `usage.nan`, with `usage.updatedAt` taken from `monthToDate.cachedAt` or `allTime.cachedAt` when present. NaN has no rate-limit windows and no credit balance, so the popup renders token totals per window plus a per-model breakdown instead of percentage bars or credits.

The compact label is reduced to a deterministic identity and both used percentages, for example `A1 · 46% / 31%`. Codex activity is attributed from filesystem metadata under candidate homes from string-valued `codexProfileHomePaths` in the local CodexBar config plus `${CODEX_HOME:-$HOME/.codex}`. `KODEXBAR_CODEX_ACCOUNT_HOMES` remains an explicit `account=home;...` override. The wrapper checks only the newest candidate home, runs one scoped Codex usage query to identify its account, and attaches the timestamp only when that identity is unambiguous. OpenCode Go activity reads only the newest `session.time_updated` value from its local SQLite database, defaulting to `${XDG_DATA_HOME:-$HOME/.local/share}/opencode/opencode.db`; `KODEXBAR_OPENCODE_DB` may override it. The wrapper emits timestamps only, never session contents, prompts, messages, project names, titles, credentials, or paths. Missing tools, databases, logs, schema differences, ambiguous accounts, or failed discovery simply omit activity metadata and preserve quota output. A missing activity timestamp falls back to the selected or first usable popup entry.

To override upstream CLI discovery at runtime:

```sh
export KODEXBAR_CODEXBAR_COMMAND=/opt/codexbar/bin/codexbar
```

This variable must be present in Plasma's runtime environment; setting it only while running `install.sh` does not persist it. Without the override, the wrapper uses `codexbar` from `PATH`, then `${XDG_BIN_HOME:-$HOME/.local/bin}/codexbar`.

To override the separate NaN CLI discovery at runtime:

```sh
export KODEXBAR_NAN_COMMAND=/opt/nan/bin/nan
```

This variable only affects the bundled wrapper's NaN runner and must likewise be present in Plasma's runtime environment. Without the override, the wrapper uses `nan` from `PATH`, then `${XDG_BIN_HOME:-$HOME/.local/bin}/nan`, and skips NaN when neither exists. It is used only when the cloud quota helper is unavailable.

To override the cloud quota helper (for example when testing a rebuilt helper):

```sh
export KODEXBAR_NAN_QUOTA_COMMAND=/opt/kodexbar/nan-cloud-quota
```

This variable selects only the executable to run; it does not configure an endpoint. The bundled helper's endpoint is hard-coded, but the override is trusted-executable selection, not a safety boundary: any replacement you name executes with access to your Chrome cookie and KWallet, so point it only at a helper you have reviewed. An untrusted override can read and send your session data anywhere.

## Usage

- Click the panel item to open the popup.
- Use the refresh button in the popup to query the CLI immediately.
- Open widget settings to change provider, source, refresh cadence, and compact label fields.
- Leave Provider as `Best available` if you want KodexBar to find the first usable Linux-capable provider/source combination.
- Choose `All enabled` to ask the CLI for all providers enabled in `${XDG_CONFIG_HOME:-$HOME/.config}/codexbar/config.json`.

The popup renders common CodexBar CLI fields:

- session, weekly, tertiary, and extra rate-limit windows
- reset countdowns and usage bars
- NaN cloud quota per model (used, remaining, cap, period end, and rolling-window details when reported)
- NaN token totals per window (24h, 30d, month to date) and per-model input/output breakdown when no cloud helper is available
- provider spend/budget rows
- credit balances
- OpenAI dashboard summaries where present
- provider status when status fetching is enabled
- per-provider CLI/runtime errors

Provider-specific charts, account management, cookie/API-key editing, notifications, and cost scans remain available through the upstream CodexBar app and CLI.

## Settings

KodexBar exposes these Plasma widget settings:

| Setting | Purpose |
| --- | --- |
| Command | `codexbar` binary name or full path. New installs use `kodexbar-multi`; existing stored commands are unchanged. |
| Provider | `Best available`, `All enabled`, or a specific CodexBar provider ID. |
| Source | `Best available`, `auto`, `web`, `cli`, `oauth`, or `api`. |
| Refresh | Poll interval, from 10 to 3600 seconds. |
| Show provider in panel | Include the reduced provider/account identity, such as `A1`, in the compact label. |
| Show used percent in panel | Include both 5-hour and weekly used percentages when available. |
| Show credits in panel | Include remaining credits only when a positive numeric balance is available. |
| Show email in widget | Show the account email inside the popup when available. |
| Fetch provider status | Add `--status` to CLI calls and display incident/maintenance state. |

Provider credentials and provider toggles are still controlled by the CodexBar CLI config at `${XDG_CONFIG_HOME:-$HOME/.config}/codexbar/config.json` (XDG config semantics apply).

## Linux provider fallback

Some CodexBar sources are macOS-specific, especially WebKit/browser integrations from the upstream app. KodexBar's `Best available` mode first lets the CLI use its configured defaults, then falls back through Linux-friendly combinations such as:

- Codex via CLI, OAuth, or API
- Claude via CLI, OAuth, or API
- OpenAI, Gemini, Copilot, Kilo, Kimi, z.ai, MiniMax, Vertex AI, Warp, OpenRouter, ElevenLabs, Ollama, DeepSeek, Bedrock, GroqCloud, LLM Proxy, Deepgram, and other API/CLI-backed providers

If you already know which provider works on your system, select it directly and leave Source as `Auto` or `Best available`.

## Test The CLI

Run these before debugging the widget:

```sh
codexbar usage --format json --json-only --provider all --source auto | python3 -m json.tool
codexbar usage --format json --json-only --provider codex --source oauth | python3 -m json.tool
```

If the widget shows a CLI error, either install the CLI, configure provider credentials, or set the full command path in the widget settings.

## How It Works

1. Plasma runs the applet from `metadata.json` and `contents/ui/main.qml`.
2. New installs configure the applet to call `kodexbar-multi`; the wrapper shells out to upstream `codexbar` for aggregate usage.
3. The JSON payload is normalized into provider cards, usage rows, credit rows, status text, and compact panel text.
4. A separate `codexbar cost` query supplies optional local cost summaries.
5. A timer refreshes the data at the configured interval.
6. Provider icons are loaded from `contents/icons/providers/`.

## Update, uninstall, and rollback

Run the installer again from the repository to update both the applet and wrapper:

```sh
./install.sh
```

When an existing wrapper differs, it is backed up beside the target with a timestamped `.backup.*` suffix before replacement; the backup path is printed. To remove KodexBar and its recognizable bundled wrapper only:

```sh
./install.sh --uninstall
```

Uninstall preserves an unrecognized user-owned `kodexbar-multi` or `nan-cloud-quota`, all CodexBar credentials, custom commands, and Plasma applet configuration. The quota helper is removed only when it is a byte-for-byte copy of the repository file; an edited or user-owned helper is preserved with a warning. To roll back the wrapper, replace the installed wrapper with a printed backup (or reinstall the desired repository version); Plasma itself is not restarted.

## Troubleshooting

| Symptom | Likely fix |
| --- | --- |
| Widget says `No data` | Run `codexbar usage --format json --pretty` in a terminal and verify the CLI returns usable data. |
| Cost section is missing | Run `codexbar cost --format json --pretty` and verify the CLI reports local cost data for the selected provider. |
| Widget says Codex is signed out | Run `codex login` in a terminal, then refresh the widget. |
| Widget shows a CLI/runtime error | Install `codexbar`, set the full command path, or select a provider/source that works on Linux. |
| Provider works in terminal but not in the widget | Use an absolute command path in settings if Plasma does not inherit your shell `PATH`. |
| `Best available` picks the wrong provider | Select the provider explicitly in settings. |
| Status never appears | Enable **Fetch provider status** in widget settings. |
| `kodexbar-multi` cannot find upstream CodexBar | Confirm `codexbar` is executable, or export `KODEXBAR_CODEXBAR_COMMAND` in the environment that launches Plasma. |
| Only some aggregate providers appear | Check the unavailable provider's credentials/source; successful providers are intentionally preserved. |
| NaN usage never appears | Install the `nan` CLI (`nan auth login`) or export `KODEXBAR_NAN_COMMAND` to its executable path in the environment that launches Plasma. |
| NaN cloud quota rows never appear | The helper needs Python 3 with `cryptography`, `kwallet-query`, an unlocked KDE KWallet `Chrome Safe Storage` entry, and a signed-in Linux Google Chrome `Default` profile. Any missing or inaccessible piece fails closed and the popup falls back to `nan` CLI token totals. |
| Installer refuses a dependency | Install Bash, `jq`, `kpackagetool6`, or upstream `codexbar`; the installer never downloads dependencies. |

## License

MIT. See [LICENSE](LICENSE).
