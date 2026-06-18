---
description: Send a steering message to a live interactive run — push operator text into a parked or running interactive agent session (RFC AI, loomcycle ≥ v1.1.1).
argument-hint: "<run_id> <text...>"
allowed-tools: Bash
---

# Steer an interactive loomcycle run

Parse `$ARGUMENTS`:

- First token = `<run_id>` (the `run_id` from the original `spawn_run` response
  or the `awaiting_input` event — looks like `r_…`).
- Everything after = the steering text to inject.

If either is missing, stop and ask the operator.

## Send the steering input

Call `POST /v1/runs/{run_id}/input` on the running loomcycle instance. Use the
**`loomcurl.sh` helper** if one is present in the current working directory (it
handles bearer auth securely — never echoing the token in argv). Otherwise use
`curl` with the token piped via stdin (the `-K -` pattern):

```bash
# Preferred (if ./loomcurl.sh exists):
./loomcurl.sh -X POST \
  "${LOOMCYCLE_BASE_URL:-http://127.0.0.1:8787}/v1/runs/<run_id>/input" \
  -H 'Content-Type: application/json' \
  -d "$(python3 -c "import json,sys; print(json.dumps({'text':sys.argv[1]}))" "<steering text>")"

# Fallback (curl with bearer via stdin, token never in argv):
python3 -c "import json,sys; print(json.dumps({'text':sys.argv[1]}))" "<steering text>" \
  | (if [ -n "${LOOMCYCLE_AUTH_TOKEN:-}" ]; then
       printf 'header = "Authorization: Bearer %s"\n' "$LOOMCYCLE_AUTH_TOKEN" \
         | curl -sS -K - -X POST \
             "${LOOMCYCLE_BASE_URL:-http://127.0.0.1:8787}/v1/runs/<run_id>/input" \
             -H 'Content-Type: application/json' -d @-
     else
       curl -sS -X POST \
         "${LOOMCYCLE_BASE_URL:-http://127.0.0.1:8787}/v1/runs/<run_id>/input" \
         -H 'Content-Type: application/json' -d @-
     fi)
```

Use `python3` for the JSON body so steering text with quotes, backslashes, or
newlines is encoded safely. **Never interpolate raw user text into the JSON
string yourself** — pass it as an argument to python3 or `jq`, never with
`echo` / shell substitution directly into the JSON.

## Interpret the response

| HTTP status | Meaning | Action |
|---|---|---|
| `200` `{"run_id":"…","delivered":true}` | Steering delivered | Report delivered; the run will continue on its next iteration |
| `404` | No live run for that `run_id` | The run may have completed, been cancelled, or the id is wrong. Offer to list recent runs with `/loomcycle:runs`. |
| `429` | Run input queue full | Retry in ~1s (the `Retry-After: 1` header confirms). |
| `503` | Steering not enabled on this server | The runtime wasn't started with steer registry support — unlikely on v1.1.1+. |
| `422` | Empty text | The steering text was empty after trimming. Ask the operator for non-empty input. |

Report the `run_id` and whether the text was `delivered`. On success, note that
the run's stream will emit the steered response (the operator can watch it via
`GET /v1/runs/{id}/stream`).

## Context

Steering is for **interactive runs** — started with `"interactive": true` on
`POST /v1/runs`. An interactive run parks at `end_turn` (emitting an
`awaiting_input` SSE event) instead of completing, then resumes when a steer
arrives. Non-interactive runs ignore steering and return 404. Full reference:
`skills/loomcycle-configure/reference/interactive.md`.
