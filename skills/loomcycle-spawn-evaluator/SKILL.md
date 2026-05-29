---
name: loomcycle-spawn-evaluator
description: Spawn a loomcycle evaluator agent to score the current Claude Code transcript (or a named run) and report the result. Use when the user wants an independent quality/score judgement of work just done via loomcycle.
---

# Spawn a loomcycle evaluator

Use this when the operator wants an **independent evaluation** of work — either
the current Claude Code transcript or a specific loomcycle run — scored by a
loomcycle evaluator agent rather than by you directly.

Steps:

1. **Identify what's being evaluated.** Ask the operator (or infer) whether
   they want to evaluate (a) the work in the current conversation, or (b) a
   specific completed run. If (b), get the `run_id`.

2. **Choose the evaluator agent.** Ask which registered loomcycle agent should
   act as evaluator (e.g. `evaluator`, `judge`). Do not guess a name — if none
   is known, list options via the runs/agents the operator mentions, or ask.

3. **Spawn the evaluator** with `mcp__loomcycle__spawn_run`. Pass the material
   to be judged as the prompt, wrapped as segments:

   ```json
   {
     "agent": "<evaluator-agent>",
     "segments": [
       { "role": "user", "content": [
         { "type": "trusted-text", "text": "Evaluate the following and return a score 0-1 with a one-line rationale:\n\n<material>" }
       ] }
     ]
   }
   ```

   Use the active `user_id` / `user_bearer` from `/loomcycle:connect` if set.

4. **Report the evaluator's score + rationale** back to the operator clearly.

5. **Offer to record it.** If the work corresponds to a real `run_id`, offer to
   submit the score via `/loomcycle:eval <run_id> <score>`. loomcycle does not
   auto-promote on scores — recording is the operator's call.

Keep the loop honest: you are orchestrating an *independent* judge, so don't
pre-bias the evaluator's prompt toward a verdict.
