#!/usr/bin/env bash
# Tests for skills/mig-mode/scripts/setup.sh across Claude Code, Codex and Antigravity.
# Runs entirely inside a temp HOME directory so real configs are untouched.
#
# Usage: bash tests/mig-mode-setup.test.sh

set -u

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
setup="$repo/skills/mig-mode/scripts/setup.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/.claude" "$tmp/.codex" "$tmp/.gemini" "$tmp/.agents/skills/unslop" "$tmp/.agents/mig"
cat > "$tmp/.agents/skills/unslop/SKILL.md" <<'EOF'
---
name: unslop
description: Cut AI tells.
---

# Unslop

No em dashes.
EOF
cat > "$tmp/.agents/mig/rules.local.md" <<'EOF'
# Personal rules

- Local test rule.
EOF
cat > "$tmp/.gemini/GEMINI.md" <<'EOF'
## Writing style (always on)

@~/.agents/skills/unslop/SKILL.md
EOF

pass=0 fail=0
assert_ok() {
    local label=$1
    shift
    if "$@"; then
        pass=$(( pass + 1 ))
    else
        fail=$(( fail + 1 ))
        printf 'FAIL  %s\n' "$label"
    fi
}

export HOME="$tmp"
export CODEX_HOME="$tmp/.codex"
export GEMINI_HOME="$tmp/.gemini"

# Check fails before install.
assert_ok "check exits 1 before install" bash -c '! bash "$1" --check >/dev/null' _ "$setup"

# Install writes all three hosts.
assert_ok "install succeeds" bash "$setup" >/dev/null
assert_ok "check exits 0 after install" bash "$setup" --check >/dev/null

# Claude uses @ imports; Codex and Gemini inline rules, local rules, and unslop.
assert_ok "claude has @rules.md" grep -Fq "@$repo/skills/mig-mode/rules.md" "$tmp/.claude/CLAUDE.md"
assert_ok "claude has @rules.local.md" grep -Fq "@$tmp/.agents/mig/rules.local.md" "$tmp/.claude/CLAUDE.md"
assert_ok "codex inlines rules.md" grep -Fq "# Working rules (mig-mode)" "$tmp/.codex/AGENTS.md"
assert_ok "codex inlines rules.local.md" grep -Fq "Local test rule." "$tmp/.codex/AGENTS.md"
assert_ok "codex inlines unslop" grep -Fq "# Unslop" "$tmp/.codex/AGENTS.md"
assert_ok "gemini inlines rules.md" grep -Fq "# Working rules (mig-mode)" "$tmp/.gemini/GEMINI.md"
assert_ok "gemini inlines rules.local.md" grep -Fq "Local test rule." "$tmp/.gemini/GEMINI.md"
assert_ok "gemini inlines unslop even with bare @path outside block" grep -Fq "# Unslop" "$tmp/.gemini/GEMINI.md"

# Antigravity @[label](path) include counts as unslop already loaded.
cat > "$tmp/.gemini/GEMINI.md" <<'EOF'
@[unslop](~/.agents/skills/unslop/SKILL.md)
EOF
assert_ok "reinstall with @[label](path) succeeds" bash "$setup" >/dev/null
assert_ok "gemini skips duplicate unslop with @[label](path)" bash -c '! grep -Fq "# Unslop" "$1"' _ "$tmp/.gemini/GEMINI.md"

# Remove clears all three blocks cleanly.
assert_ok "remove succeeds" bash "$setup" --remove >/dev/null
assert_ok "claude block removed" bash -c '! grep -Fq "mig-mode:start" "$1"' _ "$tmp/.claude/CLAUDE.md"
assert_ok "codex block removed" bash -c '! grep -Fq "mig-mode:start" "$1"' _ "$tmp/.codex/AGENTS.md"
assert_ok "gemini block removed" bash -c '! grep -Fq "mig-mode:start" "$1"' _ "$tmp/.gemini/GEMINI.md"

printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
