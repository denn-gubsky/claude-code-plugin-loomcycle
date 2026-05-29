---
description: List recent loomcycle runs for a user, rendered as a table.
argument-hint: "[--user=<id>] [--status=<running|completed|failed|cancelled>] [--limit=<n>]"
allowed-tools: mcp__loomcycle__list_runs
---

# List loomcycle runs

List recent runs. Parse `$ARGUMENTS`:

- `--user=<id>` → `user_id`. **Required by the tool.** If absent, fall back to
  the `user_id` from `/loomcycle:connect`; if still unknown, ask the operator
  rather than calling the tool (it will error without it).
- `--status=<value>` → optional `status` filter, one of
  `running | completed | failed | cancelled`.
- `--limit=<n>` → optional `limit` (1–200).

Call `mcp__loomcycle__list_runs`:

```json
{ "user_id": "<id>", "status": "<status if given>", "limit": <n if given> }
```

Render the result as a markdown table with columns:
`agent_id | agent | status | started | duration | run_id`.

Sort most-recent first. If the list is empty, say so plainly. For any
still-`running` row, remind the operator they can cancel it with
`/loomcycle:cancel <agent_id>`.
