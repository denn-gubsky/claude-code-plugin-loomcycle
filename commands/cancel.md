---
description: Cancel a running loomcycle agent by agent_id (cascades to sub-agents).
argument-hint: "<agent_id> [--reason=<text>]"
allowed-tools: mcp__loomcycle__cancel_run
---

# Cancel a loomcycle run

Cancel a still-running agent. Parse `$ARGUMENTS`:

- First token = `<agent_id>` (the cancel handle shown by `/loomcycle:run` and
  `/loomcycle:runs`).
- Optional `--reason=<text>` = a human-readable cancellation reason.

Call `mcp__loomcycle__cancel_run`:

```json
{ "agent_id": "<agent_id>", "reason": "<reason if given>" }
```

The cancel cascades to sub-agents and is idempotent (cancelling an
already-finished or unknown agent is safe). Report the result tersely:
which `agent_id` was cancelled and the reason, if any.

If no `agent_id` was supplied, ask for one — do not call the tool with a guess.
