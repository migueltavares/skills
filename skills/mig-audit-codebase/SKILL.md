---
name: mig-audit-codebase
description: Audit an app for security, performance and reliability problems, verify each finding, file the confirmed ones as issues, and write a safe work order. Use for /mig-audit-codebase, "audit this app", "security review of the whole codebase", or "turn the audit into issues". Add "invisible" for apps whose staff are already trained.
metadata:
  credits:
    - skill: triage, to-tickets
      author: Matt Pocock
      url: https://github.com/mattpocock/skills/tree/main/skills/engineering
      license: MIT
    - skill: blast-radius
      author: poteto
      url: https://github.com/cursor/plugins/blob/main/pstack/skills/blast-radius/SKILL.md
      license: MIT
    - skill: review-findings
      author: gtapps
      url: https://github.com/gtapps/skills/blob/main/skills/review-findings/SKILL.md
      note: Finding verification adapted with the author's permission.
---

# mig-audit-codebase

A whole-app audit for an app that already runs in production. It ends with verified issues on GitHub and an order to fix them in, since every merge deploys.

## 1. Scope

Read the project's AGENTS.md, the README and the deploy setup. Settle:

- **Mode.** Normal, or **invisible**: fixes the app's users never notice, with no changes to workflows, permissions, screens or wording. Use invisible for apps whose staff are already trained on the current behaviour.
- **What is in scope**: the app, its admin panel, its API, background jobs, the server config in the repo.
- Anything the user already knows about or wants left alone.
- Decisions the owner already made. Read the recorded ones (AGENTS.md, `docs/decisions.md`, issues closed as a decision or "won't fix") and don't propose those changes again unless the user asks. A finding that only repeats one goes in the report as "settled", not in the table.
- Policies that decide whether a fix is welcome, asked in one batch when AGENTS.md doesn't answer them: the MFA and password policy for admins, the CI time budget, which monitoring, error reporting and backup tools already run, and whether a new service or a new paid tool is acceptable.

## 2. Map the app

Before judging anything, list: routes and who can reach each, authentication and roles, models holding personal or financial data, file uploads, scheduled and queued jobs, outside services, the deploy path, and how backups work. Run the dependency audits the stack has (`composer audit`, `npm audit`).

## 3. Audit by lens

Run each lens as a read-only subagent in parallel when the host has them, each with the map from step 2. Otherwise go lens by lens.

- **Security**: authorization on every route and action, access to other users' records, mass assignment, validation, uploads, injection, output escaping, secrets in the repo or logs, sessions, rate limits, admin panel access.
- **Data safety**: backups and whether a restore was ever tested, migrations that drop or rewrite data, deletes without scoping, audit trails where the business needs them.
- **Performance**: N+1 queries, missing indexes on filtered and sorted columns, work that belongs in a queue, unbounded queries and exports, caching.
- **Reliability**: a test suite that gates deploys, failed-job handling, error reporting, scheduler health, dependency and runtime versions that are out of support.

For Laravel apps, also go through [references/laravel.md](references/laravel.md).

## 4. Verify every finding

Treat each finding as a claim. Open the code, and run it when reading can't settle the claim. A finding stays only with evidence: a `path:line` you read, or a command and its output. Give each one a severity:

- **Critical**: exploitable now, or data loss is likely.
- **High**: exploitable with some effort, or a serious outage risk.
- **Medium**: a real weakness with limited impact.
- **Low**: hardening and hygiene.

In invisible mode, drop or rewrite any fix that changes what users see or do, and say so.

## 5. Agree the list

Show one table: severity, finding, evidence, proposed fix, whether the fix needs the user (credentials, server access, legal or business decisions), and whether it changes something that works today or adds a service, a tool or CI time. Propose the fix that fits the policies from step 1, and offer the stricter one as an option, not the default. Wait for the user's OK, and apply their edits, before filing anything.

## 6. File the issues

One issue per finding, with `gh issue create --body-file`. Each body has the problem, the evidence, the proposed fix, how to verify it, and "Blocked by #N" where one fix depends on another. Label with severity when the repo has labels for it.

## 7. Write the work order

Write `docs/handoff/<YYYY-MM-DD>-audit.md`, ordered by these rules:

1. A test gate first. When tests don't block deploys yet, that comes before any risky fix, because every merge deploys.
2. Backups before fixes that touch data.
3. Critical and High after that, with blockers before what they block.
4. Related small fixes grouped into one PR. Write "Closes #12, closes #18": GitHub closes only the first issue in "Closes #12 and #18".
5. Items that need the user last, each marked with what it needs.

In a Laravel repo without the test database guard, the first item adds it with `mig-laravel-guardrails`.

Commit the work order on its own branch and open a docs PR for it, so it reaches the default branch before the first fix. Then hand over the first item with `mig-relay`.
