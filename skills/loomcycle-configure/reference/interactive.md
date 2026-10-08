# Interactive agentic sessions (loomcycle ≥ v1.1.1; checked against v1.107.0)

## Overview

An **interactive run** parks at the end of each turn instead of completing,
emitting an `awaiting_input` event. The operator sends a steering message over
HTTP and the run takes another turn. This repeats until the operator cancels the
run or releases it (`interactive: false`, see `retune_run` below).

Interactive runs are useful for:
- Human-in-the-loop agentic pipelines (operator approves each phase)
- Exploratory sessions where the next step isn't known upfront
- Incremental delegation — operator extends the goal one step at a time
- Taking hold of a run that is going the wrong way: any running run can be
  promoted to interactive after it started

An interactive run executes in the runtime, not in the request that started it:
closing the stream does not stop it.

---

## Starting an interactive run

There are three ways a run becomes interactive.

### 1. Over MCP — `spawn_runs` with `mode: "detach"`

`spawn_run` and each `spawn_runs` child accept `interactive: true`. But
`spawn_run` **blocks for the whole run and has no detached form**, and an
interactive run does not end by itself — so over MCP start it through
`spawn_runs` with `mode: "detach"`, which returns each child's `run_id` and
`agent_id` as soon as it has started (`status: "running"`):

```json
{
  "mode": "detach",
  "spawns": [
    {
      "agent": "<agent-name>",
      "interactive": true,
      "segments": [
        {"role": "user", "content": [{"type": "trusted-text", "text": "<initial prompt>"}]}
      ]
    }
  ]
}
```

`timeout_ms` is refused with `mode: "detach"`. To bound a detached run's
lifetime give the child `max_wall_seconds` (time parked for input counts).

### 2. Promote a run that is already going — `retune_run`

`retune_run` with `interactive: true` parks a running run at its **next turn
boundary**. `interactive: false` releases a run that was started interactive, so
it finishes at its next turn end instead of parking. HTTP twin:
`POST /v1/runs/{run_id}/retune`.

### 3. Over HTTP — `POST /v1/runs`

```bash
# Use ./loomcurl.sh if the working directory has one (it handles bearer auth);
# otherwise curl with the bearer supplied the way /loomcycle:steer does.
./loomcurl.sh -X POST \
  "${LOOMCYCLE_BASE_URL:-http://127.0.0.1:8787}/v1/runs" \
  -H 'Content-Type: application/json' \
  -d '{
    "agent": "<agent-name>",
    "interactive": true,
    "user_id": "<user_id>",
    "segments": [
      {"role":"user","content":[{"type":"trusted-text","text":"<initial prompt>"}]}
    ]
  }'
```

The response is SSE (`text/event-stream`). The run starts immediately and the
first parking point emits `awaiting_input`. Disconnecting does not stop the run;
re-attach with `GET /v1/runs/{run_id}/stream`.

### Agent settings that matter

- `unbounded_iterations: true` on the agent — each steer and each park spends an
  iteration, so the default iteration cap would otherwise end a live session.
- Add `Interruption` to the agent's `tools:` if the operator should be able to
  answer the agent's own questions inline.
- `context:` mode — `mode: auto` always resolves to **recap** for an interactive
  run, whatever provider it lands on. An explicit `mode: stateful` is honoured:
  the run still parks with `awaiting_input` and emits a single `done` only when
  it really ends, and the operator's message reaches the model as its next
  observation, prefixed `operator:`. Two things are refused on a stateful run
  with 409: manual compaction (`stateful_run`) and turn-cancel.

---

## SSE event reference

Each frame on the stream is `event: <type>` followed by `data: {…}`; the JSON
repeats the type in its `type` field. The interactive-specific ones:

### `awaiting_input`

Emitted when the run parks at the end of a turn and waits for a steer. The run
is live but idle.

```json
{ "type": "awaiting_input", "awaiting_input": { "since_turn": 3 } }
```

The run's ids are not in this frame. They arrive once, in the `agent` frame at
the start of the stream (`agent_id`, `run_id`, `session_id`).

Action: call `/loomcycle:steer <run_id> <text>` (or `POST /v1/runs/{run_id}/input`
directly).

### `steer`

The operator's message, as the run took it into the conversation.

```json
{ "type": "steer", "user_input": { "text": "<operator text>", "source": "api" } }
```

`source` is `api` or `webui`. On a re-attached stream the operator's earlier
turns (the opening prompt and every steer) are replayed as `steer` frames with
`source: "replay"`.

### `turn_cancelled`

Emitted when the operator stops the current turn (see turn-cancel below). The
run is not ended: an `awaiting_input` follows.

```json
{ "type": "turn_cancelled", "turn_cancelled": { "reason": "<optional>", "since_turn": 3 } }
```

### `awaiting_review`

Emitted by a run armed for review when it finishes an answer (see review holds
below). Carries `since_turn`, `round`, and `expires_at` when the hold has a
deadline.

### Other events on the same stream

| Event type | When |
|---|---|
| `started` | A model call begins |
| `text` | Streamed answer text |
| `thinking` | Streamed reasoning trace |
| `tool_call` | Agent calls a tool |
| `tool_result` | Tool returns |
| `usage` | Token usage for a call |
| `limit` | A token budget was crossed (see `token-limits.md`) |
| `done` | The run ended (carries `stop_reason`) |
| `error` | Run failed |

---

## Steering an interactive run

```http
POST /v1/runs/{run_id}/input
Content-Type: application/json
Authorization: Bearer <token>

{ "text": "<operator message>" }
```

Needs the `runs:create` scope. Responses:

| Status | Meaning |
|---|---|
| `200` `{"run_id": "r_…", "delivered": true}` | Delivered |
| `404` | No in-flight run for that `run_id` — it ended, the id is wrong, or it belongs to another tenant. A message sent after the run finished gets this, not `delivered` |
| `422` | `text` is empty after trimming |
| `429` (`Retry-After: 1`) | The run's input queue is full; retry shortly |
| `503` | Steering is not wired on this server |

The text is appended to the conversation as a user turn at the top of the run's
next iteration.

The body may also carry `overrides` (same field names as retune) to change the
run's settings on the turn this message starts.

**There is no MCP tool for steering.** Use `/loomcycle:steer <run_id> <text>`
from Claude Code, which calls this route without putting the token in argv.

---

## Re-attaching to a stream

If the original SSE connection drops, re-attach:

```bash
./loomcurl.sh "${LOOMCYCLE_BASE_URL:-http://127.0.0.1:8787}/v1/runs/<run_id>/stream"
```

The stream replays the run's persisted events and then continues live. Pass
`?from_seq=<n>` to replay only events after that sequence number. Needs
`runs:read`, and a persistence backend (503 without one).

Over MCP, poll with `get_run`: a parked run reads `status: "running"` with
`awaited_state: "input"`.

---

## Lifecycle

```
POST /v1/runs (interactive: true)   or   spawn_runs mode:"detach"   or   retune_run interactive:true
     │
     ▼
  running ─── turn ends ──► awaiting_input (parked)
                                   │
                         POST /v1/runs/{run_id}/input
                                   │
                                   ▼
                              running ─── ...
                                   │
              whole-run cancel  OR  released (interactive:false)  OR  max_iterations / max_wall_seconds
                                   │
                                   ▼
                                ended
```

- Each steer and each park spends an iteration. Unless the agent sets
  `unbounded_iterations: true`, a session ends at its `max_iterations`.
- A parked run has no idle timeout of its own. The only time bound is the
  per-run `max_wall_seconds`; past it the run ends `cancelled` with
  `stop_reason: "wall_limit"`.
- A parked run survives a runtime pause and a restart: it comes back parked.

---

## What steering is not — the neighbours

| You want to… | Use | Not |
|---|---|---|
| Send the run a message | `POST /v1/runs/{run_id}/input` | retune, review |
| Change the run's settings, say nothing | `retune_run` | steering |
| Stop this turn, keep the session | turn-cancel | whole-run cancel |
| End the run | `cancel_run` / `POST /v1/agents/{agent_id}/cancel` | turn-cancel |
| Rule on a finished answer | `review_run` | steering |

### `retune_run` — change settings without a message

Targets a run by `agent_id` (HTTP: `POST /v1/runs/{run_id}/retune`, fields
inline in the body, `runs:create`). At least one field is required; an empty
call is refused. It writes nothing to the transcript and returns the run's
merged configuration. Fields include `model`, `provider`, `tier`, `effort`,
`max_tokens`, `max_iterations`, `unbounded_iterations`, `interactive`, `review`,
`interruption`, `tool_choice` and `output_format`. Overrides select within what
the agent's definition allows; one it forbids is refused. `GET
/v1/runs/{run_id}/config` and `/effective-config` read what a run holds.

### Turn-cancel — stop the current turn only

`POST /v1/runs/{run_id}/cancel` with an optional `{"reason": "…"}` body
(`runs:create`). It stops the in-flight model generation and the tool calls that
turn started, and parks the run at `awaiting_input` with its session and
transcript intact. No MCP tool.

| Status | Meaning |
|---|---|
| `200` `{"run_id", "stopped", "parked"}` | Turn stopped, run parked |
| `409` `not_interactive` | The run is not interactive — use whole-run cancel |
| `409` `not_mid_turn` | The run is already parked or has ended |
| `404` | No in-flight run for that `run_id` |
| `503` | Turn-cancel is not wired on this server |

A **team walk** has no turns: the same route on a walk's run id ends the walk
and its member runs.

Whole-run cancel is a different route: the `cancel_run` tool (by `agent_id`) or
`POST /v1/agents/{agent_id}/cancel`. It ends the run and cascades to its
sub-agents.

### Review holds — a verdict on a finished answer

A run started with `review: true` (on `POST /v1/runs`, `spawn_run`, a
`spawn_runs` child, or set later with `retune_run`) does not complete when its
model finishes. It emits `awaiting_review` and waits; `get_run` reports
`awaited_state: "review"`. A blocking `spawn_run` with `review: true` returns
only once the answer is approved or the run is rejected.

Rule on it with the `review_run` tool (`agent_id`, `decision`, optional
`feedback`) or `POST /v1/runs/{run_id}/review` (`runs:create`):

| Verdict | Effect |
|---|---|
| `decision: "approve"` | The run completes on the held answer. `feedback` with approve is refused |
| `decision: "reject"` with `feedback` | The feedback is sent as the agent's next message; it revises and is held again |
| `decision: "reject"`, no feedback | The run ends with status `rejected` |

A run that is not held answers 409 `not_held`. `review_ttl_seconds` (set at
start) ends an unanswered hold as `rejected` with stop reason `review_expired`;
each hold gets the full window, and 0 or absent means no deadline.
`retune_run` with `review: false` releases a held run as approved.

Review and interactive are independent: review waits for a verdict on work the
agent considers done, interactive waits for more work.

### Resident interactive sub-agents

An agent can keep its own steerable child with the `Agent` tool's `open` /
`send` / `poll` / `cancel` / `close` ops. That is an agent driving an agent, not
an operator session, and it is bounded by operator env:

| Env var | Default | Bounds |
|---|---|---|
| `LOOMCYCLE_MAX_INTERACTIVE_CHILDREN` | 8 | Resident children one run holds open; `open` past it is refused |
| `LOOMCYCLE_INTERACTIVE_CHILD_IDLE_TTL_MS` | 1800000 (30 min) | Idle time with no `send` before a resident child is reaped |
| `LOOMCYCLE_RESIDENT_MAX_TURN_SECONDS` | 7200 (2 h) | A resident child whose current turn runs longer is reaped |

---

## MCP gap summary

| Operation | MCP tool | HTTP |
|---|---|---|
| Start interactive run | ✅ `spawn_runs` with `mode: "detach"` and `interactive: true` on the child (`spawn_run` accepts the field but blocks) | `POST /v1/runs` with `"interactive": true` |
| Promote / release a running run | ✅ `retune_run` (`interactive: true` / `false`) | `POST /v1/runs/{run_id}/retune` |
| Steer (send input) | ❌ (no steering tool) | `POST /v1/runs/{run_id}/input` — or `/loomcycle:steer` |
| Stop the current turn | ❌ | `POST /v1/runs/{run_id}/cancel` |
| Re-attach to stream | ❌ | `GET /v1/runs/{run_id}/stream` |
| Get run status | ✅ `get_run` | `GET /v1/runs/{run_id}` |
| Rule on a held answer | ✅ `review_run` | `POST /v1/runs/{run_id}/review` |
| Cancel run | ✅ `cancel_run` | `POST /v1/agents/{agent_id}/cancel` |
| List runs | ✅ `list_runs` | `GET /v1/runs` |

`DELETE /v1/runs/{run_id}` is **not** cancel: it discards a configured draft
run that was never started.

`/loomcycle:steer` bridges the steering gap — it uses Bash + `curl` (or
`loomcurl.sh` when present) to call `POST /v1/runs/{run_id}/input` token-safely
from inside Claude Code.

---

## Example session (operator walkthrough)

```
# 1. Start it detached over MCP: the spawn_runs tool with
#    {"mode":"detach","spawns":[{"agent":"my-agent","interactive":true,
#      "segments":[{"role":"user","content":[{"type":"trusted-text","text":"Analyse the codebase."}]}]}]}
#    → each child comes back {status:"running", run_id:"r_abc123", agent_id:"a_…"}

# 2. Poll until it parks: get_run {"run_id":"r_abc123"}
#    → status "running", awaited_state "input"

# 3. Steer it:
/loomcycle:steer r_abc123 Focus on the authentication module specifically.

# 4. Watch the stream if needed:
./loomcurl.sh http://127.0.0.1:8787/v1/runs/r_abc123/stream

# 5. Cancel when done (by agent_id):
/loomcycle:cancel a_…
```
