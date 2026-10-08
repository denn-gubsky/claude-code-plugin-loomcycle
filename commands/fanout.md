---
description: Fan out N concurrent loomcycle runs of one agent in a single call and render the combined results, or start them detached.
argument-hint: "<agent> [--count=N] [--detach] [--user=<id>] <prompt...>"
allowed-tools: mcp__loomcycle__spawn_runs mcp__plugin_loomcycle_loomcycle__spawn_runs
---

# Fan out loomcycle runs

Spawn **several runs at once** with the `spawn_runs` tool of the loomcycle MCP
server. The server runs them concurrently (bounded by the per-user admission
gate) and returns one index-aligned envelope: `result[i]` belongs to
`spawns[i]`. Prefer this over firing N separate `/loomcycle:run` calls, which
serialize over the single MCP connection.

Parse `$ARGUMENTS`:

- First token = `<agent>` (the registered agent name).
- `--count=N` = how many runs to fan out (**1–32**; over 32 is refused, not
  truncated). If omitted, default to a small N (e.g. 3) and say so; if `N` would
  be 1, suggest `/loomcycle:run` instead.
- `--detach` = start the runs and do not wait for them (see below).
- Optional `--user=<id>` = `user_id` (else the `/loomcycle:connect` identity).
- Everything else = the shared prompt text.

Build a `spawns` array of N entries (each a **fresh** run; `session_id` is
ignored here), then call the tool:

```json
{
  "spawns": [
    { "agent": "<agent>",
      "segments": [ { "role": "user", "content": [ { "type": "trusted-text", "text": "<prompt text>" } ] } ],
      "user_id": "<user_id, if known>" }
  ],
  "mode": "join"
}
```

Notes for the call:

- Every child needs `segments`. A child without a prompt fails the whole batch.
- Each child takes the same per-run overrides `spawn_run` does (`model`, `tier`,
  `effort`, `sampling`, `max_tokens`, `output_format`, …), so one batch can fan
  the same agent out across different models or budgets. See
  `/loomcycle:run` for the list.
- To group the batch for cost attribution, set the **same**
  `parent_context.root_agent_run_id` on every entry.
- Give each child its own `idempotency_key` if the batch may be retried. Two
  children of one batch may not share a key.
- Do **not** invent `tools` / `allowed_hosts`. Omit them so the operator's
  static policy applies.

## `join` or `detach`

| `mode` | The call returns | Use when |
|---|---|---|
| `join` (default) | when **all** children settle, with their results | you want the answers now |
| `detach` | as soon as every child has **started**, each with `status: "running"`, a `run_id` and an `agent_id` | the runs are long, or wait for a person |

With `join`, an optional `timeout_ms` sets a deadline: a child still running
when it elapses is **cancelled and reported with a cancelled status
in-envelope**, not raised as an error.

With `detach`, `timeout_ms` is refused. The runs go on after the call returns;
read each later with `get_run` by `run_id`, and stop one with
`/loomcycle:cancel <agent_id>`. Give a detached child `max_wall_seconds` if it
needs a time bound.

## Render the result

Render the returned envelope as a markdown table, in index order:
`# | agent_id | status | run_id | result (first line / error)`.

- A **per-child failure is captured in that child's result and never fails the
  batch**. Show failed children inline (status + error); do not abort the table.
  A child that could not start is reported in its own slot in either mode.
- For `detach`, there is no result text yet. Show the handles and say how to
  read them.
- Remind the operator each `agent_id` is a cancel handle
  (`/loomcycle:cancel <agent_id>`), and that the batch is capped at 32.

If the agent name is missing or unknown, stop and ask rather than guessing.
