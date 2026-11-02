#!/usr/bin/env bash
# Writes the mig-mode rules, and unslop, into the files every session loads:
#   ~/.claude/CLAUDE.md   gets a marked block of @imports
#   $CODEX_HOME/AGENTS.md gets a marked block with the text itself, since
#                         AGENTS.md cannot import files (CODEX_HOME
#                         defaults to ~/.codex)
# A personal file, ~/.agents/mig/rules.local.md, is added after the rules when
# it exists, so local changes survive skill updates.
#
# Usage: setup.sh [--check | --remove]
#   --check   report whether each block is present and current; exit 1 if not.
#   --remove  delete both blocks.
# Every file it changes is backed up first as <file>.bak-<timestamp>.

set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
mode=${1:-install}
case "$mode" in install|--check|--remove) ;; *) echo "usage: setup.sh [--check|--remove]" >&2; exit 2 ;; esac
command -v python3 >/dev/null || { echo "MISSING python3" >&2; exit 1; }

unslop=""
for f in "$HOME/.agents/skills/unslop/SKILL.md" "$HOME/.claude/skills/unslop/SKILL.md"; do
    [ -f "$f" ] && { unslop=$f; break; }
done
if [ -z "$unslop" ] && [ "$mode" != --remove ]; then
    echo "MISSING  unslop. Install it with: npx skills add cursor/plugins --skill unslop -g"
    exit 1
fi

python3 - "$mode" "$here/rules.md" "$HOME/.agents/mig/rules.local.md" "$unslop" "$HOME" "${CODEX_HOME:-$HOME/.codex}" <<'PY'
import os, re, shutil, sys, time
mode, rules, local, unslop, home, codex_home = sys.argv[1:7]
START, END = "<!-- mig-mode:start -->", "<!-- mig-mode:end -->"
stamp = time.strftime("%Y%m%d-%H%M%S")
missing = False
found = 0

def backup(path):
    # A unique name, so two runs in the same second keep both backups.
    n, dest = 0, f"{path}.bak-{stamp}"
    while os.path.exists(dest):
        n += 1
        dest = f"{path}.bak-{stamp}-{n}"
    shutil.copy(path, dest)

def body(path):
    text = open(path, encoding="utf-8").read()
    return re.sub(r"\A---\n.*?\n---\n", "", text, flags=re.S).strip()

def block_for(target, text):
    other = text.split(START)[0] + (text.split(END, 1)[1] if END in text else "")
    has_unslop = "unslop/SKILL.md" in other or "unslop:start" in other
    lines = []
    if target == "claude":
        lines.append("@" + rules)
        if os.path.exists(local):
            lines.append("@" + local)
        if not has_unslop:
            lines.append("@" + unslop)
    else:
        lines.append(body(rules))
        if os.path.exists(local):
            lines.append(body(local))
        if not has_unslop:
            lines.append(body(unslop))
    return START + "\n" + "\n\n".join(lines) + "\n" + END

for target, path in (("claude", f"{home}/.claude/CLAUDE.md"), ("codex", f"{codex_home}/AGENTS.md")):
    if not os.path.isdir(os.path.dirname(path)):
        print(f"SKIPPED  {target}: {os.path.dirname(path)} does not exist")
        continue
    found += 1
    override = f"{codex_home}/AGENTS.override.md"
    if target == "codex" and os.path.exists(override):
        print(f"WARNING  {override} exists, and Codex reads it instead of AGENTS.md. Move its content into AGENTS.md, or add the block there by hand.")
        missing = True
    text = open(path, encoding="utf-8").read() if os.path.exists(path) else ""
    pattern = re.compile(re.escape(START) + r".*?" + re.escape(END) + r"\n?", re.S)
    current = pattern.search(text)
    if mode == "--remove":
        if current:
            backup(path)
            open(path, "w", encoding="utf-8").write(pattern.sub("", text))
            print(f"REMOVED  block in {path}")
        else:
            print(f"OK       no block in {path}")
        continue
    wanted = block_for(target, text)
    if current and current.group(0).rstrip("\n") == wanted:
        print(f"OK       {path}")
        continue
    if mode == "--check":
        print(f"{'OUTDATED' if current else 'MISSING '} {path}")
        missing = True
        continue
    if os.path.exists(path):
        backup(path)
    if current:
        # A function, so backslashes in the rules are never read as regex escapes.
        new = pattern.sub(lambda _: wanted + "\n", text)
    else:
        new = text.rstrip("\n") + ("\n\n" if text.strip() else "") + wanted + "\n"
    open(path, "w", encoding="utf-8").write(new)
    print(f"{'UPDATED ' if current else 'ADDED   '} {path}")

if not found:
    print("MISSING  neither ~/.claude nor the Codex home exists, so there is nothing to set up")
    missing = True
sys.exit(1 if missing else 0)
PY
