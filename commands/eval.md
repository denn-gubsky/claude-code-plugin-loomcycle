---
description: Submit an evaluation score (and optional rationale) against a completed loomcycle run.
argument-hint: "<run_id> <score> [--rationale=<text>]"
allowed-tools: mcp__loomcycle__evaluation
---

# Submit a loomcycle evaluation

Record an evaluation against a completed run. Parse `$ARGUMENTS`:

- First token = `<run_id>`.
- Second token = `<score>` (a number).
- Optional `--rationale=<text>` = free-text justification.

Call the `mcp__loomcycle__evaluation` tool with the `submit` op:

```json
{
  "op": "submit",
  "run_id": "<run_id>",
  "score": <score>,
  "rationale": "<rationale if given>"
}
```

`evaluation` is a multi-op tool; the `op` discriminator must be `"submit"`.
The score is recorded as data — loomcycle does **not** auto-promote anything
based on it; selection stays an operator decision.

Report the submitted score + run_id. If `run_id` or `score` is missing, ask
for the missing value rather than guessing.
