# loomcycle MCP tools — which one, and which not

The plugin ships **no tool definitions**. `.mcp.json` wires
`loomcycle mcp --upstream <base_url>`, a stdio↔`/v1/_mcp` proxy that forwards
every `tools/list` to the runtime, so the tools you see and their descriptions
come from **the loomcycle instance you are connected to**, not from this repo.
Upgrade the runtime and the surface changes under you.

So this page is deliberately **not** a copy of those descriptions. Duplicating
them here would go stale on the next runtime patch and quietly disagree with
what your session is actually holding. What is here instead is the **map**: the
clusters where two tools sound alike, which one owns which job, and the traps
that cost a wasted call. For the authoritative text of any one tool, ask the
session: `context` with `op=doc` returns a tool's full schema.

**54 tools** as of loomcycle v1.107.0.

> **What a tool is called in your session.** With this plugin's own server the
> tools are named `mcp__plugin_loomcycle_loomcycle__<tool>`. A project that
> registers the server itself under the name `loomcycle` gets
> `mcp__loomcycle__<tool>`. This page uses the bare tool name.

---

## Start here

| You want to… | Tool |
|---|---|
| Run an agent once and get its answer | `spawn_run` |
| Run the same agent over many inputs, or start runs without waiting | `spawn_runs` |
| Prepare a run, look at it, then start it | `configured_run` |
| Get a yes/no, a pick or a score about some text, cheaply | `decision` |
| Run a multi-agent workflow | `teamdef` (`op=run`) |
| Watch runs change state live | `stream_user_run_states` |
| Find out what this deployment supports | `context` (`op=capabilities`) |
| See which tools *you* may call | `context` (`op=tools`) |
| Know what agents exist | `list_agents` |

---

## The clusters

### Running agents

| Tool | Owns |
|---|---|
| `spawn_run` | ONE run, blocking. Fresh agent, or continue a `session_id`. |
| `spawn_runs` | Up to 32 runs concurrently, one call, index-aligned results. `mode: "detach"` returns once they have started. |
| `configured_run` | A run that is created but **not started**: `create`, `update`, `start`, `delete`. |
| `get_run` | Status of one run you hold a handle for. |
| `list_runs` | Find runs you have no handle for: by `user_id`, or by `walk_id`. |
| `cancel_run` | Stop one run; cascades to sub-agents. |
| `compact_run` | Summarize a **parked** run's history so it can continue. |
| `retune_run` | Change a **running** run's settings without sending it a message. |
| `review_run` | Rule on a run whose answer is **held for review**. |
| `interruption_resolve` | Answer a question a run asked a human. |

**Traps**

- **N parallel `spawn_run` calls do not fan out.** One MCP connection serializes
  them, so they run one after another. `spawn_runs` is concurrent server-side.
- **`spawn_run` has no detached form.** It holds the connection for the whole
  run. A run that waits for a person (`interactive: true`, or `review: true`)
  is started through `spawn_runs` with `mode: "detach"`.
- **Two time bounds, two meanings.** `timeout_ms` bounds the *call* and cancels
  the run when it expires (`status: "timeout"`); it is refused with `detach`.
  `max_wall_seconds` bounds the *run* and ends it `cancelled` with
  `stop_reason: "wall_limit"`.
- **`idempotency_key` does not compare the request.** The same key with a
  different prompt returns the first run, marked `deduplicated`. Put what makes
  the work distinct into the key.
- **`get_run` takes exactly one of `run_id` or `agent_id`.** An `agent_id`
  resolves to that agent's *latest* run. Several runs can share one: every walk
  of a team is filed under `team:<name>`. Read a specific run by `run_id`.
- **`list_runs` takes exactly one of `user_id` or `walk_id`.** There is no
  unfiltered listing.
- **`compact_run` needs the run PARKED** (awaiting input). A mid-turn run is
  refused, not queued.
- `cancel_run` does not return partial output, and does not undo side effects
  the run already committed.
- **A failed run comes back as a tool error** (`isError: true`), with a category
  (`validation`, `business`, `permission` or `transient`) and whether a retry
  can help. Read that before re-spawning.

**The four ways to reach a run that is going**

They are different jobs and each refuses the others' cases:

| You want to | Use |
|---|---|
| change its model, bounds or mode, and say nothing to it | `retune_run` |
| approve or reject an answer it is being held on | `review_run` |
| answer a question the agent asked | `interruption_resolve` |
| send it a message | continue its session with `spawn_run` + `session_id`; for a live interactive run, steer it over HTTP (`/loomcycle:steer`) — **there is no steering tool** |

`retune_run` returns the run's merged configuration, which is not an echo of the
request: naming a model clears the provider, and naming a tier clears the model.

**A configured run** costs nothing until `op=start`: it takes no concurrency
slot and no token budget. Admission happens at start, so a busy or over-budget
refusal leaves it configured to start again later. It never stores
`user_bearer` or `user_credentials`; give those to `start`. `op=delete` is for a
draft; a run that has started is stopped with `cancel_run`.

### Defining agents — the one people get wrong

| Tool | Lifetime | Use when |
|---|---|---|
| `register_agent` | A TTL. Dies with the runtime. | A scratch agent for this session. |
| `agentdef` | Durable, versioned, content-hashed. | Anything that should exist tomorrow. |

**Traps**

- **A def you `create` is not live until you `promote` it.** `create` and `fork`
  mint a *version*; promote decides which version runs. This catches everyone
  once.
- `register_agent` **strips Bash, Write and Edit** unless the operator opted in,
  so you can ask for them and quietly get an agent without them. Check what came
  back.
- You cannot widen your own reach: an agent's `tools` must be a subset of what
  your token already holds. A create that tries is refused, not trimmed.
- `scheduledef` is the exception to "not live until promoted": its forks
  **auto-promote**, so a fork goes live immediately.

### Teams

`teamdef` authors a **team**: a workflow written as a state machine of agent
nodes and the transitions between them. Its ops are `create`, `fork`, `get`,
`list`, `promote`, `retire`, `delete`, `verify`, `render_diagram` and `run`.

- **Not for one agent** (`spawn_run`), and not for fanning one agent over many
  inputs (`spawn_runs`). A team is for work that hands off between several.
- The graph is validated **before** any write. `verify` re-checks a stored team
  against the agents and channels it names; run it before `run`.
- **`run` waits for the whole walk** unless `mode` is `"detach"`, which returns
  the walk's `run_id` at once. Follow a detached walk with `get_run` (by that
  `run_id`), `list_runs` with `walk_id`, or `stream_user_run_states` with
  `walk_id`. A walk's own `run_id` **is** its walk id.
- Poll mode (`op=poll`, `op=cancel`, `mode: "poll"`) reports to a calling
  agent's run, so it exists only inside a run and is not offered over MCP.
- Authoring a team needs no run scope; `op=run` needs `runs:create`.

### Hooks

`hookdef` authors a reusable **hook**: one gate on an agent. It names the event
it answers (a tool call before or after it runs, or a point in the run such as
its start or each finished answer), the tools it matches, a body (a code-js
script, or a webhook URL), a fail mode and a timeout.

- **A hook definition fires on nothing by itself.** An agent definition, a team
  definition or a run names it, and that decides which agent it gates.
- A hook narrows or checks calls **within** what an agent may do. What the agent
  may do in the first place is its own `tools` and grants (`agentdef`).
- A run can add hooks to its agent's own with `hooks` / `tool_hooks` on
  `spawn_run`. It can only add; nothing there removes a hook the agent carries.
- A code-js body is refused unless the server enables code hooks.
- **The old registry is gone.** `register_hook`, `list_hooks` and `delete_hook`
  were removed in v1.97.0, with the `/v1/hooks` routes. If something still calls
  them, move the hook onto the agent definition.

### Channels

| Tool | Owns |
|---|---|
| `channel` | Every op, including `await`, `broadcast` and `release`, which exist nowhere else. |
| `publish_channel` / `subscribe_channel` / `peek_channel` / `ack_channel` | Single-op twins of four of those. |
| `channeldef` | The channel DEFINITION — create, update, delete, purge. Moves no messages. |
| `list_channels` | Operator aggregate across every scope. **Admin only.** |

**The delivery decision**

- `subscribe_channel` commits the cursor as it reads — **at-most-once**. A message
  you fail to process is gone.
- `peek_channel` then `ack_channel` — **at-least-once**. Read, do the durable
  work, then commit.

Peeking without ever acking re-reads the same messages forever.

**Traps**

- Publishing to a channel nobody declared is **refused**; it does not create one.
- `channeldef` `purge` discards buffered messages irreversibly and works on any
  channel; `delete` removes a runtime-declared channel entirely. Channels
  declared in the operator's yaml cannot be created, updated or deleted here.
- A channel with `hold` set stores publishes and delivers nothing until
  `channel op=release`.

### Memory, documents and names

The split is by **shape**, not by topic:

| Tool | Holds |
|---|---|
| `memory` | Values and facts, looked up by key or by meaning. |
| `document` | Structured chunked prose you navigate and cite. |
| `path` | Only the NAMING layer over both. Resolves a path; never reads content. |
| `history` | Past **chats**: browse, search, rename, pin, recap. |

**Traps**

- **`path rm` removes the NAME, not the thing.** The document still exists and is
  still reachable by id. This is not a delete.
- `document` requires SQL Memory to be enabled on the runtime.
- **`memory add` is asynchronous.** It enqueues for background consolidation and
  the facts appear later.
- `history` groups runs into **chats**. For the run-level view use `list_runs` /
  `get_run`; for durable facts use `memory`, not a pinned chat. `history search`
  matches a chat's *title* by default; pass `match: "content"` to search what
  was said.
- `documentsourcedef` only makes a peer loomcycle **nameable**. Nothing syncs
  because a source exists: `document op=set_remote` binds a document to it and
  `op=sync` moves content.
- `memorybackenddef` decides where memory lives, not what is in it. Repointing
  an agent at another backend migrates nothing.

The `loomcycle-memory` skill covers this ground in full.

### Decisions

`decision` asks a **decision model** typed questions about text you pass in, and
returns each answer with probabilities. It takes `state`, `questions` and an
optional `model`; there is no `op`.

- Use it where you would otherwise spend a run on a judgement: route, gate, rank
  or grade. It cannot explain, summarise or extract.
- **The probabilities are not calibrated.** Compare options within one answer;
  do not treat a threshold as a guarantee.
- The request is never shortened for you. One that does not fit is refused with
  `prompt_too_large`.
- Outside a run the call is charged to **you**, the calling principal, and
  counts against your token budget.
- A deployment that lists no decision models answers every call with
  `decision_not_configured`.

See `/loomcycle:decide`.

### People and their data

| Tool | Owns |
|---|---|
| `directory` | READ-ONLY. Who has activity in your tenant (`users`), and what is held for one subject (`inspect`). |
| `erasure` | Report or erase what the deployment holds about one subject. |

- A user is **derived from run activity**, not a stored record, so `directory`
  has nothing to create or delete. An empty list means no activity.
- `erasure` **defaults to a dry run**, and the tenant comes from your
  credentials. See `/loomcycle:erasure` for the one-shot residue report.

### A2A — the direction matters

| Tool | Direction |
|---|---|
| `a2aservercarddef` | Advertises **us** to peers. |
| `a2aagentdef` | Registers a peer **we** call. |

Getting these the wrong way round is the usual mistake.

### External MCP servers, webhooks, schedules

- `mcpserverdef` registers an external MCP server so its tools become available.
  **HTTP servers only**; stdio servers stay in the operator's yaml. Registering
  publishes the tools; an agent's own `tools` list still has to name them. A
  `${NAME}` reference in a url or header reads the server's environment, so only
  an admin may store one. Anyone else passes a credential as
  `${run.credentials.<name>}` or `$cred:<name>`.
- `webhookdef` is the door **inward** (an external callback starts a run). To
  call out, an agent uses the HTTP tool.
- `scheduledef` retires stop future fires; a run already in flight is stopped
  with `cancel_run`.
- A webhook or schedule restored from a snapshot without its literal credentials
  carries `capture_disabled` and stays off until a fork supplies them.

### Snapshots — all admin-only

| Tool | Owns |
|---|---|
| `create_snapshot` | Capture state into a versioned envelope. |
| `list_snapshots` | Metadata only, newest first, capped at 200. |
| `get_snapshot` | The envelope as parsed JSON — the one to **read**. |
| `export_snapshot` | The canonical bytes — the one to **move**. |
| `restore_snapshot` | Write state back, from an id or from raw bytes. |
| `delete_snapshot` | Prune. Idempotent. |

**Traps**

- **`restore_snapshot` only ever ADDS.** Restoring an older snapshot does not
  roll back rows created since. It is not undo.
- A run in flight is captured only if it is **parked**. Restored paused runs
  resume on the instance that ran the restore.
- Per-run secrets are deliberately excluded from a capture and re-derived from
  the agent definition on restore. `create_snapshot` warns, by location, about
  every literal-looking credential it did capture.

### Volumes and credentials

- **`volumedef` `delete` vs `purge` is unrecoverable either way you get it
  wrong**: `delete` unmaps and **keeps** the files; `purge` removes the row **and
  deletes the directory tree**.
- **`credentialdef` never returns a secret.** `get` and `list` are metadata only,
  by design. Record it elsewhere on create, or rotate.
- **`operatortokendef` shows a token's plaintext exactly once**, on create and on
  rotate. `create` needs an explicit `scopes` list; an omitted one is refused.

### Runtime control

`pause_runtime` → `resume_runtime`, with `get_runtime_state` to poll. All admin.

- `pause_runtime` stops the **deployment**; `cancel_run` stops one run.
- A pause cancels nothing: each run finishes the call it is in and parks. New
  runs are refused while paused, and the runtime stays paused until
  `resume_runtime`.
- `get_runtime_state` reports the quiesce gate. It is **not** a health check.
- `resolve_probe` makes a live call to every provider. Escape hatch, not a poll.

### Asking the runtime about itself

`context` is the introspection tool. `capabilities` says what this deployment
supports; `tools` lists what you may call; `doc` returns one tool's schema;
`help` returns a help article by topic (`{"op": "help", "topic": "Decision"}`).
Every listing is confined to your own grant. `op=agents` is definition metadata;
the runnable inventory is `list_agents`.

**`op=help` is the manual, and it matches the runtime you are connected to.**
Omit `topic` for the index. A tool's article is named after the tool
(`Decision`, `Path`), one of its operations is `<Tool>/<op>` (`Path/ls`), and
the subject articles cover what this plugin does not: `agent-teams`, `hooks`,
`subagents`, `resident-sub-agents`, `fan-out-patterns`, `scheduled-runs`,
`input-webhooks`, `a2a-integration`, `code-agents`, `memory-consolidation`,
`sql-memory`, `credentials`, `scopes`, `operator-tokens`, `volumes`,
`pause-resume-snapshot`. Read the article before authoring a team, a hook or a
schedule by hand.

---

## What your token can reach

Three things decide which tools a session sees. A tool you may not call is not
merely refused: it is **absent from `tools/list`**. If a tool you expect is
missing, check here before assuming the runtime is broken.

**1. Twelve tools are admin-only.** They are runtime-global with no tenant
dimension:

```
create_snapshot   list_snapshots   get_snapshot      export_snapshot
restore_snapshot  delete_snapshot  pause_runtime     resume_runtime
get_runtime_state resolve_probe    operatortokendef  list_channels
```

The other **42 are tenant-confinable**: a tenant session may call them, and the
runtime stamps your tenant on what you write and folds another tenant's rows to
an opaque not-found on read.

**2. Sixteen of those 42 also need a scope** (since v1.107.0). A token that
lacks it does not see the tool:

| Scope | Tools |
|---|---|
| `runs:create` | `spawn_run`, `spawn_runs`, `cancel_run`, `compact_run`, `retune_run`, `review_run`, `configured_run`, `interruption_resolve`, `decision` |
| `runs:read` | `get_run`, `list_runs`, `stream_user_run_states` |
| `channel:publish` | `publish_channel`, `ack_channel` |
| `channel:read` | `subscribe_channel`, `peek_channel` |

`substrate:tenant` implies all four, and `substrate:admin` implies everything.
The definition and data tools (`agentdef`, `memory`, `document`, `path`, …) need
no scope beyond being a non-isolated token of the tenant.

One tool is gated per operation: `teamdef` is listed for any tenant token, but
its `op=run` needs `runs:create`.

**3. An isolated `substrate:user` token sees one tool**: `credentialdef`,
confined to its own user-scope credentials.

So a token minted with only `runs:read` can list and read runs here and nothing
else on the run plane, which matches what the HTTP API allows it.

Two that are easy to misread:

- `list_channels` is admin-only, but `channel` with `op=list_channels` is the
  tenant-confined equivalent. Same listing, confined to what you may see.
- `directory` is tenant-confinable, but its `op=tenants` sub-op is refused for a
  non-admin — the tool is reachable, that one op is not.

---

## After upgrading the runtime

Claude Code reads `tools/list` **once, at connection**. A session opened against
an older runtime keeps the old schemas: new ops still dispatch, but an argument
the cached schema does not declare is sent as a string and the server rejects it
(`cannot unmarshal string into Go struct field …`). Reload the plugin after
upgrading the runtime. There is no schema in this repo to fix.

---

## Keeping this page honest

The descriptions live in the runtime, in `internal/api/mcp/tools.go`, and are
tested there: every op a tool dispatches must be named in its description, no
internal design-doc references may appear in model-visible text, and every tool
must state a boundary — what NOT to use it for. The authorization split is in
`internal/api/mcp/toolauthz.go`.

This page restates the **clusters and the traps**, which change far less often
than the text does. When the runtime adds a tool, the surface picks it up
automatically; this page needs an edit only when a new tool joins a cluster or
creates one.
