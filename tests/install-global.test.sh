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

# With the mig-skills plugin enabled, the plugin's hook covers Claude Code.
rm -rf "$tmp/.claude" "$tmp/.codex"; mkdir -p "$tmp/.claude" "$tmp/.codex/rules"
echo '{"enabledPlugins": {"mig-skills@mig": true}}' > "$tmp/.claude/settings.json"
check "plugin: install succeeds" 0 "$(run)"
check "plugin: no second claude hook" null "$(hook_command "$tmp/.claude/settings.json")"
check "plugin: deny rules still added" 4 "$(jq '[.permissions.deny[] | select(contains("artisan"))] | length' "$tmp/.claude/settings.json")"
check "plugin: check passes" 0 "$(run --check)"
grep -q '^OK *claude hook comes from the mig-skills plugin' "$tmp/out"
check "plugin: check names the plugin" 0 $?
jq --arg g "$guard" '.hooks.PreToolUse += [{"matcher": "Bash", "hooks": [{"type": "command", "command": $g}]}]' \
    "$tmp/.claude/settings.json" > "$tmp/s.json" && mv "$tmp/s.json" "$tmp/.claude/settings.json"
run --check >/dev/null
grep -q '^NOTE *claude hook .* second time' "$tmp/out"
check "plugin: duplicate hook reported" 0 $?

# --check changes nothing, not even the guard's execute bit.
mkdir -p "$tmp/copy"
cp "$repo/skills/mig-laravel-guardrails/scripts/"*.sh "$tmp/copy/"
chmod -x "$tmp/copy/laravel-db-guard.sh"
HOME="$tmp" CODEX_HOME="$tmp/.codex" bash "$tmp/copy/install-global.sh" --check >"$tmp/out" 2>&1
check "check fails on a guard that can't run" 1 $?
check "check leaves the execute bit alone" no "$([ -x "$tmp/copy/laravel-db-guard.sh" ] && echo yes || echo no)"

echo "install-global: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
