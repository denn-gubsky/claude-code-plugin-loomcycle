---
description: Spawn a loomcycle agent run against a registered agent and stream the result into Claude Code.
argument-hint: "<agent> [--user=<id>] <prompt...>"
allowed-tools: mcp__loomcycle__spawn_run
---

# Spawn a loomcycle run

Spawn a run on a registered loomcycle agent.

Parse `$ARGUMENTS`:

- First token = `<agent>` (the registered agent name).
- Optional `--user=<id>` anywhere = `user_id`. If omitted, use the `user_id`
  from the active identity set by `/loomcycle:connect`.
- Everything else = the prompt text.

Call the `mcp__loomcycle__spawn_run` tool with this shape (note: the prompt is
wrapped as **segments**, not a `prompt` string):

```json
{
  "agent": "<agent>",
  "segments": [
    { "role": "user", "content": [ { "type": "trusted-text", "text": "<prompt text>" } ] }
  ],
  "user_id": "<user_id, if known>",
  "user_bearer": "<user_bearer from /loomcycle:connect, if set>"
}
```

Omit `user_id` / `user_bearer` when not known rather than sending empty strings.
Do **not** invent `allowed_tools` or `allowed_hosts` — leave them out so the
operator's static policy applies.

The server streams intermediate events as `notifications/loomcycle/run_event`
while the call runs (the plugin's MCP client opts into this). When the call
returns, render for the operator:

- The final assistant text.
- The `agent_id` (the cancel handle — tell the user they can
  `/loomcycle:cancel <agent_id>`).
- The `run_id` and token usage if present.

If the agent name is missing or unknown, stop and ask the operator which
registered agent to use rather than guessing.
