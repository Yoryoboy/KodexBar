#!/usr/bin/env bash
set -u
set -o pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
wrapper=$root/bin/kodexbar-multi
fixtures=$root/tests/fixtures
tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/kodexbar-wrapper-test.XXXXXX")
trap 'rm -rf "$tmpdir"' EXIT HUP INT TERM
fake=$tmpdir/codexbar
log=$tmpdir/args.log
cat >"$fake" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$FAKE_LOG"
if [[ ${FAKE_MODE:-normal} == fail-all ]]; then exit 1; fi
if [[ ${FAKE_MODE:-normal} == partial && $* == *"--provider opencodego"* ]]; then exit 1; fi
if [[ $* == *"--provider codex"* ]]; then
    if [[ ${FAKE_MODE:-normal} == auto-codex && -n ${CODEX_HOME-} ]]; then
        if [[ ${FAKE_MODE_AUTO_RESULT:-match} == ambiguous ]]; then
            printf '[{"provider":"codex","account":"account-a"},{"provider":"codex","account":"account-b"}]\n'
        elif [[ ${FAKE_MODE_AUTO_RESULT:-match} == fail ]]; then
            exit 1
        else
            printf '{"provider":"codex","account":"account-b"}\n'
        fi
    else
        cat "$FAKE_FIXTURES/codex.json"
    fi
elif [[ $* == *"--provider opencodego"* ]]; then
    if [[ ${FAKE_MODE:-normal} == multiple-opencode ]]; then cat "$FAKE_FIXTURES/opencodego-multiple.json"; else cat "$FAKE_FIXTURES/opencodego.json"; fi
elif [[ $* == *"--provider deepseek"* ]]; then
    if [[ ${FAKE_MODE:-normal} == unmatched ]]; then cat "$FAKE_FIXTURES/deepseek-unmatched.json"; else cat "$FAKE_FIXTURES/deepseek.json"; fi
elif [[ $* == *"--provider claude"* ]]; then
    case ${FAKE_MODE:-normal} in
        claude-missing) exit 0 ;;
        claude-fail) exit 1 ;;
        claude-invalid) printf 'not json\n'; exit 0 ;;
        claude-empty) printf '{}\n'; exit 0 ;;
        claude-wrong-provider) printf '{"provider":"gemini","usage":{"primary":{"usedPercent":10}}}\n'; exit 0 ;;
        claude-no-window) printf '{"provider":"claude","usage":{"primary":{"resetsAt":"2026-09-21T21:00:00Z"},"secondary":{}}}\n'; exit 0 ;;
        claude-primary-only) printf '{"provider":"claude","usage":{"primary":{"usedPercent":25}}}\n'; exit 0 ;;
        claude-remaining-percent) printf '{"provider":"claude","usage":{"secondary":{"remainingPercent":40}}}\n'; exit 0 ;;
        claude-array-valid) printf '[{"provider":"claude","usage":{"primary":{"usedPercent":25}}} ]\n'; exit 0 ;;
        claude-array-mixed) printf '[{"provider":"claude","usage":{"primary":{"usedPercent":25}}},{}]\n'; exit 0 ;;
        *) cat "$FAKE_FIXTURES/claude.json" ;;
    esac
elif [[ $1 == cost ]]; then printf '{"provider":"codex","totals":{"totalCost":1}}\n'
else printf '{"provider":"custom"}\n'; fi
FAKE
chmod 755 "$fake"
export FAKE_LOG=$log FAKE_FIXTURES=$fixtures KODEXBAR_CODEXBAR_COMMAND=$fake

fake_nan=$tmpdir/nan
nan_counter=$tmpdir/nan-metrics-count
export FAKE_NAN_COUNTER=$nan_counter
cat >"$fake_nan" <<'FAKENAN'
#!/usr/bin/env bash
case ${FAKE_NAN_MODE:-normal} in
    metrics-fail) exit 1 ;;
    metrics-invalid) printf 'not json\n'; exit 0 ;;
    metrics-flaky)
        # Fail only the first `metrics usage` call; the `me` call keeps succeeding.
        if [[ ${1-} == metrics ]]; then
            count=0
            [[ -f $FAKE_NAN_COUNTER ]] && count=$(cat "$FAKE_NAN_COUNTER")
            printf '%s\n' "$((count + 1))" >"$FAKE_NAN_COUNTER"
            (( count == 0 )) && exit 1
        fi
        ;;
esac
if [[ ${1-} == me ]]; then
    [[ ${FAKE_NAN_MODE:-normal} == me-fail ]] && exit 1
    cat "$FAKE_FIXTURES/nan-me.json"
    exit 0
fi
cat "$FAKE_FIXTURES/nan-metrics.json"
FAKENAN
chmod 755 "$fake_nan"
# Disable NaN for every case that does not exercise it, so the suite is deterministic
# even when the host has a real `nan` CLI installed.
export KODEXBAR_NAN_COMMAND=$tmpdir/no-nan
# Disable the local cloud quota helper unless a case exercises it, so the suite never
# reads the host's real Chrome profile, cookies, or KWallet.
export KODEXBAR_NAN_QUOTA_COMMAND=$tmpdir/no-quota-helper

codex_home_a=$tmpdir/codex-home-a
codex_home_b=$tmpdir/codex-home-b
mkdir -p "$codex_home_a/sessions" "$codex_home_b/sessions"
printf '{}' >"$codex_home_a/sessions/recent.jsonl"
printf '{}' >"$codex_home_b/sessions/recent.jsonl"
touch -d '2025-01-02 03:04:05 UTC' "$codex_home_a/sessions/recent.jsonl"
touch -d '2025-01-03 03:04:05 UTC' "$codex_home_b/sessions/recent.jsonl"
export KODEXBAR_CODEX_ACCOUNT_HOMES="account-a=$codex_home_a;account-b=$codex_home_b"
export XDG_DATA_HOME=$tmpdir/xdg-data
mkdir -p "$XDG_DATA_HOME/opencode"
sqlite3 "$XDG_DATA_HOME/opencode/opencode.db" 'CREATE TABLE session (time_updated INTEGER); INSERT INTO session VALUES (1735959845000);'

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
assert() { "$@" || fail "$*"; }
assert_json() { jq -e "$1" >/dev/null <<<"$2" || fail "jq $1"; }

out=$("$wrapper" usage --format json --json-only)
assert_json 'length == 5 and any(.[]; .provider == "codex" and .activity.lastActivityAt == "2025-01-02T03:04:05Z") and any(.[]; .provider == "opencodego" and .activity.lastActivityAt == "2025-01-04T03:04:05Z") and any(.[]; .provider == "deepseek") and any(.[]; .provider == "claude")' "$out"
assert_json '.[] | select(.provider == "deepseek") | .credits | .remaining == 2.05 and .paidBalance == 2.05 and .grantedBalance == 0 and .currencyCode == "USD"' "$out"

export KODEXBAR_NAN_COMMAND=$fake_nan
unset FAKE_NAN_MODE
out=$("$wrapper" usage --format json --json-only)
assert_json 'length == 6 and any(.[]; .provider == "nan" and .source == "cli" and .account == "nan@example.com" and .usage.updatedAt == "2026-09-21T16:11:42Z" and .usage.nan.monthToDate.totalTokens == 930278 and .usage.nan.last30d.totalTokens == 930278)' "$out"
assert_json '.[] | select(.provider == "nan") | .usage.nan.monthToDate.byModel[0].model == "deepseek-v4-flash" and .usage.nan.monthToDate.byModel[0].inputTokens == 690429 and .usage.nan.monthToDate.byModel[0].outputTokens == 10442' "$out"
# The aggregate contract pins the provider order end to end: the Codex accounts
# first, then NaN, then OpenCode Go, then DeepSeek, then Claude. Asserting the exact
# ordered provider sequence (not just membership) fails if the order regresses.
assert_json 'map(.provider) == ["codex", "codex", "nan", "opencodego", "deepseek", "claude"]' "$out"
export FAKE_NAN_MODE=me-fail
out=$("$wrapper" usage --format json --json-only)
assert_json 'length == 6 and any(.[]; .provider == "nan" and (.account == null) and .usage.nan.monthToDate.totalTokens == 930278)' "$out"
unset FAKE_NAN_MODE

# A failed, invalid, or missing NaN binary is silent; the other providers still aggregate.
export KODEXBAR_NAN_COMMAND=$tmpdir/missing-nan
out=$("$wrapper" usage --format json --json-only)
assert_json 'length == 5 and all(.[]; .provider != "nan")' "$out"
export KODEXBAR_NAN_COMMAND=$fake_nan
export FAKE_NAN_MODE=metrics-fail
out=$("$wrapper" usage --format json --json-only)
assert_json 'length == 5 and all(.[]; .provider != "nan")' "$out"
export FAKE_NAN_MODE=metrics-invalid
out=$("$wrapper" usage --format json --json-only)
assert_json 'length == 5 and all(.[]; .provider != "nan")' "$out"
# A transient first `metrics usage` failure is recovered by the single retry.
export FAKE_NAN_MODE=metrics-flaky
: >"$nan_counter"
out=$("$wrapper" usage --format json --json-only)
assert_json 'length == 6 and any(.[]; .provider == "nan" and .account == "nan@example.com" and .usage.nan.monthToDate.totalTokens == 930278)' "$out"
assert grep -q '^2$' "$nan_counter"
unset FAKE_NAN_MODE
export KODEXBAR_NAN_COMMAND=$tmpdir/no-nan

# --- Claude Code subscription windows ----------------------------------------
# Claude is an upstream CodexBar provider queried with an explicit CLI source, so the
# wrapper never reads a Claude credential or session file itself. The sanitized
# fixture carries the primary (5-hour) and secondary (weekly) windows observed from
# `codexbar usage --provider claude --source cli --format json --json-only`.
: >"$log"
out=$("$wrapper" usage --format json --json-only)
assert_json 'length == 5 and any(.[]; .provider == "claude")' "$out"
assert_json '.[] | select(.provider == "claude") | .usage.primary.windowMinutes == 300 and .usage.secondary.windowMinutes == 10080 and .usage.primary.usedPercent == 25 and .usage.secondary.usedPercent == 60 and .usage.primary.resetsAt == "2026-09-21T21:00:00Z" and .usage.primary.resetDescription == "Resets in 4 hours" and .usage.secondary.resetDescription == "Resets in 3 days"' "$out"
assert grep -q -- "--provider claude --source cli" "$log"

# A missing, failed, or invalid Claude query is omitted without dropping peers.
export FAKE_MODE=claude-missing
out=$("$wrapper" usage --format json --json-only)
assert_json 'length == 4 and all(.[]; .provider != "claude") and any(.[]; .provider == "deepseek")' "$out"
export FAKE_MODE=claude-fail
out=$("$wrapper" usage --format json --json-only)
assert_json 'length == 4 and all(.[]; .provider != "claude") and any(.[]; .provider == "deepseek")' "$out"
export FAKE_MODE=claude-invalid
out=$("$wrapper" usage --format json --json-only)
assert_json 'length == 4 and all(.[]; .provider != "claude") and any(.[]; .provider == "deepseek")' "$out"
# Truthy off-shape payloads are still invalid: an empty object, another provider's
# entry, or a Claude entry without any usable percentage window must be omitted.
for mode in claude-empty claude-wrong-provider claude-no-window; do
    export FAKE_MODE=$mode
    out=$("$wrapper" usage --format json --json-only)
    assert_json 'length == 4 and all(.[]; .provider != "claude") and any(.[]; .provider == "deepseek")' "$out"
done
unset FAKE_MODE
# One usable window is enough: the secondary (weekly) window may be absent.
export FAKE_MODE=claude-primary-only
out=$("$wrapper" usage --format json --json-only)
assert_json 'length == 5 and any(.[]; .provider == "claude" and .usage.primary.usedPercent == 25 and (.usage.secondary == null))' "$out"
# A remaining-percent window and the array form are both accepted, matching the QML
# and the aggregate's array-tolerant providers.
export FAKE_MODE=claude-remaining-percent
out=$("$wrapper" usage --format json --json-only)
assert_json 'length == 5 and any(.[]; .provider == "claude" and .usage.secondary.remainingPercent == 40)' "$out"
export FAKE_MODE=claude-array-valid
out=$("$wrapper" usage --format json --json-only)
assert_json 'length == 5 and any(.[]; .provider == "claude" and .usage.primary.usedPercent == 25)' "$out"
# A single invalid element invalidates the whole array response.
export FAKE_MODE=claude-array-mixed
out=$("$wrapper" usage --format json --json-only)
assert_json 'length == 4 and all(.[]; .provider != "claude") and any(.[]; .provider == "deepseek")' "$out"
unset FAKE_MODE

# --- NaN cloud quota helper -----------------------------------------------------------------
# The helper is always mocked: no test reads a live Chrome cookie, KWallet entry, or network.
fake_quota=$tmpdir/nan-cloud-quota
cat >"$fake_quota" <<'FAKEQUOTA'
#!/usr/bin/env bash
case ${FAKE_QUOTA_MODE:-ok} in
    fail) printf 'sanitized helper failure\n' >&2; exit 1 ;;
    invalid) printf 'not json\n'; exit 0 ;;
    malformed-model) printf '{"periodStart":"2026-09-01T00:00:00Z","models":[{"model":"","tokensUsed":1,"cap":2,"remaining":1,"periodEnd":"2026-10-01T00:00:00Z"}]}\n'; exit 0 ;;
    malformed-model-fields) printf '{"periodStart":"2026-09-01T00:00:00Z","models":[{"model":"nan-large","tokensUsed":1,"cap":"2","remaining":-1}]}\n'; exit 0 ;;
    malformed-optional) printf '{"periodStart":"2026-09-01T00:00:00Z","models":[{"model":"nan-large","tokensUsed":1,"cap":2,"remaining":1,"periodEnd":"2026-10-01T00:00:00Z","windowHours":-3}]}\n'; exit 0 ;;
    empty-models) printf '{"periodStart":"2026-09-01T00:00:00Z","models":[]}\n'; exit 0 ;;
    secret-stderr) printf 'cookie=SECRET_SESSION_MARKER wallet=SECRET_WALLET_MARKER\n' >&2 ;;
esac
cat "$FAKE_FIXTURES/nan-quota.json"
FAKEQUOTA
chmod 755 "$fake_quota"

# The helper wins over the CLI when it succeeds, even though the nan CLI is available.
unset FAKE_QUOTA_MODE
export KODEXBAR_NAN_COMMAND=$fake_nan
export KODEXBAR_NAN_QUOTA_COMMAND=$fake_quota
out=$("$wrapper" usage --format json --json-only)
assert_json 'length == 6 and (map(.provider) == ["codex", "codex", "nan", "opencodego", "deepseek", "claude"])' "$out"
assert_json '.[] | select(.provider == "nan") | .source == "cloud" and .account == "nan@example.com" and (.usage.nan == null) and .usage.updatedAt == "2026-09-21T16:11:42Z" and .usage.nanQuota.models[0].model == "deepseek-v4-flash" and .usage.nanQuota.models[0].tokensUsed == 125000 and .usage.nanQuota.models[0].cap == 500000 and .usage.nanQuota.models[0].remaining == 375000 and .usage.nanQuota.models[0].windowHours == 24 and .usage.nanQuota.models[0].periodEnd == "2026-10-01T00:00:00Z"' "$out"

# Cloud quota still appears when no nan CLI exists: the helper owns the Chrome session read.
export KODEXBAR_NAN_COMMAND=$tmpdir/missing-nan
out=$("$wrapper" usage --format json --json-only)
assert_json 'length == 6 and any(.[]; .provider == "nan" and .source == "cloud" and (.account == null))' "$out"
export KODEXBAR_NAN_COMMAND=$fake_nan

# Any helper failure preserves the CLI metrics fallback.
export FAKE_QUOTA_MODE=fail
out=$("$wrapper" usage --format json --json-only)
assert_json 'length == 6 and any(.[]; .provider == "nan" and .source == "cli" and .usage.nan.monthToDate.totalTokens == 930278)' "$out"
export FAKE_QUOTA_MODE=invalid
out=$("$wrapper" usage --format json --json-only)
assert_json 'length == 6 and any(.[]; .provider == "nan" and .source == "cli")' "$out"
# A structurally valid envelope with a malformed model must not win the cloud
# branch and leave blank popup rows: each case falls back to CLI metrics.
export FAKE_QUOTA_MODE=malformed-model
out=$("$wrapper" usage --format json --json-only)
assert_json 'length == 6 and any(.[]; .provider == "nan" and .source == "cli") and all(.[]; (.provider != "nan") or (.usage.nanQuota == null))' "$out"
export FAKE_QUOTA_MODE=malformed-model-fields
out=$("$wrapper" usage --format json --json-only)
assert_json 'length == 6 and any(.[]; .provider == "nan" and .source == "cli")' "$out"
export FAKE_QUOTA_MODE=malformed-optional
out=$("$wrapper" usage --format json --json-only)
assert_json 'length == 6 and any(.[]; .provider == "nan" and .source == "cli")' "$out"
export FAKE_QUOTA_MODE=empty-models
out=$("$wrapper" usage --format json --json-only)
assert_json 'length == 6 and any(.[]; .provider == "nan" and .source == "cli")' "$out"
unset FAKE_QUOTA_MODE

# A missing helper target also falls back to the CLI.
export KODEXBAR_NAN_QUOTA_COMMAND=$tmpdir/missing-quota-helper
out=$("$wrapper" usage --format json --json-only)
assert_json 'length == 6 and any(.[]; .provider == "nan" and .source == "cli")' "$out"

# Resolution without an override: the copy installed next to the wrapper wins.
sibling_dir=$tmpdir/sibling/bin
mkdir -p "$sibling_dir"
cp "$wrapper" "$sibling_dir/kodexbar-multi"
cp "$fake_quota" "$sibling_dir/nan-cloud-quota"
out=$(env -u KODEXBAR_NAN_QUOTA_COMMAND KODEXBAR_NAN_COMMAND="$fake_nan" "$sibling_dir/kodexbar-multi" usage --format json --json-only)
assert_json 'length == 6 and any(.[]; .provider == "nan" and .source == "cloud")' "$out"

# With no sibling, the ${XDG_BIN_HOME:-~/.local/bin} install path is used. The wrapper
# resolves sibling, then PATH, then XDG_BIN_HOME, so a host-installed nan-cloud-quota
# on PATH would legitimately win and mask the fallback this case targets. Build a
# self-contained PATH that links only the external tools the wrapper and its mocked
# helpers need, so the case is isolated from host PATH entries without hiding any
# required tool. The production resolution order is untouched.
isolated_path=$tmpdir/isolated-path
mkdir -p "$isolated_path"
for tool in awk bash cat date dirname find grep head jq mktemp mv readlink rm sleep sort sqlite3 tr; do
    tool_path=$(command -v "$tool" 2>/dev/null) || continue
    ln -s "$tool_path" "$isolated_path/$tool"
done
installed_dir=$tmpdir/installed/bin
installed_home=$tmpdir/installed-home
mkdir -p "$installed_dir" "$installed_home"
cp "$wrapper" "$installed_dir/kodexbar-multi"
cp "$fake_quota" "$installed_home/nan-cloud-quota"
out=$(env -u KODEXBAR_NAN_QUOTA_COMMAND PATH="$isolated_path" XDG_BIN_HOME="$installed_home" HOME="$tmpdir/empty-home" KODEXBAR_NAN_COMMAND="$fake_nan" "$installed_dir/kodexbar-multi" usage --format json --json-only)
assert_json 'length == 6 and any(.[]; .provider == "nan" and .source == "cloud")' "$out"
export KODEXBAR_NAN_QUOTA_COMMAND=$tmpdir/no-quota-helper

# Helper diagnostics must never reach the aggregate or the wrapper's stderr.
export KODEXBAR_NAN_QUOTA_COMMAND=$fake_quota
export FAKE_QUOTA_MODE=secret-stderr
out=$("$wrapper" usage --format json --json-only 2>"$tmpdir/quota-helper.err")
assert_json 'any(.[]; .provider == "nan" and .source == "cloud")' "$out"
if grep -q 'SECRET_SESSION_MARKER\|SECRET_WALLET_MARKER' <<<"$out"; then fail 'helper diagnostics leaked into aggregate output'; fi
if grep -q 'SECRET_SESSION_MARKER\|SECRET_WALLET_MARKER' "$tmpdir/quota-helper.err"; then fail 'helper diagnostics leaked into wrapper stderr'; fi
unset FAKE_QUOTA_MODE
export KODEXBAR_NAN_QUOTA_COMMAND=$tmpdir/no-quota-helper
export KODEXBAR_NAN_COMMAND=$tmpdir/no-nan

export FAKE_MODE=multiple-opencode
out=$("$wrapper" usage --format json --json-only)
assert_json 'length == 6 and all(.[]; (.provider != "opencodego" or .activity == null))' "$out"
unset FAKE_MODE

export FAKE_MODE=unmatched
out=$("$wrapper" usage --format json --json-only)
assert_json 'any(.[]; .provider == "deepseek" and .credits.description == "Balance unavailable" and .extra == "preserve")' "$out"

export FAKE_MODE=normal
: >"$log"
export FAKE_MODE=partial
out=$("$wrapper" usage --format json --json-only)
assert_json 'length == 4 and all(.[]; .provider != "opencodego") and any(.[]; .provider == "claude")' "$out"

unset FAKE_MODE KODEXBAR_CODEX_ACCOUNT_HOMES
export HOME=$tmpdir/test-home
export XDG_CONFIG_HOME=$tmpdir/xdg-config
mkdir -p "$XDG_CONFIG_HOME/codexbar"
auto_home_old=$tmpdir/auto-home-old
auto_home_new=$tmpdir/auto-home-new
mkdir -p "$auto_home_old/sessions" "$auto_home_new/sessions"
touch -d '2025-01-02 03:04:05 UTC' "$auto_home_old/sessions/old.jsonl"
touch -d '2025-01-03 03:04:05 UTC' "$auto_home_new/sessions/new.jsonl"
jq -n --arg old "$auto_home_old" --arg new "$auto_home_new" '{providers:["ignored", {codexProfileHomePaths:[$old]}, {codexProfileHomePaths:$new}, 42]}' >"$XDG_CONFIG_HOME/codexbar/config.json"
export FAKE_MODE=auto-codex
out=$("$wrapper" usage --format json --json-only)
assert_json 'any(.[]; .provider == "codex" and .account == "account-b" and .activity.lastActivityAt == "2025-01-03T03:04:05Z") and any(.[]; .provider == "codex" and .account == "account-a" and .activity == null)' "$out"
jq -n --arg old "$auto_home_old" --arg new "$auto_home_new" '{providers:{codex:{codexProfileHomePaths:[$old, $new]}, other:"ignored"}}' >"$XDG_CONFIG_HOME/codexbar/config.json"
out=$("$wrapper" usage --format json --json-only)
assert_json 'any(.[]; .provider == "codex" and .account == "account-b" and .activity.lastActivityAt == "2025-01-03T03:04:05Z")' "$out"
export FAKE_MODE_AUTO_RESULT=ambiguous
out=$("$wrapper" usage --format json --json-only)
assert_json 'all(.[]; .provider != "codex" or .activity == null)' "$out"
export FAKE_MODE_AUTO_RESULT=fail
out=$("$wrapper" usage --format json --json-only)
assert_json 'all(.[]; .provider != "codex" or .activity == null)' "$out"
unset FAKE_MODE FAKE_MODE_AUTO_RESULT XDG_CONFIG_HOME

export FAKE_MODE=fail-all
: >"$log"
if "$wrapper" usage --format json --json-only >"$tmpdir/all.out" 2>"$tmpdir/all.err"; then fail 'all-provider failure returned success'; fi
assert grep -q "all provider usage queries failed" "$tmpdir/all.err"
# The all-provider failure includes Claude: it was queried with the explicit CLI source.
assert grep -q -- "--provider claude --source cli" "$log"
unset FAKE_MODE
export XDG_DATA_HOME=$tmpdir/missing-data
out=$("$wrapper" usage --format json --json-only)
assert_json 'all(.[]; (.activity == null) or (.provider != "opencodego"))' "$out"
unset KODEXBAR_CODEX_ACCOUNT_HOMES XDG_DATA_HOME

assert grep -q 'function codexAccountKey' "$root/contents/ui/main.qml"
assert grep -q 'keys.sort()' "$root/contents/ui/main.qml"
assert grep -q 'entry.creditsRemaining > 0' "$root/contents/ui/main.qml"

# Aggregate card display: the popup hides DeepSeek, keeps Claude before the
# remaining providers, and wraps a wide card row into extra rows instead of
# clipping it or scrolling horizontally.
assert grep -q 'function visibleEntries' "$root/contents/ui/main.qml"
assert grep -q 'model: root.visibleEntries()' "$root/contents/ui/main.qml"
assert grep -q 'columns: Math.max(1, full.cardColumns)' "$root/contents/ui/main.qml"
assert grep -q 'Layout.preferredHeight: full.cardsGridHeight' "$root/contents/ui/main.qml"
assert grep -q 'Layout.minimumHeight: full.cardsGridHeight' "$root/contents/ui/main.qml"
# The card height is derived from the tallest visible card so OpenCode's third
# (Monthly) window always has room, and the popup width is computed from the
# wrapped row instead of a fixed cap.
assert grep -q 'function cardHeight' "$root/contents/ui/main.qml"
assert grep -q 'function popupWidthForCards' "$root/contents/ui/main.qml"
assert grep -q 'root.cardHeight(' "$root/contents/ui/main.qml"
assert grep -q 'root.popupWidthForCards(' "$root/contents/ui/main.qml"
# On a screen narrower than one card the popup is clamped to the screen, so the
# card row and the card itself must both be allowed to shrink below their preferred
# width instead of spilling past the popup edge.
assert grep -q 'Layout.minimumWidth: 0' "$root/contents/ui/main.qml"
assert grep -q 'Layout.maximumWidth: full.accountCardWidth' "$root/contents/ui/main.qml"
max_card_rows_body=$(grep -A6 'readonly property int maxCardRows' "$root/contents/ui/main.qml")
grep -q 'root.visibleEntries()' <<<"$max_card_rows_body" || fail 'maxCardRows no longer derives from the visible cards'
assert grep -q 'i18n("Monthly")' "$root/contents/ui/main.qml"
if grep -q 'maxPopupWidth' "$root/contents/ui/main.qml"; then
    fail 'a fixed popup width cap was reintroduced'
fi
# The card row must never regain a horizontal scrollbar. The popup's only ScrollView
# is the vertical usage list, whose horizontal policy stays AlwaysOff.
assert grep -q 'QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff' "$root/contents/ui/main.qml"
if grep -q 'QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AsNeeded' "$root/contents/ui/main.qml"; then
    fail 'a horizontal ScrollView policy was reintroduced'
fi

# Explicit compact pinning: a card click must pin the compact label to the last
# clicked provider/account card for the widget session, independently of the
# automatic newest-activity selection. These structural checks cover the real
# MouseArea wiring, which the extracted-function QML regressions cannot load
# without a Plasma shell.
assert grep -q 'property string pinnedEntryKey' "$root/contents/ui/main.qml"
assert grep -q 'function clickEntry' "$root/contents/ui/main.qml"
assert grep -q 'function pinnedEntry' "$root/contents/ui/main.qml"
assert grep -q 'function clearMissingPin' "$root/contents/ui/main.qml"
assert grep -q 'onClicked: root.clickEntry(modelData)' "$root/contents/ui/main.qml"
assert grep -q 'clearMissingPin()' "$root/contents/ui/main.qml"
if grep -q 'onClicked: root.selectedEntryKey = root.entryKey(modelData)' "$root/contents/ui/main.qml"; then
    fail 'card clicks no longer pin the compact account'
fi

# NaN cloud quota rendering: the popup must prefer the helper's per-model quota
# payload, keep the CLI token fallback, and label the period explicitly instead
# of reusing a reset countdown that would misrepresent the quota window.
assert grep -q 'usage.nanQuota' "$root/contents/ui/main.qml"
assert grep -q 'function nanQuotaRows' "$root/contents/ui/main.qml"
assert grep -q 'nanQuotaRows(nanQuota)' "$root/contents/ui/main.qml"
assert grep -q 'Period ends %1' "$root/contents/ui/main.qml"
assert grep -q '%1 used of %2' "$root/contents/ui/main.qml"

# candidateList() must recognize both aggregate wrapper basenames -- the legacy
# `codexbar-multi` and the bundled `kodexbar-multi` -- as a single aggregate
# query, while keeping the upstream per-provider fallback for other commands.
# The regression exercises the function extracted from main.qml when a QML test
# runtime is present; otherwise it degrades to a structural check on that same
# function (reduced coverage reported below).
candidate_source=$(awk '
    /^    function candidateList\(\) \{$/ { capture = 1 }
    capture { print }
    capture && /^    \}$/ { exit }
' "$root/contents/ui/main.qml")
[[ -n $candidate_source ]] || fail 'candidateList() was not found in contents/ui/main.qml'

# The aggregate card row is a display-only projection of the wrapper payload: it
# hides DeepSeek, places Claude after the Codex account cards and before the
# remaining providers, and keeps selection on a visible card. These functions are
# extracted from main.qml and exercised through qmltestrunner when available;
# otherwise the suite degrades to structural checks (reduced coverage reported).
extract_function() {
    awk -v name="$1" '
        $0 ~ "^    function " name "\\(" { capture = 1 }
        capture { print }
        capture && /^    \}$/ { exit }
    ' "$root/contents/ui/main.qml"
}
display_functions=""
for name in isAggregateView visibleEntries entryKey selectedEntry clickEntry pinnedEntry clearMissingPin isUsableEntry activityTime compactEntry compactIdentity codexAccountKey codexAccountNumber usedPercent keepSelectionValid cardsRowWidth cardsRowOverflows cardsPerRow cardsRowCount cardsGridHeight cardHeight popupWidthForCards; do
    fn_source=$(extract_function "$name")
    [[ -n $fn_source ]] || fail "function $name was not found in contents/ui/main.qml"
    display_functions+=$fn_source$'\n'
done

qml_test_runner=/usr/lib/qt6/bin/qmltestrunner
[[ -x $qml_test_runner ]] || qml_test_runner=$(command -v qmltestrunner || true)
if [[ -x $qml_test_runner ]]; then
    cat >"$tmpdir/tst_candidates.qml" <<QML
import QtQuick
import QtTest

Item {
    property string codexbarCommand: "codexbar"
    property string selectedProvider: "detect"
    property string selectedSource: "detect"

$candidate_source

    function listFor(command) {
        codexbarCommand = command
        return candidateList()
    }

    TestCase {
        name: "candidateList"

        function test_bundled_aggregate_name() {
            var candidates = listFor("/home/user/.local/bin/kodexbar-multi")
            compare(candidates.length, 1)
            compare(candidates[0].provider, "")
            compare(candidates[0].source, "")
        }

        function test_legacy_aggregate_name() {
            var candidates = listFor("codexbar-multi")
            compare(candidates.length, 1)
            compare(candidates[0].provider, "")
            compare(candidates[0].source, "")
        }

        function test_upstream_fallback_preserved() {
            var candidates = listFor("codexbar")
            verify(candidates.length > 1)
            compare(candidates[0].provider, "codex")
            compare(candidates[0].source, "cli")
        }

        function test_similar_name_falls_back() {
            var candidates = listFor("kodexbar-multi-extra")
            verify(candidates.length > 1)
            compare(candidates[0].provider, "codex")
        }
    }
}
QML
    QT_QPA_PLATFORM=offscreen "$qml_test_runner" -input "$tmpdir/tst_candidates.qml" >"$tmpdir/qmltest.out" 2>&1 \
        || fail "candidateList regression failed: $(cat "$tmpdir/qmltest.out")"

    cat >"$tmpdir/tst_display_order.qml" <<QML
import QtQuick
import QtQuick.Layouts
import QtTest

Item {
    property var entries: []
    property string selectedProvider: "detect"
    property string selectedSource: "detect"
    property string selectedEntryKey: ""
    property string pinnedEntryKey: ""

    // Mirrors the card row in main.qml: a ColumnLayout constrains the card
    // GridLayout to the popup inner width, the grid may shrink below its preferred
    // content width, and the card fills the column up to its preferred width. If
    // the shrink permission or the delegate's flexible width regresses, probeCard
    // keeps its preferred width and spills past probeGrid and this test fails.
    readonly property real probeInnerWidth: 78

    Item {
        width: probeInnerWidth
        height: 40
        ColumnLayout {
            id: probeContent
            anchors.fill: parent
            spacing: 0
            GridLayout {
                id: probeGrid
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.preferredHeight: 40
                columns: 1
                columnSpacing: 4
                rowSpacing: 4
                Rectangle {
                    id: probeCard
                    Layout.preferredWidth: 111.6
                    Layout.maximumWidth: 111.6
                    Layout.fillWidth: true
                    Layout.preferredHeight: 40
                }
            }
        }
    }

$display_functions
    TestCase {
        name: "aggregateCardDisplay"

        function init() {
            entries = []
            selectedProvider = "detect"
            selectedSource = "detect"
            selectedEntryKey = ""
            pinnedEntryKey = ""
        }

        function entry(provider, account) {
            return { provider: provider, account: account || "", source: "cli" }
        }

        // Minimal usable entry with a used percentage, one window row, an
        // optional account and last-activity timestamp. It mirrors the normalized
        // shape compactEntry(), compactIdentity() and isUsableEntry() consume.
        function usageEntry(provider, account, usedPercentValue, lastActivityAt) {
            return {
                provider: provider,
                account: account || "",
                source: "cli",
                name: provider,
                primaryPercentLeft: 100 - usedPercentValue,
                secondaryPercentLeft: null,
                creditsRemaining: null,
                codeReviewRemainingPercent: null,
                rows: [{ title: "5h", percentLeft: 100 - usedPercentValue }],
                lastActivityAt: lastActivityAt || "",
                errorMessage: ""
            }
        }

        function test_aggregate_hides_deepseek_and_places_claude_fourth() {
            entries = [entry("codex", "a"), entry("codex", "b"), entry("codex", "c"),
                entry("nan"), entry("opencodego"), entry("deepseek"), entry("claude")]
            var cards = visibleEntries()
            compare(cards.length, 6)
            compare(cards[0].provider, "codex")
            compare(cards[1].provider, "codex")
            compare(cards[2].provider, "codex")
            compare(cards[3].provider, "claude")
            compare(cards[4].provider, "nan")
            compare(cards[5].provider, "opencodego")
        }

        function test_single_codex_keeps_claude_before_remaining_providers() {
            entries = [entry("codex", "a"), entry("nan"), entry("opencodego"),
                entry("deepseek"), entry("claude")]
            var cards = visibleEntries()
            compare(cards.length, 4)
            compare(cards[0].provider, "codex")
            compare(cards[1].provider, "claude")
            compare(cards[2].provider, "nan")
            compare(cards[3].provider, "opencodego")
        }

        function test_explicit_deepseek_view_is_unfiltered() {
            entries = [entry("deepseek")]
            selectedProvider = "deepseek"
            selectedSource = "api"
            var cards = visibleEntries()
            compare(cards.length, 1)
            compare(cards[0].provider, "deepseek")
            compare(selectedEntry().provider, "deepseek")
        }

        function test_only_deepseek_present_remains_visible() {
            entries = [entry("deepseek")]
            var cards = visibleEntries()
            compare(cards.length, 1)
            compare(cards[0].provider, "deepseek")
        }

        function test_selection_moves_off_hidden_deepseek_on_refresh() {
            entries = [entry("deepseek"), entry("codex", "a"), entry("claude")]
            selectedEntryKey = entryKey(entries[0])
            keepSelectionValid()
            compare(selectedEntryKey, entryKey(entries[1]))
            compare(selectedEntry().provider, "codex")
        }

        function test_selected_entry_falls_back_to_first_visible() {
            entries = [entry("deepseek"), entry("codex", "a"), entry("claude")]
            selectedEntryKey = entryKey(entries[0])
            compare(selectedEntry().provider, "codex")
        }

        function test_keep_selection_valid_clears_when_empty() {
            entries = []
            selectedEntryKey = "stale"
            keepSelectionValid()
            compare(selectedEntryKey, "")
        }

        // Explicit compact pinning: the last clicked provider/account card owns
        // the compact label while it stays visible and usable, ahead of the
        // automatic newest-activity default.
        function test_no_click_defaults_to_newest_activity() {
            entries = [usageEntry("codex", "a", 40, "2026-01-01T00:00:00Z"),
                usageEntry("claude", "", 10, "2026-02-01T00:00:00Z")]
            var picked = compactEntry()
            compare(picked.provider, "claude")
            compare(usedPercent(picked.primaryPercentLeft), 10)
        }

        function test_clicked_card_pins_over_newer_activity() {
            entries = [usageEntry("codex", "a", 40, "2026-01-01T00:00:00Z"),
                usageEntry("claude", "", 10, "2026-02-01T00:00:00Z")]
            clickEntry(entries[0])
            compare(pinnedEntryKey, entryKey(entries[0]))
            var picked = compactEntry()
            compare(picked.provider, "codex")
            compare(usedPercent(picked.primaryPercentLeft), 40)
            compare(compactIdentity(picked), "A1")
        }

        function test_next_click_replaces_pin() {
            entries = [usageEntry("codex", "a", 40, "2026-01-01T00:00:00Z"),
                usageEntry("claude", "", 10, "2026-02-01T00:00:00Z")]
            clickEntry(entries[0])
            compare(compactEntry().provider, "codex")
            clickEntry(entries[1])
            compare(pinnedEntryKey, entryKey(entries[1]))
            var picked = compactEntry()
            compare(picked.provider, "claude")
            compare(usedPercent(picked.primaryPercentLeft), 10)
        }

        function test_pin_survives_refresh_and_reordering() {
            entries = [usageEntry("codex", "a", 40, "2026-01-01T00:00:00Z"),
                usageEntry("claude", "", 10, "2026-02-01T00:00:00Z")]
            clickEntry(entries[0])
            // The refresh reorders the cards and gives Claude newer activity.
            entries = [usageEntry("claude", "", 10, "2026-03-01T00:00:00Z"),
                usageEntry("codex", "a", 40, "2026-01-01T00:00:00Z")]
            clearMissingPin()
            compare(pinnedEntryKey, entryKey(entries[1]))
            var picked = compactEntry()
            compare(picked.provider, "codex")
            compare(compactIdentity(picked), "A1")
        }

        function test_hidden_pin_is_cleared_and_falls_back() {
            var deepseek = usageEntry("deepseek", "", 30, "")
            var codex = usageEntry("codex", "a", 40, "2026-01-01T00:00:00Z")
            entries = [deepseek, codex]
            selectedProvider = "deepseek"
            selectedSource = "api"
            clickEntry(deepseek)
            compare(compactEntry().provider, "deepseek")
            // The aggregate view hides DeepSeek, so the pinned card is gone.
            selectedProvider = "detect"
            selectedSource = "detect"
            clearMissingPin()
            compare(pinnedEntryKey, "")
            var picked = compactEntry()
            compare(picked.provider, "codex")
            verify(!picked.errorMessage)
        }

        function test_removed_pin_is_cleared_and_falls_back() {
            entries = [usageEntry("codex", "a", 40, "2026-01-01T00:00:00Z"),
                usageEntry("claude", "", 10, "2026-02-01T00:00:00Z")]
            clickEntry(entries[0])
            // The next refresh no longer reports the pinned account.
            entries = [usageEntry("claude", "", 10, "2026-02-01T00:00:00Z")]
            clearMissingPin()
            compare(pinnedEntryKey, "")
            compare(compactEntry().provider, "claude")
        }

        function test_unusable_pin_falls_back_and_recovers() {
            var broken = usageEntry("codex", "a", 40, "2026-01-01T00:00:00Z")
            broken.rows = []
            broken.errorMessage = "runtime failure"
            var claude = usageEntry("claude", "", 10, "2026-02-01T00:00:00Z")
            entries = [broken, claude]
            clickEntry(broken)
            // The pin is kept for the session, but an unusable account must never
            // produce invalid compact output.
            compare(pinnedEntryKey, entryKey(broken))
            var picked = compactEntry()
            compare(picked.provider, "claude")
            verify(!picked.errorMessage)
            // When the pinned account reports data again the pin is honored.
            var recovered = usageEntry("codex", "a", 40, "2026-01-01T00:00:00Z")
            entries = [recovered, claude]
            clearMissingPin()
            compare(pinnedEntryKey, entryKey(recovered))
            compare(compactEntry().provider, "codex")
        }

        function test_card_row_overflow_detection() {
            verify(Math.abs(cardsRowWidth(0, 111.6, 4)) < 0.001)
            verify(Math.abs(cardsRowWidth(6, 111.6, 4) - 689.6) < 0.001)
            verify(!cardsRowOverflows(6, 111.6, 4, 744))
            verify(cardsRowOverflows(7, 111.6, 4, 744))
        }

        function test_card_row_wrap_arithmetic() {
            // Six cards share one row at an ordinary desktop width.
            compare(cardsPerRow(6, 111.6, 4, 800), 6)
            compare(cardsRowCount(6, 111.6, 4, 800), 1)
            // A width that cannot hold all six wraps into two rows instead of
            // overflowing horizontally.
            compare(cardsPerRow(6, 111.6, 4, 600), 5)
            compare(cardsRowCount(6, 111.6, 4, 600), 2)
            // Height reserves every wrapped row so no card clips at the bottom.
            compare(cardsGridHeight(2, 50, 4), 104)
            compare(cardsGridHeight(1, 50, 4), 50)
            compare(cardsGridHeight(0, 50, 4), 0)
        }

        function test_wrapped_layout_never_overflows_available_width() {
            // The chosen column count always fits the available width, so the popup
            // wraps instead of needing a horizontal scrollbar.
            var widths = [744, 689.6, 600, 300, 120]
            for (var i = 0; i < widths.length; i++) {
                var columns = cardsPerRow(6, 111.6, 4, widths[i])
                verify(columns >= 1)
                verify(!cardsRowOverflows(columns, 111.6, 4, widths[i]))
            }
        }

        function test_single_row_when_six_cards_fit() {
            // Exactly enough room for all six cards stays a single row.
            verify(!cardsRowOverflows(6, 111.6, 4, 689.6))
            compare(cardsRowCount(6, 111.6, 4, 690), 1)
            compare(cardsPerRow(6, 111.6, 4, 690), 6)
            // A tiny width still yields at least one column, never zero.
            compare(cardsPerRow(6, 111.6, 4, 10), 1)
            compare(cardsRowCount(6, 111.6, 4, 10), 6)
        }

        function test_card_height_covers_every_usage_row() {
            // Each additional usage row (for example OpenCode's Monthly window)
            // grows the card by one full text line plus one row spacing, so a card
            // tall enough for two windows also reserves the third.
            var twoRows = cardHeight(16, 15, 2, 0, 4)
            var threeRows = cardHeight(16, 15, 3, 0, 4)
            compare(threeRows - twoRows, 19)
            verify(threeRows >= twoRows + 15)
            // The optional account line reserves the same amount of room.
            compare(cardHeight(16, 15, 3, 1, 4) - threeRows, 19)
            // A zero-row card still reserves its icon and name line.
            verify(cardHeight(16, 15, 0, 0, 4) > 0)
        }

        function test_popup_width_fits_six_card_row() {
            // Six cards on an ordinary desktop share one row and the popup width is
            // exactly that row plus both margins, never wider than the screen.
            var screenWidth = 1920
            var available = screenWidth - 32
            var width = popupWidthForCards(6, 111.6, 4, available, 16, 540, screenWidth)
            compare(cardsPerRow(6, 111.6, 4, available), 6)
            compare(width, 689.6 + 32)
            verify(width <= screenWidth)
            // A single card on a wide screen is raised to the readable minimum.
            compare(popupWidthForCards(1, 111.6, 4, available, 16, 540, screenWidth), 540)
        }

        function test_popup_width_wraps_and_clamps_on_narrow_screen() {
            // A narrow screen wraps the row and the popup stays on screen instead of
            // growing a horizontal scrollbar; the wrapped content still fits.
            var screenWidth = 500
            var available = screenWidth - 32
            var width = popupWidthForCards(6, 111.6, 4, available, 16, 540, screenWidth)
            var columns = cardsPerRow(6, 111.6, 4, available)
            verify(columns >= 1)
            verify(columns < 6)
            verify(width <= screenWidth)
            verify(!cardsRowOverflows(columns, 111.6, 4, width - 32))
        }

        function test_popup_width_clamps_below_one_card() {
            // Blocking case: the screen is narrower than one card plus both margins.
            // The popup clamps to the screen, the inner width stays positive, and it
            // is smaller than one card, so the card must shrink to fit inside it.
            var cardWidth = 111.6
            var margin = 36
            var screenWidth = 150
            var available = Math.max(cardWidth, screenWidth - margin * 2)
            var width = popupWidthForCards(1, cardWidth, 4, available, margin, 540, screenWidth)
            compare(width, screenWidth)
            verify(width - margin * 2 > 0)
            verify(width - margin * 2 < cardWidth)
            compare(cardsPerRow(1, cardWidth, 4, available), 1)
        }

        function test_card_stays_inside_narrow_popup() {
            // The card must shrink to the popup inner width instead of keeping its
            // preferred width and spilling past the popup edge.
            waitForRendering(probeGrid)
            verify(probeCard.width > 0)
            verify(probeCard.width <= probeGrid.width + 0.001)
        }
    }
}
QML
    QT_QPA_PLATFORM=offscreen "$qml_test_runner" -input "$tmpdir/tst_display_order.qml" >"$tmpdir/qmltest-display.out" 2>&1 \
        || fail "aggregate card display regression failed: $(cat "$tmpdir/qmltest-display.out")"
else
    printf 'WARN: qmltestrunner unavailable; candidateList and aggregate card display regressions fell back to structural checks\n' >&2
    grep -q 'codexbar-multi' <<<"$candidate_source" || fail 'legacy aggregate basename no longer recognized in candidateList()'
    grep -q 'kodexbar-multi' <<<"$candidate_source" || fail 'bundled aggregate basename not recognized in candidateList()'
    grep -q 'deepseek' <<<"$(extract_function visibleEntries)" || fail 'visibleEntries() no longer hides DeepSeek in the aggregate'
    grep -q 'codex.concat(claude, rest)' <<<"$(extract_function visibleEntries)" || fail 'visibleEntries() no longer orders Claude after Codex'
    grep -q 'pool\[0\]' <<<"$(extract_function keepSelectionValid)" || fail 'keepSelectionValid() no longer snaps to a visible entry'
    grep -q 'function cardsPerRow' "$root/contents/ui/main.qml" || fail 'cardsPerRow() was not found in contents/ui/main.qml'
    grep -q 'function cardsRowCount' "$root/contents/ui/main.qml" || fail 'cardsRowCount() was not found in contents/ui/main.qml'
    grep -q 'function cardsGridHeight' "$root/contents/ui/main.qml" || fail 'cardsGridHeight() was not found in contents/ui/main.qml'
    grep -q 'function cardHeight' "$root/contents/ui/main.qml" || fail 'cardHeight() was not found in contents/ui/main.qml'
    grep -q 'function popupWidthForCards' "$root/contents/ui/main.qml" || fail 'popupWidthForCards() was not found in contents/ui/main.qml'
    grep -q 'function clickEntry' "$root/contents/ui/main.qml" || fail 'clickEntry() was not found in contents/ui/main.qml'
    grep -q 'function pinnedEntry' "$root/contents/ui/main.qml" || fail 'pinnedEntry() was not found in contents/ui/main.qml'
    grep -q 'function clearMissingPin' "$root/contents/ui/main.qml" || fail 'clearMissingPin() was not found in contents/ui/main.qml'
    grep -q 'root.clickEntry(modelData)' "$root/contents/ui/main.qml" || fail 'card clicks no longer pin the compact account'
fi

if "$wrapper" usage --account second >"$tmpdir/selector.out" 2>"$tmpdir/selector.err"; then fail 'no-provider account selector returned success'; fi
assert grep -q 'account selection requires --provider codex' "$tmpdir/selector.err"

: >"$log"
"$wrapper" usage --provider codex >/dev/null
assert grep -q -- "--provider codex --all-accounts" "$log"
: >"$log"
"$wrapper" usage --provider codex --account second >/dev/null
if grep -q -- "--all-accounts" "$log"; then fail 'explicit account selector was overridden'; fi

: >"$log"
"$wrapper" cost --format json --pretty >/dev/null
assert grep -q "^cost --format json --pretty$" "$log"

fake_package_tool=$tmpdir/kpackagetool6
cat >"$fake_package_tool" <<'FAKEPKG'
#!/usr/bin/env bash
if [[ ${1-} == -t && ${3-} == -l ]]; then exit 0; fi
exit 0
FAKEPKG
chmod 755 "$fake_package_tool"

# Install must not overwrite a pre-existing non-identical helper: it preserves the
# user-owned file and warns, while still installing the wrapper.
install_taken=$tmpdir/install-taken
mkdir -p "$install_taken"
printf 'user-owned helper\n' >"$install_taken/nan-cloud-quota"
printf 'user-owned helper\n' >"$tmpdir/expected-helper"
PATH="$tmpdir:$PATH" XDG_BIN_HOME="$install_taken" "$root/install.sh" >"$tmpdir/install-taken.out" 2>"$tmpdir/install-taken.err"
assert cmp -s "$tmpdir/expected-helper" "$install_taken/nan-cloud-quota"
assert grep -q 'preserving unrecognized quota helper' "$tmpdir/install-taken.err"
assert cmp -s "$root/bin/kodexbar-multi" "$install_taken/kodexbar-multi"

# An absent helper target is installed as a byte-for-byte copy of the repository file.
install_fresh=$tmpdir/install-fresh
PATH="$tmpdir:$PATH" XDG_BIN_HOME="$install_fresh" "$root/install.sh" >"$tmpdir/install-fresh.out" 2>"$tmpdir/install-fresh.err"
assert cmp -s "$root/bin/nan-cloud-quota" "$install_fresh/nan-cloud-quota"
assert test -x "$install_fresh/nan-cloud-quota"

protected_dir=$tmpdir/bin
mkdir -p "$protected_dir"
printf 'user-owned command\n' >"$protected_dir/kodexbar-multi"
printf 'user-owned helper\n' >"$protected_dir/nan-cloud-quota"
PATH="$tmpdir:$PATH" XDG_BIN_HOME="$protected_dir" "$root/install.sh" --uninstall >"$tmpdir/uninstall.out" 2>"$tmpdir/uninstall.err"
assert test -f "$protected_dir/kodexbar-multi"
assert test -f "$protected_dir/nan-cloud-quota"
assert grep -q 'preserving unrecognized wrapper' "$tmpdir/uninstall.err"
assert grep -q 'preserving unrecognized quota helper' "$tmpdir/uninstall.err"

printf 'test-wrapper.sh: all tests passed\n'
