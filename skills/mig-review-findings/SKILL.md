---
name: mig-review-findings
description: Verify the review comments on a pull request against the current code, then fix only the confirmed ones. Use for /mig-review-findings <PR>, when a PR has bot or human review findings to handle, and from mig-merge or mig-orchestrator before a merge.
metadata:
  credits:
    - skill: review-findings
      author: gtapps
      url: https://github.com/gtapps/skills/blob/main/skills/review-findings/SKILL.md
      note: Adapted with the author's permission.
    - skill: babysit-pr
      author: Theo Browne
      url: https://github.com/t3dotgg/tstack/blob/main/skills/babysit-pr/SKILL.md
      license: MIT
---

# mig-review-findings

Every review comment is a hypothesis. Settle it from the current code and real behavior, never from the reviewer's quoted snippet or line number. Fix what holds up, answer what doesn't, and keep the PR at the size its goal needs.

Input: a PR number, or the PR for the current branch (`gh pr view --json number`). Add `report` to stop after classifying.

## 1. Collect

Read every review thread, review body and PR comment:

```bash
gh api graphql -F o=<owner> -F r=<repo> -F n=<number> -f query='
query($o:String!,$r:String!,$n:Int!){repository(owner:$o,name:$r){pullRequest(number:$n){
  headRefOid
  reviewThreads(first:100){nodes{id isResolved isOutdated path line
    comments(first:20){nodes{databaseId author{login} body createdAt}}}}
  reviews(last:30){nodes{author{login} state body submittedAt commit{oid}}}
  comments(last:50){nodes{author{login} body createdAt}}
}}}'
```

Keep unresolved threads, plus review bodies and comments that ask for a change. Merge duplicates, since two bots often flag the same line. Order the list with security, data loss and correctness first.

Done when every open request on the PR appears in the list exactly once.

## 2. Verify

For each finding:

1. Locate the code by symbol. The review may target an older commit, and the code may have moved.
2. Read the current file.
3. Compare the claim with what the code does. When reading cannot settle it, run it: a focused test, a `tinker` call, a request against the local app.
4. Judge the proposed fix separately from the claimed problem.

Classify it:

- **Confirmed**: the claim is accurate, and fixing it improves the code.
- **Refuted**: the claim or its fix is wrong.
- **Partial**: a real problem, but the framing or the fix is wrong.
- **Needs investigation**: name exactly what evidence would settle it.
- **Out of scope**: real, but outside the PR's goal. Extra tests, edge cases that don't matter here, small performance costs and new features go here as follow-ups.

With more than three independent findings, verify them in parallel read-only subagents (T3 Code `delegate_task`, or the host's own agent tool), grouped by file. Otherwise verify them one by one.

Done when each finding has a class and evidence: a `path:line` you read or a command you ran. A paraphrase of the review is not evidence.

## 3. Report

One block per finding:

```text
### <n>. <title> [high|med|low]
Claim: <one line>
Evidence: <path:line or command, and what it showed>
Verdict: Confirmed | Refuted | Partial | Needs investigation | Out of scope
Action: <the change, or none>
```

With `report`, stop here.

## 4. Act

1. Fix the Confirmed findings and the valid part of the Partial ones. Everything else stays as it is.
2. Run the checks the project's AGENTS.md (or CLAUDE.md, or CI workflow) names. A red check stops here, with its output shown.
3. Commit with a message that names what was fixed, then push the PR branch with a plain `git push`.
4. Reply on each thread, then resolve it:
   - Fixed: `Fixed in <sha>: <one line>`.
   - Refuted or Out of scope: the reason in one or two sentences. For Out of scope, say it is listed as a follow-up.

   Reply with `gh api repos/<owner>/<repo>/pulls/<number>/comments/<databaseId>/replies -f body='<text>'`. Resolve with the GraphQL mutation `resolveReviewThread(input:{threadId:"<id>"})`.
5. Leave Needs investigation threads open. List them numbered and stop for the user, who answers like "1. agree, 2. skip because ...".

Done when every thread is resolved or listed for the user, and the checks are green on the pushed head.

## Finish

End with the counts per verdict, the commit, and the follow-ups as a list. File follow-ups as issues only when the user or the calling skill asks for it.
