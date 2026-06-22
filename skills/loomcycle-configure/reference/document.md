# Document primitive reference — RFC AK (v1.4.0+)

A `Document` is a **chunked-graph document**: instead of one opaque blob, it's a
tree of **chunks** — each a first-class unit with a UUID, a hierarchy position,
an optional type, structured fields, graph edges, and a Markdown body — that
agents and humans co-author and query.

**Content/structure split** (the mechanism): chunk **bodies + fields** live in
Memory (keyed by the chunk UUID); chunk **structure**
(parent/position/type/status/title/revision + edges + type schemas) lives in
**SQL Memory** across four tables, so agents query `SELECT … FROM chunks WHERE
type=… AND status=…`. A Document is **named in the Path tree** via a `document`
dirent (see [path.md](path.md)).

---

## Enablement — gate + the SQL Memory prerequisite

Two requirements:

1. **`allowed_tools: [Document]`** — the per-agent gate (Document is always
   registered).
2. **SQL Memory enabled** — the chunk-structure tables live there, so the
   deployment needs **`LOOMCYCLE_SQLMEM_ENABLED=1`**. Without it every
   `Document` call is refused with "requires SQL Memory."

```yaml
agents:
  author:
    allowed_tools: [Document, Memory, Path]
```

```bash
# .env.insecure (feature flag, not a secret)
LOOMCYCLE_SQLMEM_ENABLED=1
```

> SQL Memory (RFC AA, loomcycle v1.2.0) is a per-scope SQL database that is a
> facet of the `Memory` tool — Document piggybacks on it for structure storage.
> An agent that uses Document does **not** need `Memory`'s `sql_scopes` gate; the
> Document tool issues its own trusted SQL. It only needs the env flag on.

---

## Operations (13)

| group | ops |
|---|---|
| Document lifecycle | `create_document` (optional `path:` → a Path dirent), `get_document` (by `id` or `path`), `delete_document` |
| Chunk lifecycle | `create_chunk`, `get_chunk`, `update_chunk`, `delete_chunk`, `move_chunk` |
| Edges | `link_chunks`, `unlink_chunks` |
| Query | `query_chunks` |
| Types | `define_type`, `list_types` |

`scope` is `agent` (default) or `user` (needs a `user_id` on the run). **Tenant
scope is deferred** (SQL Memory has no tenant scope yet) — `scope:tenant` is
refused; documents are still tenant-*isolated* via the SQL Memory scope key.

### Behaviour worth teaching the agent

- **Optimistic concurrency.** `update_chunk` takes the chunk's current
  `revision`; a stale revision returns a conflict instead of a silent lost
  update. Two agents editing different chunks never clobber.
- **`move_chunk`** re-parents with a cycle guard (a chunk can't become its own
  ancestor).
- **`query_chunks`** takes structured filters (`document_id`/`type`/`status`/
  `parent_id`, plus `under_path:` joining the Path tree) **or** a `sql:` escape
  hatch — a raw read-only `SELECT`, validator-gated (no `ATTACH`/`PRAGMA`/writes).
- **Change events.** `update_chunk`/`move_chunk`/`link_chunks`/`delete_chunk`
  publish `{op, chunk_id, timestamp, actor}` to `documents/<id>/chunks`, so a
  co-authoring UI sees edits live.
- **Atomic, orphan-free deletes.** `delete_document`/`delete_chunk` run the whole
  cascade in one SQL Memory transaction; edge cleanup is bidirectional (no
  dangling incoming cross-document edge); `link_chunks` validates both endpoints;
  `delete_chunk` refuses a document's root chunk (use `delete_document`).

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

## Caveats

- **SQL Memory required** (`LOOMCYCLE_SQLMEM_ENABLED=1`) — the single most common
  "Document refused" cause.
- **Tenant scope deferred** — `agent`/`user` only in v1.
- **Markdown round-trip (`export_md`/`import_md`) and a Web UI tree/editor** are
  later RFC AK phases — not in this core.

Full runtime reference: the loomcycle `document` `Context op=help` topic and
`docs/DOCUMENTS.md`; the backing store is `docs/SQL_MEMORY.md`.
