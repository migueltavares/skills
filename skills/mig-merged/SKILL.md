---
name: mig-merged
description: Clean up after merged pull requests. Verify each merge, update the default branch, retarget stacked PRs, remove merged worktrees and branches, then hand off with mig-relay. Use for /mig-merged [PR numbers], when the user says a PR is merged, and from mig-merge after each merge.
metadata:
  credits:
    - skill: handoff
      author: Matt Pocock
      url: https://github.com/mattpocock/skills/tree/main/skills/productivity/handoff
      license: MIT
    - skill: wrap
      author: gtapps
      url: https://github.com/gtapps/skills/blob/main/skills/wrap/SKILL.md
      note: Loose ends line adapted with the author's permission.
---

# mig-merged

A merged PR leaves branches, worktrees and sometimes a stacked PR pointing at a branch that is about to disappear. This skill clears all of it, so the checkout sits on an up-to-date default branch and the next step can start.

Input: PR numbers in any form (`/mig-merged 12 14`, "PR 12 and 14", "#12, #14"), optionally followed by `from mig-merge` when `mig-merge` calls it. With no numbers, find candidates: merged PRs whose head branch still exists locally or as a worktree.

```bash
gh pr list --state merged --limit 30 --json number,headRefName,headRefOid,mergedAt
git branch --format='%(refname:short)'
git worktree list --porcelain
```

Show the candidates and clean up the ones the user confirms.

## Safety rules

- Delete a branch only after `gh` reports its PR as `MERGED`, and only when the branch holds nothing the PR did not (step 4).
- Retarget before deleting. Deleting a branch that an open PR uses as its base closes that PR.
- History only moves forward here: plain pushes, merges and cherry-picks.

## Steps

Run from the main checkout of the PR's own repo, the first entry in its `git worktree list`. When the PR belongs to a repo other than the working directory, run every step there, including step 2, with `git -C <path>` or `cd <path>`.

**1. Verify.** For each PR:

```bash
gh pr view <n> --json state,mergedAt,mergeCommit,headRefName,headRefOid,baseRefName
```

A PR that is not `MERGED` is skipped and reported. When the user wants the agent to merge it, invoke `mig-merge` for it. Never merge with a bare `gh pr merge`, which skips the gate and the deploy wait.

**2. Update the default branch.** `git fetch --prune origin`, switch to the default branch, `git pull --ff-only`. Uncommitted changes in the main checkout come along when the switch and pull succeed: list them in the report. Stop and ask only when git refuses because they conflict.

**3. Retarget stacked PRs.** For each merged head branch:

```bash
gh pr list --state open --base <headRefName> --json number,headRefName
```

For each PR found:
1. `gh pr edit <m> --base <default branch>`.
2. In that PR's branch or worktree, `git merge origin/<default branch>`. The merged content is already on the default branch, so conflicts usually resolve to its side. Stop and ask when a resolution is not obvious.
3. Run the project's checks, then `git push`.
4. Tell the user that CI runs again on that PR before it can merge.

**4. Rescue late commits.** Commits pushed to a branch after its PR merged would vanish with the branch. Check both copies:

```bash
git rev-list <headRefOid>..<branch>          # local
git rev-list <headRefOid>..origin/<branch>   # remote, if it still exists
```

When git reports `<headRefOid>` as an unknown revision, fetch it first with `git fetch origin pull/<n>/head`. When either check lists commits, create `<branch>-followup` from `origin/<default branch>`, cherry-pick them, push, and open a PR that names the original. In T3 Code, link it with `link_pull_request`. The old branch stays until that PR exists.

**5. Remove worktrees.** For each worktree on a merged branch:
- Skip it when `git -C <path> status --porcelain` shows changes. It goes in the loose ends line.
- In T3 Code, skip it when an open thread still uses it (`t3_worktree_list`, `t3_worktree_status`).
- Otherwise `git worktree remove <path>`.

Then run `git worktree prune`.

**6. Delete branches.**
- Local: when `git merge-base --is-ancestor <branch> <headRefOid>` succeeds, `git branch -D <branch>`. Squash merges make `git branch -d` refuse, and the ancestor check is what makes `-D` safe.
- Remote: `git push origin --delete <branch>`, unless `git ls-remote --heads origin <branch>` shows GitHub already removed it.

**7. Close the issues.** For each issue the PR body names with `Closes #N`, `gh issue view <N> --json state` should show `CLOSED`. Close a fully delivered issue that stayed open with `gh issue close <N> --comment "Delivered in #<n>."`. On a partly delivered one, comment with what the PR did and what is left, and leave it open. GitHub closes an issue for phrases like "Closes part of #N" too: reopen such an issue with `gh issue reopen <N>` and the same comment.

Done when every merged PR's branch and clean worktrees are gone, its issues are closed or commented, every stacked PR targets the default branch, and the main checkout is on the updated default branch.

## Report and hand off

One line per PR: number, merge commit, branches deleted, worktrees removed, PRs retargeted, late commits moved, issues closed. Then the loose ends. Each one names who acts and what to run, such as "you: commit or drop the changes in `<path>`" or "CI: #14 reruns after the retarget, nothing to do". Print only the parts that apply, or `Loose ends: none`.

Then:
- Called with `from mig-merge`: return here. `mig-merge` hands off once, after its last PR.
- The next step needs the user first (credentials, a server step, a decision): say exactly what, and stop.
- Work remains in an order (a plan in `docs/handoff/`, open issues this thread was working through, a later phase): invoke `mig-relay` for the next prompt.
- Nothing remains: stop after the report.
