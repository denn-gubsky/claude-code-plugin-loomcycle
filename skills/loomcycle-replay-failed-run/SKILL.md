---
name: loomcycle-replay-failed-run
description: Walk through replaying a failed loomcycle run — inspect the failure, adjust the prompt or agent, and re-spawn. Use when a loomcycle run errored or produced a bad result and the user wants to retry with a fix.
---

# Replay a failed loomcycle run

Use when a loomcycle run failed (errored or produced a bad result) and the
operator wants to retry with a change rather than blindly re-running.

Steps:

1. **Fetch the failed run.** Call the `get_run` tool of the loomcycle MCP
   server with exactly one of `run_id` or `agent_id`:

   ```json
   { "run_id": "<run_id>" }
   ```

   Prefer `run_id`. An `agent_id` resolves to that agent's *latest* run, which
   is not the failed one if the agent has run since, and every walk of a team
   shares the id `team:<name>`.

   Read the snapshot: `status`, `stop_reason`, `error`, the agent name, and
   `spec` — the settings the run was started with, which is what you will replay.
   `result` holds what it produced, if anything.

2. **Diagnose, briefly.** Summarise *why* it failed in one or two lines:
   provider/tool error, bad prompt, missing capability, timeout, etc. If the
   cause is a loomcycle-side error (provider 5xx, tool denial), say so — a
   replay won't fix an operator-policy or config problem; flag that instead.

   The status and stop reason usually name the class:

   | You see | It means | A replay helps? |
   |---|---|---|
   | `failed`, error category `transient` | provider or network trouble | yes, unchanged |
   | `failed`, category `validation` | the request was malformed | only after fixing the request |
   | `failed`, category `permission` | a grant or scope is missing | no — an operator fix |
   | `stop_reason: repeated_failed_call` | the agent made the same failing tool call over and over | only with a changed prompt or tool grant |
   | `stop_reason: max_iterations` | it ran out of loop budget | with a higher `max_iterations`, if the work was converging |
   | `cancelled`, `stop_reason: wall_limit` | it outlived its `max_wall_seconds` | with a larger bound |
   | `rejected` | a reviewer rejected its answer, or a review hold expired | not a failure to replay; ask what the reviewer wanted |
   | `token_limit_exceeded` on the spawn itself | a hard budget was over; nothing ran | no — the operator raises the budget |

3. **Propose the change.** Suggest the smallest adjustment likely to fix it:
   a clarified prompt, a different registered agent, narrowed/expanded tools,
   or different inputs. Confirm with the operator before re-spawning.

4. **Re-spawn** with `spawn_run`, carrying the adjustment. Per-run overrides
   (`model`, `tier`, `effort`, `max_iterations`, `max_tokens`, …) let you change
   one setting for this run without touching the agent's definition:

   ```json
   {
     "agent": "<same-or-new-agent>",
     "segments": [ { "role": "user", "content": [ { "type": "trusted-text", "text": "<revised prompt>" } ] } ]
   }
   ```

   Reuse the active `user_id` / `user_bearer` from `/loomcycle:connect`.

   If the run is **still going** and merely heading the wrong way, do not
   cancel and replay: `/loomcycle:retune` changes its model or bounds in place.

5. **Compare.** Report the new run's result against the old failure so the
   operator can see whether the change helped. Surface the new `agent_id`
   (cancel handle) and `run_id`.

Do not loop endlessly — if a second replay also fails the same way, stop and
recommend an operator-side fix (config, agent definition, provider tier policy)
rather than spawning a third time.
