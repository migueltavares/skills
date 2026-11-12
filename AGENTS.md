# migueltavares/skills

Public agent skills for Claude Code and Codex. Each skill lives in `skills/mig-<name>/`, and the `mig-` prefix keeps them together in the slash menu.

## Layout

- `skills/mig-<name>/SKILL.md` is the entrypoint. Its frontmatter has `name`, `description`, and sources under `metadata.credits`.
- `skills/mig-<name>/agents/openai.yaml` is the Codex metadata. A skill that only runs when called sets `disable-model-invocation: true` in SKILL.md and `policy.allow_implicit_invocation: false` here.
- `references/` and `scripts/` exist only when a skill needs them. Steps that differ by host go in `references/claude.md` and `references/agents.md`.
- A new skill is listed in `.claude-plugin/plugin.json` and in the README table.

## Writing

- Follow the writing-for-agents and unslop skills: no em dashes, straight quotes, sentence case headings.
- Server names, paths, and client or project names stay out of every file here. Skills read those facts from each project's AGENTS.md.
- Skills treat a project's AGENTS.md as the source of project facts, and its CLAUDE.md as a pointer to it.
- Skills don't depend on other authors' skills. Unslop is the one exception, installed by `mig-mode`, never copied.
- Credit every source in `metadata.credits`. Material from gtapps/skills is used with the author's permission.

## Checks

Run these before opening a PR:

- `npx skills add . --list` lists every skill.
- `claude plugin validate .` passes. The missing icon warning is expected.
- `grep -rnP '[\x{2014}\x{2013}\x{201C}\x{201D}]' skills README.md AGENTS.md` prints nothing.
- Every script passes `bash -n`, and its own tests when it has them.

## Workflow

Branch from `main`, open a PR, and squash-merge it with `/mig-merge`. Nothing is pushed to `main` directly.

## Deploy

- Trigger: merge to `main`.
- Method: none. Merging publishes the skills to anyone who runs `npx skills update`.
