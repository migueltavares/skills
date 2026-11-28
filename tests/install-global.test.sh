#!/usr/bin/env bash
# Tests for skills/mig-laravel-guardrails/scripts/install-global.sh.
# Runs entirely inside a temp HOME directory so real configs are untouched.
#
# Usage: bash tests/install-global.test.sh

set -u

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$repo/skills/mig-laravel-guardrails/scripts/install-global.sh"
guard="$repo/skills/mig-laravel-guardrails/scripts/laravel-db-guard.sh"
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
    fi
}

run() { HOME="$tmp" CODEX_HOME="$tmp/.codex" bash "$script" "$@" >"$tmp/out" 2>&1; echo $?; }
hook_command() { jq -r '[.hooks.PreToolUse[].hooks[].command | select(endswith("laravel-db-guard.sh"))][0]' "$1"; }

mkdir -p "$tmp/.claude" "$tmp/.codex/rules"

# A fresh machine: check fails, install adds, check passes.
check "fresh check fails" 1 "$(run --check)"
check "install succeeds" 0 "$(run)"
check "check passes after install" 0 "$(run --check)"
check "claude hook runs the skill's guard" "$guard" "$(hook_command "$tmp/.claude/settings.json")"

# A hook that runs an older copy of the guard is reported, then repointed.
mkdir -p "$tmp/.claude/hooks"
echo '#!/usr/bin/env bash' > "$tmp/.claude/hooks/laravel-db-guard.sh"
for f in "$tmp/.claude/settings.json" "$tmp/.codex/hooks.json"; do
    jq --arg old "$tmp/.claude/hooks/laravel-db-guard.sh" \
        '(.hooks.PreToolUse[].hooks[] | select(.command | endswith("laravel-db-guard.sh"))).command = $old' \
        "$f" > "$f.new" && mv "$f.new" "$f"
done
check "stale copy fails check" 1 "$(run --check)"
grep -q 'runs .*/.claude/hooks/laravel-db-guard.sh' "$tmp/out"
check "check names the stale copy" 0 $?
check "install repoints stale hooks" 0 "$(run)"
grep -q '^UPDATED' "$tmp/out"
check "install reports UPDATED" 0 $?
check "claude hook repointed" "$guard" "$(hook_command "$tmp/.claude/settings.json")"
check "codex hook repointed" "$guard" "$(hook_command "$tmp/.codex/hooks.json")"
check "check passes after repoint" 0 "$(run --check)"

echo "install-global: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
