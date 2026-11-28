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
gh pr list --state open --json number,title,isDraft,baseRefName,reviewDecision,mergeStateStatus,statusCheckRollup \
  --jq 'map({number,title,isDraft,baseRefName,reviewDecision,mergeStateStatus,checks:(.statusCheckRollup|map(.conclusion // .state // .status)|group_by(.)|map("\(.[0]):\(length)")|join(" "))})'
```

Show a table (number, title, checks, review, mergeable) and ask "All of them, or which numbers?" with the host's question tool (`AskUserQuestion` in Claude Code, `request_user_input` in Codex), so the thread shows it is waiting. Drafts never count as "all".

## 2. Read the Deploy section

Once per repo, read the project's instructions: AGENTS.md, or CLAUDE.md when it holds the guidance instead of pointing to AGENTS.md. Use its `## Deploy` section for every PR in that repo. When the section is missing, read [references/prepare.md](references/prepare.md) and follow it before the first merge.

## 3. Order

1. A PR stacked on another PR's branch goes after that PR.
2. A PR with migrations goes before PRs whose code needs them.
3. Across repos, the side that accepts both the old and the new shape of shared data deploys first, usually the API before its clients.
4. PRs that touch the same files go in the order they were opened.
5. Everything else, oldest first.

Show the order as a numbered list, one line of reasoning per PR, then start.

## 4. For each PR, in order

**a. Gate.** Read the state, the checks and the unresolved review threads.

- In T3 Code: `pull_request_read` with `include: ["checks", "threads", "body"]`. It has no review decision, so also run `gh pr view <n> --json reviewDecision`.
- Elsewhere:

  ```bash
  gh pr view <n> --json state,isDraft,mergeable,mergeStateStatus,reviewDecision,headRefOid,baseRefName,body,statusCheckRollup \
    --jq '{state,isDraft,mergeable,mergeStateStatus,reviewDecision,headRefOid,baseRefName,hasDeployNotes:(.body|test("(?m)^## Deploy notes")),checks:(.statusCheckRollup|map({name:(.name // .context),result:(if (.conclusion // "") != "" then .conclusion else (.state // .status) end)})|{passed:(map(select(.result=="SUCCESS"))|length),other:map(select(.result!="SUCCESS"))})}'
  bash <mig-review-findings dir>/scripts/pr-threads.sh collect <n>
  ```

  `pr-threads.sh` reads every page of threads and says `"complete": false` when anything was cut short. Treat an incomplete read as not green.

Then:

- Its base must be the default branch. A stacked PR gets retargeted by the cleanup after its base merges, and then needs green checks again.
- `BEHIND`: `gh pr update-branch <n>`, then wait for checks.
- `DIRTY`: merge the default branch into the PR branch, resolve, run the checks, push. Stop when a resolution is not obvious.
- Checks pending: wait without polling. In T3 Code, call `watch_pull_request` and end the turn, and you are woken when something changes. Elsewhere, run `gh pr checks <n> --watch --fail-fast` as one command.
- Checks red: find the cause. Fix real failures on the PR branch. Rerun an infrastructure flake once with `gh run rerun <id> --failed`.
- Unresolved threads, or review bodies and comments that ask for a change: run `mig-review-findings` on the PR and hand it what you just read, so it doesn't collect again. Items it leaves for the user stop the run.
- A human review that requests changes stops the run.
- Server steps that must happen before the merge (a new env var, a package to install, a directory to create), named in the deploy notes or the Deploy section: hand them to `mig-my-turn` and wait for them to be confirmed.

The gate passes when, on the latest head commit, checks are green, every review thread is resolved, no review requests changes, the pre-merge server steps are done, and GitHub reports the PR mergeable. Read the gate again after any push or new review.

**b. Deploy notes.** When the PR body has no `## Deploy notes` section, add one from the diff: write the body to a file and run `gh pr edit <n> --body-file <file>`. Cover migrations (say if any drop or rewrite data), new env vars, queue or scheduler restarts, cache clears, server steps, and the rollback (`git revert <merge commit>`, plus what a migration needs).

**c. Merge.** In T3 Code, `pull_request_merge` with `method: "squash"` and `expectedHeadSha: <headRefOid>`. Elsewhere:

```bash
gh pr merge <n> --squash --match-head-commit <headRefOid>
```

Both refuse the merge when someone pushed after the gate passed. With a merge queue or auto-merge, wait until GitHub reports `MERGED`.

**d. Deploy.** Follow the Deploy section and its `Starts:` line. With `Method: none`, or when the Deploy section says this PR's paths deploy nothing, go straight to cleanup.
- GitHub Actions: start the run by hand first when `Starts:` says so. Then wait with the script next to this file, as one command:

  ```bash
  bash <skill-dir>/scripts/wait-deploy.sh --sha <merge commit sha> --workflow <deploy workflow> [--after <CI workflow>] [--timeout <seconds>]
  ```

  Pass `--after` when the deploy starts after CI; the script watches CI first and fails fast when it goes red. It prints `RUN <workflow> <id> <url>` as soon as a run exists. Exit 0 is deployed, 1 a failed deploy with the log tail, 2 a red CI, 3 no run in time, 4 a disabled or missing workflow. In T3 Code, run it in the background and wait with `t3_background_wait`.
- Platform: run the status command from the Deploy section until it reports the merge commit as deployed.
- Manual: hand the step to `mig-my-turn` when it is installed. Otherwise give the user one block, labeled with the machine ("On <server>"), holding the exact commands. Ask with the question tool for the output or "deployed", and check the reply before going on.
- Then the health check, when the section names one.

Never tell the user a deploy is running until you have a run id or the platform shows it. Exit 3 or 4 from the script: say so plainly and ask.

A deploy the user postpones (they will run it later, or the script refuses to run now): run the cleanup for this PR anyway, list the deploy in the loose ends, and stop before the next PR.

A failed deploy stops the whole run, and leaves the remaining PRs unmerged. Show the failing log tail, then:
- When it failed before production changed (a build, test or packaging step), propose a fix-forward PR.
- When production changed, offer the rollback from the deploy notes.

**e. Clean up.** Run `mig-merged`'s script for this PR:

```bash
bash <mig-merged dir>/scripts/cleanup.sh [--skip-worktree <path>]... <n>
```

In T3 Code, pass `--skip-worktree` for each worktree another thread uses, found as `mig-merged` step 2 describes. Exit 0: done. Exit 3: invoke `mig-merged` with `<n> from mig-merge` to handle the lines the script handed back. Never replace the script or `mig-merged` with a hand-rolled cleanup.

A PR is done when it is merged, its deploy is confirmed healthy, and its cleanup ran.

## 5. Finish

Print the report before anything else: one row per PR with number, title, merge commit, the environment it deployed to and the deploy result. List the PRs that were not merged, and why. Unwatch any PR still watched (`unwatch_pull_request` in T3 Code). End with the loose ends, each naming who acts and what to run:

```text
Loose ends: <PRs left unmerged> | <postponed deploys> | <retargeted PRs waiting for CI> | <dirty worktrees> | none
```

Next, sweep for older merged branches and worktrees with `bash <mig-merged dir>/scripts/cleanup.sh` and no arguments. It changes nothing. Show the `CANDIDATE` lines for confirmation, and run the script with the confirmed PR numbers.

Then invoke `mig-relay` once, when work remains in an order, and pass it the loose ends.

When a cleanup printed a `LAST` line, this thread runs in a worktree that is now detached. Run that command only when this thread needs nothing more: after the user declines the next thread, after the next thread is launched, or right after the report when no hand-off follows. It is the final command of the run.
