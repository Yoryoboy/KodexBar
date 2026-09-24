#!/usr/bin/env bash
set -u
set -o pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
bin_dir=${XDG_BIN_HOME:-$HOME/.local/bin}
wrapper_target=$bin_dir/kodexbar-multi
helper_source=$root/bin/nan-cloud-quota
helper_target=$bin_dir/nan-cloud-quota
package_id=org.kde.plasma.kodexbar

usage() {
    printf 'Usage: %s [--uninstall]\n' "${0##*/}"
}

need_command() {
    command -v "$1" >/dev/null 2>&1 || {
        printf 'install.sh: required command not found: %s\n' "$1" >&2
        exit 1
    }
}

validate_upstream() {
    local configured=${KODEXBAR_CODEXBAR_COMMAND-} candidate
    if [[ -n $configured ]]; then
        if [[ $configured == */* ]]; then
            candidate=$configured
        else
            candidate=$(command -v -- "$configured" 2>/dev/null || true)
        fi
        [[ -n ${candidate:-} && -x $candidate ]] || {
            printf 'install.sh: KODEXBAR_CODEXBAR_COMMAND is not an executable: %s\n' "$configured" >&2
            exit 1
        }
        return
    fi
    candidate=$(command -v codexbar 2>/dev/null || true)
    [[ -n $candidate && -x $candidate ]] || candidate=${XDG_BIN_HOME:-$HOME/.local/bin}/codexbar
    [[ -x $candidate ]] || {
        printf 'install.sh: upstream codexbar CLI not found; install it or set KODEXBAR_CODEXBAR_COMMAND\n' >&2
        exit 1
    }
}

if [[ ${1-} == --uninstall ]]; then
    need_command kpackagetool6
    if kpackagetool6 -t Plasma/Applet -l 2>/dev/null | grep -Fqx "$package_id"; then
        kpackagetool6 -t Plasma/Applet -r "$package_id"
    else
        printf 'Applet not installed: %s\n' "$package_id"
    fi
    if [[ -f $wrapper_target && ! -L $wrapper_target ]] && grep -Fqx '# KODEXBAR_MULTI_BUNDLED_WRAPPER v1' "$wrapper_target"; then
        rm -f -- "$wrapper_target"
        printf 'Removed wrapper: %s\n' "$wrapper_target"
    elif [[ -e $wrapper_target || -L $wrapper_target ]]; then
        printf 'Warning: preserving unrecognized wrapper: %s\n' "$wrapper_target" >&2
    else
        printf 'Wrapper not installed: %s\n' "$wrapper_target"
    fi
    # The quota helper carries no marker line, so it is recognized by being a
    # byte-for-byte copy of the repository file. Anything else -- a user-owned
    # script, a symlink, or an edited helper -- is preserved untouched.
    if [[ -f $helper_target && ! -L $helper_target ]] && cmp -s "$helper_source" "$helper_target"; then
        rm -f -- "$helper_target"
        printf 'Removed quota helper: %s\n' "$helper_target"
    elif [[ -e $helper_target || -L $helper_target ]]; then
        printf 'Warning: preserving unrecognized quota helper: %s\n' "$helper_target" >&2
    else
        printf 'Quota helper not installed: %s\n' "$helper_target"
    fi
    printf 'CodexBar credentials and custom commands were not changed.\n'
    exit 0
fi
if [[ $# -ne 0 ]]; then usage >&2; exit 2; fi

need_command bash
need_command jq
need_command kpackagetool6
validate_upstream
bash -n "$root/bin/kodexbar-multi" || exit 1

mkdir -p -- "$bin_dir"
tmp_wrapper=$(mktemp "$bin_dir/.kodexbar-multi.XXXXXX") || {
    printf 'install.sh: unable to create temporary wrapper in %s\n' "$bin_dir" >&2
    exit 1
}
trap 'rm -f -- "$tmp_wrapper"' EXIT HUP INT TERM
cp -- "$root/bin/kodexbar-multi" "$tmp_wrapper"
chmod 0755 "$tmp_wrapper"

if [[ -e $wrapper_target || -L $wrapper_target ]]; then
    if cmp -s "$tmp_wrapper" "$wrapper_target"; then
        printf 'Wrapper already current: %s\n' "$wrapper_target"
        rm -f -- "$tmp_wrapper"
        trap - EXIT HUP INT TERM
    else
        backup=$wrapper_target.backup.$(date +%Y%m%d%H%M%S)
        cp -p -- "$wrapper_target" "$backup"
        printf 'Backed up existing wrapper: %s\n' "$backup"
        mv -f -- "$tmp_wrapper" "$wrapper_target"
        trap - EXIT HUP INT TERM
    fi
else
    mv -f -- "$tmp_wrapper" "$wrapper_target"
    trap - EXIT HUP INT TERM
fi

# Install the optional NaN cloud quota helper beside the wrapper. The helper is
# installed only when the target is absent or already byte-identical; a
# pre-existing user-owned or edited helper is preserved untouched with a warning
# rather than overwritten. A missing python3 or `cryptography` does not fail the
# install: the wrapper falls back to the nan CLI, and the helper itself fails
# closed at runtime.
tmp_helper=$(mktemp "$bin_dir/.nan-cloud-quota.XXXXXX") || {
    printf 'install.sh: unable to create temporary quota helper in %s\n' "$bin_dir" >&2
    exit 1
}
trap 'rm -f -- "$tmp_helper"' EXIT HUP INT TERM
cp -- "$helper_source" "$tmp_helper"
chmod 0755 "$tmp_helper"

if [[ -e $helper_target || -L $helper_target ]]; then
    if cmp -s "$tmp_helper" "$helper_target"; then
        printf 'Quota helper already current: %s\n' "$helper_target"
    else
        printf 'Warning: preserving unrecognized quota helper: %s\n' "$helper_target" >&2
    fi
    rm -f -- "$tmp_helper"
    trap - EXIT HUP INT TERM
else
    mv -f -- "$tmp_helper" "$helper_target"
    trap - EXIT HUP INT TERM
fi

if ! command -v python3 >/dev/null 2>&1; then
    printf 'Warning: python3 not found; NaN cloud quota will be skipped and the wrapper falls back to the nan CLI.\n' >&2
fi
if ! command -v kwallet-query >/dev/null 2>&1; then
    printf 'Note: kwallet-query not found; NaN cloud quota needs an unlocked KDE KWallet holding "Chrome Safe Storage".\n' >&2
fi

if kpackagetool6 -t Plasma/Applet -l 2>/dev/null | grep -Fqx "$package_id"; then
    kpackagetool6 -t Plasma/Applet -u "$root"
    package_action=upgraded
else
    kpackagetool6 -t Plasma/Applet -i "$root"
    package_action=installed
fi

printf '\nKodexBar %s.\n' "$package_action"
printf 'Wrapper: %s\nQuota helper: %s\nApplet source: %s\n' "$wrapper_target" "$helper_target" "$root"
printf 'Add KodexBar to a Plasma panel, then refresh the widget. Existing widget settings are preserved.\n'
printf 'No Plasma restart or applet configuration-file edits were made.\n'
