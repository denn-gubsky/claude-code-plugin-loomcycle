---
description: Change a running loomcycle agent's settings without sending it a message — move it to another model, raise its iteration bound, park it for steering, or hold its answer for review.
argument-hint: "<agent_id> [--model=<m>] [--tier=<t>] [--provider=<p>] [--effort=low|medium|high] [--max-iterations=<n>] [--max-tokens=<n>] [--interactive[=false]] [--review[=false]]"
allowed-tools: mcp__loomcycle__retune_run mcp__plugin_loomcycle_loomcycle__retune_run
---

# Retune a running loomcycle run

Take hold of a run that is going the wrong way. Wraps the `retune_run` tool of
the loomcycle MCP server. A retune changes what the run holds from its next
turn and **writes nothing to its transcript**: the agent is not told.

Parse `$ARGUMENTS`:

- First token = `<agent_id>` (the handle `/loomcycle:run` returned).
- At least one setting. An empty retune is refused rather than reported as a
  no-op.

| Flag | Field | Effect |
|---|---|---|
| `--model=<m>` | `model` | Pin a model. **Clears the provider.** |
| `--tier=<t>` | `tier` | Route through another tier. **Clears the model.** |
| `--provider=<p>` | `provider` | Narrow the tier's cascade to one vendor. |
| `--effort=<e>` | `effort` | `low`, `medium` or `high`. Anything else is refused. |
| `--max-iterations=<n>` | `max_iterations` | Loop bound. May be raised above the definition's. |
| `--max-tokens=<n>` | `max_tokens` | Per-reply output cap. |
| `--interactive` | `interactive: true` | Park the run at its next turn boundary so it can be steered. `=false` releases a run that was started interactive. |
| `--review` | `review: true` | Hold the run's finished answer for a verdict. `=false` releases a held run as approved. |

The tool also accepts `unbounded_iterations`, `max_concurrent_children` (may only
be lowered), `retry_attempts`, `memory_inject_max_tokens`,
`memory_index_max_bytes`, `inject_tool_guide`, `interruption`, `tool_choice` and
`output_format`. Pass one when the operator names it. `tool_choice` and
`output_format` replace the run's own whole and take effect from its next turn.

It does **not** accept `sampling`, `compaction`, `context`, `max_context_tokens`
or `metadata`. Those are set when a run starts.

```json
{ "agent_id": "<agent_id>", "model": "<model>" }
```

## Read the reply, do not echo the request

The tool returns the run's **merged configuration**: what it now holds. That is
not the request played back, because the merge is not a field-wise union. Naming
a model clears the provider, and naming a tier clears the model. Show the
operator the returned configuration.

## Refusals

- An override selects **within** what the agent's definition allows. One the
  definition forbids is refused here, at the retune, not applied and discovered
  later. Relay the refusal; do not try a different value on your own.
- The run must be running. A finished run has nothing to retune.
- `retune_run` needs the `runs:create` scope on the plugin's token.

## Related

- To send the run a message, use `/loomcycle:steer` (interactive runs) or
  continue its session. A retune never does.
- After `--interactive`, the run parks at its next turn boundary; continue it
  with `/loomcycle:steer <run_id> <text>`.
- After `--review`, rule on the held answer with `/loomcycle:review`.
