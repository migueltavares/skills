#!/usr/bin/env bash
# PreToolUse guard for shell commands, shared by Claude Code and Codex.
# Part of mig-laravel-guardrails: https://github.com/migueltavares/skills
#
# Stops agents from wiping a local Laravel database:
#   1. Blocks migrate:fresh, migrate:refresh, migrate:reset and db:wipe, in any
#      form artisan accepts: quoted, split across lines, abbreviated
#      (migrate:fr), inside ssh commands, or through Artisan::call in tinker.
#   2. Blocks test runs while bootstrap/cache/config.php exists, because a cached
#      config ignores phpunit.xml and the environment. Also blocks a test run in
#      the same command as config:cache or optimize, which create that file
#      after this check has looked.
#   3. Blocks test runs unless the database is SQLite in memory or a database
#      whose name contains "test": set by phpunit.xml (read as XML, so
#      commented-out lines don't count) or by environment assignments directly
#      in front of the test command. An assignment wins over phpunit.xml, a
#      DB_URL assignment is refused, and a run that picks its own PHPUnit
#      configuration (-c, --no-configuration) needs safe assignments.
# Test runs outside a Laravel app (no artisan file found) are left alone.
# Hooks run in every permission mode, including full access.

set -u

input=$(cat)
cmd="" cwd=""
if command -v jq >/dev/null 2>&1 \
    && cmd=$(printf '%s' "$input" | jq -r '
         (.tool_input.command // .tool_input.cmd // empty)
         | if type == "array" then join(" ") else . end' 2>/dev/null); then
    [ -n "$cmd" ] || exit 0   # not a shell command
    # Codex runs this hook for every tool, and its file edits carry a command too.
    case $(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null) in
        apply_patch|Edit|Write|MultiEdit) exit 0 ;;
    esac
    cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
else
    # Without jq, or with input jq cannot read, check the raw input so the
    # destructive-command rule still applies. JSON escapes for line breaks and
    # tabs become spaces, as they would in the decoded command.
    cmd=$(printf '%s' "$input" | sed -E 's/\\[nrt]/ /g')
fi
[ -n "$cwd" ] || cwd=$PWD

deny() {
    # Escape the reason for JSON: it can hold a path, and a path can hold anything.
    local reason=${1//\\/\\\\}
    reason=${reason//\"/\\\"}
    reason=${reason//[[:cntrl:]]/ }
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Blocked by laravel-db-guard.sh (mig-laravel-guardrails): %s"}}\n' "$reason"
    exit 0
}

# One line, no quotes or backslashes: what the shell would run, as plain words.
norm=$(printf '%s' "$cmd" | tr '\n\r\t' '   ' | tr -d "\"'\\\\")

# 1. Commands that drop every table. Artisan accepts unique abbreviations, so
#    match the prefixes too: mi*:f* is migrate:fresh, mi*:ref* migrate:refresh,
#    mi*:res* migrate:reset, db:w* db:wipe.
if printf '%s' "$norm" | grep -Eiq 'artisan[^;&|]*[[:space:](,]+(mi[a-z]*:(f|ref|res)[a-z]*|db:w[a-z]*)([^a-z:]|$)'; then
    deny "this command drops every table. Agents never run it. Ask the user to run it themselves if it is really needed."
fi

# 2 and 3 only apply to test runs.
test_cmd='(php[[:space:]]+)?([^;&|[:space:]]*/)?(artisan[[:space:]]+test|pest|phpunit)([[:space:]]|$)|composer[[:space:]]+(run[[:space:]]+)?test'
# Brackets, braces, backticks, $ and the separators ; & | count as spaces
# here, so a test run in a subshell or a command substitution is found, and
# so is one with a separator right after it.
printf '%s' "$norm" | tr '(){}`$;&|' '         ' | grep -Eq "(^|[;&|[:space:]])($test_cmd)" || exit 0

# Find the Laravel root: a "cd <dir>" at the start of the command, the cwd, or the git top level.
root=""
target=$(printf '%s' "$norm" | sed -nE 's/^[[:space:]]*cd[[:space:]]+([^;&|[:space:]]+).*/\1/p')
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
    deny "bootstrap/cache/config.php exists, so tests would ignore phpunit.xml and run against the real database. Run php artisan config:clear first, then run the tests again."
fi

# The cache file can also appear during the command itself. Artisan accepts
# abbreviations, so co*:ca* is config:cache. optimize caches the config too;
# optimize:clear does not.
# Same separators as rule 1, so Artisan::call(config:cache) in tinker counts.
if printf '%s' "$norm" | grep -Eiq 'artisan[^;&|]*[[:space:](,]+(co[a-z]*:ca[a-z]*|optimize)([^a-z:]|$)'; then
    deny "this command caches the config and runs tests, so the tests would ignore phpunit.xml and run against the real database. Run the tests in a separate command, after php artisan config:clear."
fi

# A safe pair of values: SQLite in memory, or any database named for testing.
safe_pair() { # $1 connection, $2 database
    [ "$1" = sqlite ] && [ "$2" = ":memory:" ] && return 0
    case "$2" in *test*) return 0 ;; esac
    return 1
}

# 3a. phpunit.xml, parsed as XML so comments don't count. Only the <env> and
#     <server> entries directly inside <php> apply, as in PHPUnit. A name set
#     twice with different values counts as unsafe.
xml="" xml_conn="" xml_db=""
for f in phpunit.xml phpunit.xml.dist; do [ -f "$root/$f" ] && { xml="$root/$f"; break; }; done
if [ -n "$xml" ] && command -v python3 >/dev/null 2>&1; then
    pair=$(python3 -I - "$xml" <<'PY' 2>/dev/null
import sys
import xml.etree.ElementTree as ET
try:
    text = open(sys.argv[1], encoding="utf-8").read()
    if "<!ENTITY" in text:
        sys.exit(0)  # phpunit.xml never needs entities; treat the file as unsafe
    tree = ET.ElementTree(ET.fromstring(text))
except Exception:
    sys.exit(0)
values = {}
for el in (child for php in tree.getroot().findall("php") for child in php):
    name = el.get("name")
    if el.tag in ("env", "server") and name in ("DB_CONNECTION", "DB_DATABASE"):
        value = el.get("value", "")
        if values.get(name, value) != value:
            sys.exit(0)  # conflicting values: treat the file as unsafe
        values[name] = value
print(values.get("DB_CONNECTION", ""), values.get("DB_DATABASE", ""))
PY
)
    xml_conn=${pair%% *} xml_db=${pair#* }
fi

# 3b. Each test command, with the environment assignments directly in front
#     of it. Split the command on ; & | and line breaks. In every part that
#     runs tests, find the first test command and walk back over the words
#     before it. Walking back, the first value seen is the rightmost
#     one, which is the one the shell uses, even when it is empty.
#     - An assignment wins over phpunit.xml, because PHPUnit keeps a variable
#       that is already set. So the pair checked is the assigned value where
#       there is one, and the phpunit.xml value otherwise.
#     - Every assignment before the test command in its part counts, not only
#       an unbroken run of them, so "env", "php -d x=y" or a quoted value with
#       a space cannot hide one.
#     - An earlier "export VAR=value" or bare "VAR=value" part can make a run
#       unsafe, and never makes it safe: the guard cannot tell whether that
#       part ran, in which shell, or whether an unset followed it.
#     - "env" with options (-u, -i) can drop the assignments in front of it,
#       so phpunit.xml must be safe as well.
#     - Brackets, braces, backticks and $ also split the command, so a test
#       run inside a subshell or a command substitution is checked by itself.
#       A database variable set from a substitution or another variable is
#       refused, since its value cannot be read here.
#     - A DB_URL or DATABASE_URL assignment is refused: Laravel reads the
#       database from it.
#     - -c, --configuration and --no-configuration after the test command make
#       PHPUnit skip the file read above, so only the assignments count.
#     - A backslash before a line break may or may not continue the line. Such
#       commands are read as continued, and phpunit.xml must be safe as well.
trusted=true joined=$cmd
case "$cmd" in *$'\\\n'*) trusted=false; joined=${cmd//$'\\\n'/ } ;; esac
start_re="^($test_cmd)"
assign_re='^[A-Za-z_][A-Za-z0-9_]*='
config_re='(^|[[:space:]])(-c[^[:space:]]*|--conf[a-z-]*|--no-conf[a-z-]*)([[:space:]=]|$)'
computed_re='(^|[^A-Za-z0-9_])(DB_CONNECTION|DB_DATABASE|DB_URL|DATABASE_URL)=[$`]'
if [[ $norm =~ $computed_re ]]; then
    deny "the command sets a database variable from a substitution or another variable, so the guard cannot read its value. Write the value out, or use DB_CONNECTION=sqlite DB_DATABASE=:memory:."
fi
checked=0
kept_conn="" kept_db="" kept_url="" kept_durl=""
kept_conn_set=false kept_db_set=false
while IFS= read -r seg; do
    read -ra words <<< "$seg"
    start=-1
    for (( i = 0; i < ${#words[@]}; i++ )); do
        # An assignment is never the command, even when its value looks like one.
        [[ ${words[i]} =~ $assign_re ]] && continue
        rest="${words[*]:i}"
        [[ $rest =~ $start_re ]] && { start=$i; break; }
    done
    if [ "$start" -lt 0 ]; then
        # An export, or a part made only of assignments, may stay set for
        # later parts. A quoted value with a space splits into extra words, so
        # an export keeps every assignment it holds.
        keeps=true
        if [ "${words[0]:-}" != export ]; then
            for (( i = 0; i < ${#words[@]}; i++ )); do
                [[ ${words[i]} =~ $assign_re ]] || { keeps=false; break; }
            done
        fi
        $keeps && for (( i = 0; i < ${#words[@]}; i++ )); do
            w=${words[i]}
            case $w in
                DB_CONNECTION=*) kept_conn=${w#*=} kept_conn_set=true ;;
                DB_DATABASE=*) kept_db=${w#*=} kept_db_set=true ;;
                DB_URL=*) kept_url=${w#*=} ;;
                DATABASE_URL=*) kept_durl=${w#*=} ;;
            esac
        done
        continue
    fi
    checked=$(( checked + 1 ))
    file_conn=$xml_conn file_db=$xml_db own_config=false
    rest="${words[*]:start}"
    [[ $rest =~ $config_re ]] && { file_conn="" file_db="" own_config=true; }
    conn=$file_conn db=$file_db url=$kept_url durl=$kept_durl
    conn_here=false db_here=false url_here=false durl_here=false
    part_trusted=$trusted option_seen=false
    for (( i = start - 1; i >= 0; i-- )); do
        w=${words[i]}
        case $w in
            DB_CONNECTION=*) $conn_here || { conn=${w#*=}; conn_here=true; } ;;
            DB_DATABASE=*) $db_here || { db=${w#*=}; db_here=true; } ;;
            DB_URL=*) $url_here || { url=${w#*=}; url_here=true; } ;;
            DATABASE_URL=*) $durl_here || { durl=${w#*=}; durl_here=true; } ;;
            -*) option_seen=true ;;
            env) $option_seen && part_trusted=false ;;
        esac
    done
    [ -z "$url$durl" ] || deny "the command sets DB_URL or DATABASE_URL, and Laravel reads the database from it, whatever DB_DATABASE says. Remove it from the command."
    # The same pair with the values an earlier part may have left set.
    kept_pair_conn=$conn kept_pair_db=$db
    $conn_here || { $kept_conn_set && kept_pair_conn=$kept_conn; }
    $db_here || { $kept_db_set && kept_pair_db=$kept_db; }
    safe_pair "$conn" "$db" && safe_pair "$kept_pair_conn" "$kept_pair_db" \
        && { $part_trusted || safe_pair "$file_conn" "$file_db"; } && continue
    if $own_config; then
        deny "the command picks its own PHPUnit configuration (-c, --configuration or --no-configuration), so ${xml:-phpunit.xml} does not decide which database the tests use. Prefix the command with DB_CONNECTION=sqlite DB_DATABASE=:memory:, or drop the option."
    elif $conn_here || $db_here || $kept_conn_set || $kept_db_set; then
        safe_pair "$file_conn" "$file_db" && deny "the command sets DB_CONNECTION or DB_DATABASE to something other than SQLite in memory or a test database, and those values win over ${xml:-phpunit.xml}. Remove them, or put DB_CONNECTION=sqlite DB_DATABASE=:memory: directly in front of the test command."
    fi
    checked=0
    break
done < <(printf '%s\n' "$joined" | tr -d "\"'\\\\" | tr '\r\t' '  ' | sed -E 's/[;&|(){}`$]+/\n/g')
[ "$checked" -gt 0 ] && exit 0

deny "${xml:-phpunit.xml} does not point tests at SQLite in memory or a test database, so they could reach the real one. Inside <php>, add <env name='DB_CONNECTION' value='sqlite'/> and <env name='DB_DATABASE' value=':memory:'/>, or prefix the command with DB_CONNECTION=sqlite DB_DATABASE=:memory:."
