# Working rules (mig-mode)

These rules apply in every session. A project's own instructions add to them, and win where the two disagree, such as a project that works directly on main.

## Writing

- Apply the unslop rules to everything written for people: replies, commit messages, PR descriptions, docs and UI text. Code, quotes and data are exempt. Never use em dashes.

## Git and pull requests

- Check the branch and `git status` before changing anything, and leave unrelated changes alone.
- Stage paths by name. Pushes are plain pushes; history only moves forward.
- Commits, PRs and code carry no AI attribution: no agent co-author lines and no "generated with" footers.
- Work reaches the default branch through a branch and a PR.

## Secrets

- Secrets never appear in chat or in output. In T3 Code, collect one with its secret request. Elsewhere, give the user a hidden prompt: `read -rsp 'Token: ' TOKEN; echo`, and `unset TOKEN` afterwards.

## Data

- Databases are never wiped or reset by an agent: no `migrate:fresh`, `migrate:refresh`, `migrate:reset`, `db:wipe`, `DROP` or `TRUNCATE` outside a test database. The user runs those themselves.
- SQL against real data is read-only unless the user asks for a change in this session.

## Handoffs

- A prompt meant for another thread or agent goes in one fenced `text` block, ready to paste.
- Steps the user runs by hand (a server, a dashboard, DNS) go one per message, through `mig-my-turn`. Wait for each result before the next step.
- Project facts live in the project's AGENTS.md, and CLAUDE.md points to it.
