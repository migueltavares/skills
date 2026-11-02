---
name: mig-merge
description: Merge pull requests in a safe order, waiting for each deploy, then clean up and hand off the next step.
disable-model-invocation: true
metadata:
  credits:
    - skill: full-send
      author: Theo Browne
      url: https://github.com/t3dotgg/tstack/blob/main/skills/full-send/SKILL.md
      license: MIT
    - skill: babysit-pr
      author: Theo Browne
      url: https://github.com/t3dotgg/tstack/blob/main/skills/babysit-pr/SKILL.md
      license: MIT
---

# mig-merge

In most repos a merge to the default branch deploys to production. This skill merges the PRs the user names, one at a time. It waits for each deploy before the next merge, and stops at the first thing that is not green.

Running `/mig-merge` with PR numbers, or naming them in answer to its question, is the user's approval to merge those PRs and trigger their deploys. That approval covers nothing else: no `--admin`, no force-push, no closing PRs.

## 1. Choose the PRs

With PR numbers in any form (`/mig-merge 12 14 15`, "PR 12 and 14"), take exactly those.

With none, list the open PRs:

```bash
gh pr list --state open --json number,title,isDraft,baseRefName,reviewDecision,mergeStateStatus,statusCheckRollup
```

Show a table (number, title, checks, review, mergeable) and ask "All of them, or which numbers?" with the host's question tool (`AskUserQuestion` in Claude Code, `request_user_input` in Codex), so the thread shows it is waiting. Drafts never count as "all".

## 2. Prepare the repo

Once per repo, before the first merge.

**Squash only.** Check with `gh api repos/<owner>/<repo> --jq '{squash: .allow_squash_merge, merge: .allow_merge_commit, rebase: .allow_rebase_merge}'`. When merge commits or rebase are allowed:

```bash
gh repo edit --enable-squash-merge --enable-merge-commit=false --enable-rebase-merge=false \
  --squash-merge-commit-message pr-title-description
```

Tell the user it changed. Without admin rights on the repo, say so and carry on with `--squash`.

**Deploy section.** Read the project's instructions: AGENTS.md, or CLAUDE.md when it holds the guidance instead of pointing to AGENTS.md. Find the `## Deploy` section. When it's missing, work it out:
- A workflow in `.github/workflows/` that runs on push to the default branch and deploys means GitHub Actions.
- No such workflow means a manual deploy. Ask the user where they run it (a server alias, never a secret), the directory, the command, and how they know it worked.
- A repo that ships nothing on merge (a library, a docs or skills repo) gets `Method: none`. Confirm it with the user before writing it.

Then write the section into the file that owns the guidance, never into both. When neither file exists, create AGENTS.md, plus a CLAUDE.md that holds only `@AGENTS.md`.

```markdown
## Deploy

- Trigger: merge to `main`.
- Method: GitHub Actions, workflow `deploy.yml`.
  (Or: Manual, on <server>, run `cd <dir> && ./deploy.sh`.)
- Healthy when: the workflow run succeeds, and <URL> returns 200.
```

The edit goes in a small docs PR. Ask the user whether to add it to the end of this run.

## 3. Order

1. A PR stacked on another PR's branch goes after that PR.
2. A PR with migrations goes before PRs whose code needs them.
3. PRs that touch the same files go in the order they were opened.
4. Everything else, oldest first.

Show the order as a numbered list, one line of reasoning per PR, then start.

## 4. For each PR, in order

**a. Gate.** Read the state:

```bash
gh pr view <n> --json state,isDraft,mergeable,mergeStateStatus,reviewDecision,headRefOid,baseRefName,statusCheckRollup
```

- Its base must be the default branch. A stacked PR gets retargeted by the cleanup after its base merges, and then needs green checks again.
- `BEHIND`: `gh pr update-branch <n>`, then wait for checks.
- `DIRTY`: merge the default branch into the PR branch, resolve, run the checks, push. Stop when a resolution is not obvious.
- Checks pending: wait without polling. In T3 Code, call `watch_pull_request` and end the turn, and you are woken when something changes. Elsewhere, run `gh pr checks <n> --watch --fail-fast` as one command.
- Checks red: find the cause. Fix real failures on the PR branch. Rerun an infrastructure flake once with `gh run rerun <id> --failed`.
- Review comments: run `mig-review-findings` on the PR. Items it leaves for the user stop the run.
- A human review that requests changes stops the run.

The gate passes when, on the latest head commit, checks are green, every review thread is resolved, no review requests changes, and GitHub reports the PR mergeable.

**b. Deploy notes.** When the PR body has no deploy notes, add a `## Deploy notes` section from the diff with `gh pr edit <n> --body-file <file>`. Cover migrations (say if any drop or rewrite data), new env vars, queue or scheduler restarts, cache clears, server steps, and the rollback (`git revert <merge commit>`, plus what a migration needs).

**c. Merge.**

```bash
gh pr merge <n> --squash --match-head-commit <headRefOid>
```

`--match-head-commit` refuses the merge when someone pushed after the gate passed. With a merge queue or auto-merge, wait until GitHub reports `MERGED`.

**d. Deploy.** Follow the Deploy section. With `Method: none`, go straight to cleanup.
- GitHub Actions: find the run with `gh run list --branch <default branch> --commit <merge commit sha> --json databaseId,workflowName,status,conclusion`. It can take a minute to appear. Wait on it with `gh run watch <id> --exit-status`. In T3 Code, run that as a background command and wait with `t3_background_wait`.
- Manual: hand the step to `mig-my-turn` when it is installed. Otherwise give the user one block, labeled with the machine ("On <server>"), holding the exact commands. Ask with the question tool for the output or "deployed", and check the reply before going on.
- Then the health check, when the section names one.

A failed deploy stops the whole run. Show the failing log tail (`gh run view <id> --log-failed | tail -50`) and offer the rollback from the deploy notes. Leave the remaining PRs unmerged.

**e. Clean up.** Invoke `mig-merged` for this PR.

A PR is done when it is merged, its deploy is confirmed healthy, and its cleanup ran.

## 5. Finish

Report one row per PR: number, title, merge commit, deploy result. List the PRs that were not merged, and why. Unwatch any PR still watched (`unwatch_pull_request` in T3 Code). End with one line:

```text
Loose ends: <PRs left unmerged> | <retargeted PRs waiting for CI> | <dirty worktrees> | none
```

Then invoke `mig-relay` once, when work remains in an order.
