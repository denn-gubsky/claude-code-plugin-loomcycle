# Interactive agentic sessions — RFC AI (loomcycle ≥ v1.1.1)

## Overview

An **interactive run** parks at `end_turn` instead of completing, emitting an
`awaiting_input` SSE event. The operator sends a steering message via HTTP and
the run resumes. This loop repeats until the operator cancels or the run exits
normally.

Interactive runs are useful for:
- Human-in-the-loop agentic pipelines (operator approves each phase)
- Exploratory sessions where the next step isn't known upfront
- Incremental delegation — operator extends the goal one step at a time

---

## Starting an interactive run

`mcp__loomcycle__spawn_run` does **not** expose `interactive` — it cannot start
an interactive run. Use `POST /v1/runs` directly:

```bash
# Minimal form (loomcurl.sh handles bearer auth):
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

The response is SSE (`text/event-stream`) — keep the connection open for the
run to proceed. The run starts immediately; the first parking point emits
`awaiting_input`.

---

## SSE event reference

All run events are `data: {...}` lines on the stream. Interactive-specific ones:

### `awaiting_input`

Emitted when the run parks at `end_turn` and waits for a steer. The run is live
but idle — it holds its context window in memory.

```json
{
  "type": "awaiting_input",
  "run_id": "r_…",
  "agent": "<agent-name>",
  "iteration": 3
}
```

Action: call `/loomcycle:steer <run_id> <text>` (or `POST /v1/runs/{id}/input`
directly). The run will resume on the next event loop tick.

### `steer`

Emitted when the runtime accepts a steering message and injects it into the
context. Confirms delivery before the run resumes.

```json
{
  "type": "steer",
  "run_id": "r_…",
  "text": "<the injected operator text>"
}
```

### Standard events (unchanged)

| Event type | When |
|---|---|
| `message_start` | Claude starts a reply |
| `content_block_delta` | Streaming token |
| `tool_use` | Agent calls a tool |
| `tool_result` | Tool returns |
| `message_end` | Claude finishes a reply |
| `run_end` | Run completed (final status) |
| `error` | Run failed |

---

## Steering an interactive run

```http
POST /v1/runs/{run_id}/input
Content-Type: application/json
Authorization: Bearer <token>

{ "text": "<operator message>" }
```

Response:
```json
{ "run_id": "r_…", "delivered": true }
```

The steering text is injected as an operator-role message into the next
iteration of the run's context. From the perspective of the running agent, it
appears as a continuation of the conversation.

Use `/loomcycle:steer <run_id> <text>` from Claude Code for the same action
without handling auth manually.

---

## Re-attaching to a stream

If the original SSE connection drops, re-attach:

```bash
./loomcurl.sh "${LOOMCYCLE_BASE_URL:-http://127.0.0.1:8787}/v1/runs/<run_id>/stream"
```

The stream replays recent events then continues live. The run is not affected
by connection drops — it keeps running in the loomcycle process.

---

## Lifecycle

```
POST /v1/runs  (interactive: true)
     │
     ▼
  running ─── iteration N completes ──► awaiting_input (parked)
                                              │
                                    POST /v1/runs/{id}/input
                                              │
                                              ▼
                                         running ─── ...
                                              │
                                    operator cancels  OR  agent natural exit
                                              │
                                              ▼
                                           ended
```

- Parked runs count against the `max_concurrent_runs` limit.
- Parked runs respect `max_iterations` — parking consumes one iteration.
- There is no timeout for parked runs by default; configure
  `interactive_timeout_seconds` in `loomcycle.yaml` if needed (v1.1.1+).

---

## MCP gap summary

| Operation | MCP tool | HTTP alternative |
|---|---|---|
| Start interactive run | ❌ (`spawn_run` has no `interactive`) | `POST /v1/runs` with `"interactive": true` |
| Steer (send input) | ❌ (no steering tool) | `POST /v1/runs/{id}/input` — or `/loomcycle:steer` |
| Re-attach to stream | ❌ | `GET /v1/runs/{id}/stream` |
| Get run status | ✅ `get_run` | `GET /v1/runs/{id}` |
| Cancel run | ✅ `cancel_run` | `DELETE /v1/runs/{id}` |
| List runs | ✅ `list_runs` | `GET /v1/runs` |

`/loomcycle:steer` bridges the steering gap — it uses Bash + `curl`/`loomcurl.sh`
to call `POST /v1/runs/{id}/input` token-safely from inside Claude Code.

---

## Example session (operator walkthrough)

```bash
# 1. Start an interactive run (HTTP, not MCP)
./loomcurl.sh -X POST http://127.0.0.1:8787/v1/runs \
  -H 'Content-Type: application/json' \
  -d '{"agent":"my-agent","interactive":true,"user_id":"op1",
       "segments":[{"role":"user","content":[{"type":"trusted-text","text":"Analyse the codebase."}]}]}'
# → stream opens, events flow, then: {"type":"awaiting_input","run_id":"r_abc123"}

# 2. From Claude Code, steer it:
/loomcycle:steer r_abc123 Focus on the authentication module specifically.

# 3. Re-attach if needed:
./loomcurl.sh http://127.0.0.1:8787/v1/runs/r_abc123/stream

# 4. Cancel when done:
/loomcycle:cancel r_abc123
```
