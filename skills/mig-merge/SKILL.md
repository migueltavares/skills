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
- Run `gh workflow list --all` and read the deploy workflows in `.github/workflows/`. Note how each one starts: on push to the default branch, after another workflow finishes (`workflow_run`, usually CI), by hand (`workflow_dispatch`), or on a release tag. A workflow marked disabled deploys nothing.
- A hosting platform that deploys on push (Forge, Ploi, Vercel, Netlify, a PaaS) means the platform deploys. Look for its API or CLI. Ask the user for a read-only token with the host's secret tool (`request_secret` in T3 Code), and write the status command into the section, so later runs check the deploy themselves instead of asking the user.
- Nothing of the above means a manual deploy. Ask the user where they run it (a server alias, never a secret), the directory, the command, and how they know it worked.
- A repo that ships nothing on merge (a library, a docs or skills repo) gets `Method: none`. Confirm it with the user before writing it.

Then write the section into the file that owns the guidance, never into both. When neither file exists, create AGENTS.md, plus a CLAUDE.md that holds only `@AGENTS.md`.

```markdown
## Deploy

- Trigger: merge to `main`.
- Method: GitHub Actions, workflow `deploy.yml`.
  (Or: Platform, <name>, status with `<command>`. Or: Manual, on <server>, run `cd <dir> && ./deploy.sh`.)
- Starts: on push. (Or: after the CI workflow passes on `main`. Or: by hand, `gh workflow run deploy.yml --ref main`. Or: on a release tag, `<command>`.)
- Environment: production, <URL>.
- Healthy when: the workflow run succeeds, and <URL> returns 200.
```

The edit goes in a small docs PR. Ask the user whether to add it to the end of this run. A yes approves merging that docs PR in this run too.

## 3. Order

1. A PR stacked on another PR's branch goes after that PR.
2. A PR with migrations goes before PRs whose code needs them.
3. Across repos, the side that accepts both the old and the new shape of shared data deploys first, usually the API before its clients.
4. PRs that touch the same files go in the order they were opened.
5. Everything else, oldest first.

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
- Review threads: list the unresolved ones. REST comments can't show whether a thread is resolved, so use GraphQL:

  ```bash
  gh api graphql -F owner=<owner> -F repo=<repo> -F n=<n> -f query='
    query($owner:String!,$repo:String!,$n:Int!){repository(owner:$owner,name:$repo){pullRequest(number:$n){
      reviewThreads(first:100){nodes{isResolved path line comments(first:1){nodes{author{login} body}}}}}}}' \
    --jq '[.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved|not)]'
  ```

  Any unresolved thread: run `mig-review-findings` on the PR. Items it leaves for the user stop the run.
- A human review that requests changes stops the run.
- Server steps that must happen before the merge (a new env var, a package to install, a directory to create), named in the deploy notes or the Deploy section: hand them to `mig-my-turn` and wait for them to be confirmed.

The gate passes when, on the latest head commit, checks are green, every review thread is resolved, no review requests changes, the pre-merge server steps are done, and GitHub reports the PR mergeable.

**b. Deploy notes.** When the PR body has no deploy notes, add a `## Deploy notes` section from the diff with `gh pr edit <n> --body-file <file>`. Cover migrations (say if any drop or rewrite data), new env vars, queue or scheduler restarts, cache clears, server steps, and the rollback (`git revert <merge commit>`, plus what a migration needs).

**c. Merge.**

```bash
gh pr merge <n> --squash --match-head-commit <headRefOid>
```

`--match-head-commit` refuses the merge when someone pushed after the gate passed. With a merge queue or auto-merge, wait until GitHub reports `MERGED`.

**d. Deploy.** Follow the Deploy section and its `Starts:` line. With `Method: none`, go straight to cleanup.
- GitHub Actions: start the run by hand first when `Starts:` says so. Then find it with one background command instead of a loop you write each time:

  ```bash
  sha=<merge commit sha>; for i in $(seq 1 36); do
    id=$(gh run list --commit "$sha" --workflow <deploy workflow> --json databaseId --jq '.[0].databaseId')
    [ -n "$id" ] && exec gh run watch "$id" --exit-status; sleep 10; done; echo "no deploy run after 6 minutes"; exit 1
  ```

  When the deploy starts after CI, CI runs first, so allow for its time. In T3 Code, run the command in the background and wait with `t3_background_wait`.
- Platform: run the status command from the Deploy section until it reports the merge commit as deployed.
- Manual: hand the step to `mig-my-turn` when it is installed. Otherwise give the user one block, labeled with the machine ("On <server>"), holding the exact commands. Ask with the question tool for the output or "deployed", and check the reply before going on.
- Then the health check, when the section names one.

Never tell the user a deploy is running until you have a run id or the platform shows it. When no run appears in time, say so plainly, check whether the workflow is disabled or waits on CI, and ask.

A deploy the user postpones (they will run it later, or the script refuses to run now): run the cleanup for this PR anyway, list the deploy in the loose ends, and stop before the next PR.

A failed deploy stops the whole run, and leaves the remaining PRs unmerged. Show the failing log tail (`gh run view <id> --log-failed | tail -50`), then:
- When it failed before production changed (a build, test or packaging step), propose a fix-forward PR.
- When production changed, offer the rollback from the deploy notes.

**e. Clean up.** Invoke `mig-merged` with `<n> from mig-merge`, so it skips its own hand-off.

A PR is done when it is merged, its deploy is confirmed healthy, and its cleanup ran.

## 5. Finish

Print the report before anything else: one row per PR with number, title, merge commit, the environment it deployed to and the deploy result. List the PRs that were not merged, and why. Unwatch any PR still watched (`unwatch_pull_request` in T3 Code). End with the loose ends, each naming who acts and what to run:

```text
Loose ends: <PRs left unmerged> | <postponed deploys> | <retargeted PRs waiting for CI> | <dirty worktrees> | none
```

Then, after the report is printed, invoke `mig-relay` once, when work remains in an order.
