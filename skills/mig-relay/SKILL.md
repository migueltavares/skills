---
name: mig-relay
description: Find the next item in a project's work order and write the ready-to-paste prompt that starts its thread. Use for /mig-relay, when the user asks for the next prompt, at the end of a step or phase, and after mig-merged or mig-merge.
metadata:
  credits:
    - skill: handoff
      author: Matt Pocock
      url: https://github.com/mattpocock/skills/tree/main/skills/productivity/handoff
      license: MIT
    - skill: tackle-task
      author: gtapps
      url: https://github.com/gtapps/skills/blob/main/skills/tackle-task/SKILL.md
      note: Premise check adapted with the author's permission.
    - skill: safe-pause
      author: Mayank
      url: https://github.com/mayank-io/mstack/tree/main/plugins/dev/skills/safe-pause
      license: MIT
---

# mig-relay

The user works one issue or phase per thread, each with a fresh context. A thread ends here, with a prompt the next thread can run without anything else: no memory of this conversation, no running history.

## 1. Find the work order

Look, in this order:

1. The plan this thread has been working from, or else the newest file in `docs/handoff/` (`ls -t docs/handoff/*.md`).
2. An order written in the project's AGENTS.md or CLAUDE.md, or in a parent issue.
3. Open issues and their "Blocked by" links: `gh issue list --state open --json number,title,body,labels`.

When none of these gives an order, propose one, show it, and on the user's OK write it to `docs/handoff/<YYYY-MM-DD>-<slug>.md`. Order by these rules:
- The test gate and backups come first, because merges deploy.
- Blockers come before what they block.
- Items that need the user (credentials, legal, server access, a design decision) come last, each marked with what it needs.

## 2. Check the next item

Take the first item not done. Cross-check with `gh issue view <n>` and recently merged PRs, since the plan file may lag behind.

Before writing its prompt, try to prove it is no longer needed:
- Read the issue and open the files and symbols it names.
- Read `git log` and the merged PRs since the issue was written. Earlier work often fixes part of it.

Reach one verdict, citing the files you read or the commands you ran:
- **Still needed** as written.
- **Needed, scope changed**: say what changed.
- **Already done**: show the evidence, suggest closing the issue, and move to the next item.
- **Blocked on the user**: say exactly what they must do first, and stop without a prompt.

## 3. Write the prompt

One fenced `text` block of about 40 lines or fewer, shaped like this:

```text
<Project>: <stack line, e.g. Laravel 12, Filament 4, PHP 8.3, Pest>. Repo: <path>.
Read first: AGENTS.md, <plan file>, issue #<N>.
Last step: <PR #, one or two lines on what changed that this step builds on>.
Task: #<N> <title>. <Required behaviour, including any scope change from the check>.
Where: <files and symbols as path:line>.
Done when: <observable behaviour>, and <the project's check commands> are green.
Stop and ask if: <a named file or symbol is missing> / <the fix needs changes outside this scope> / <an unrelated test goes red>.
Workflow: <the project's workflow from AGENTS.md>. <Model and delegation rules from the project's instructions>. Mark #<N> done in <plan file> in the same commit or PR.
Lessons that apply: <only the ones that bear on this task>.
After this: <the remaining order, short>.
Start with #<N>.
```

Write the Workflow line from the project's AGENTS.md. When it says nothing, use the default: "Branch <name> from origin/<default branch>. Open a PR with "Closes #<N>" (one "closes" per issue). Never push to <default branch>." A project that commits straight to the default branch gets that instead, never the branch and PR wording.

Carry only the last step. History lives in the plan file, which the next thread updates. Every path and command in the prompt must exist, and no secret goes in it.

Keep "Lessons that apply" short. A lesson that has already appeared in three prompts is a project rule: offer to move it into AGENTS.md, and from then on cite AGENTS.md instead of repeating it.

## 4. Hand over

1. Print the block.
2. Print the loose ends: uncommitted worktrees, untracked files, open PRs, checks not run. Give each one a verdict, either "fix now: <what you would do>" or "leave, because <reason>". Print `Loose ends: none` when there are none.
3. Send a push notification when the host has one (`PushNotification` in Claude Code): "<project>: next prompt ready, #<N>".
4. Ask: "Open the next thread? Reply go." When any loose end says "fix now", ask instead: "Reply go to fix the loose ends marked fix now and open the next thread."

On "go", fix the loose ends marked "fix now" first. Then, in T3 Code, open a thread in the same project with `t3_thread_launch`:
- the prompt as its first message;
- `modelSelection` set to the orchestrator role from the project's `## Models` section or `~/.agents/mig/models.md`, else this thread's model, with the effort the prompt asks for;
- the same workspace strategy as this thread (a new worktree when this thread runs in one).

Outside T3 Code, the prompt is ready to paste.

**Standing permission.** When the user, or the prompt this thread started from, says to keep going without asking, skip the question and launch. Copy the permission into the new prompt as its own line ("Standing permission: launch the next thread without asking, until an item is blocked on the user"), so it carries forward. Stop at the first item blocked on the user, or when the user withdraws it.
