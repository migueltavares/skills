---
name: mig-orchestrator
description: Run an issue or plan step as orchestrator. Check the issue still holds, brief cheaper models with contracts, judge their work from git, get an independent review from another provider, and open the PR. Use for /mig-orchestrator <issue>, "orchestrate this", or a relay prompt that names it.
metadata:
  credits:
    - skill: tackle-task, plan-implementation, review-to-pr, delegate-plan
      author: gtapps
      url: https://github.com/gtapps/skills
      note: Adapted with the author's permission.
    - skill: sol-loop
      author: Theo Browne
      url: https://github.com/t3dotgg/tstack/blob/main/skills/sol-loop/SKILL.md
      license: MIT
    - skill: poteto-mode
      author: poteto
      url: https://github.com/cursor/plugins/blob/main/pstack/skills/poteto-mode/SKILL.md
      license: MIT
---

# mig-orchestrator

The main thread owns judgment: what to build, whether the result is right, and all security logic. Cheaper models write most of the code. Evidence comes from git and from commands you run yourself, never from a model's summary of its own work.

Input: an issue (`#42` or a URL), a step in a plan file, or a pasted task.

## 1. Check the claim

Treat the task as a claim to disprove before planning it.

1. Read the issue (`gh issue view <n> --json title,body,comments,state`) and check for an open PR that already covers it (`gh pr list --state open --search "<n>"`).
2. Open the files and symbols it names. Read `git log` since it was written, since earlier work often fixes part of it.
3. When reading can't settle a claimed bug, reproduce it.

Reach one verdict, citing the files you read or the commands you ran:

- **Still needed** as written.
- **Needed, scope changed**: say what changed.
- **Already done**: show the evidence, suggest closing the issue, and stop.
- **Blocked on the user**: say exactly what they must do first, and stop.

## 2. Plan

1. Read the project's AGENTS.md (or the CLAUDE.md that holds its guidance) for checks, conventions, model rules and the Deploy section.
2. When `~/.agents/mig/checklist.md` exists, answer each of its questions in the plan.
3. Split the work into steps in dependency order. Write each step as a contract with [references/brief.md](references/brief.md).
4. In a Laravel repo without the test database guard (no `guardTestDatabase` in `tests/`), add it as step 1, following `mig-laravel-guardrails`.

Show the plan and wait when it leaves a real design choice open or the scope changed. Otherwise continue.

## 3. Pick models

Read the override files before the bundled table, in this order, and take the first row that names the role:

1. The project's AGENTS.md, section `## Models`.
2. `~/.agents/mig/models.md`. Open it with the Read tool or `cat`, and say so when it doesn't exist.
3. The defaults in [references/models.md](references/models.md).

In T3 Code, call `orchestrator_capabilities` once and map each role to a model it lists. Name the source of each pick (project, machine file or default) in the Report.

## 4. Delegate

Before the first delegation, write every file, class and symbol that a brief names but that doesn't exist yet. An implementer that can't find a named symbol stops, and a fresh run costs a full restart.

For each step, in order:

- In T3 Code, call `delegate_task` with `role: "implementation"`, the brief as `task`, and `target` set to the provider, model and options for the role. Use `mode: "wait"` when the next step depends on this one, and the default `isolation: "shared"`, so the changes land in this checkout where step 5 reads them.
- Elsewhere, use the host's own subagent tool with the role's model.
- Run one implementer at a time when steps share files or a test database.

Implementers edit files and run checks. They never stage, commit, push or open a PR, and every brief says so.

When an implementer stops to ask, answer it in its own thread (`t3_thread_send` in T3 Code, `SendMessage` for a Claude subagent) so it keeps its context. Start a new `delegate_task` only when the brief itself was wrong.

While a child runs, do work outside its fence: the next brief, the security logic, the PR body. Never sit idle on a child for more than 2 minutes. When nothing else is left, check its status instead of waiting for a notification.

## 5. Judge from git

For each step, after its implementer reports:

1. Read `git status` and the full `git diff`. Hand a diff over about 400 lines to a read-only subagent for a first pass, and keep the verdict yourself.
2. Run the step's Verify command yourself, after the implementers have stopped.
3. Check the diff against the contract and the fence.

A step that misses its contract goes back with specific corrections, at most twice. After that, do it yourself. Security logic (authorization, permissions, payments, secrets, uploads, anything that touches personal data) is written or rewritten by the main thread.

Then run the full test suite once, and every other check CI runs (lint, static analysis, dependency audit), so a push never fails on a check nobody ran locally. Use the project's local CI command when AGENTS.md names one.

Done when every step's Verify, the full suite and the CI checks pass in your own run.

## 6. Commit

Read the project's workflow in AGENTS.md first. Most projects use a branch and a PR. Some commit straight to the default branch; for those, skip the branch in this step and follow the "No PR" path in step 8.

1. Use the project's branch convention, else `feat/<issue>-<slug>` or `fix/<issue>-<slug>`, branched from `origin/<default branch>`.
2. When the task came from a work order (a `docs/handoff/` plan, a phase list), mark the item done in the same commit, with the PR number once it exists.
3. Stage paths by name. Check the staged list for files that look like secrets (`.env`, keys, credentials) and stop if you find one.
4. Write a message that says why the change exists. Record the commit as `<pre-review>`.

## 7. Independent review

1. List which provider wrote each part of the diff: each implementer's files, and the files the main thread wrote itself. The main thread counts as its own provider (Claude in Claude Code, OpenAI in Codex).
2. Send each part to a reviewer from the other provider, using the Review row in [references/models.md](references/models.md). A diff written by Sol is reviewed by Claude, and a diff written by Sonnet or by the main Claude thread is reviewed by Sol. When one provider wrote everything, one reviewer covers it all.
3. In T3 Code, call `delegate_task` with `role: "review"` and a task built from [references/review.md](references/review.md). Elsewhere, use the other provider's CLI in read-only mode when it is installed, else a fresh-context subagent, and say in the Report that the review was same-provider.
4. When a project rule skips or narrows the review for this step, follow it and say so in the Report.
5. Verify every finding the way `mig-review-findings` step 2 does, with the same classes: Confirmed, Refuted, Partial, Needs investigation, Out of scope.
6. Fix the Confirmed findings and the valid part of the Partial ones. Run the checks again and commit.
7. Needs investigation items stop the run for the user.

## 8. Open the PR

**No PR.** When the project commits straight to the default branch: the local commits are already reviewed, so run the CI checks locally once more, then `git push`. Don't wait on remote CI unless AGENTS.md says to. Report, then invoke `mig-relay`.

**With a PR:**

1. Check for an existing PR with `gh pr list --head <branch>`.
2. Push with `git push -u origin HEAD`.
3. Write the body to a file and use `gh pr create --body-file`. Cover: the behaviour before and after, the evidence (commands and results), the review (reviewer model, each finding and its verdict), deploy notes as `mig-merge` describes them, and `Closes #<n>` with one "closes" per issue.
4. In T3 Code, call `link_pull_request` with the PR URL right after creating it, then `watch_pull_request`, and end the turn. Handle failing checks and new review comments with `mig-review-findings` as they arrive.

Stop when the checks are green and every thread is resolved. Unwatch the PR, then report. Merging is the user's call, through `/mig-merge <n>`.

## Report

The PR URL or the pushed commit, the verdict from step 1, the model used for each role and where the pick came from, which reviewer covered which part of the diff, the checks before and after review, and each finding with its verdict. End with one line:

```text
Loose ends: <steps done by hand and why> | <follow-ups> | <checks not run> | none
```
