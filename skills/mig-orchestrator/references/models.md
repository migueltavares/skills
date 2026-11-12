# Models by role

Defaults as of November 2026. Model names change often, so each run checks what is available instead of trusting this table blindly.

## Which table wins

1. The project's AGENTS.md, section `## Models`, for that project.
2. `~/.agents/mig/models.md`, for every project on this machine.
3. This file.

Both override files use the same rows: `- <Role>: <model id>, <option>=<value>`. For example `- Implement: gpt-6.1-sol, reasoningEffort=medium`.

## Defaults

| Role | Default | When it's unavailable |
| --- | --- | --- |
| Orchestrate: plan, judge, security logic, commit | The main thread, Claude Opus 5.5 | The strongest model available |
| Implement a step | Claude Sonnet 5.5, effort medium | GPT-6.1 Sol, reasoning medium |
| Mechanical work: renames, copy edits, translation drafts, test scaffolding | GPT-6.1 Terra, reasoning low (trial, below) | GPT-6.1 Sol, reasoning low |
| Read-only discovery: find files, map callers | Claude Haiku 5.5 | Claude Sonnet 5.5 |
| Independent review | The other provider from whoever wrote that part of the diff: Claude Opus 5.5 for code Sol wrote, GPT-6.1 Sol at high for code Sonnet or the main Claude thread wrote | A fresh-context subagent on the same model, reported as same-provider |

Sonnet implements by default because Sol at high was slow for little gain on these tasks. When Sol implements, it runs at medium.

## The Terra trial

Terra is new and cheap, and its row starts as a trial. When no override file has a Mechanical row yet:

1. Give the first mechanical step to both Terra and Sol, each with `isolation: "worktree"`, so they work in separate checkouts.
2. In each child's checkout, read `git diff` and run the step's Verify, and judge both against the contract as in step 5 of the skill.
3. Bring the better diff into this checkout with `git -C <child checkout> diff | git apply`, run Verify again here, and write the winner as `- Mechanical: <model id>, <option>=<value>` in `~/.agents/mig/models.md`, with the date and one line on why.

## Reading what's available

In T3 Code, `orchestrator_capabilities` lists each provider's `providerInstanceId`, its models, and their options. Codex models take `reasoningEffort`, Claude models take `effort`. Use the exact ids it returns, such as `claude-opus-5-5`, `claude-sonnet-5-5`, `claude-haiku-5-5`, `gpt-6.1-sol` and `gpt-6.1-terra`. Pass `search` to find models the short list leaves out.

When a model from the table isn't listed, pick the closest one by role from what is, and say which one you used in the report.

Outside T3 Code:

- Claude Code: the Agent tool's `model` takes `opus`, `sonnet` or `haiku`.
- Codex: its subagent tool takes the model id.
- A cross-provider review goes through the other CLI in read-only mode when it is installed: `codex exec --sandbox read-only "<task>"` or `claude -p --permission-mode plan "<task>"`.
