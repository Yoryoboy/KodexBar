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
assert_json 'length == 4 and any(.[]; .provider == "codex" and .activity.lastActivityAt == "2025-01-02T03:04:05Z") and any(.[]; .provider == "opencodego" and .activity.lastActivityAt == "2025-01-04T03:04:05Z") and any(.[]; .provider == "deepseek")' "$out"
assert_json '.[] | select(.provider == "deepseek") | .credits | .remaining == 2.05 and .paidBalance == 2.05 and .grantedBalance == 0 and .currencyCode == "USD"' "$out"

export KODEXBAR_NAN_COMMAND=$fake_nan
unset FAKE_NAN_MODE
out=$("$wrapper" usage --format json --json-only)
assert_json 'length == 5 and any(.[]; .provider == "nan" and .source == "cli" and .account == "nan@example.com" and .usage.updatedAt == "2026-09-21T16:11:42Z" and .usage.nan.monthToDate.totalTokens == 930278 and .usage.nan.last30d.totalTokens == 930278)' "$out"
assert_json '.[] | select(.provider == "nan") | .usage.nan.monthToDate.byModel[0].model == "deepseek-v4-flash" and .usage.nan.monthToDate.byModel[0].inputTokens == 690429 and .usage.nan.monthToDate.byModel[0].outputTokens == 10442' "$out"
# The aggregate contract pins the provider order end to end: the Codex accounts
# first, then NaN, then OpenCode Go, then DeepSeek. Asserting the exact ordered
# provider sequence (not just membership) fails if the order regresses.
assert_json 'map(.provider) == ["codex", "codex", "nan", "opencodego", "deepseek"]' "$out"
export FAKE_NAN_MODE=me-fail
out=$("$wrapper" usage --format json --json-only)
assert_json 'length == 5 and any(.[]; .provider == "nan" and (.account == null) and .usage.nan.monthToDate.totalTokens == 930278)' "$out"
unset FAKE_NAN_MODE

# A failed, invalid, or missing NaN binary is silent; the other providers still aggregate.
export KODEXBAR_NAN_COMMAND=$tmpdir/missing-nan
out=$("$wrapper" usage --format json --json-only)
assert_json 'length == 4 and all(.[]; .provider != "nan")' "$out"
export KODEXBAR_NAN_COMMAND=$fake_nan
export FAKE_NAN_MODE=metrics-fail
out=$("$wrapper" usage --format json --json-only)
assert_json 'length == 4 and all(.[]; .provider != "nan")' "$out"
export FAKE_NAN_MODE=metrics-invalid
out=$("$wrapper" usage --format json --json-only)
assert_json 'length == 4 and all(.[]; .provider != "nan")' "$out"
# A transient first `metrics usage` failure is recovered by the single retry.
export FAKE_NAN_MODE=metrics-flaky
: >"$nan_counter"
out=$("$wrapper" usage --format json --json-only)
assert_json 'length == 5 and any(.[]; .provider == "nan" and .account == "nan@example.com" and .usage.nan.monthToDate.totalTokens == 930278)' "$out"
assert grep -q '^2$' "$nan_counter"
unset FAKE_NAN_MODE
export KODEXBAR_NAN_COMMAND=$tmpdir/no-nan

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
assert_json 'length == 5 and (map(.provider) == ["codex", "codex", "nan", "opencodego", "deepseek"])' "$out"
assert_json '.[] | select(.provider == "nan") | .source == "cloud" and .account == "nan@example.com" and (.usage.nan == null) and .usage.updatedAt == "2026-09-21T16:11:42Z" and .usage.nanQuota.models[0].model == "deepseek-v4-flash" and .usage.nanQuota.models[0].tokensUsed == 125000 and .usage.nanQuota.models[0].cap == 500000 and .usage.nanQuota.models[0].remaining == 375000 and .usage.nanQuota.models[0].windowHours == 24 and .usage.nanQuota.models[0].periodEnd == "2026-10-01T00:00:00Z"' "$out"

# Cloud quota still appears when no nan CLI exists: the helper owns the Chrome session read.
export KODEXBAR_NAN_COMMAND=$tmpdir/missing-nan
out=$("$wrapper" usage --format json --json-only)
assert_json 'length == 5 and any(.[]; .provider == "nan" and .source == "cloud" and (.account == null))' "$out"
export KODEXBAR_NAN_COMMAND=$fake_nan

# Any helper failure preserves the CLI metrics fallback.
export FAKE_QUOTA_MODE=fail
out=$("$wrapper" usage --format json --json-only)
assert_json 'length == 5 and any(.[]; .provider == "nan" and .source == "cli" and .usage.nan.monthToDate.totalTokens == 930278)' "$out"
export FAKE_QUOTA_MODE=invalid
out=$("$wrapper" usage --format json --json-only)
assert_json 'length == 5 and any(.[]; .provider == "nan" and .source == "cli")' "$out"
# A structurally valid envelope with a malformed model must not win the cloud
# branch and leave blank popup rows: each case falls back to CLI metrics.
export FAKE_QUOTA_MODE=malformed-model
out=$("$wrapper" usage --format json --json-only)
assert_json 'length == 5 and any(.[]; .provider == "nan" and .source == "cli") and all(.[]; (.provider != "nan") or (.usage.nanQuota == null))' "$out"
export FAKE_QUOTA_MODE=malformed-model-fields
out=$("$wrapper" usage --format json --json-only)
assert_json 'length == 5 and any(.[]; .provider == "nan" and .source == "cli")' "$out"
export FAKE_QUOTA_MODE=malformed-optional
out=$("$wrapper" usage --format json --json-only)
assert_json 'length == 5 and any(.[]; .provider == "nan" and .source == "cli")' "$out"
export FAKE_QUOTA_MODE=empty-models
out=$("$wrapper" usage --format json --json-only)
assert_json 'length == 5 and any(.[]; .provider == "nan" and .source == "cli")' "$out"
unset FAKE_QUOTA_MODE

# A missing helper target also falls back to the CLI.
export KODEXBAR_NAN_QUOTA_COMMAND=$tmpdir/missing-quota-helper
out=$("$wrapper" usage --format json --json-only)
assert_json 'length == 5 and any(.[]; .provider == "nan" and .source == "cli")' "$out"

# Resolution without an override: the copy installed next to the wrapper wins.
sibling_dir=$tmpdir/sibling/bin
mkdir -p "$sibling_dir"
cp "$wrapper" "$sibling_dir/kodexbar-multi"
cp "$fake_quota" "$sibling_dir/nan-cloud-quota"
out=$(env -u KODEXBAR_NAN_QUOTA_COMMAND KODEXBAR_NAN_COMMAND="$fake_nan" "$sibling_dir/kodexbar-multi" usage --format json --json-only)
assert_json 'length == 5 and any(.[]; .provider == "nan" and .source == "cloud")' "$out"

# With no sibling, the ${XDG_BIN_HOME:-~/.local/bin} install path is used.
installed_dir=$tmpdir/installed/bin
installed_home=$tmpdir/installed-home
mkdir -p "$installed_dir" "$installed_home"
cp "$wrapper" "$installed_dir/kodexbar-multi"
cp "$fake_quota" "$installed_home/nan-cloud-quota"
out=$(env -u KODEXBAR_NAN_QUOTA_COMMAND XDG_BIN_HOME="$installed_home" HOME="$tmpdir/empty-home" KODEXBAR_NAN_COMMAND="$fake_nan" "$installed_dir/kodexbar-multi" usage --format json --json-only)
assert_json 'length == 5 and any(.[]; .provider == "nan" and .source == "cloud")' "$out"
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
assert_json 'length == 5 and all(.[]; (.provider != "opencodego" or .activity == null))' "$out"
unset FAKE_MODE

export FAKE_MODE=unmatched
out=$("$wrapper" usage --format json --json-only)
assert_json 'any(.[]; .provider == "deepseek" and .credits.description == "Balance unavailable" and .extra == "preserve")' "$out"

export FAKE_MODE=normal
: >"$log"
export FAKE_MODE=partial
out=$("$wrapper" usage --format json --json-only)
assert_json 'length == 3 and all(.[]; .provider != "opencodego")' "$out"

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
if "$wrapper" usage --format json --json-only >"$tmpdir/all.out" 2>"$tmpdir/all.err"; then fail 'all-provider failure returned success'; fi
assert grep -q "all provider usage queries failed" "$tmpdir/all.err"
unset FAKE_MODE
export XDG_DATA_HOME=$tmpdir/missing-data
out=$("$wrapper" usage --format json --json-only)
assert_json 'all(.[]; (.activity == null) or (.provider != "opencodego"))' "$out"
unset KODEXBAR_CODEX_ACCOUNT_HOMES XDG_DATA_HOME

assert grep -q 'function codexAccountKey' "$root/contents/ui/main.qml"
assert grep -q 'keys.sort()' "$root/contents/ui/main.qml"
assert grep -q 'entry.creditsRemaining > 0' "$root/contents/ui/main.qml"

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
else
    printf 'WARN: qmltestrunner unavailable; candidateList regression fell back to structural checks\n' >&2
    grep -q 'codexbar-multi' <<<"$candidate_source" || fail 'legacy aggregate basename no longer recognized in candidateList()'
    grep -q 'kodexbar-multi' <<<"$candidate_source" || fail 'bundled aggregate basename not recognized in candidateList()'
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
