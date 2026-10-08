---
description: Ask a loomcycle decision model typed questions (choice, yes/no, score) about text you supply, and get each answer with its probabilities.
argument-hint: "[--model=<name>] <what to decide, and about what>"
allowed-tools: mcp__loomcycle__decision mcp__loomcycle__context mcp__plugin_loomcycle_loomcycle__decision mcp__plugin_loomcycle_loomcycle__context
---

# Ask a loomcycle decision model

A **decision model** does not write. It reads the text you give it and answers a
choice, a yes/no or a score, with probabilities. One call costs a few output
tokens, so use it to route, gate, rank or grade text you already have instead of
spending a whole agent run on the judgement. Wraps the `decision` tool of the
loomcycle MCP server.

Not for anything that needs reasoning or written output, and not for lookup: the
model reads only `state`.

## Build the call

From `$ARGUMENTS`, work out the text being judged and the questions, then call
`decision`. There is no `op`, and only three arguments exist:

- `state` (required): a JSON **object** holding what the questions are about.
  Any shape. Every question in the call is answered about this same state.
- `questions` (required): an object of 1 to 64 questions. Each key is a name you
  choose, and the answer comes back under that name.
- `model`: omit it for the deployment's default. Pass `--model` only when the
  operator named one.

Each question is `{"type", "instructions", "criteria"}`. `instructions` is the
question in plain words, and is required for all three types:

| `type` | `criteria` | Answer |
|---|---|---|
| `choice` | required: an object, each key an option (2 to 26), each value its description or `null` | `choice` (the key picked), `probabilities`, `confidence` |
| `noul` | optional: an object describing `"true"` and/or `"false"` | `noul`: the probability of YES, 0 to 1 |
| `score` | required: an **array** of level descriptions, lowest first (2 to 26) | `score` (expected position from 0), `legend`, `probabilities`, `confidence` |

```json
{
  "state": { "ticket": "My invoice for March was charged twice and I want my money back.", "customer_tier": "gold" },
  "questions": {
    "route":  { "type": "choice", "instructions": "Which team should handle this ticket?",
                "criteria": { "billing": "invoices, refunds, charges", "support": "bugs, outages, login problems", "sales": "upgrades, quotes" } },
    "urgent": { "type": "noul", "instructions": "Does this ticket need a reply within the hour?" }
  }
}
```

The reply is `{model, provider, served_model, answers, usage}`.

## Render the result

One row per question: the name, the answer, and the probabilities. For a
`choice`, show the runner-up when it is close. For a `noul`, show the number;
`0` is a definite no, not a missing answer, and there is no separate true/false
field. Then the model that answered and the token usage.

## Reading the numbers

**The probabilities are not calibrated.** 0.9 does not mean "right nine times in
ten". Say so when the operator is about to gate on a threshold.

- Compare options **within one answer**: which is highest, and by how much.
- The same question can come back differently when asked alongside others or
  with different wording. Keep the wording and the grouping stable for answers
  that will be compared.

## Errors

A failed call's error starts `Decision: <code>: `. The ones that change what to
do:

| Code | Do |
|---|---|
| `decision_not_configured` | This deployment lists no decision models. Do not retry. The operator adds a `decision:` block and a model tagged `kind: decision`; see the `loomcycle-configure` skill. |
| `model_not_allowed` | The named model is not one you may ask. Omit `model`, or use a name from the list in the message. |
| `prompt_too_large` | The request does not fit the model's context. It is **never shortened for you**: shorten the state or the criteria, or ask fewer questions. |
| `bad_question`, `bad_options`, `too_many_questions`, `invalid_input` | Fix the call; the message names the problem. |
| `timeout` | Send the same call once more. |
| `operator_key_restricted` | The caller may not use the operator's provider key and has none of its own. Do not retry. |

## Who pays

Called from here, outside any run, the tokens are charged to the plugin's own
principal and count against its token budget. A caller at a hard budget is
refused before the model is asked. The tool needs the `runs:create` scope.

For the full article, with a worked example per question type, call the
`context` tool with `{"op": "help", "topic": "Decision"}`.
