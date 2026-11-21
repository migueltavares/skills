#!/usr/bin/env bash
# Tests for skills/mig-laravel-guardrails/scripts/laravel-db-guard.sh.
# Feeds the guard hook payloads and checks whether it allows or denies each.
# Nothing here runs artisan, PHPUnit or a database: the guard only reads text.
#
# Usage: bash tests/laravel-db-guard.test.sh

set -u

guard="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/skills/mig-laravel-guardrails/scripts/laravel-db-guard.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Laravel roots: "safe" has SQLite in memory in phpunit.xml, "unsafe" names a
# real database, "bare" has no phpunit.xml, "cached" has a cached config.
# "plain" is not a Laravel app.
for app in safe unsafe bare cached; do
    mkdir -p "$tmp/$app/bootstrap/cache"
    touch "$tmp/$app/artisan"
done
mkdir -p "$tmp/plain"
xml() { printf '<phpunit><php><env name="DB_CONNECTION" value="%s"/><env name="DB_DATABASE" value="%s"/></php></phpunit>\n' "$1" "$2"; }
xml sqlite :memory: > "$tmp/safe/phpunit.xml"
xml sqlite :memory: > "$tmp/cached/phpunit.xml"
xml mysql app > "$tmp/unsafe/phpunit.xml"
xml mysql app > "$tmp/safe/other.xml"
touch "$tmp/cached/bootstrap/cache/config.php"

pass=0 fail=0
# check <allow|deny> <app> <command> [tool name]
check() {
    local want=$1 app=$2 cmd=$3 tool=${4:-Bash} out got=allow
    out=$(jq -nc --arg c "$cmd" --arg d "$tmp/$app" --arg t "$tool" \
        '{tool_name: $t, tool_input: {command: $c}, cwd: $d}' | bash "$guard")
    case "$out" in *'"permissionDecision":"deny"'*) got=deny ;; esac
    if [ "$got" = "$want" ]; then
        pass=$(( pass + 1 ))
    else
        fail=$(( fail + 1 ))
        printf 'FAIL  wanted %s, got %s  [%s] %s\n' "$want" "$got" "$app" "$cmd"
    fi
}

# Commands that drop every table.
check deny  plain  'php artisan migrate:fresh'
check deny  plain  'php artisan migrate:fresh --seed'
check deny  plain  'php artisan "migrate:refresh"'
check deny  plain  'php artisan migrate:reset'
check deny  plain  'php artisan db:wipe'
check deny  plain  'php artisan mi:fr'
check deny  plain  'ssh server "cd /srv/app && php artisan migrate:fresh"'
check deny  plain  "php artisan tinker --execute=\"Artisan::call('migrate:fresh')\""
check allow plain  'php artisan migrate'
check allow plain  'php artisan migrate:status'
check allow plain  'php artisan migrate:rollback'
check allow plain  'php artisan db:seed'

# Test runs outside a Laravel app are left alone.
check allow plain  'vendor/bin/phpunit'
check allow plain  'composer test'

# phpunit.xml decides when the command sets nothing.
check allow safe   'php artisan test'
check allow safe   'vendor/bin/pest --filter=Login'
check allow safe   'composer test'
check allow safe   'cd . && php artisan test'
check deny  unsafe 'php artisan test'
check deny  unsafe 'vendor/bin/phpunit'
check deny  bare   'php artisan test'

# A cached config, or one made in the same command.
check deny  cached 'php artisan test'
check deny  cached 'DB_CONNECTION=sqlite DB_DATABASE=:memory: php artisan test'
check deny  safe   'php artisan config:cache && php artisan test'
check deny  safe   'php artisan optimize; php artisan test'
check allow safe   'php artisan optimize:clear && php artisan test'

# Safe assignments in front of the test command.
check allow bare   'DB_CONNECTION=sqlite DB_DATABASE=:memory: php artisan test'
check allow unsafe 'DB_CONNECTION=sqlite DB_DATABASE=:memory: vendor/bin/phpunit'
check allow bare   'DB_DATABASE=app_testing php artisan test'
check allow unsafe 'XDEBUG_MODE=off DB_CONNECTION=sqlite DB_DATABASE=:memory: php artisan test'
check deny  unsafe 'DB_CONNECTION=sqlite DB_DATABASE=:memory: php artisan test && php artisan test'
check allow safe   'DB_DATABASE=:memory: php artisan test'

# An assignment wins over phpunit.xml, so an unsafe one is refused.
check deny  safe   'DB_CONNECTION=mysql DB_DATABASE=app php artisan test'
check deny  safe   'DB_DATABASE=app php artisan test'
check deny  safe   'DB_CONNECTION=mysql php artisan test'
check deny  safe   'DB_CONNECTION=mysql DB_DATABASE=app vendor/bin/phpunit --filter phpunit'
check deny  safe   'php artisan test && DB_DATABASE=app vendor/bin/pest'
check deny  safe   'TOOL=bin/pest DB_DATABASE=app php artisan test'

# The rightmost assignment counts, even when it is empty.
check deny  bare   'DB_DATABASE=testing DB_DATABASE= DB_CONNECTION=mysql php artisan test'
check deny  bare   'DB_DATABASE=testing DB_DATABASE=app php artisan test'
check allow bare   'DB_DATABASE=app DB_DATABASE=testing php artisan test'

# DB_URL is refused unless it is emptied.
check deny  safe   'DB_URL=mysql://localhost/app DB_DATABASE=testing php artisan test'
check deny  bare   'DB_URL=mysql://localhost/app DB_CONNECTION=sqlite DB_DATABASE=:memory: php artisan test'
check allow safe   'DB_URL= php artisan test'
check deny  safe   'DATABASE_URL=mysql://localhost/app php artisan test'

# A run that picks its own configuration cannot lean on phpunit.xml.
check deny  safe   'vendor/bin/phpunit -c other.xml'
check deny  safe   'vendor/bin/phpunit --configuration other.xml'
check deny  safe   'vendor/bin/phpunit --configuration=other.xml'
check deny  safe   'vendor/bin/phpunit --no-configuration'
check deny  safe   'php artisan test -c other.xml'
check allow safe   'DB_CONNECTION=sqlite DB_DATABASE=:memory: vendor/bin/phpunit -c other.xml'
check allow safe   'vendor/bin/pest --compact --coverage'
check allow safe   'php -c php.ini artisan test'
check deny  safe   'php -c php.ini vendor/bin/phpunit -c other.xml'
check deny  safe   'vendor/bin/phpunit -cconfig/other-file.xml'

# A backslash before a line break: assignments are read, and phpunit.xml must be safe too.
check allow safe   $'php artisan test \\\n  --filter=Login'
check deny  safe   $'DB_CONNECTION=mysql \\\n  DB_DATABASE=app php artisan test'
check deny  unsafe $'DB_CONNECTION=sqlite DB_DATABASE=:memory: \\\n  php artisan test'
check allow safe   $'DB_CONNECTION=sqlite DB_DATABASE=:memory: \\\n  php artisan test'

# Wrappers, PHP options and quoted values cannot hide an assignment.
check deny  safe   'DB_DATABASE=app php -d x=y vendor/bin/phpunit'
check deny  safe   'DB_DATABASE=app env php artisan test'
check deny  safe   'env DB_DATABASE=app php artisan test'
check deny  safe   'DB_URL=mysql://localhost/app php -d x=y vendor/bin/phpunit'
check deny  safe   'DB_URL="mysql://localhost/app name" php artisan test'
check deny  safe   'DB_DATABASE="app name" php artisan test'

# Exported and bare assignments stay set for later commands.
check deny  safe   'export DB_DATABASE=app && php artisan test'
check deny  safe   'export DB_CONNECTION=mysql DB_DATABASE=app; php artisan test'
check deny  safe   'DB_URL=mysql://localhost/app; php artisan test'
check allow safe   'export DB_CONNECTION=sqlite DB_DATABASE=:memory: && php artisan test'
check deny  safe   'export DB_CONNECTION=sqlite DB_DATABASE=:memory:; export DB_DATABASE="app name"; php artisan test'

# An earlier part never makes a run safe: it may not have run, or not in this shell.
check deny  unsafe 'export DB_CONNECTION=sqlite DB_DATABASE=:memory: && php artisan test'
check deny  unsafe '(export DB_CONNECTION=sqlite DB_DATABASE=:memory:); php artisan test'
check deny  bare   'export DB_CONNECTION=sqlite DB_DATABASE=:memory:; unset DB_DATABASE; php artisan test'
check deny  unsafe 'true || export DB_CONNECTION=sqlite DB_DATABASE=:memory:; php artisan test'
check deny  bare   'DB_CONNECTION=sqlite DB_DATABASE=:memory:; php artisan test'
check allow unsafe 'export APP_ENV=testing; DB_CONNECTION=sqlite DB_DATABASE=:memory: php artisan test'

# env with options can drop the assignments in front of it.
check deny  unsafe 'DB_DATABASE=testing DB_CONNECTION=sqlite env -u DB_DATABASE -u DB_CONNECTION php artisan test'
check deny  bare   'DB_DATABASE=testing env -i php artisan test'
check allow safe   'env -u XDEBUG_MODE php artisan test'
check allow unsafe 'env DB_CONNECTION=sqlite DB_DATABASE=:memory: php artisan test'

# A separator right after the test command.
check deny  cached 'php artisan test;'
check deny  unsafe 'php artisan test&& echo done'
check deny  unsafe 'vendor/bin/phpunit|tee out.log'
check allow safe   'php artisan test; echo done'

# DB_URL and DATABASE_URL are separate variables.
check deny  safe   'DB_URL=mysql://h/app DATABASE_URL= php artisan test'
check deny  safe   'DATABASE_URL=mysql://h/app DB_URL= php artisan test'
check allow safe   'DB_URL= DATABASE_URL= php artisan test'

# A database variable set from a substitution or another variable cannot be read.
check deny  safe   'DB_URL="$(printf mysql://h/app)" php artisan test'
check deny  safe   'DB_URL=`printf mysql://h/app` php artisan test'
check deny  safe   'DB_DATABASE=$REAL_DB php artisan test'
check allow safe   'APP_KEY=$(php -r "echo 1;") php artisan test'
check allow safe   'export APP_ENV=testing && php artisan test'

# Subshells and command substitutions are checked by themselves.
check deny  unsafe 'DB_DATABASE=testing vendor/bin/phpunit --filter "$(DB_DATABASE=app vendor/bin/phpunit )"'
check deny  unsafe 'DB_DATABASE=testing vendor/bin/phpunit --filter "`DB_DATABASE=app vendor/bin/phpunit`"'
check deny  unsafe '(php artisan test)'
check deny  safe   '(DB_DATABASE=app php artisan test)'
check deny  cached '(php artisan test)'
check allow safe   '(php artisan test)'
check allow safe   'out=$(php artisan test)'

# File edits that mention a test command are not shell commands.
check allow unsafe 'php artisan test' apply_patch
check allow unsafe 'php artisan test' Edit
check deny  unsafe 'php artisan test' shell

# Deny reasons for destructive commands and optimize+test tell agents to use --body-file for prose.
check_reason() {
    local app=$1 cmd=$2 needle=$3 out
    out=$(jq -nc --arg c "$cmd" --arg d "$tmp/$app" \
        '{tool_name: "Bash", tool_input: {command: $c}, cwd: $d}' | bash "$guard")
    case "$out" in
        *"$needle"*) pass=$(( pass + 1 )) ;;
        *) fail=$(( fail + 1 )); printf 'FAIL  missing %s in output for [%s] %s\n' "$needle" "$app" "$cmd" ;;
    esac
}
check_reason plain 'gh pr create --body "never run php artisan migrate:fresh"' '--body-file'
check_reason safe  'gh pr create --body "ran php artisan optimize and php artisan test"' '--body-file'

printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
