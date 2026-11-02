#!/usr/bin/env bash
# PreToolUse guard for shell commands, shared by Claude Code and Codex.
# Part of mig-laravel-guardrails: https://github.com/migueltavares/skills
#
# Stops agents from wiping a local Laravel database:
#   1. Blocks migrate:fresh, migrate:refresh, migrate:reset and db:wipe outright,
#      including inside ssh commands.
#   2. Blocks test runs while bootstrap/cache/config.php exists, because a cached
#      config ignores DB_CONNECTION=sqlite and RefreshDatabase then wipes the
#      real database.
#   3. Blocks test runs when phpunit.xml does not point tests at SQLite or a
#      database whose name contains "test", unless the command sets
#      DB_CONNECTION=sqlite itself.
# Hooks run in every permission mode, including full access.

set -u

input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '
  (.tool_input.command // .tool_input.cmd // empty)
  | if type == "array" then join(" ") else . end' 2>/dev/null)
[ -n "$cmd" ] || exit 0
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$cwd" ] || cwd=$PWD

deny() {
    jq -n --arg reason "Blocked by laravel-db-guard.sh (mig-laravel-guardrails): $1" '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: $reason
      }
    }'
    exit 0
}

# 1. Commands that drop every table.
if printf '%s' "$cmd" | grep -Eq 'artisan[^;&|]*[[:space:]](migrate:(fresh|refresh|reset)|db:wipe)([[:space:]]|$|[;&|])'; then
    deny "this command drops every table. Agents never run it. Ask the user to run it themselves if it is really needed."
fi

# 2 and 3 only apply to test runs.
test_run='(artisan[[:space:]]+test|(^|[[:space:]/])(pest|phpunit)([[:space:]]|$)|composer[[:space:]]+(run[[:space:]]+)?test)'
printf '%s' "$cmd" | grep -Eq "$test_run" || exit 0

# Find the Laravel root: a "cd <dir>" at the start of the command, the cwd, or the git top level.
root=""
target=$(printf '%s' "$cmd" | sed -nE 's/^[[:space:]]*cd[[:space:]]+([^;&|[:space:]]+).*/\1/p')
target=${target/#\~/$HOME}
case "$target" in
    "") ;;
    /*) ;;
    *) target="$cwd/$target" ;;
esac
for dir in "$target" "$cwd" "$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)"; do
    [ -n "$dir" ] && [ -f "$dir/artisan" ] && { root=$dir; break; }
done
[ -n "$root" ] || exit 0

if [ -f "$root/bootstrap/cache/config.php" ]; then
    deny "bootstrap/cache/config.php exists, so tests would ignore DB_CONNECTION and run against the real database. Run 'php artisan config:clear' first, then run the tests again."
fi

case "$cmd" in *DB_CONNECTION=sqlite*) exit 0 ;; esac

xml=""
for f in phpunit.xml phpunit.xml.dist; do [ -f "$root/$f" ] && { xml="$root/$f"; break; }; done
if [ -n "$xml" ]; then
    grep -Eq 'name="DB_CONNECTION"[^>]*value="sqlite"' "$xml" && exit 0
    grep -Eq 'name="DB_DATABASE"[^>]*value="[^"]*test[^"]*"' "$xml" && exit 0
fi

deny "${xml:-phpunit.xml} does not point tests at SQLite or a test database, so they could hit the real one. Add <env name=\"DB_CONNECTION\" value=\"sqlite\"/> and <env name=\"DB_DATABASE\" value=\":memory:\"/>, or prefix the command with DB_CONNECTION=sqlite DB_DATABASE=:memory:."
