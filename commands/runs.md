---
description: List recent loomcycle runs for a user, or every run of one team walk, rendered as a table.
argument-hint: "[--user=<id>] [--status=<running|completed|failed|cancelled>] [--limit=<n>] | --walk=<walk run_id>"
allowed-tools: mcp__loomcycle__list_runs mcp__plugin_loomcycle_loomcycle__list_runs
---

# List loomcycle runs

List runs in one of two ways. The tool takes **exactly one** of `user_id` or
`walk_id`; there is no unfiltered listing of everything in the deployment.

Parse `$ARGUMENTS`:

- `--user=<id>` → `user_id`. If absent and no `--walk` was given, fall back to
  the `user_id` from `/loomcycle:connect`; if still unknown, ask the operator
  rather than calling the tool.
- `--status=<value>` → optional `status` filter, one of
  `running | completed | failed | cancelled`. With `--user` only.
- `--limit=<n>` → optional `limit`: 1–200 with `--user`, 1–1000 (default 100)
  with `--walk`.
- `--walk=<run_id>` → `walk_id`: the `run_id` a team walk returned. Lists the
  walk's own run and every run it spawned, oldest first.

Call the `list_runs` tool of the loomcycle MCP server:

```json
{ "user_id": "<id>", "status": "<status if given>", "limit": <n if given> }
```

or, for one team walk:

```json
{ "walk_id": "<the walk's run_id>", "limit": <n if given>, "cursor": "<next_cursor of the previous page>" }
```

A walk listing is paged: pass the previous page's `next_cursor` as `cursor` to
continue. `next_cursor` is empty on the last page.

Render the result as a markdown table with columns:
`agent_id | agent | status | started | duration | run_id`.

A user listing is newest first; a walk listing is oldest first. If the list is
empty, say so plainly. For any still-`running` row, remind the operator they can
cancel it with `/loomcycle:cancel <agent_id>`.

The listing is run metadata only. For one run's status, including what it is
waiting on, use `get_run` with its `run_id`. Several runs can share an
`agent_id` (every walk of a team is filed under `team:<name>`), so read a
specific run by `run_id`.

`list_runs` needs the `runs:read` scope on the plugin's token.
