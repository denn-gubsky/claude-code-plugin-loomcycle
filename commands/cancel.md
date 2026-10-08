---
description: Cancel a running loomcycle agent by agent_id (cascades to sub-agents).
argument-hint: "<agent_id> [--reason=<text>]"
allowed-tools: mcp__loomcycle__cancel_run mcp__plugin_loomcycle_loomcycle__cancel_run
---

# Cancel a loomcycle run

Cancel a still-running agent. Parse `$ARGUMENTS`:

- First token = `<agent_id>` (the cancel handle shown by `/loomcycle:run` and
  `/loomcycle:runs`).
- Optional `--reason=<text>` = a human-readable cancellation reason.

Call the `cancel_run` tool of the loomcycle MCP server:

```json
{ "agent_id": "<agent_id>", "reason": "<reason if given>" }
```

The cancel cascades to sub-agents and is idempotent (cancelling an
already-finished or unknown agent is safe). Report the result tersely:
which `agent_id` was cancelled and the reason, if any.

Three things the operator may expect and will not get:

- **No partial result.** Cancelling ends the run; it does not return what the
  run had so far.
- **No undo.** Side effects the run already committed stay.
- **Not the deployment.** This stops one run. Quiescing everything is
  `pause_runtime`, an admin tool.

`cancel_run` needs the `runs:create` scope on the plugin's token.

If no `agent_id` was supplied, ask for one — do not call the tool with a guess.
