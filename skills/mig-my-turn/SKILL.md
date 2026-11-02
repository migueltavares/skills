---
name: mig-my-turn
description: Walk the developer through steps only they can run, such as a server, a dashboard, DNS or a secret, one step at a time, naming the machine for each command. Use when a task needs access the agent lacks, for a manual deploy, or for /mig-my-turn.
metadata:
  credits:
    - skill: wizard
      author: Matt Pocock
      url: https://github.com/mattpocock/skills/tree/main/skills/engineering/wizard
      license: MIT
---

# mig-my-turn

Some steps need the developer's hands: a server the agent can't reach, a dashboard, a DNS record, a secret. A block that leaves out where it runs gets run in the wrong place, so every step names its machine, holds the full command, and waits for the result before the next one.

## 1. Do your part first

Do everything the agent can do before handing over: local setup, config files, migrations on a test database, scripts the user will run. Then list only what needs the user, with one line each on why the agent can't do it.

## 2. One step at a time

Give one step per message, in this shape:

```text
Step <n> of <total>: <what this step achieves>
Where: <your computer | the server <alias> | <dashboard> > <page> | GitHub > <repo> > Settings>

<the exact commands, with full paths, or the exact clicks: Menu > Submenu > Button>

Expected: <the output or what the screen shows>
Reply with the output, or "done".
```

- Use the alias or name the project's AGENTS.md gives the machine. A command that has to run from a directory starts with `cd <dir> &&`.
- Before a step that is hard to undo (a DNS change, a delete, a production restart, a data change), say what it changes and how to undo it, and wait for a yes.

## 3. Check every reply

Compare the reply with what you expected. Anything else means you diagnose it before the next step. Partial output, a warning, or "done" after a step that prints something all get a follow-up question.

Done for a step when its result matches the expectation, or the user decides to skip it.

## Secrets

Secrets never go through chat.

- In T3 Code, call `request_secret`. For a shell command, use `delivery: "file"` and read it inside the command: `TOKEN="$(cat <file>)" <command>`.
- On a machine the agent can't reach, give the user a hidden prompt: `read -rsp 'Token: ' TOKEN; echo`, the command that uses `$TOKEN`, then `unset TOKEN`.
- For a value that belongs in a server's `.env`, name the variable and tell the user to add it with an editor on that machine. List variable names, never values.

## SQL

SQL on real data is read-only (`SELECT`, `EXPLAIN`, `SHOW`) unless the user asks for a change. A write starts with a backup step and its own confirmation.

## Finish

Report what was done, step by step. Lasting facts the steps revealed, such as server versions, paths or how deploys run, go in the project's AGENTS.md, under the section they belong to.
