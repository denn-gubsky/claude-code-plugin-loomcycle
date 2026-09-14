# loomcycle MCP tools — which one, and which not

The plugin ships **no tool definitions**. `.mcp.json` wires
`loomcycle mcp --upstream <base_url>`, a stdio↔`/v1/_mcp` proxy that forwards
every `tools/list` to the runtime, so the tools you see and their descriptions
come from **the loomcycle instance you are connected to** — not from this repo.
Upgrade the runtime and the surface changes under you.

So this page is deliberately **not** a copy of those descriptions. Duplicating 52
strings here would go stale on the next runtime patch and quietly disagree with
what your session is actually holding. What is here instead is the **map**: the
clusters where two tools sound alike, which one owns which job, and the traps
that cost a wasted call. For the authoritative text of any one tool, ask the
session — `context` with `op=doc` returns a tool's full schema.

**52 tools** as of loomcycle v1.78.0.

---

## Start here

| You want to… | Tool |
|---|---|
| Run an agent once and get its answer | `spawn_run` |
| Run the same agent over many inputs | `spawn_runs` |
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
| `spawn_runs` | Up to 32 runs concurrently, one call, index-aligned results. |
| `get_run` | Status of one run you hold a handle for. |
| `list_runs` | Find runs you have no handle for. `user_id` is required. |
| `cancel_run` | Stop one run; cascades to sub-agents. |
| `compact_run` | Summarize a **parked** run's history so it can continue. |

**Traps**

- **N parallel `spawn_run` calls do not fan out.** One MCP connection serializes
  them, so they run one after another. `spawn_runs` is concurrent server-side.
- **`compact_run` needs the run PARKED** (awaiting input). A mid-turn run is
  refused, not queued.
- `cancel_run` does not return partial output, and does not undo side effects
  the run already committed.

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

### Memory, documents and names

The split is by **shape**, not by topic:

| Tool | Holds |
|---|---|
| `memory` | Values and facts, looked up by key or by meaning. |
| `document` | Structured chunked prose you navigate and cite. |
| `path` | Only the NAMING layer over both. Resolves a path; never reads content. |

**Traps**

- **`path rm` removes the NAME, not the thing.** The document still exists and is
  still reachable by id. This is not a delete.
- `document` requires SQL Memory to be enabled on the runtime.
- `history` groups runs into **chats**. For the run-level view use `list_runs` /
  `get_run`; for durable facts use `memory`, not a pinned chat.

### A2A — the direction matters

| Tool | Direction |
|---|---|
| `a2aservercarddef` | Advertises **us** to peers. |
| `a2aagentdef` | Registers a peer **we** call. |

Getting these the wrong way round is the usual mistake.

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
- Per-run secrets are deliberately excluded from a capture and re-derived from
  the agent definition on restore.

### Volumes and credentials

- **`volumedef` `delete` vs `purge` is unrecoverable either way you get it
  wrong**: `delete` unmaps and **keeps** the files; `purge` removes the row **and
  deletes the directory tree**.
- **`credentialdef` never returns a secret.** `get` and `list` are metadata only,
  by design. Record it elsewhere on create, or rotate.
- **`operatortokendef` shows a token's plaintext exactly once**, on create and on
  rotate.

### Runtime control

`pause_runtime` → `resume_runtime`, with `get_runtime_state` to poll. All admin.

- `pause_runtime` stops the **deployment**; `cancel_run` stops one run.
- Runs FORCE-CANCELLED during a pause do not come back on resume — only parked
  ones do.
- `get_runtime_state` reports the quiesce gate. It is **not** a health check.
- `resolve_probe` makes a live call to every provider. Escape hatch, not a poll.

### Hooks

`register_hook` / `list_hooks` / `delete_hook` — pre- and post-tool webhooks to
an endpoint you run.

- Hooks are **in-memory**: gone after a loomcycle restart. An empty `list_hooks`
  means "nobody has registered since boot", not "nobody wants hooks". Consumers
  are expected to re-register on startup, which is why re-registering the same
  `(owner, name)` replaces rather than duplicates.
- A hook **watches** tool calls; it does not provide a tool. Adding tools is
  `mcpserverdef`.

---

## What your token can reach

Twelve tools are **admin-only** — they are runtime-global with no tenant
dimension, so a `substrate:tenant` or user token does not merely get refused, it
**does not see them in `tools/list` at all**. If a tool you expect is missing,
check this list before assuming the runtime is broken:

```
create_snapshot   list_snapshots   get_snapshot      export_snapshot
restore_snapshot  delete_snapshot  pause_runtime     resume_runtime
get_runtime_state resolve_probe    operatortokendef  list_channels
```

The other **40 are tenant-confinable**: a tenant session may call them, and the
runtime stamps your tenant on what you write and folds another tenant's rows to
an opaque not-found on read.

Two that are easy to misread:

- `list_channels` is admin-only, but `channel` with `op=list_channels` is the
  tenant-confined equivalent. Same listing, confined to what you may see.
- `directory` is tenant-confinable, but its `op=tenants` sub-op is refused for a
  non-admin — the tool is reachable, that one op is not.

---

## Keeping this page honest

The descriptions live in the runtime, in `internal/api/mcp/tools.go`, and are
tested there: every op a tool dispatches must be named in its description, no
internal design-doc references may appear in model-visible text, and every tool
must state a boundary — what NOT to use it for.

This page restates the **clusters and the traps**, which change far less often
than the text does. When the runtime adds a tool, the surface picks it up
automatically; this page needs an edit only when a new tool joins a cluster or
creates one.
