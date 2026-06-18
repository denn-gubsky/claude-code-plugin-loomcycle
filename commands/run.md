---
description: Spawn a loomcycle agent run against a registered agent and stream the result into Claude Code.
argument-hint: "<agent> [--user=<id>] [--compact] <prompt...>"
allowed-tools: mcp__loomcycle__spawn_run
---

# Spawn a loomcycle run

Spawn a run on a registered loomcycle agent.

Parse `$ARGUMENTS`:

- First token = `<agent>` (the registered agent name).
- Optional `--user=<id>` anywhere = `user_id`. If omitted, use the `user_id`
  from the active identity set by `/loomcycle:connect`.
- Optional `--compact` = turn on per-run auto context-compaction (loomcycle
  ≥ v0.32.0). When present, add `"compaction": { "enabled": true }` so a long
  run summarises its own history instead of overflowing the context window.
- Optional `--interactive` = start an interactive run (loomcycle ≥ v1.1.1,
  RFC AI). **Cannot be set via this command** — the `mcp__loomcycle__spawn_run`
  schema does not expose `interactive`. To start an interactive run, the
  operator must call `POST /v1/runs` directly with `"interactive": true` (see
  `skills/loomcycle-configure/reference/interactive.md`). If the operator
  passes `--interactive`, stop and explain this gap, then offer to produce the
  equivalent `curl` command.
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
operator's static policy applies. `spawn_run` accepts an optional `compaction`
override (a per-field merge over the agent's own `compaction:` block) — only
send it when `--compact` was passed; otherwise omit it and the agent's
configured behaviour applies.

The server streams intermediate events as `notifications/loomcycle/run_event`
while the call runs (the plugin's MCP client opts into this). For
**non-interactive** runs the call resolves when the run completes. Render:

- The final assistant text.
- The `agent_id` (the cancel handle — tell the user they can
  `/loomcycle:cancel <agent_id>`).
- The `run_id` and token usage if present.

**Interactive runs** (started via `POST /v1/runs` with `"interactive": true`,
RFC AI, v1.1.1+) emit two additional SSE event types to watch for:
- `awaiting_input` — the run has parked at `end_turn` and is waiting for
  operator steering. Contains `run_id`. Tell the operator to use
  `/loomcycle:steer <run_id> <text>` to continue.
- `steer` — a steer was accepted; the run is resuming. Contains `run_id` and
  the text that was injected.

MCP gap note: `spawn_run` cannot start interactive runs — `interactive` is not
in its schema. Use HTTP (`POST /v1/runs`) to start one; the MCP client can then
monitor it via `get_run` / `stream_user_run_states`.

If the agent name is missing or unknown, stop and ask the operator which
registered agent to use rather than guessing.
