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
if [[ $* == *"--provider codex"* ]]; then cat "$FAKE_FIXTURES/codex.json"
elif [[ $* == *"--provider opencodego"* ]]; then cat "$FAKE_FIXTURES/opencodego.json"
elif [[ $* == *"--provider deepseek"* ]]; then
    if [[ ${FAKE_MODE:-normal} == unmatched ]]; then cat "$FAKE_FIXTURES/deepseek-unmatched.json"; else cat "$FAKE_FIXTURES/deepseek.json"; fi
elif [[ $1 == cost ]]; then printf '{"provider":"codex","totals":{"totalCost":1}}\n'
else printf '{"provider":"custom"}\n'; fi
FAKE
chmod 755 "$fake"
export FAKE_LOG=$log FAKE_FIXTURES=$fixtures KODEXBAR_CODEXBAR_COMMAND=$fake

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
assert() { "$@" || fail "$*"; }
assert_json() { jq -e "$1" >/dev/null <<<"$2" || fail "jq $1"; }

out=$("$wrapper" usage --format json --json-only)
assert_json 'length == 3 and any(.[]; .provider == "codex") and any(.[]; .provider == "opencodego") and any(.[]; .provider == "deepseek")' "$out"
assert_json '.[] | select(.provider == "deepseek") | .credits | .remaining == 2.05 and .paidBalance == 2.05 and .grantedBalance == 0 and .currencyCode == "USD"' "$out"

export FAKE_MODE=unmatched
out=$("$wrapper" usage --format json --json-only)
assert_json 'any(.[]; .provider == "deepseek" and .credits.description == "Balance unavailable" and .extra == "preserve")' "$out"

export FAKE_MODE=normal
: >"$log"
export FAKE_MODE=partial
out=$("$wrapper" usage --format json --json-only)
assert_json 'length == 2 and all(.[]; .provider != "opencodego")' "$out"

FAKE_MODE=fail-all
if "$wrapper" usage --format json --json-only >"$tmpdir/all.out" 2>"$tmpdir/all.err"; then fail 'all-provider failure returned success'; fi
assert grep -q "all provider usage queries failed" "$tmpdir/all.err"
unset FAKE_MODE

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
