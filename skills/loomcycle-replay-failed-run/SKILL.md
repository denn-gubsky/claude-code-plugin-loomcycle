---
name: loomcycle-replay-failed-run
description: Walk through replaying a failed loomcycle run — inspect the failure, adjust the prompt or agent, and re-spawn. Use when a loomcycle run errored or produced a bad result and the user wants to retry with a fix.
---

# Replay a failed loomcycle run

Use when a loomcycle run failed (errored or produced a bad result) and the
operator wants to retry with a change rather than blindly re-running.

Steps:

1. **Fetch the failed run.** With the `agent_id` (or `run_id`) the operator
   gives you, call `mcp__loomcycle__get_run`:

   ```json
   { "agent_id": "<agent_id>" }
   ```

   Read the status snapshot — the failure reason, the agent name, and (if
   present) the input that produced it.

2. **Diagnose, briefly.** Summarise *why* it failed in one or two lines:
   provider/tool error, bad prompt, missing capability, timeout, etc. If the
   cause is a loomcycle-side error (provider 5xx, tool denial), say so — a
   replay won't fix an operator-policy or config problem; flag that instead.

3. **Propose the change.** Suggest the smallest adjustment likely to fix it:
   a clarified prompt, a different registered agent, narrowed/expanded tools,
   or different inputs. Confirm with the operator before re-spawning.

4. **Re-spawn** with `mcp__loomcycle__spawn_run`, carrying the adjustment:

   ```json
   {
     "agent": "<same-or-new-agent>",
     "segments": [ { "role": "user", "content": [ { "type": "trusted-text", "text": "<revised prompt>" } ] } ]
   }
   ```

   Reuse the active `user_id` / `user_bearer` from `/loomcycle:connect`.

5. **Compare.** Report the new run's result against the old failure so the
   operator can see whether the change helped. Surface the new `agent_id`
   (cancel handle) and `run_id`.

Do not loop endlessly — if a second replay also fails the same way, stop and
recommend an operator-side fix (config, agent definition, provider tier policy)
rather than spawning a third time.
