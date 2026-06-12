---
description: Fan out N concurrent loomcycle runs of one agent in a single call and render the combined results (loomcycle ≥ v0.32.0).
argument-hint: "<agent> [--count=N] [--user=<id>] <prompt...>"
allowed-tools: mcp__loomcycle__spawn_runs
---

# Fan out loomcycle runs

Spawn **several runs at once** with `mcp__loomcycle__spawn_runs` (RFC Y external
fan-out, loomcycle ≥ v0.32.0). The server runs them concurrently (bounded by the
per-user admission gate), blocks until **all** settle, and returns one
index-aligned envelope. Prefer this over firing N separate `/loomcycle:run`
calls, which serialize over the single MCP connection.

Parse `$ARGUMENTS`:

- First token = `<agent>` (the registered agent name).
- `--count=N` = how many runs to fan out (**1–32**; the tool caps at 32). If
  omitted, default to a small N (e.g. 3) and say so; if `N` would be 1, suggest
  `/loomcycle:run` instead — a single run doesn't need a batch.
- Optional `--user=<id>` = `user_id` (else the `/loomcycle:connect` identity).
- Everything else = the shared prompt text.

Build a `spawns` array of N entries (each a **fresh** run — `session_id` is
ignored here), then call the tool:

```json
{
  "spawns": [
    { "agent": "<agent>",
      "segments": [ { "role": "user", "content": [ { "type": "trusted-text", "text": "<prompt text>" } ] } ],
      "user_id": "<user_id, if known>" }
    /* … repeated --count times … */
  ],
  "mode": "join"
}
```

Notes for the call:
- `mode` is `"join"` (the only supported mode today — it blocks until every
  child settles; `"detach"` is reserved and rejected).
- Optional `timeout_ms` sets a join deadline; a child still running when it
  elapses is **cancelled and reported with a cancelled status in-envelope**, not
  raised as an error.
- To group the batch for cost attribution, set the **same**
  `parent_context.root_agent_run_id` on every entry.
- Do **not** invent `allowed_tools` / `allowed_hosts` — omit so the operator's
  static policy applies.

Render the returned envelope as a markdown table, in index order:
`# | agent_id | status | run_id | result (first line / error)`.

- A **per-child failure is captured in that child's result and never fails the
  batch** — show failed children inline (status + error), don't abort the table.
- Remind the operator each `agent_id` is a cancel handle
  (`/loomcycle:cancel <agent_id>`), and that the batch is capped at 32.

If the agent name is missing or unknown, stop and ask rather than guessing.
