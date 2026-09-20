#!/usr/bin/env bash
# Tests for scripts/install-desktop-entry.sh. Run: bash tests/test-install-desktop-entry.sh
set -uo pipefail
export LC_ALL=C
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="$here/../scripts/install-desktop-entry.sh"

failures=0
check() { # check DESCRIPTION EXPECTED ACTUAL
    if [[ "$2" == "$3" ]]; then
        printf 'ok    %s\n' "$1"
    else
        printf 'FAIL  %s\n      expected: %q\n      actual:   %q\n' "$1" "$2" "$3"
        failures=$((failures + 1))
    fi
}
status() { "$@" >/dev/null 2>&1; echo $?; }

# Everything is written below a throwaway XDG_DATA_HOME, never the real one.
root="$(mktemp -d)"
trap 'rm -rf "$root"' EXIT
export XDG_DATA_HOME="$root/data"
entry="$XDG_DATA_HOME/applications/elgato-4k60-play.desktop"
play="$(cd "$here/../scripts" && pwd)/play.sh"

check "install succeeds"            "0" "$(status bash "$script")"
check "entry exists"                "0" "$(status test -f "$entry")"
check "Exec points at this clone"   "Exec=\"$play\"" "$(grep '^Exec=' "$entry")"
check "no terminal window"          "Terminal=false" "$(grep '^Terminal=' "$entry")"
check "window class matches entry"  "StartupWMClass=elgato-4k60-play" "$(grep '^StartupWMClass=' "$entry")"
if command -v desktop-file-validate >/dev/null; then
    check "desktop-file-validate"   "" "$(desktop-file-validate "$entry" 2>&1)"
fi
check "install twice is fine"       "0" "$(status bash "$script")"
check "unknown argument rejected"   "2" "$(status bash "$script" --bogus)"
check "entry survives a bad call"   "0" "$(status test -f "$entry")"
check "remove succeeds"             "0" "$(status bash "$script" --remove)"
check "entry is gone"               "1" "$(status test -e "$entry")"
check "remove twice is fine"        "0" "$(status bash "$script" --remove)"

echo
if (( failures )); then echo "$failures test(s) failed"; exit 1; fi
echo "all tests passed"
