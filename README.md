# mig skills

Agent skills for Claude Code and Codex, built for repos where a merge to `main` deploys to production. Every skill starts with `mig-`, so typing `/mig` (or `$mig` in Codex) lists them together.

## Install

```bash
npx skills add migueltavares/skills
```

Pick the skills when prompted. Install `mig-merge`, `mig-merged`, `mig-relay` and `mig-review-findings` together, since they call each other. Update later with `npx skills update`.

Claude Code can also install them as a plugin, which turns on the database guard automatically:

```text
/plugin marketplace add migueltavares/skills
/plugin install mig-skills@mig
```

Call a skill as `/mig-merge 12` in Claude Code, or `$mig-merge 12` in Codex.

## Skills

| Skill | You type | What it does |
| --- | --- | --- |
| [mig-merge](skills/mig-merge/SKILL.md) | `/mig-merge 12 14`, or `/mig-merge` to choose | Merges PRs in a safe order with squash, waits for each deploy before the next, then cleans up and hands off. |
| [mig-merged](skills/mig-merged/SKILL.md) | `/mig-merged 12` after you merge on GitHub | Verifies the merge, retargets stacked PRs, rescues late commits, removes merged worktrees and branches. |
| [mig-relay](skills/mig-relay/SKILL.md) | `/mig-relay` | Finds the next item in the work order, checks it still needs doing, and writes the prompt for the next thread. |
| [mig-review-findings](skills/mig-review-findings/SKILL.md) | `/mig-review-findings 12` | Checks each review comment against the code, fixes the confirmed ones, and answers the rest. |
| [mig-laravel-guardrails](skills/mig-laravel-guardrails/SKILL.md) | `/mig-laravel-guardrails` once | Blocks `migrate:fresh`, `db:wipe` and test runs that could reach a real database, in Claude Code and Codex. |
| [mig-orchestrator](skills/mig-orchestrator/SKILL.md) | `/mig-orchestrator #42` | Checks the issue still holds, briefs cheaper models with contracts, judges their work from git, gets a review from the other provider, and opens the PR. |
| [mig-mode](skills/mig-mode/SKILL.md) | `/mig-mode setup` once | Writes the always-on working rules, and unslop, into global CLAUDE.md and Codex's AGENTS.md. |
| [mig-mockup](skills/mig-mockup/SKILL.md) | `/mig-mockup pricing page` | Builds 2 or 3 HTML mockups, checks them at desktop and phone widths, and records the chosen design before any app code changes. |
| [mig-my-turn](skills/mig-my-turn/SKILL.md) | other skills hand over to it | Gives the steps only you can run, one at a time, with the machine named for each, and checks every result. |

How they chain:

```text
/mig-merge 12 14
  -> mig-review-findings   (each PR's review comments, before it merges)
  -> merge, wait for the deploy
  -> mig-merged            (cleanup after each PR)
  -> mig-relay             (once, at the end: the next thread's prompt)
```

## Project conventions

The skills read project facts from `AGENTS.md`, which Codex and Claude Code both use. Keep `CLAUDE.md` as a pointer to it (`@AGENTS.md`). Two sections matter:

- `## Deploy` says how a merge reaches production: a GitHub Actions workflow, or a manual command on a named server. `mig-merge` writes it the first time it runs in a repo.
- Work orders live in `docs/handoff/<date>-<slug>.md`. `mig-relay` reads the newest one.

Server names, paths and client names stay in each project's files. The skills hold none.

## Planned

`mig-audit-codebase`, `mig-pt-pt`, `mig-seo-audit`, `mig-memory-evolution`.

## Credits

These skills adapt ideas and text from [mattpocock/skills](https://github.com/mattpocock/skills), [t3dotgg/tstack](https://github.com/t3dotgg/tstack), [cursor/plugins pstack](https://github.com/cursor/plugins/tree/main/pstack) and [mayank-io/mstack](https://github.com/mayank-io/mstack), all MIT, and from [gtapps/skills](https://github.com/gtapps/skills) with the author's permission. Each skill names its sources under `metadata.credits`.

## License

[MIT](LICENSE)
