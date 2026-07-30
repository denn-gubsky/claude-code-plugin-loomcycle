# Document primitive reference — RFC AK (v1.4.0+), entity tier (v1.42.0)

A `Document` is a **chunked-graph document**: instead of one opaque blob, it's a
tree of **chunks** — each a first-class unit with a UUID, a hierarchy position,
an optional type, structured fields, graph edges, and a Markdown body — that
agents and humans co-author and query.

**Content/structure split** (the mechanism): chunk **bodies + fields** live in
Memory (keyed by the chunk UUID); chunk **structure**
(parent/position/type/status/title/revision + edges + type schemas + the
entity-tier sidecar) lives in **SQL Memory**, so agents query `SELECT … FROM
chunks WHERE type=… AND status=…`. A Document is **named in the Path tree** via a
`document` dirent (see [path.md](path.md)) — always, since v1.6.5: omit `path:`
and it lands at `/documents/<title-slug>` rather than being reachable by id alone.

---

## Enablement — gate + the SQL Memory prerequisite

Two requirements:

1. **`tools: [Document]`** — the per-agent gate (Document is always registered).
2. **SQL Memory enabled** — the chunk-structure tables live there, so the
   deployment needs **`LOOMCYCLE_SQLMEM_ENABLED=1`**. Without it every
   `Document` call is refused with "requires SQL Memory."

```yaml
agents:
  author:
    tools: [Document, Memory, Path]
```

```bash
# .env.insecure (feature flag, not a secret)
LOOMCYCLE_SQLMEM_ENABLED=1
```

> The config key is **`tools:`**. It was `allowed_tools:` before loomcycle
> v1.13.0, and the old spelling is now **silently ignored** — `validate` still
> prints `OK` while the agent ends up with an empty allowlist, which fails closed
> to *no tools at all*. If an agent mysteriously has nothing available, check this
> first.

> SQL Memory (RFC AA, loomcycle v1.2.0) is a per-scope SQL database that is a
> facet of the `Memory` tool — Document piggybacks on it for structure storage. At
> `agent`/`user` scope an agent that uses Document does **not** need `Memory`'s
> `sql_scopes` gate; the Document tool issues its own trusted SQL. **Tenant scope
> is the exception — see below.**

---

## Operations

| group | ops |
|---|---|
| Document lifecycle | `create_document`, `get_document` (by `id` or `path`), `documents_summary`, `delete_document`, `set_path` |
| Chunk lifecycle | `create_chunk` (`parent_id`/`position`/`after_id`), `get_chunk`, `update_chunk`, `delete_chunk`, `move_chunk`, `reorder_chunk` |
| Entity tier (v1.42.0) | `upsert_chunk`, `supersede_chunk`, `graph_recall` |
| Edges | `link_chunks`, `unlink_chunks`, `get_edges` |
| Query | `query_chunks` |
| Types | `define_type`, `list_types` |
| Images (v1.30.0) | `set_asset`, `get_asset` |
| Markdown | `export_md`, `import_md` |

`scope` is `agent` (default), `user` (needs a `user_id` on the run), or **`tenant`**
(shared by every user and agent in the tenant — since v1.41.0).

### Tenant scope needs TWO grants

A tenant document is read and written by everything in the tenant, so it is
default-deny and requires the operator to list `tenant` in **both**:

```yaml
agents:
  curator:
    tools: [Document, Memory]
    memory_scopes: [agent, user, tenant]   # the chunk BODIES
    sql_scopes:    [agent, user, tenant]   # the chunk STRUCTURE
```

Granting one and not the other reaches half a tenant store, and half a document is
not a partial success — it is structure with no text. The refusal names whichever
grant is missing. (`agent` and `user` scope are ungated on this path, which
predates the tenant work.)

### Behaviour worth teaching the agent

- **Optimistic concurrency.** `update_chunk` takes the chunk's current `revision`;
  a stale revision returns a conflict instead of a silent lost update. Two agents
  editing different chunks never clobber.
- **`upsert_chunk` deliberately takes no `revision`** — see the entity tier below.
- **`move_chunk`** re-parents with a cycle guard (a chunk can't become its own
  ancestor); **`reorder_chunk`** shifts one chunk up/down among its siblings.
- **`query_chunks`** takes structured filters (`document_id`/`type`/`status`/
  `parent_id`, plus `under_path:` joining the Path tree) **or** a `sql:` escape
  hatch — a raw read-only `SELECT`, validator-gated (no `ATTACH`/`PRAGMA`/writes).
  The chunk table is named **`chunks`**, and the entity sidecar
  **`chunk_memory_meta`**.
- **Change events.** `update_chunk`/`move_chunk`/`link_chunks`/`delete_chunk`
  publish `{op, chunk_id, timestamp, actor}` to `documents/<id>/chunks`, so a
  co-authoring UI sees edits live.
- **Atomic, orphan-free deletes.** `delete_document`/`delete_chunk` run the whole
  cascade in one SQL Memory transaction — descendants, edges in both directions,
  image assets, the entity sidecar, and the chunk bodies in the Memory plane.
  `link_chunks` validates both endpoints; `delete_chunk` refuses a document's root
  chunk (use `delete_document`).

---

## The entity tier (v1.42.0)

Three ops turn a document into a **bi-temporal fact store**: facts that can be
corrected without losing what they corrected, and recalled as of a past instant.

**Two time axes, and they answer different questions.** `valid_at`/`invalid_at` is
**world** time — when the fact was true. `created_at`/`expired_at` is **system**
time — when the store believed it. That split is what lets "who was on call last
Tuesday" and "what did we *think* last Tuesday" be different queries. The system
pair is never caller-settable: a first write sets `created_at`, `supersede_chunk`
sets `expired_at`.

### `upsert_chunk` — write by natural key, not by id

```
mcp__loomcycle__document {
  "op": "upsert_chunk", "scope": "user", "document_id": "<id>",
  "natural_key": "person:alice:role", "title": "Alice's role",
  "body": "Alice leads the platform team.",
  "type": "fact", "class": "evidential", "confidence": 0.9
}
→ { "id": "<chunk>", "natural_key": "…", "created": true }
```

The `natural_key` is the **idempotency handle** and is unique **per scope**, which
is what stops the same fact accumulating a row per mention: call it twice and you
get one chunk (`created: false` the second time). It takes **no `revision`** on
purpose — optimistic concurrency assumes the caller read the row and knows its
version, while an upsert's whole premise is that the caller knows only the key.

**Unspecified fields are preserved.** An upsert carrying only a fresh `body` keeps
the existing title, type, `class`, `valid_at`, `created_at` and any retirement, so
a re-observation updates the wording without disturbing the fact's history. (This
was broken in exactly v1.42.0 and fixed immediately after: on that one tag a
re-upsert silently un-retires a superseded fact, resets `created_at`, and
downgrades `class: evidential` to `derived`. Upgrade past it before relying on the
entity tier, and keep any retention prune in dry-run until you have.)

**`class`** is `derived` (default) or **`evidential`**. Evidential material is
what everything else was distilled from, so it is **exempt from retention pruning
at any age**; derived material can be re-derived. The class is caller-supplied, so
treat it as a claim an agent makes rather than something the runtime verified.

### `supersede_chunk` — correct without deleting

```
mcp__loomcycle__document {
  "op": "supersede_chunk", "scope": "user",
  "id": "<the new fact>", "supersedes_id": "<the fact it replaces>"
}
```

Stamps both end-timestamps on the retired chunk and links the replacement to it
with a `supersedes` edge. **The retired chunk stays readable** — that is the whole
point, so a question about an earlier instant still has an answer. `id` and
`supersedes_id` are separate named fields rather than a reused `from_id`/`to_id`
pair precisely because transposing them would invalidate the *new* fact and leave
the stale one current.

Reviving a retired fact is possible but must be **explicit** (pass `invalid_at`
yourself). It is not something a routine write does as a side effect.

### `graph_recall` — walk the relations, time-aware

```
mcp__loomcycle__document {
  "op": "graph_recall", "scope": "user",
  "query": "on-call rotation",          // or "seed_ids": ["<chunk>", …]
  "hops": 2, "as_of": 1785424758000000000, "include_retired": false
}
→ { "chunks": [{ "id", "title", "type", "hop", "valid_at", "retired" }, …],
    "hops": 1, "seeds": 1, "truncated": false }
```

Expands bidirectionally from seeds (found by `query`, or named outright via
`seed_ids`) up to `hops` (max 2, frontier capped at 500). `as_of` drops facts the
store did not believe at that instant — applied to **discovery only**, never to
seeds you named explicitly, so asking about a fact you already hold still works.
Retired chunks are excluded unless `include_retired: true`.

> `seed_ids` is an array, `hops`/`as_of` integers, `include_retired` a boolean.
> If your MCP client sends them as strings you will get
> `cannot unmarshal string into Go struct field` — see the upgrade note below.

---

## The tenant ontology (v1.42.0)

The entity **types** agents extract against are `base seed ⊕ tenant layer`. The
seed is POLE+O — person / object / location / event / organization — plus
`preference` and `fact`. A tenant adds its own types in a document at
**`/memory/ontology`** (tenant scope), reachable like any other document.

**The tenant layer is INERT until an operator confirms it.** Editing the document
changes nothing; the root chunk's `status` must be exactly `confirmed`. Any other
value — including a typo like `confirmd` — leaves the deployment on the seed alone,
with no error anywhere.

Do that flip through the **Web UI → Settings → Ontology** tab (or
`POST /v1/_ontology {"status":"confirmed"}`), not by hand-editing the status
field: the endpoint accepts only `confirmed`/`draft`, and the page shows your types
beside the types actually in force so you can see whether the gate is open.
`GET /v1/_ontology` **creates** the document on first read (as a draft), so an
operator can author the ontology before any run needs it.

Agents reach the effective list through the `{{memory:ontology}}` system-prompt
placeholder.

---

## Off-run: callable directly from the plugin (MCP meta-tool)

Document is a first-class MCP meta-tool — call it through the thin client to
co-author the same documents agents build, without spawning a run:

```
mcp__loomcycle__document  { "op": "create_document", "scope": "user", "title": "Launch plan", "path": "/docs/launch" }
mcp__loomcycle__document  { "op": "create_chunk", "scope": "user", "document_id": "<id>", "parent_id": "<root>", "type": "decision", "title": "Ship date", "body": "## Ship date\n2026-07-01" }
mcp__loomcycle__document  { "op": "query_chunks", "scope": "user", "document_id": "<id>", "type": "decision", "status": "open" }
```

Also on HTTP (`POST /v1/_document`), gRPC (`Document` RPC), and the TS/Python
adapters (`client.document(...)`). **Scope + tenant are resolved server-side from
the authenticated principal, never the wire**; an off-run `scope:"user"` op keys
on the principal's subject, so it interoperates with that user's agent runs.
Tenant-confined (`ScopeTenant`). `.mcp.json` needs no edit — the thin client
auto-advertises the tool.

---

## ⚠️ After you upgrade the runtime, reload the plugin

The plugin ships **no tool schemas of its own** — `loomcycle mcp --upstream`
proxies the runtime's own `tools/list`, and Claude Code caches that **once, at
connection**. It is never refreshed mid-session.

So a session opened against an older deployment keeps the old schema after you
upgrade. Ops the runtime gained are still *dispatchable* (string arguments pass
straight through), but any argument the cached schema doesn't declare gets
serialized as a string and the server rejects it:

```
cannot unmarshal string into Go struct field docInput.seed_ids of type []string
cannot unmarshal string into Go struct field docInput.as_of  of type int64
```

That is a stale cache, not a runtime bug — the runtime's schema is generated from
the tool's own definition and is always current. **Reload the plugin (or restart
the session) after upgrading the deployment** and the full typed surface appears.

---

## Caveats

- **SQL Memory required** (`LOOMCYCLE_SQLMEM_ENABLED=1`) — the single most common
  "Document refused" cause.
- **Tenant scope needs both `memory_scopes` and `sql_scopes`** to include
  `tenant`; `agent`/`user` are ungated.
- **`upsert_chunk` on create still requires `title`** (it delegates to
  `create_chunk`), and the error says `create_chunk: missing required field:
  title` — naming an op you did not call.
- **The entity sidecar is not returned by `get_chunk`.** `class`, the two time
  axes and `confidence` are readable via `graph_recall` or a `query_chunks` SQL
  read against `chunk_memory_meta`.

Full runtime reference: the loomcycle `document` `Context op=help` topic and
`docs/DOCUMENTS.md`; the backing store is `docs/SQL_MEMORY.md`.
