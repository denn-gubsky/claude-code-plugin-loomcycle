---
description: Compact a parked loomcycle run's conversation — summarize its history to free context, then continue (loomcycle ≥ v0.32.0).
argument-hint: "<agent_id> [--reason=<text>]"
allowed-tools: mcp__loomcycle__compact_run
---

# Compact a loomcycle run

Summarize a run's conversation history to reclaim context, then continue from
the summary. Wraps `mcp__loomcycle__compact_run` (loomcycle ≥ v0.32.0). Parse
`$ARGUMENTS`:

- First token = `<agent_id>` (the run's tracking handle from `/loomcycle:run`
  or `/loomcycle:runs`). The tool resolves it to the run.
- Optional `--reason=<text>` = a free-text note (audit only).

Call `mcp__loomcycle__compact_run`:

```json
{ "agent_id": "<agent_id>", "reason": "<reason if given>" }
```

**The run must be PARKED — awaiting input.** A run mid-turn (actively
generating) is **refused**; that is expected, not a plugin bug — surface the
refusal plainly and tell the operator to retry once the run is waiting for
input. Compaction honours the agent's own `compaction:` settings
(`keep_last_n` / `keep_first` / `target_percentage` / summary `model`).

Render the result `{ compacted, before_tokens, after_tokens, applied }` as a
short summary, interpreting `applied`:

- `live` — pushed into the running loop (it continues with the summary).
- `marker` — persisted for a terminal run's next continuation.
- `noop` — history too short to be worth compacting (nothing changed).

Report the token delta (`before_tokens → after_tokens`). If `<agent_id>` is
missing, ask for it rather than guessing.
