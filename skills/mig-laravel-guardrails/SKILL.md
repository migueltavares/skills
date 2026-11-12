---
name: mig-laravel-guardrails
description: Stop agents from wiping Laravel databases. Installs a command guard for Claude Code and Codex, and a test database guard in a Laravel repo. Use once per machine, in a Laravel repo whose TestCase has no database guard, or after an agent ran migrate:fresh, db:wipe or tests against a real database.
metadata:
  credits:
    - skill: git-guardrails-claude-code
      author: Matt Pocock
      url: https://github.com/mattpocock/skills/tree/main/skills/misc/git-guardrails-claude-code
      license: MIT
    - skill: correct
      author: poteto
      url: https://github.com/cursor/plugins/blob/main/pstack/skills/correct/SKILL.md
      license: MIT
---

# mig-laravel-guardrails

Agents with a cached config have run `RefreshDatabase` against real local databases. A note in memory did not stop it, so this skill installs checks that fail instead. It has two parts, and after setup nobody needs to call it again.

## Machine part

The guard is `scripts/laravel-db-guard.sh` in this skill's directory, run before every shell command in Claude Code and Codex, in every permission mode. It blocks:

- `migrate:fresh`, `migrate:refresh`, `migrate:reset` and `db:wipe`, in any form artisan accepts: quoted, abbreviated (`migrate:fr`), inside ssh commands, or through `Artisan::call` in tinker.
- Test runs while `bootstrap/cache/config.php` exists, since a cached config ignores `phpunit.xml` and the environment, and test runs in the same command as `config:cache` or `optimize`, which create that file.
- Test runs whose database is not SQLite in memory or a database whose name contains "test". The guard reads `phpunit.xml` as XML, so commented-out lines don't count, and accepts `DB_CONNECTION=sqlite DB_DATABASE=:memory:` written directly in front of the test command.

Steps:

1. Run `bash <skill-dir>/scripts/install-global.sh --check`, with `<skill-dir>` resolved to this skill's absolute installed path.
2. When a line says `MISSING`, tell the user what the install changes (their global Claude Code settings, Codex hooks and Codex rules, each backed up first) and run `bash <skill-dir>/scripts/install-global.sh`.
3. Tell the user that Codex asks them to trust the new hook on its next start, and to approve it.

Done when `--check` prints no `MISSING` line. Installed as a Claude Code plugin, the guard is already active through the plugin's own hook, so step 2 only adds Codex and the deny rules.

## Repo part

Applies when the repo has an `artisan` file. The repo guard is present when `tests/TestCase.php` (or `tests/CreatesApplication.php`) calls `guardTestDatabase`.

1. When it's missing, read [references/repo-guard.md](references/repo-guard.md) and add the TestCase guard, the `phpunit.xml` lines and the guard's own test.
2. Run the guard test, then the full suite, and show both results.
3. Ship it on its own branch and PR (`chore/test-database-guard`), or as the first commit of the PR you are already working on. The default branch deploys in most repos, so never commit to it directly.
4. Offer the CI part from the same reference. Add it only when the user agrees.

Done when the guard test and the full suite pass, and the change is in a PR.

## Proving the guard

Prove it only through its own test, which calls `guardTestDatabase` directly with fake values. Don't improvise a live proof: no `config:cache` before a test run, no unreachable or scratch database to watch the guard fire, no suite run aimed at a real database. Each of those puts a database at risk if the guard is wrong, and the direct test already covers them.

A project may make the guard stricter, such as one exact database name. Keep the `DB_URL` check, and refuse parallel runs as [references/repo-guard.md](references/repo-guard.md) explains.
