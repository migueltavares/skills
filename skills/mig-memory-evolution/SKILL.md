---
name: mig-memory-evolution
description: Find rules the user has taught agents in several projects and move each to one home, such as a skill, global instructions, a hook or a checklist. Run /mig-memory-evolution every few weeks.
disable-model-invocation: true
metadata:
  credits:
    - skill: surface-usage-patterns
      author: Mayank
      url: https://github.com/mayank-io/mstack/tree/main/plugins/ccimprove/skills/surface-usage-patterns
      license: MIT
    - skill: automate-me
      author: poteto
      url: https://github.com/cursor/plugins/blob/main/pstack/skills/automate-me/SKILL.md
      license: MIT
    - skill: final-plan-check and wrap
      author: gtapps
      url: https://github.com/gtapps/skills
      note: The growing plan checklist, adapted with the author's permission.
---

# mig-memory-evolution

Agents save feedback per project, so the same rule ends up in four or five memory folders, worded a little differently each time. A rule that lives in five places gets applied in five ways and fixed in one. This skill finds those rules and gives each one a single home.

## 1. Read the memories

The log of earlier runs is `~/.agents/mig/memory-evolution.md`. Read its last `## <date>` entry: the decisions already made, the contradictions left open, and the items pending a merge.

- With a log entry, read in full only the notes changed since that date: `find ~/.claude/projects/*/memory -name '*.md' ! -name MEMORY.md -newermt <date>`, and the Codex files the same way. Read every `MEMORY.md` index too, so a changed note can be grouped with older notes that state the same rule, and open those older notes when they do.
- With no log, or when the user asks for a full pass, read every note.

Where the notes live:

- Claude Code: `~/.claude/projects/*/memory/*.md`, plus each folder's `MEMORY.md` index. The folder names start with `-home`, so pass paths after `--` (`cat -- "$f"`, `grep -- pattern "$f"`).
- Codex: `~/.codex/memories/`, when it exists.
- Project AGENTS.md and CLAUDE.md files only for context. They are already a home.

## 2. Group them

Group notes that state the same rule, even when worded differently. For each group, record the rule in one sentence, the projects it appears in, and any notes that contradict each other.

Done when every note is in a group or marked as specific to its project.

## 3. Propose a home

| Group | Home |
| --- | --- |
| A rule for how to work everywhere | `~/.agents/mig/rules.local.md`, loaded by `mig-mode` |
| A procedure with steps | A skill: an existing mig skill's text, or a new skill |
| Something that must never happen | A hook or a deny rule, since a note only asks |
| A question the user keeps asking after seeing a plan | `~/.agents/mig/checklist.md`, which `mig-orchestrator` answers in every plan |
| A fact about one project | That project's AGENTS.md |
| A note about one project's history | Stays in memory |

Show the proposal as a table: the rule, how many projects, the home, the change. Contradictions go in a separate list for the user to settle. Wait for approval, item by item when the user wants.

## 4. Apply the approved changes

1. Write the rule into its new home, in that file's own style.
2. For a skill change, edit the skill in its repo and open a PR, rather than editing an installed copy that updates will overwrite.
3. When `rules.local.md` changed, run `bash <mig-mode skill dir>/scripts/setup.sh`, then the same with `--check`, so Codex and Antigravity get the new text. `mig-mode` itself can't be invoked by the model.
4. Delete the per-project memory files the rule replaces, and remove their lines from each `MEMORY.md` index, only once the new home is live: the file is written and loaded, or the skill PR is merged and installed.

Never delete a memory the user didn't approve, and never one that holds project history beyond the rule itself. Trim that kind instead.

## Report

One line per change: the rule, its new home, and the memory files removed. Then the contradictions still open, the deletions waiting on a merge, and the date. Append the same report to `~/.agents/mig/memory-evolution.md` under a `## <date>` heading, so the next run starts from what changed since.
