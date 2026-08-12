---
description: Read and write a loomcycle agent's memory over MCP — semantic recall, key/value, per-scope SQL, and the consolidation queue.
argument-hint: "<recall|search|add|get|set|list|sql|…> [--scope=agent|user|tenant|run] [args…]"
allowed-tools: mcp__loomcycle__memory
---

# loomcycle memory

Read or write a loomcycle memory keyspace from the IDE. Wraps the `memory`
meta-tool, which is multi-op: every call MUST carry an `op` discriminator and a
`scope`.

Parse `$ARGUMENTS`:

- First token = the op (families below).
- `--scope=<agent|user|tenant|run>` selects the keyspace. **Default to `agent`**
  when omitted.
- Remaining tokens are the op's payload.

Render results as markdown, not raw JSON.

## Scopes — four, not two

| scope | keyspace |
|---|---|
| `agent` | this agent's, across runs and users |
| `user` | this end-user's, across agents. Needs a `user_id` on the run |
| `tenant` | shared by **every** user and agent in the tenant — anything written here is read by all of them, so use it for curated reference material, never for anything derived from untrusted text |
| `run` | ephemeral, dropped at run end. **SQL ops only** |

`tenant` requires the operator to have granted BOTH `memory_scopes` and
`sql_scopes` with the `tenant` value — granting one and not the other is the
usual cause of a refusal that looks like a bug.

## Op families

### Semantic — `recall`, `search`, `add`

```json
{ "op": "recall", "scope": "<scope>", "query": "<text>", "threshold": <0..1 optional> }
{ "op": "search", "scope": "<scope>", "query": "<text>", "top_k": <n, max 50> }
{ "op": "add",    "scope": "<scope>", "messages": [{"role":"user","content":"<text>"}], "infer": true }
```

`recall` returns `{facts: [{id, memory, score}]}` — render `score | memory | id`,
highest first. `search` is vector similarity over stored key/value rows and
returns `{key, value, score}`.

**`add` IS ASYNCHRONOUS.** With `infer: true` (the default) it returns
`{event_id, status: "pending"}` — the turns are enqueued for a background
consolidator, and the extracted facts appear later. Do **not** report failure
because no facts came back, and do not immediately `recall` and conclude the write
was lost. `infer: false` stores the turns verbatim as one row instead.

### Key/value — `get`, `set`, `delete`, `list`, `incr`

```json
{ "op": "get",  "scope": "<scope>", "key": "<key>" }
{ "op": "set",  "scope": "<scope>", "key": "<key>", "value": <json>, "ttl": <seconds optional> }
{ "op": "list", "scope": "<scope>", "prefix": "<optional>", "limit": <n> }
{ "op": "incr", "scope": "<scope>", "key": "<key>", "delta": <n, default 1> }
```

`set` also takes `embed: true` + `embed_text` to make the row reachable by
`search`, and a `provenance` object (`class`, `source_session_id`,
`source_run_id`) recording where a fact came from. Provenance is what makes an
erasure able to *find* a fact later — see `/loomcycle:erasure`.

### Compound writes — `merge`, `append_dedupe`, `bounded_list`

```json
{ "op": "merge",         "scope": "<scope>", "key": "<k>", "value": {"field": "…"} }
{ "op": "append_dedupe", "scope": "<scope>", "key": "<k>", "value": <item> }
{ "op": "bounded_list",  "scope": "<scope>", "key": "<k>", "value": <item>, "limit": <n> }
```

All three are atomic read-modify-write at the store, so concurrent callers do not
lose updates. Prefer them over `get` → mutate → `set`, which does.

### Per-scope SQL — `sql_query`, `sql_exec`, `sql_begin`/`sql_commit`/`sql_rollback`

```json
{ "op": "sql_query", "scope": "<scope>", "statement": "SELECT …", "args": [] }
{ "op": "sql_exec",  "scope": "<scope>", "statement": "CREATE TABLE …" }
```

A real per-scope database the runtime owns. **Gated separately by `sql_scopes`** —
having `memory` in `tools` is not enough. `sql_query` is read-only; `sql_exec` is
DDL/DML. One statement per call: `ATTACH`, `PRAGMA`, `load_extension`, explicit
transactions inside the statement, and multiple `;`-separated statements are all
refused. `sql_begin`/`commit`/`rollback` nest via savepoints.

On postgres, `{"$embed": "text"}` in `args` is replaced server-side by that text's
embedding — reference it with a `::vector` cast. That keeps raw vectors out of the
model's context.

### Consolidation queue — `cursor_*`, `supersede`, `pending_*`

`cursor_get`, `cursor_scan`, `cursor_lease`, `cursor_advance`, `cursor_release`,
`supersede`, `pending_drain`, `pending_ack`. These drive the background
consolidator and are gated behind their own grant. **Do not call them to "help"
consolidation along** — `cursor_advance` moves a watermark that decides what has
already been processed, and `supersede` retires a fact. Both require holding the
lease. Use them only when explicitly asked to inspect or repair the queue.

## Capability notes

`add` and `recall` work against loomcycle's **default in-process backend**, which
is a native memory layer. (Earlier plugin versions said they required a Mem9
smart-mode backend and refused otherwise — that is wrong now: the external `mem9`
kind was removed, and authoring it is refused.)

A refusal you *will* see is `sql_scopes` or `memory_scopes` not granting the scope
you asked for. Surface the refusal text plainly; never silently retry a different
scope or a different op.

If the op is missing or unrecognised, list the families above and stop rather than
guessing.
