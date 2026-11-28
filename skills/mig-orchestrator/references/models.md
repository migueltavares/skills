# Models by role

Defaults as of November 2026. Model names change often, so each run checks what is available instead of trusting this table blindly.

## Override rows

The project's `## Models` section and `~/.agents/mig/models.md` override this table, in that order, as `mig-orchestrator` step 3 says. Their rows use the keys below: `- <Key>: <model id>, <option>=<value>`, with `then <model id>, <option>=<value>` for a fallback. For example `- Implement: claude-sonnet-5-5, effort=medium, then gpt-6.2-sol, reasoningEffort=medium`.

## Defaults

| Key | Role | Default | When it's unavailable |
| --- | --- | --- | --- |
| Orchestrate | Plan, judge, security logic, commit | The main thread, Claude Opus 5.5 | The strongest model available |
| Implement | Implement a step | Claude Sonnet 5.5, effort medium | GPT-6.2 Sol, reasoning medium |
| Heavy | Implement a heavy step: many files, a hard algorithm, a step that came back twice | Gemini 4 Neon, thought_level high | Claude Sonnet 5.5, effort high |
| Mechanical | Renames, copy edits, translation drafts, test scaffolding | Gemini 3.8 Flash, thought_level low | GPT-6.2 Sol, reasoning low |
| Discovery | Read-only lookups: find files, map callers | Claude Haiku 5.5 | Gemini 3.8 Flash, thought_level low, then Claude Sonnet 5.5 |
| Verify | Check review findings for `mig-review-findings` | Claude Sonnet 5.5, effort medium | GPT-6.2 Sol, reasoning medium |
| Review | Independent review: a provider that didn't write that part of the diff | Gemini 4 Neon at high for code Claude or Sol wrote, Claude Opus 5.5 for code Gemini wrote. GPT-6.2 Sol at high is the second choice for code Claude or Gemini wrote | A fresh-context subagent on the same model, reported as same-provider |

Sonnet implements by default because Sol at high was slow for little gain on these tasks. When Sol implements, it runs at medium.

Gemini 4 Neon reviews first because it shares no provider with the Claude or Sol code it reads. A Neon implementer leaves Opus to review that step. Gemini 3.8 Flash costs less than Neon and fits mechanical and lookup work, not security logic or review. Neon takes `thought_level=xhigh` for a review of security logic or a diff over about 400 lines.

## Comparing two models

Only when the user asks for a comparison, such as GPT-6.1 Terra against Gemini 3.8 Flash for the Mechanical row:

1. Give the same step to both, each with `isolation: "worktree"`, so they work in separate checkouts.
2. In each child's checkout, read `git status` and `git diff`, run the step's Verify, and judge both against the contract as in step 5 of the skill.
3. Bring the better result into this checkout, new files included (`git diff` leaves out untracked files), run Verify again here, and write the winner as an override row in `~/.agents/mig/models.md`, with the date and one line on why.

## Reading what's available

In T3 Code, `orchestrator_capabilities` lists each provider's `providerInstanceId`, its models, and their options. Codex models take `reasoningEffort`, Claude models take `effort`, and Gemini models take `thought_level` (`low`, `medium`, `high`, plus `xhigh` on Neon and Hydrogen). Use the exact ids it returns, such as `claude-opus-5-5`, `claude-sonnet-5-5`, `claude-haiku-5-5`, `gpt-6.2-sol`, `gpt-6.1-terra`, `gemini-4-neon` and `gemini-3.8-flash`. Always pass `thought_level`, since the defaults differ by model. Pass `search` to find models the short list leaves out.

Gemini runs through the `antigravity` provider instance, so a Gemini target is `{providerInstanceId: "antigravity", model: "gemini-4-neon", options: {thought_level: "high"}}`. `options` is an object of option ids and values for every provider. Its usage counts against the signed-in Google account's plan. Antigravity also lists Claude models; run those on the Claude provider instead. Skip its `gemini-pro-orchestrator-*` entries for children. When `antigravity` is missing or can't run child tasks, use the next model in the row.

When a model from the table isn't listed, pick the closest one by role from what is, and say which one you used in the report.

Outside T3 Code, Gemini isn't available, so rows that name it fall through to their next model:

- Claude Code: the Agent tool's `model` takes `opus`, `sonnet` or `haiku`.
- Codex: its subagent tool takes the model id.
- A cross-provider review goes through the other CLI in read-only mode when it is installed: `codex exec --sandbox read-only "<task>"` or `claude -p --permission-mode plan "<task>"`.
