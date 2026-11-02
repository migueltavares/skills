#!/usr/bin/env bash
# Installs, or checks, the machine part of mig-laravel-guardrails:
#   - laravel-db-guard.sh as a PreToolUse hook in Claude Code and Codex
#   - Claude Code deny rules for the commands that drop every table
#   - a Codex "forbidden" rule for the same commands
#
# Usage: install-global.sh [--check]
#   --check  report what is installed and exit 1 if anything is missing.
# Every file it changes is backed up first as <file>.bak-<timestamp>.

set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
guard="$here/laravel-db-guard.sh"
check=false
[ "${1:-}" = "--check" ] && check=true

for tool in jq python3; do
    command -v "$tool" >/dev/null || { echo "MISSING $tool: install it first, the guard needs it." >&2; exit 1; }
done
chmod +x "$guard"

claude_settings="$HOME/.claude/settings.json"
codex_dir="$HOME/.codex"
codex_hooks="$codex_dir/hooks.json"
codex_rules="$codex_dir/rules/default.rules"
codex_rule='prefix_rule(pattern=["php", "artisan", ["migrate:fresh", "migrate:refresh", "migrate:reset", "db:wipe"]], decision="forbidden", justification="Drops every table. Ask the user to run it themselves.")'
stamp=$(date +%Y%m%d-%H%M%S)
missing=0

backup() { [ -f "$1" ] && cp "$1" "$1.bak-$stamp"; return 0; }
report() { printf '%-8s %s\n' "$1" "$2"; [ "$1" = "MISSING" ] && missing=1; return 0; }

# JSON edits go through python3 so existing settings keep their structure.
# $1 file, $2 "claude" or "codex", $3 "check" or "install". Prints OK, MISSING or ADDED lines.
edit_json() {
    python3 - "$1" "$2" "$3" "$guard" <<'PY'
import json, os, sys
path, host, mode, guard = sys.argv[1:5]
data = {}
if os.path.exists(path):
    with open(path) as f:
        text = f.read().strip()
        data = json.loads(text) if text else {}
pre = data.setdefault("hooks", {}).setdefault("PreToolUse", [])
has_hook = any(h.get("command", "").endswith("laravel-db-guard.sh")
               for entry in pre for h in entry.get("hooks", []))
changed = False
if has_hook:
    print(f"OK       {host} hook in {path}")
elif mode == "check":
    print(f"MISSING  {host} hook in {path}")
else:
    entry = {"hooks": [{"type": "command", "command": guard, "timeout": 10}]}
    if host == "claude":
        entry = {"matcher": "Bash", **entry}
    pre.append(entry)
    changed = True
    print(f"ADDED    {host} hook in {path}")
if host == "claude":
    deny = data.setdefault("permissions", {}).setdefault("deny", [])
    rules = ["Bash(*artisan migrate:fresh*)", "Bash(*artisan migrate:refresh*)",
             "Bash(*artisan migrate:reset*)", "Bash(*artisan db:wipe*)"]
    absent = [r for r in rules if r not in deny]
    if not absent:
        print(f"OK       claude deny rules in {path}")
    elif mode == "check":
        print(f"MISSING  claude deny rules in {path}: {', '.join(absent)}")
    else:
        deny.extend(absent)
        changed = True
        print(f"ADDED    claude deny rules in {path}")
if changed:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")
PY
}

run_json() {
    local file=$1 host=$2 mode=check status rest
    if ! $check && edit_json "$file" "$host" check | grep -q '^MISSING'; then
        backup "$file"
        mode=install
    fi
    while read -r status rest; do
        report "$status" "$rest"
    done < <(edit_json "$file" "$host" "$mode")
}

run_json "$claude_settings" claude

if [ -d "$codex_dir" ]; then
    run_json "$codex_hooks" codex
    if [ -f "$codex_rules" ] && grep -Fq 'migrate:fresh' "$codex_rules" && grep -Fq 'forbidden' "$codex_rules"; then
        report OK "codex forbidden rule in $codex_rules"
    elif $check; then
        report MISSING "codex forbidden rule in $codex_rules"
    else
        mkdir -p "$(dirname "$codex_rules")"
        backup "$codex_rules"
        printf '%s\n' "$codex_rule" >> "$codex_rules"
        report ADDED "codex forbidden rule in $codex_rules"
    fi
else
    report SKIPPED "Codex is not installed (no $codex_dir)"
fi

if ! $check; then
    echo
    echo "Codex asks you to trust a new hook the next time it starts. Approve it."
fi
exit $missing
