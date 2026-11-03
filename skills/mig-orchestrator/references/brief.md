# Brief template

The implementer has no access to this conversation. A brief that leans on it fails silently: the implementer guesses, and the guess shows up later at review. Implementers fail from missing anchors and missing stopping conditions far more than from missing code.

```text
Repo: <absolute path>, branch <branch>, base commit <sha>. Read AGENTS.md first.
Goal: <the user's goal in one line, so trade-offs go the right way>.

Step <n>: <imperative title>.
Where: <path:line -> symbol> for each place the change goes.
Reuse: <the existing helper or pattern to follow, with path:line>.
Contract: <the behaviour that must be true afterwards, observable by someone who never read this brief>.
Verify: <exact command> exits 0. <Name the new test that fails before the change and passes after.>
Fence: change only <files or areas>. Leave <the adjacent thing> alone.
Stop and ask if: a named file or symbol is missing or has moved; the contract needs changes outside the fence; a test outside this step goes red; Verify passes for a reason the contract doesn't explain.

Rules: do not stage, commit, push or open a PR. Run only the test files for this step, never the full suite, since other implementers may be testing at the same time and fakes such as Storage::fake share one directory. <Project rules that apply.>
Report: the files you changed, the Verify output, and anything you could not do, with the reason.
```

## Writing it

- **Ground every anchor.** Open the file and find the symbol before writing `Where`. The symbol locates the work; the line number is a citation that drifts. When they disagree later, the symbol wins.
- **Contracts state behaviour, never the edit.** "A visit at 23:59 counts on that day" can be checked by anyone. "Update the date logic" can't.
- **Verify is a command.** A check that asks the implementer to judge its own work isn't one. When you can't write the command, the step isn't decided yet.
- **Code only where prose can't be exact.** A schema, a signature, a regex or a state transition can go in as a snippet of five lines or fewer. Never a whole function, never a diff.
- **Skip what other skills own.** Branching, commits and PRs belong to the orchestrator, so the brief never mentions them beyond the rule above.
