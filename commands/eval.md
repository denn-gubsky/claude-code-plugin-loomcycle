---
description: Submit an evaluation score (and optional rationale) against a completed loomcycle run.
argument-hint: "<run_id> <score> [--rationale=<text>]"
allowed-tools: mcp__loomcycle__evaluation mcp__plugin_loomcycle_loomcycle__evaluation
---

# Submit a loomcycle evaluation

Record an evaluation against a completed run. Parse `$ARGUMENTS`:

- First token = `<run_id>`.
- Second token = `<score>` (a number).
- Optional `--rationale=<text>` = free-text justification.

Call the `evaluation` tool of the loomcycle MCP server with the `submit` op:

```json
{
  "op": "submit",
  "run_id": "<run_id>",
  "score": <score>,
  "rationale": "<rationale if given>"
}
```

`evaluation` is a multi-op tool; the `op` discriminator must be `"submit"`.
The score's range is the operator's convention (`[0,1]` or `[-1,1]`); ask if it
is unclear. An optional `dimensions` object records named axes, e.g.
`{"correctness": 0.8, "speed": 0.6}`. Scores are additive: submitting again
records another evaluation rather than replacing the last.

The score is recorded as data — loomcycle does **not** auto-promote anything
based on it; selection stays an operator decision.

To read scores back, the same tool has `get`, `list_for_run`, `list_for_def`
(every score for one definition) and `aggregate`, which is how two versions of
an agent are compared.

Report the submitted score + run_id. If `run_id` or `score` is missing, ask
for the missing value rather than guessing.
