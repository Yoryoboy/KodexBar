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
protected_dir=$tmpdir/bin
mkdir -p "$protected_dir"
printf 'user-owned command\n' >"$protected_dir/kodexbar-multi"
PATH="$tmpdir:$PATH" XDG_BIN_HOME="$protected_dir" "$root/install.sh" --uninstall >/dev/null
assert test -f "$protected_dir/kodexbar-multi"

printf 'test-wrapper.sh: all tests passed\n'
