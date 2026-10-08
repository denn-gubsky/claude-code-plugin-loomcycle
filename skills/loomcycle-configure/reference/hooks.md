# Agent hooks — gates on an agent's tool calls and on its run

A hook is a **webhook or a JavaScript body that an agent's definition carries**
and the agent loop calls at a fixed point: around a tool call, or at a point in
the run. It can check, rewrite, deny or hold. It wraps what an agent already may
do; it never adds a capability.

> **These are loomcycle's own hooks, not Claude Code's.** The two opt-in hooks
> this plugin ships (`hooks/hooks.json`) watch the IDE's tool calls and have
> nothing to do with this page.

> **The registry is gone (loomcycle v1.97.0).** Hooks used to be registered
> globally with `register_hook` / `POST /v1/hooks` and lived in memory. Those
> tools and routes were removed. A run now fires exactly the hooks its agent's
> definition carries, plus any its run request or its team adds. A config or
> script that still registers hooks must move them onto the agent.

This page is the short form. The runtime serves the full article, matched to the
version you are connected to: call the `context` tool with
`{"op": "help", "topic": "hooks"}`.

## Where a hook is attached

A tool's hooks belong to that tool's entry in `tools`; the agent's own `hooks`
hold the run events, and tool events that apply to every tool:

```yaml
agents:
  researcher:
    tools:
      - Read
      - name: WebFetch                       # this tool's own hooks
        hooks:
          pre:
            - deny-internal                  # a hook definition (its active version)
            - { name: url-gate, url: "https://app.example/hooks/url-gate", fail_mode: closed, timeout_ms: 800 }
    hooks:                                   # the agent's own
      agent_stop: [cite-sources@3]           # a hook definition pinned to version 3
      post: [redact-secrets]
```

An entry is either the **name of a hook definition** (`gate`, or `gate@3` to pin
a version) or an **inline webhook** `{name, url, fail_mode, timeout_ms,
headers}`. Inline is always a webhook; JavaScript lives in a hook definition.

Three other places add hooks, and all three can only **add**:

- a run request: `hooks` / `tool_hooks` on `spawn_run`, `spawn_runs` and
  `POST /v1/runs`;
- a team state's `hooks` / `tool_hooks`, added to every run that state starts;
- a channel's `hooks.channel_publish`, which decide each message published to
  the channel before any reader sees it (off unless the operator sets
  `LOOMCYCLE_CHANNEL_HOOKS=1`).

## The events

| Event | Fires | It may |
|---|---|---|
| `pre` | before a tool call | rewrite the input, deny the call, or (operator-permitted only) allow extra hosts for this one call |
| `post` | after a tool call | rewrite the result, or append context |
| `post_failure` | after a tool call that failed | same as `post` |
| `agent_start` | once, before the first model call | deny the run, or add to its prompt |
| `agent_stop` | each time the model finishes an answer | `block` (send it back with a reason; more than 3 in a row fails the run) or `hold` it for a person |
| `subagent_start` / `subagent_stop` | in the parent, around a child run | deny the child or its result, or add context |
| `pre_compact` | before a compaction | deny it |
| `post_compact`, `run_end` | afterwards | report only; the answer is ignored |
| `channel_publish` | on a channel, per message | release, rewrite, drop or hold |

A tool's own entry takes only `pre`, `post` and `post_failure`.

An `agent_stop` **hold** is the same hold a run under review gets: the run waits
with `awaited_state: "review"`, and a person rules on it with the `review_run`
tool (`/loomcycle:review`).

## Hook definitions

The `hookdef` tool stores one hook once, versioned, so it can be named wherever
it is used. Ops: `create` (which also promotes), `fork` (does not promote),
`get`, `list`, `promote`, `retire`, `verify`, `delete`.

```json
{ "op": "create", "name": "net/deny-internal",
  "overlay": {
    "description": "Blocks fetches of internal hosts.",
    "event": "pre",
    "match": { "tools": ["WebFetch", "HTTP"] },
    "body": { "kind": "http", "url": "https://hooks.example/gate" },
    "fail_mode": "closed",
    "timeout_ms": 800 } }
```

- `body.kind` is `http` (a `url`) or `code-js` (a `code` body defining
  `hook(ev)`). A code body is compiled when saved and **refused unless the
  operator set `LOOMCYCLE_CODE_HOOKS_ENABLED=1`**.
- A code hook's only tool is `Interruption` (`ask`, `notify`), so it can ask an
  operator and decide on the answer. It runs in a sandbox with a 50 ms default
  time budget, 1 s at most.
- A definition **fires on nothing by itself**. Naming it from an agent, a team
  or a run is what attaches it.
- It is never an agent tool: no agent can write the hook that gates it.
- A hook an agent names that cannot be resolved (retired, deleted) **stops the
  run before any model call**. A gate must not silently go missing.

## Fail-open or fail-closed

`fail_mode` decides what a timeout, a 5xx or a network error means:

- `open` (the default): the call goes through unchanged. Right for telemetry.
- `closed`: the call fails. **A security check must be `closed`.** Under `open`,
  anything that makes the hook fail skips the check, and the model controls the
  input: an oversized one can make a hook time out on purpose.

## Secrets and hosts

- A hook's secret goes in `headers` as a credential reference
  (`Authorization: "Bearer $cred:hook_secret"`), never in the URL or as a
  literal, which would sit in the definition for anyone who can read it.
- A hook can only **narrow** a call. The one exception is a `pre` hook's
  `allow_hosts`, which counts only for a hook the operator listed under
  `hooks.permit_host_widen.owners` and that came from an operator-authored
  definition. Never derive `allow_hosts` from the tool input: the URL the model
  wants is untrusted.
- A tenant's hook webhook cannot reach a private address unless the operator
  lists the host (`LOOMCYCLE_HOOKS_PRIVATE_HOST_ALLOWLIST`).
