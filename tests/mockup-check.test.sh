#!/usr/bin/env bash
# Tests for skills/mig-mockup/scripts/check.mjs argument handling. They stop
# before Chrome starts, so they need Node 22 or later and no browser.
#
# Usage: bash tests/mockup-check.test.sh

set -u

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$repo/skills/mig-mockup/scripts/check.mjs"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

pass=0 fail=0
check() {
    local label=$1 expected=$2 actual=$3
    if [ "$expected" = "$actual" ]; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        echo "FAIL: $label (expected $expected, got $actual)"
        sed 's/^/    /' "$tmp/out"
    fi
}
run() { (cd "$tmp" && node "$script" "$@") >"$tmp/out" 2>&1; echo $?; }
has() { grep -q -- "$1" "$tmp/out" && echo yes || echo no; }

check "no input exits 2" 2 "$(run)"
check "two states on one path refused" 2 "$(run 'https://a.test/list?s=1' 'https://a.test/list?s=2')"
check "refusal names the clash" yes "$(has 'Two pages would save as before-a.test-list')"
check "duplicate --page names refused" 2 "$(run --page x=https://a.test/1 --page x=https://a.test/2)"
check "--page needs name=URL" 2 "$(run --page broken)"
check "--page needs an http URL" 2 "$(run --page x=file.html)"
check "nothing written before a refusal" no "$([ -d "$tmp/shots" ] && echo yes || echo no)"

echo "mockup check: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
