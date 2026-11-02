---
name: mig-mode
description: Always-on working rules for Claude Code and Codex, including unslop. Run /mig-mode setup once per machine, and again after updates.
disable-model-invocation: true
metadata:
  credits:
    - skill: unslop
      author: poteto
      url: https://github.com/cursor/plugins/blob/main/pstack/skills/unslop/SKILL.md
      license: MIT
      note: Installed from pstack and loaded as is, never copied into this repo.
    - skill: commit
      author: gtapps
      url: https://github.com/gtapps/skills/blob/main/skills/commit/SKILL.md
      note: Git rules adapted with the author's permission.
---

# mig-mode

A skill loads only when someone calls it or its description matches the task. Rules that must hold in every session belong in the files every session loads: `~/.claude/CLAUDE.md` for Claude Code and `~/.codex/AGENTS.md` for Codex. This skill keeps the rules in [rules.md](rules.md) and writes them into both files.

Claude Code gets `@` imports, so it always reads the current rules. Codex gets a copy of the text, because AGENTS.md can't import files. Both live between `<!-- mig-mode:start -->` and `<!-- mig-mode:end -->`, so setup can update or remove them without touching anything else.

## Setup

1. Run `bash <skill-dir>/scripts/setup.sh --check`, with `<skill-dir>` resolved to this skill's absolute installed path.
2. When it reports unslop as missing, ask the user, then run `npx skills add cursor/plugins --skill unslop -g`.
3. Show the user what setup adds: the import lines for CLAUDE.md, and the text from rules.md for AGENTS.md. Unslop is left out of a file that already loads it.
4. Run `bash <skill-dir>/scripts/setup.sh`. It backs up each file before changing it.
5. Tell the user that new sessions pick the rules up, and the current one does not.

Done when `--check` exits 0: `OK` for each host that is installed, and `SKIPPED` for one that isn't.

## Changing the rules

- Personal additions go in `~/.agents/mig/rules.local.md`. Setup adds that file after the rules, and skill updates leave it alone.
- After `npx skills update`, run setup again so the Codex copy matches.
- `bash <skill-dir>/scripts/setup.sh --remove` takes both blocks out.
