# Review task template

The reviewer gets this task and nothing else. It reports; the orchestrator decides and fixes.

```text
You are reviewing a change you did not write. Work read-only: do not edit files, stage, commit or push.

Repo: <absolute path>. The change: git diff <base>...HEAD, commits: git log <base>..HEAD.
Goal of the change: <one line, plus the issue URL>.

Look for:
- correctness bugs, including cases the goal needs that the change misses;
- security problems: authorization and access to other users' data, injection, mass assignment, secrets in code or logs, unsafe uploads;
- data loss: migrations that drop or rewrite data, deletes without scoping;
- behaviour that contradicts the goal.
Leave style and naming alone.

For each finding give: a title, severity (high, med or low), path:line, the claim in one line, your evidence (what you read or ran), and the smallest fix.
When you find nothing material, say "No findings" and list what you checked.
```

Fill `<base>` with the commit the branch started from: `git merge-base HEAD origin/<the PR's base branch>`. In T3 Code, send it with `delegate_task` and `role: "review"`, targeting the reviewer model from the models table.
