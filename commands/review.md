---
description: Rule on a loomcycle run whose answer is held for review — approve it, send it back with feedback, or reject it.
argument-hint: "<agent_id> <approve|reject> [feedback...]"
allowed-tools: mcp__loomcycle__review_run mcp__loomcycle__get_run mcp__plugin_loomcycle_loomcycle__review_run mcp__plugin_loomcycle_loomcycle__get_run
---

# Review a held loomcycle run

A run started or retuned with `review: true` does not complete when the agent
finishes: its answer is **held** until someone rules on it. This command is that
ruling. It wraps the `review_run` tool of the loomcycle MCP server.

Parse `$ARGUMENTS`:

- First token = `<agent_id>` (the handle `/loomcycle:run` returned).
- Second token = `approve` or `reject`.
- Everything after = feedback text. Only with `reject`.

If the agent id or the decision is missing, ask. Do not guess a verdict.

## Before ruling

If the operator has not seen the answer, show it first. Call `get_run` with the
`agent_id` and confirm the run is held: `status` is `running` and
`awaited_state` is `review`. A run that is still working, or waiting for input,
is refused as not held.

## The three outcomes

```json
{ "agent_id": "<agent_id>", "decision": "approve" }
{ "agent_id": "<agent_id>", "decision": "reject", "feedback": "<what to change>" }
{ "agent_id": "<agent_id>", "decision": "reject" }
```

| Call | What happens |
|---|---|
| `approve` | The run completes on the answer it was held on. |
| `reject` with `feedback` | The feedback goes to the agent as its next message. It revises, and is **held again** for another verdict. |
| `reject` without feedback | The run ends with status `rejected`. |

Feedback with `approve` is refused, because nobody would read it.

The tool returns `{run_id, decision, delivered}`. Report the decision and, after
a reject with feedback, say that the run is working again and will be held again
when it answers.

## Things to carry into the answer

- **This is the reviewer's verdict on someone else's work.** Do not approve a run
  on the operator's behalf because the answer looks fine to you. Ask.
- A hold with `review_ttl_seconds` ends as rejected when nobody rules in time.
  The deadline is on the run-state stream (`stream_user_run_states`, as
  `hold_expires_at`), not on `get_run`.
- It is not a way to talk to a run. To send a message to a run that is not held,
  continue its session (`spawn_run` with its `session_id`) or steer an
  interactive run with `/loomcycle:steer`.
- `review_run` needs the `runs:create` scope on the plugin's token.
