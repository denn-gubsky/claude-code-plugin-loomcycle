---
description: Spawn a loomcycle agent run against a registered agent and stream the result into Claude Code.
argument-hint: "<agent> [--user=<id>] [--compact] [--interactive] [--review] [--max-wall=<sec>] [--key=<idempotency key>] <prompt...>"
allowed-tools: mcp__loomcycle__spawn_run mcp__loomcycle__spawn_runs mcp__plugin_loomcycle_loomcycle__spawn_run mcp__plugin_loomcycle_loomcycle__spawn_runs
---

# Spawn a loomcycle run

Spawn a run on a registered loomcycle agent.

Parse `$ARGUMENTS`:

- First token = `<agent>` (the registered agent name).
- Optional `--user=<id>` anywhere = `user_id`. If omitted, use the `user_id`
  from the active identity set by `/loomcycle:connect`.
- Optional `--compact` = add `"compaction": { "enabled": true }` so a long run
  summarises its own history instead of overflowing the context window.
- Optional `--max-wall=<sec>` = `max_wall_seconds`: the longest the run may
  live. Past it the run is cancelled and ends `cancelled` with
  `stop_reason: "wall_limit"`.
- Optional `--key=<text>` = `idempotency_key`: makes the start safe to retry. A
  second call with the same key starts nothing and returns the first run with
  `deduplicated: true`. The prompt is not compared, so put what makes the work
  distinct into the key.
- Optional `--review` = `"review": true`: the run's finished answer is held for a
  verdict instead of completing. See *Runs that wait for a person* below.
- Optional `--interactive` = `"interactive": true`: the run parks at each turn
  boundary so an operator can steer it. See the same section.
- Everything else = the prompt text.

Call the `spawn_run` tool of the loomcycle MCP server with this shape (the prompt
is wrapped as **segments**, not a `prompt` string, and a fresh run without
segments is refused):

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
Do **not** invent `tools` or `allowed_hosts`. Leave them out so the operator's
static policy applies.

## Per-run overrides

`spawn_run` accepts overrides that apply to this run only. They select **within**
what the agent's definition allows and cannot widen it. Send one only when the
operator asked for it:

| Field | Effect |
|---|---|
| `model`, `provider`, `tier`, `effort` | Route this run differently. Naming a model pins it. |
| `max_tokens`, `max_iterations`, `unbounded_iterations` | Output cap and loop bound. |
| `sampling` | `temperature`, `top_p`, `top_k`, `seed`, `stop`, and the penalties. `temperature: 0` is deterministic, which is not the same as unset. |
| `compaction`, `context`, `max_context_tokens` | History management and the context window. |
| `tool_choice` | `{mode: auto\|none\|required\|tool, name, until}`: force a tool call. |
| `output_format` | `{schema}`: hold the final answer to a JSON Schema. |
| `metadata` | Non-secret structured data handed to the run. Never credentials. |
| `hooks`, `tool_hooks` | Hooks added to the agent's own, by event or by tool. |
| `timeout_ms` | How long **this call** may block. Past it the run is cancelled and the result has `status: "timeout"`. This bounds the call; `max_wall_seconds` bounds the run. |

A model that cannot enforce `tool_choice` or `output_format` still runs, and the
run reports what was not enforced. Relay that.

## Image input

A **user** segment may carry an `image` content block alongside text: inline
base64 bytes, no URL form. `media_type` is one of `image/png`, `image/jpeg`,
`image/gif`, `image/webp`; `data` is the base64 payload **with no `data:`
prefix**:

```json
{ "role": "user", "content": [
  { "type": "trusted-text", "text": "What's in this screenshot?" },
  { "type": "image", "media_type": "image/png", "data": "<base64 bytes>" }
] }
```

loomcycle refuses an image to a text-only model before the call, so pick a
vision-capable agent or tier.

## Runs that wait for a person

`spawn_run` **blocks for the whole run**, and there is no detached form of it. A
run started with `interactive: true` does not end by itself, and one started with
`review: true` does not end until someone rules on it. So for `--interactive`,
and for `--review` when the operator does not want this session to wait, start
the run **detached** through `spawn_runs` with one child:

```json
{
  "mode": "detach",
  "spawns": [
    { "agent": "<agent>", "interactive": true,
      "segments": [ { "role": "user", "content": [ { "type": "trusted-text", "text": "<prompt text>" } ] } ] }
  ]
}
```

It returns at once with `status: "running"`, a `run_id` and an `agent_id`. Then:

- `--interactive`: the run parks when it finishes a turn. Tell the operator to
  continue it with `/loomcycle:steer <run_id> <text>`. An interactive agent
  usually wants `unbounded_iterations`, because each park and each steer uses an
  iteration.
- `--review`: the answer is held. Tell the operator to rule on it with
  `/loomcycle:review <agent_id> approve` or `reject`. `review_ttl_seconds` ends
  an unanswered hold as rejected; without it a hold waits for a person.

`timeout_ms` is refused with `mode: "detach"`; bound a detached run with
`max_wall_seconds`.

`get_run` shows what a running run is waiting on in `awaited_state` (`input`,
`review`, `channel`, `interrupted` or `children`). A run that is already going
can be made interactive or held for review with `/loomcycle:retune`.

## Render the result

For a blocking call:

- The final assistant text (`final_text`).
- `status` and `stop_reason`. A run cancelled from outside reports `cancelled`,
  not `completed`.
- The `agent_id` (the cancel handle: `/loomcycle:cancel <agent_id>`), the
  `run_id` and the `session_id`.
- Token usage if present.
- `deduplicated: true` if present: this call started nothing and is reporting
  the run an earlier call started.
- `limits` if present: a token-budget crossing observed during the run. Show
  each as a warning (`scope`, `severity`, `used`, `limit`, `message`); the run
  still completed.

To continue a finished run's conversation, call `spawn_run` with its
`session_id` in place of `agent`.

**Budget refusal:** if the call errors with `token_limit_exceeded`, a hard
monthly budget was already over at admission and nothing was spent. Do not retry.
The operator raises the ceiling in the Web UI Limits console or waits for the
month to roll. See `skills/loomcycle-configure/reference/token-limits.md`.

**Scope refusal:** `spawn_run` needs the `runs:create` scope on the plugin's
token. A token without it does not see the tool at all.

If the agent name is missing or unknown, stop and ask the operator which
registered agent to use rather than guessing.
