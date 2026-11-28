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

Input: PR numbers in any form (`/mig-merged 12 14`, "PR 12 and 14", "#12, #14"), optionally followed by `from mig-merge` when `mig-merge` calls it. With no numbers, run the sweep in step 1.

`scripts/cleanup.sh`, next to this file, does every deterministic part and has tests. Run it, then handle only the lines it hands back. Run it from any checkout of the PR's repo; it works in the main checkout itself.

## Safety rules

- A branch is deleted only after `gh` reports its PR as `MERGED`, and only when it holds nothing the PR did not. The script checks both, and reads the remote tip again just before deleting.
- Retarget before deleting. Deleting a branch that an open PR uses as its base closes that PR, so the script keeps such a branch and reports it.
- History only moves forward here: plain pushes, merges and cherry-picks.

## 1. Sweep, when no PR numbers were given

Run `bash <skill-dir>/scripts/cleanup.sh` with no arguments. It changes nothing. Each `CANDIDATE` line names a merged PR whose branch or worktree is still around and holds nothing beyond that PR. Show them, and continue with step 2 for the ones the user confirms. `CANDIDATE none` ends the run.

## 2. Run the cleanup

In T3 Code, first find the worktrees other threads use: list the project's unsettled threads with `t3_thread_list` (`settled: false`), and for each one other than this thread, call `t3_worktree_list` with its `threadId`. Pass each of their checkout paths as `--skip-worktree <path>`.

```bash
bash <skill-dir>/scripts/cleanup.sh [--skip-worktree <path>]... <pr>...
```

The script updates the default branch in the main checkout, removes clean worktrees on merged branches, deletes the local and remote branches, and checks the issues each PR closes. Add `--plan` to see what it would do without changing anything.

Exit 0 means nothing is left for you. Exit 3 means some lines need you; the last line repeats them as `Loose ends:`. Exit 1 means git or gh failed: show the `STOP` lines, fix the cause when it is clear, and run the script again. Otherwise stop and show them to the user.

The script keeps a branch whenever anything about it is unproven, and keeps its worktrees with it. A worktree holding untracked files, or ignored files other than dependencies, build output, caches and `.env` copies, is kept as `DIRTY`.

## 3. Handle the lines it hands back

- `OPEN #m uses <branch> as head or base`: when `#m` is stacked on the branch, retarget it with `gh pr edit <m> --base <default branch>`. In that PR's branch or worktree, `git merge origin/<default branch>`; the merged content is already on the default branch, so conflicts usually resolve to its side. Stop and ask when a resolution is not obvious. Run the project's checks, `git push`, tell the user that CI runs again on that PR, then run the script again for the merged PR. When `#m` reuses the branch name for new work, leave the branch alone.
- `LATE <branch>`: commits landed after the merge and would vanish with the branch. Create `<branch>-followup` from `origin/<default branch>`, cherry-pick the listed commits, push, and open a PR that names the original. In T3 Code, link it with `link_pull_request`. The old branch stays until that PR exists.
- `DIRTY <path>`: leave it. It goes in the loose ends as "you: commit or drop the changes in `<path>`".
- `ISSUE <url> is still open`: close a fully delivered issue with `gh issue close <url> --comment "Delivered in #<n>."`. On a partly delivered one, comment with what the PR did and what is left, and leave it open.
- `PARTIAL #N was closed`: GitHub closed it because of "Closes part of #N" wording. Reopen it with `gh issue reopen <N>` and the same kind of comment.
- `SKIP #n is OPEN` (or `CLOSED`): not merged. When the user wants the agent to merge it, ask them to run `/mig-merge <n>`, or read `mig-merge/SKILL.md` and follow its full gate and deploy wait when they already gave merge approval in this thread (`mig-merge` disables model invocation, so a Skill tool call refuses it). Never merge with a bare `gh pr merge` or `pull_request_merge`, which skips the gate and the deploy wait.
- `CHANGED <branch>`: someone pushed after the merge. Treat it like `LATE`.
- `KEPT <main checkout> ...`: the main checkout could not switch to or fast-forward the default branch. List it as a loose end for the user.

Write comment text to a file and pass it with `--body-file`, never inline in the command.

Done when the script exits 0, or every line it handed back is handled or listed as a loose end.

## Report and hand off

One line per PR: number, merge commit, branches deleted, worktrees removed, PRs retargeted, late commits moved, issues closed. Then the loose ends, each naming who acts and what to run, such as "you: commit or drop the changes in `<path>`" or "CI: #14 reruns after the retarget, nothing to do". Print only the parts that apply, or `Loose ends: none`.

Then:
- Called with `from mig-merge`: return the report lines and the `LAST` line, if any, to `mig-merge`, without a hand-off. `mig-merge` hands off once, after its last PR.
- The next step needs the user first (credentials, a server step, a decision): say exactly what, and stop.
- Work remains in an order (a plan in `docs/handoff/`, open issues this thread was working through, a later phase): invoke `mig-relay` for the next prompt, and pass it the loose ends so it doesn't collect them again.
- Nothing remains: stop after the report.

When the script printed `DETACHED <path>` and a `LAST git -C <main> worktree remove <path>` line, this thread runs in that worktree. The paths are shell-quoted, so run the command as printed. Run it only once this thread needs nothing more: after the user declines the next thread, after the next thread is launched, or right after the report when no hand-off follows. This thread's shell stops working once its folder is gone, so tell the user the worktree is gone and this thread is finished. Called with `from mig-merge`, leave it to `mig-merge`.
