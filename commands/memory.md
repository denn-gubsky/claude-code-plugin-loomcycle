---
description: Read and write loomcycle memory over MCP — semantic recall, key/value, per-scope SQL, and the consolidation queue.
argument-hint: "<recall|search|add|get|set|list|placement|sql|…> [--scope=agent|user|tenant|run] [args…]"
allowed-tools: mcp__loomcycle__memory mcp__plugin_loomcycle_loomcycle__memory
---

# loomcycle memory

Read or write a loomcycle memory keyspace from the IDE. Wraps the `memory`
meta-tool, which is multi-op: every call MUST carry an `op` discriminator and a
`scope`.

Parse `$ARGUMENTS`:

- First token = the op (families below).
- `--scope=<agent|user|tenant|run>` selects the keyspace. **Default to `user`**
  when omitted. Called from here there is no agent run, so `agent` is the
  session's own synthetic agent keyspace, not a named agent's memory; pick it
  only when the operator asks for it.
- Remaining tokens are the op's payload.

Render results as markdown, not raw JSON.

## Scopes — four, not two

| scope | keyspace |
|---|---|
| `agent` | this agent's, across runs and users |
| `user` | this end-user's, across agents. Needs a `user_id` on the run |
| `tenant` | shared by **every** user and agent in the tenant — anything written here is read by all of them, so use it for curated reference material, never for anything derived from untrusted text |
| `run` | ephemeral, dropped at run end. **SQL ops only** |

**One scope per call.** A `user` recall does not see `tenant` knowledge; to
consult both, make two calls and merge by score.

**Called from here there is no run**, so the scopes resolve to the MCP session
itself: `user` is the subject of the token the session authenticated with (the
same keyspace that user's agent runs and the Web UI use); `agent` is the
session's own synthetic agent, not a named agent's keyspace; `run` is not
available. The session holds `agent`, `user` and `tenant` on both the memory and
the SQL plane.

For an *agent*, `tenant` requires the operator to have granted BOTH
`memory_scopes` and `sql_scopes` with the `tenant` value — granting one and not
the other is the usual cause of a refusal that looks like a bug. Unset grants
resolve to the caller's own data (`memory_scopes` → `user`, plus `tenant` for a
non-isolated tenant member; `sql_scopes` → `user`); `["-*"]` is the explicit
deny.

## Op families

### Semantic — `recall`, `search`, `add`

```json
{ "op": "recall", "scope": "<scope>", "query": "<text>", "top_k": <n, max 50>, "threshold": <0..1 optional> }
{ "op": "search", "scope": "<scope>", "query": "<text>", "top_k": <n, max 50> }
{ "op": "add",    "scope": "<scope>", "messages": [{"role":"user","content":"<text>"}], "infer": true }
```

`recall` returns `{memories: [{id, memory, score, kind, …}]}` (the array was
`facts` before v1.65.0) — render `score | kind | memory | id`, highest first.
`kind` is `fact` (distilled by a consolidator) or `note` (a remark an agent
recorded); say which when it matters. Items also carry, when known, `source`
(the verbatim span the fact came from), `source_session_id`, `source_run_id`,
`observed_at` and `valid_at`.

Optional on `recall` and `search`:

- `sources` — any of `facts`, `notes`, `documents`, `traces`. `recall` defaults
  to facts + notes; `search` to everything except `traces`. `traces` must be
  asked for alone.
- `when` — `{from, to, slack, missing, as_of}`, RFC3339. `from`/`to` narrow by
  when something was *said* (give a generous window); `as_of` asks what was
  *true* at that instant.

  ```json
  { "op": "recall", "scope": "user", "query": "<text>", "when": { "from": "2026-05-01T00:00:00Z", "to": "2026-06-30T00:00:00Z" } }
  ```
- `include_turns: true` (`recall` only) — attach the conversation turn each fact
  came from, as `turn`. Larger reply; the result reports `turns_attached`.
- `include_source: false` (`recall` only) — drop the `source` span.

`search` is vector similarity over stored rows and returns
`{entries: [{key, kind, value, score, rank_score, …}], truncated}`. A `set` row
is found only if it was written with `embed: true`.

**`add` IS ASYNCHRONOUS.** With `infer: true` (the default) it returns
`{status: "pending", event_id}` — the turns are enqueued for a background
consolidator, and the extracted facts appear later. Do **not** report failure
because no facts came back, and do not immediately `recall` and conclude the write
was lost. `infer: false` stores the turns verbatim as one row instead and
returns `status: "done"`.

### Key/value — `get`, `set`, `delete`, `list`, `incr`

```json
{ "op": "get",  "scope": "<scope>", "key": "<key>" }
{ "op": "set",  "scope": "<scope>", "key": "<key>", "value": <json>, "ttl": <seconds optional> }
{ "op": "list", "scope": "<scope>", "prefix": "<optional>", "limit": <n, default 100> }
{ "op": "incr", "scope": "<scope>", "key": "<key>", "delta": <n, default 1> }
```

Text goes in `value` as a plain string — `"value": "Helix"`; quotes placed
inside the string are stored too.

`set` also takes `embed: true` + `embed_text` to make the row reachable by
`search`; `path` to name the entry in the Path tree (then `get` accepts that
`path` instead of `key`); `observed_at` / `valid_at` / `invalid_at` (RFC3339) to
date it; and a `provenance` object (`class`, `source_session_id`,
`source_run_id`) recording where a fact came from. Provenance is what makes an
erasure able to *find* a fact later — see `/loomcycle:erasure`. If embedding
fails the value is still stored and the reply says `embedded: false` with an
`embed_warning`.

### Compound writes — `merge`, `append_dedupe`, `bounded_list`

```json
{ "op": "merge",         "scope": "<scope>", "key": "<k>", "value": {"field": "…"} }
{ "op": "append_dedupe", "scope": "<scope>", "key": "<k>", "value": <item> }
{ "op": "bounded_list",  "scope": "<scope>", "key": "<k>", "value": <item>, "limit": <n> }
```

All three are atomic read-modify-write at the store, so concurrent callers do not
lose updates. Prefer them over `get` → mutate → `set`, which does.

### Placement — `placement`

```json
{ "op": "placement", "scope": "<the scope you meant to write>", "items": [{"type": "service", "subject": "checkout-api"}] }
```

Read-only. Answers which scope each `{type, subject}` fact belongs in, from the
operator's per-type declarations on the tenant ontology. Returns
`{placements: [{type, subject, scope, moved, reason}], moved, caller_scope,
granted_scopes, granted_sql_scopes}`. It never writes — write each fact to the
`scope` it names afterwards. Up to 200 items per call. When nothing is declared
(no ontology, or a draft one) every item stays in the scope you passed and
`reason` says why.

### Per-scope SQL — `sql_query`, `sql_exec`, `sql_begin`/`sql_commit`/`sql_rollback`

```json
{ "op": "sql_query", "scope": "<scope>", "statement": "SELECT …", "args": [] }
{ "op": "sql_exec",  "scope": "<scope>", "statement": "CREATE TABLE …" }
```

A real per-scope database the runtime owns. **Gated separately by `sql_scopes`** —
having `memory` in `tools` is not enough. `sql_query` is read-only; `sql_exec` is
DDL/DML. One statement per call: `ATTACH`, `PRAGMA`, `load_extension`, explicit
transactions inside the statement, and multiple `;`-separated statements are all
refused. `sql_begin`/`commit`/`rollback` nest via savepoints, and need an active
run — called from here `sql_begin` is refused.

On postgres, `{"$embed": "text"}` in `args` is replaced server-side by that text's
embedding — reference it with a `::vector` cast. That keeps raw vectors out of the
model's context.

### Consolidation queue — `cursor_*`, `supersede`, `pending_*`

`cursor_get`, `cursor_scan`, `cursor_lease`, `cursor_advance`, `cursor_release`,
`supersede`, `pending_drain`, `pending_ack`. These drive the background
consolidator and are gated behind their own grant — which this MCP session
holds, so the grant will not stop you. **Do not call them to "help"
consolidation along** — `cursor_advance` moves a watermark that decides what has
already been processed, and `supersede` retires a fact. Both require holding the
lease. Use them only when explicitly asked to inspect or repair the queue.

`supersede` takes `key` (the fact's key, as `recall` reports it in `id`) and an
optional `superseded_by` (the key of the fact that replaces it — pass it for a
correction, omit it when the row was merely moved). It retires the fact in both
the key/value plane and the fact graph in one call.

## Capability notes

`add` and `recall` work against loomcycle's **default in-process backend**, which
is a native memory layer. (Earlier plugin versions said they required a Mem9
smart-mode backend and refused otherwise — that is wrong now: the external `mem9`
kind was removed, and authoring it is refused.) `recall` and `search` still need
an embedder and a vector-capable store; without them they refuse and `get` /
`list` are the fallback.

A refusal an agent *will* see is `sql_scopes` or `memory_scopes` not granting the
scope it asked for. Surface the refusal text plainly; never silently retry a
different scope or a different op.

If the op is missing or unrecognised, list the families above and stop rather than
guessing.
