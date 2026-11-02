# Document primitive reference (v1.4.0+; 64 ops, checked against v1.135.0 + `move_documents` from main)

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

**Using documents as a knowledge base** — relations as reviewed statements with
evidence, the sectioned tenant ontology, editions, classification, bulk review
and the knowledge-base bundle — is its own page:
[knowledge-base.md](knowledge-base.md). This page covers the document store
itself: chunks, facts, search, links, copying, the scope snapshot and the 3D map.

---

## Enablement — gate + the SQL Memory prerequisite

Two requirements:

1. **`tools: [Document]`** — the per-agent gate (Document is always registered).
2. **SQL Memory enabled** — the chunk-structure tables live there, so the
   deployment needs **`LOOMCYCLE_SQLMEM_ENABLED=1`** (a feature flag in
   `.env.insecure`, not a secret). Without it every
   `Document` call is refused with "not configured — requires the Store backend
   and SQL Memory". `search`, `related` by `id` and `verbatim_answer` also need
   an embedder (`related` with `related_to` does not).

```yaml
agents:
  author:
    tools: [Document, Memory, Path]
```

> The config key is **`tools:`** (before v1.13.0 `allowed_tools:`, now
> **silently ignored** — `validate` prints `OK` while the agent gets no tools).
> At `agent`/`user` scope an agent using Document does **not** need `Memory`'s
> `sql_scopes` gate; the Document tool issues its own SQL. **Tenant scope is the
> exception — see below.**

---

## Operations

The tool has **63 ops** at v1.135.0 and **64** with `move_documents`. The `op` enum in the tool's input schema is the
authority. Ops marked † are documented in [knowledge-base.md](knowledge-base.md);
everything else is on this page.

| group | ops |
|---|---|
| Documents (9) | `create_document`, `get_document`, `query_documents`, `documents_summary`, `graph_snapshot` (v1.135.0), `delete_document`, `set_path`, `copy_documents` (v1.135.0), `move_documents` (after v1.135.0) |
| Chunks (6) | `create_chunk` (`parent_id`/`position`/`after_id`), `get_chunk`, `update_chunk`, `delete_chunk`, `move_chunk`, `reorder_chunk` |
| Facts (8) | `upsert_chunk`, `supersede_chunk`, `graph_recall`, `list_facts`, `judge_fact`, `verbatim_answer`, `verification_stats`, `remember` |
| Relations (12) | `link_chunks`, `unlink_chunks`, `get_edges`, `backlinks`, `unlinked_mentions`, `get_edge`†, `propose_statement`†, `accept_statement`†, `reject_statement`†, `list_statements`†, `judge_statements`†, `maintain_statement`† |
| Ontology, works, citations (7) | `propose_entity`, `propose_subject` (SUGGEST only; see the ontology section), `describe_ontology`†, `extract_citations`†, `resolve_anchor`†, `classify`†, `accept_classification`† |
| Passes over a scope (2) | `lease`†, `release`† |
| Search (3) | `query_chunks` (by structure), `search` (by what bodies say), `related` (by meaning or by relation) |
| Tags (3) | `add_tags`, `remove_tags`, `list_tags` |
| Types (2) | `define_type`, `list_types` |
| Assets (2) | `set_asset`, `get_asset` (images) |
| History (3) | `history`, `get_version`, `diff` |
| Import / export (4) | `export_md`, `import_md` (its `reimport: true` editions are †), `export_canvas`, `import_canvas` |
| Federation (3) | `set_remote`, `sync`, `diff_remote` |

`scope` is `user` (**the default** — needs a `user_id` on the run), `agent`, or
**`tenant`** (shared by every user and agent in the tenant — since v1.41.0).
**One scope per call**: a chunk id from one scope is "no such chunk" in another,
so pass the same `scope` on every call about the same document. Path defaults to
`agent`, so pass `scope` there too when you look a document up by name.

### Three ids, and which field takes which

`create_document` returns `{document_id, root_chunk_id, title, path}`.

- `document_id` names the whole document. Chunk ops and `export_md` take it as
  `document_id`. The whole-document ops (`get_document`, `delete_document`,
  `set_path`, `set_remote`, `sync`, `diff_remote`) take it as `id` **or**
  `document_id`, or a `path`; passing `id` and `document_id` with different
  values is refused.
- `root_chunk_id` is the chunk holding the title. `list_facts` `about` wants
  this, not the `document_id`.
- A chunk `id` goes in `id`, `parent_id`, `after_id`, `from_id`, `to_id`,
  `seed_ids`.

Ids are 32 hex characters. A shortened one (`b4407b52…`, or a bare hex prefix)
is refused with "is cut short … Nothing was done" — copy the whole id.

### `create_document` validates the path first

Omit `path` and the document lands at `/documents/<title-slug>`. A malformed
`path` (a space, or any character outside letters, digits, `.`, `_`, `-`)
**fails the call and creates nothing** (so do `import_md`/`import_canvas`). A
path already in use is taken over — the old resource loses that name, so two
documents with the same title fight over one default path.

`documents_summary` needs `document_ids` and/or `under_path` (with neither it is
refused); it returns title, root type/status and colour settings for many
documents in one call, bounded at 500 by default with `truncated: true` when it
clips. Use `query_documents` to *list* a scope's documents.

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
- **A chunk with no parent goes under the root.** `create_chunk` without
  `parent_id`, and `move_chunk` with an empty `new_parent_id`, place the chunk
  directly under the document's title. A mistyped `document_id` is refused
  rather than creating an orphan.
- **`query_chunks`** takes structured filters (`document_id`/`type`/`status`/
  `parent_id`/`tag`/`tag_prefix`, plus `under_path:` joining the Path tree)
  **or** a `sql:` escape hatch — a raw read-only `SELECT`, validator-gated (no
  `ATTACH`/`PRAGMA`/writes), which ignores the filters. Tables: **`documents`**,
  **`chunks`**, **`chunk_edges`**, **`chunk_tags`**, **`document_tags`**, and the
  entity sidecar **`chunk_memory_meta`**. Chunk bodies are not in any of them.
  It also takes `as_of` (chunks in force at an instant). Each filter-form row
  carries the chunk's **`updated_at`** (unix ns), so a client holding a copy can
  tell what changed since.
- **Dated content.** Any chunk can carry its own `valid_at`/`invalid_at` (set by
  `create_chunk`/`update_chunk`, kept through `export_md`/`import_md` and
  `sync`) — an edition, a tariff, a policy clause. It is independent of the fact
  tier: a dated chunk is not a fact and `list_facts` does not list it.
- **Change events.** `update_chunk`/`move_chunk`/`link_chunks`/`delete_chunk`
  publish `{op, chunk_id, timestamp, actor}` to `documents/<id>/chunks`, so a
  co-authoring UI sees edits live. Channel listings tag these feeds
  `source: "document"`, and the MCP `list_channels` tool leaves them out.
- **Atomic, orphan-free deletes.** `delete_document`/`delete_chunk` run the whole
  cascade in one SQL Memory transaction — descendants, edges in both directions,
  image assets, the entity sidecar, and the chunk bodies in the Memory plane.
  `link_chunks` validates both endpoints; `delete_chunk` refuses a document's root
  chunk (use `delete_document`).

### Memory SQL cannot reach the Document tables (v1.128.0 — upgrade note)

Memory's `sql_query` / `sql_exec` share a database per scope with the Document
tool. Since v1.128.0 both refuse any statement that names a Document table or
index (`documents`, `chunks`, `chunk_tags`, `chunk_edges`, …) with
**`document_tables_reserved`** — otherwise an agent holding `Memory` could accept
its own proposed relation with an `UPDATE`, or read chunks past the Document
tool's access rules.

- An agent that read chunk tables through Memory SQL must switch to
  `query_chunks` (its `sql` form is unchanged) or the other Document ops.
- **An agent whose own tables carry one of those names is refused too** —
  rename them. A view, trigger or function naming a Document table blocks Memory
  SQL on that scope until it is dropped.
- **On Postgres the boundary is the engine's**: each scope gets a separate
  schema and login role for the Document tables, and `query_chunks`'s `sql` runs
  as that Document role — so it **cannot read the agent's own tables** in the
  same scope. `pg_hba` must admit the new `sqlmem_dr_…` login roles wherever it
  lists scope roles one by one. The first Document op on an older scope waits
  while its rows are copied into the new schema (bounded at 10 minutes).
- Take a runtime snapshot (`POST /v1/_snapshot`) before that upgrade: a
  non-superuser `pg_dump` cannot capture SQL Memory.

---

## Copying documents between scopes — `copy_documents` (v1.135.0)

Every row of a document is keyed by its scope, so `copy_documents` copies a set
of documents from `scope` into `to_scope` **on the server**:

```json
{"op":"copy_documents","scope":"user","to_scope":"tenant","under_path":"/loomcycle",
 "path_map":{"/loomcycle":"/kb/loomcycle"}}
```

- **Selecting the set.** `document_ids`, `under_path`, `under_paths` — combined,
  a document named twice copied once, **at most 500 per call** (split larger
  sets). `to_scope` is required; the same scope as `scope` makes duplicates and
  then `path_map` is required.
- **`path_map`** rewrites Path prefixes on the way (`from → to`, longest prefix
  wins; an unmatched name keeps its path).
- **`dry_run` defaults to `true`**: it checks the whole set and reports what
  would be copied, refused and left behind, writing nothing. Run it first, then
  repeat with `"dry_run": false`.

**What travels:** every chunk with hierarchy, type, status, fields and validity;
bodies with their edit history and import provenance; tags, canvas layout, the
document's own types, image bytes and derived search units (re-indexed in the
target); the Path names (through `path_map`); and **the relations between
members of the set, with their evidence**.

**What stays behind:**
- A relation with one end — or one evidence quote — outside the set stays in the
  source and is listed under **`dangling`** (`outside`: `from`, `to` or
  `evidence`). Copy related documents together to keep their relations.
- Refused by name, the rest of the set going ahead (`refused: [{document_id,
  code}]`): the tenant ontology (`is_ontology`), subject documents
  (`is_subject`), documents holding facts (`holds_facts` — facts and subjects
  have an identity a cross-scope copy would split), `path_collision` (a target
  name already taken, or two members would take one name), `key_collision` (the
  target already holds the document's work or identity key), `forbidden`,
  `not_found`, `write_failed`.

**The copies** get **new ids**; each root records `copied_from: {scope,
document_id}` in its fields, and each copy is announced on the target scope's
`documents/ingested` channel with reason **`copied`**. The source is untouched.
The reply is `{documents: [{id, new_id?, paths}], counts, refused, dangling,
dangling_count, …}` (lists capped at 200; the counts stay exact).

**Access.** `to_scope` passes the same gate as any `scope` (into `tenant` an
agent needs both tenant grants); under access control each source needs read and
each target name write. **Why not `export_md` + `import_md`?** That mints new
ids, keeps only current bodies, drops every relation between the documents and
pushes every body through the caller; the server copy keeps all of it.

## Moving documents between scopes — `move_documents` (after v1.135.0)

`move_documents` moves a set of documents from `scope` into `to_scope` and
**keeps every id**: the documents, their chunks and the relations between them.
A reference to any of them still resolves, now in `to_scope`, and the source no
longer holds them. It shipped on loomcycle main after the v1.135.0 tag, so it
needs the next release. On v1.135.0 itself the op is unknown: copy, check, then
`delete_document` each source (and accept new ids).

- **Same selection as a copy:** `document_ids`, `under_path`, `under_paths`, at
  most 500 per call, plus `path_map`. `to_scope` is required and **must differ**
  from `scope`. To rename inside one scope, use `path` `op=mv`.
- **Same payload as a copy**, plus the relations' statuses, rulings and
  evidence.
- **A relation cannot span two scopes.** A relation between a moved document
  and one outside the set **refuses the move** (a dry run reports
  `blocked_by: "dangling_relations"` with the list under `dangling`). Either add
  the other documents to the set, or pass `dangling: "drop"` to delete those
  relations with the source (reported under `dropped`).
- **Two-step, like a bulk ruling.** It is a dry run unless `dry_run: false`, and
  a real move also needs **`expect_count`**: the dry run's `counts.documents`.
  If the set changed in between, it is refused and nothing moves.
- **Crash-safe order:** write the target and verify it against the source, then
  remove the source, then name the target. Until it is named, the target's
  `query_documents` and `graph_snapshot` leave it out. **If a move is
  interrupted, run the same call again**: it resumes. `to_finish` (dry run),
  `resumed`, `moved` and `unfinished` (each with a code: `verify_failed`,
  `source_not_removed` or `marker_not_cleared`) report where each document
  stands. An unfinished document keeps its source.
- **Refusals:** the copy codes (`not_found`, `is_ontology`, `is_subject`,
  `holds_facts`, `forbidden`, `path_collision`, `key_collision`,
  `write_failed`) plus **`id_collision`**: the target already holds a document
  with that id. Under access control a move needs **write** on each source as
  well as read, and write on each target name. A scope held by a lease (a links
  agent pass) refuses until the lease ends.
- Each moved document is announced on the target's `documents/ingested` with
  reason **`moved`**, and each move is audited.

**Copy or move?** Move when the documents should *live* elsewhere and anything
holds their ids (notes, memory, statements from other documents in the target,
links). Copy when the source must stay, or to make a duplicate in the same
scope.

---

## Scope snapshot — `graph_snapshot` (v1.135.0)

`graph_snapshot` returns a whole scope's **structure** — documents, every chunk
tree, the relations, Path names and fact flags — as one **columnar, paged**
answer, so a viewer can draw or mirror a scope without a call per document.
**Titles and metadata only, never bodies** (use `get_chunk`/`export_md`/`search`
for text).

```json
{"op":"graph_snapshot","scope":"tenant","under_path":"/kb","page_documents":200}
```

- **Selection** (AND-combined): `under_path`, `document_ids`, `chunk_ids` (the
  documents holding them; ≤5000 ids each), `types`/`type` (the root's type, with
  subtypes), `statuses`/`status`, `tag`/`tag_prefix` (document tags). `as_of`
  filters relations only.
- **`include`** picks sections: `documents`, `chunks`, `edges`, `dirents`,
  `facts`, `projection` — default all but `projection`. `chunks` needs
  `documents`; `edges`, `facts`, `projection` need `chunks`.
- **Paging** is by whole documents in id order: `page_documents` (default 200,
  at most 1000 — lowered, never refused); pass `page.next_cursor` back as
  **`after`** until it is absent (the same name `get_edges` pages with). If the
  SQL Memory row cap cuts a page, it keeps the documents it read whole and says
  `page.clamped_to`; a single document larger than the cap is refused.
- **Relations.** `edge_budget` (default 50000, at most 200000) caps a page's
  relations and sets `truncated`. Only live relations by default;
  **`include_proposed: true`** adds the ones awaiting review.
- **Shape.** Each section is parallel arrays (position `i` across arrays is one
  item); `*_idx` columns point into another section of the same answer, `*_code`
  columns into `codes` (`types`, `statuses`, `kinds`, `fact_classes`,
  `methods`; `-1` = none). Chunks come depth-first per document, so `parent_idx`
  always points earlier. An edge end on another page is a negative index naming
  an `external` entry. `dirents` comes on the first page only.
- **Access.** A document the caller may not read is dropped before the page is
  cut — with its chunks, relations into it and its Path names — so page sizes
  and cursors look exactly as if it did not exist.

**The Web UI's universe view.** `graph_snapshot` feeds the 3D star-map navigator
in the Web UI's Path/documents explorer: a **`tree | stars`** switch in the
toolbar swaps the Path tree for a sky where documents are constellations of
chunk stars and directories are nested formations. The **structure** view lays
the sky out from ids and names; the **meaning** view (enabled once the scope has
a projection, below) moves each star to where its embedding puts it. From the
map a reader can select a star and **write a link** to another — proposed for
review by default, or asserted — and accept or reject proposed links, which
draw dashed.

---

## The 3D projection — chunks placed by meaning (v1.135.0)

Each chunk's stored embedding can be placed on its scope's top three principal
components, so chunks that mean similar things sit near each other. Vectors never
leave the server — only three coordinates per chunk do. It is **off by default**.

```yaml
memory:
  projection:
    enabled: true        # default false: nothing runs, nothing is read
    interval: 1h         # background sweeper cadence; empty or 0 = no sweeper
    refit_after: 168h    # a basis this old is refitted …
    refit_min_new: 500   # … once this many chunks were placed since its fit
    sample_max: 20000    # vectors a PCA fit samples (also capped at 64 MB)
    method: pca          # pca (default) | umap
    umap_sample_max: 10000  # chunks a UMAP fit lays out; the rest are placed among them
```

- **PCA or UMAP.** PCA (the default) is an exact basis, so a new chunk is placed
  without a refit. UMAP keeps neighbourhoods: on a measured corpus, 83% of a
  chunk's map neighbours came from its own document, against 14% with PCA. It is
  fitted on a sample (seconds of CPU on a large scope), places the rest by
  nearest neighbours, and aligns each refit to the previous map. Changing
  `method` refits each scope on its next pass; the operator route's `method=`
  fits one scope the other way to compare. Concurrent refits of one scope
  resolve to one basis (the loser reports `raced: true`).

- **`LOOMCYCLE_DOCUMENT_PROJECTION_INTERVAL`** (a Go duration) overrides
  `interval`, and a positive value also turns the projection on.
- **Needs** SQL Memory, a vector index (Postgres with pgvector) and a configured
  embedder. Without them the snapshot's `projection` block is empty.
- **The basis** is per scope and per embedder model. Later passes place only new
  or re-embedded chunks on the same basis, so the map does not move under a
  viewer. A **refit** happens when there is no basis, when forced, or when the
  basis is older than `refit_after` *and* `refit_min_new` chunks were placed
  since; its axes are turned to match the previous orientation. A pass places at
  most 5000 chunks and makes no model call.
- **Served** as `graph_snapshot` `include: ["projection"]` → `{model,
  basis_version, xyz, missing}` (one 4-decimal triple per chunk, in `chunks`
  order; `basis_version: 0` = no map yet), and as `search` `with_projection:
  true` → `query_xyz`, the query's own point.
- **Operator route** to build or refresh one scope now:
  `POST /v1/_document/project?scope=user&scope_id=<subject>` — `dry_run`
  (default `true`), `refit=true` forces a new basis, `limit` (default 5000);
  call again while `more` is true. `unsupported: true` = no vector index; 409
  while `memory.projection` is off. Operator-admin.

### Live updates — the reader document feed (v1.135.0)

`GET /v1/_document/feed?scope=user|tenant` streams (SSE) a frame whenever a
document the caller can list changes in that scope: `document.chunk.updated`,
`document.chunk.deleted`, `document.edges.changed`. Retitles, moves, reorders
and `set_path` count as updates. Frames carry ids, never values, and there is no
cursor: a reconnect is a resync. A tenant member may open it, unlike the
operator's `GET /v1/_document/changes`. `scope: agent` is refused.
- Needs `LOOMCYCLE_MEMORY_CHANGES_ENABLED`; without it the first frame says
  `enabled: false` and the stream idles.
- At most `LOOMCYCLE_DOCUMENT_FEED_MAX_STREAMS` (default 4) per principal.
  Credentials are re-checked every 30 s.
- HTTP only (TS `client.documentFeed`). There is no MCP twin: Claude Code
  cannot hold a stream.

The universe view uses it to redraw exactly the changed documents. Its **saved
views** (mode, filters, camera, selection) are stored as `type=view` documents,
so they are listed, named and permissioned like any document.

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
document {
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
a re-observation updates the wording without disturbing the fact's history.
(Broken on exactly v1.42.0 — a re-upsert un-retired superseded facts and
downgraded `evidential` — so never rely on the entity tier on that tag.)

**`class`** is `derived` (default) or **`evidential`**. Evidential material is
what everything else was distilled from, so it is **exempt from retention pruning
at any age**; derived material can be re-derived. The class is caller-supplied, so
treat it as a claim an agent makes rather than something the runtime verified.

**`source_chunk_id`** names the passage (a chunk of this scope) the fact was
taken from. The runtime links the fact to it with a `derived_from` relation,
using `source_quote` as evidence — the quote must occur in that chunk
(`char_start`/`char_end` pick the occurrence, or select the quote when
`source_quote` is omitted), and the caller must be allowed to read and link that
document. A fact has one source; passing another replaces it. The reply adds
`derived_from: {statement_id, chunk_id, char_start, char_end}`, `judge_fact`
then checks the fact against the passage as it reads now, and `Memory op=recall`
returns `source_chunk_id`/`source_document_id`. **Deleting the passage keeps the
quote on the fact** (copied onto `source_quote` if it had none) and marks it
`source_gone`, so the claim stays checkable. `about_ids` (+ `relation`) link the
fact to its subjects — see [knowledge-base.md](knowledge-base.md).

### `supersede_chunk` — correct without deleting

```
document {
  "op": "supersede_chunk", "scope": "user",
  "id": "<the new fact>", "supersedes_id": "<the fact it replaces>"
}
→ { "id": "…", "supersedes": "…", "retired_at": 1785424758000000000 }
```

Write the replacement first — `upsert_chunk` under a **new** `natural_key`;
reusing the old key overwrites the fact in place instead of correcting it.
A chunk can be retired only once: a second, different replacement is refused and
the refusal names the newer fact to supersede instead. Repeating the same call
returns `already: true`.

Stamps both end-timestamps on the retired chunk and links the replacement to it
with a `supersedes` edge. **The retired chunk stays readable**, so a question
about an earlier instant still has an answer. (`id` and `supersedes_id` are
named fields because transposing a `from_id`/`to_id` pair would retire the *new*
fact.)

**A retired fact cannot be revived through the upsert**: `retired` keys on
system time (`expired_at`), which is append-only and never caller-settable, so
moving `invalid_at` changes only world time. To retract a correction, **record
another one** — write a new fact and supersede the superseder (Berlin → Hamburg →
Berlin-again keeps the whole chain).

### `graph_recall` — walk the relations, time-aware

```
document {
  "op": "graph_recall", "scope": "user",
  "query": "on-call rotation",          // or "seed_ids": ["<chunk>", …]
  "hops": 2, "as_of": 1785424758000000000, "include_retired": false
}
→ { "chunks": [{ "id", "title", "type", "hop", "via_kind", "via_id", "via_quote", "valid_at", "retired", "body" }, …],
    "seeds": 5, "hops": 2, "truncated": false, "seeded_by": "semantic" }
```

Expands from seeds (found by `query`, or named outright via `seed_ids`, at most
500) up to `hops` — 0 to 6, default 1, each hop's frontier capped at 500. **A hop
is one edge**, so fact → subject → fact costs two: a two-step question needs
`hops: 2`, a three-step one `hops: 4`. With an embedder the `query` seeds by
meaning (`seeds`, default 5); without one it matches fact titles. `limit` is 50
by default, 200 at most. `budget_chars` caps the answer on content instead of
rows and backfills what the walk did not reach (`hop: -1`); bound a long walk
with it rather than with fewer hops.

**Text.** A fact comes back as its title (the title is the claim); a chunk that
is not a fact (a clause, a section) carries the first 600 characters of its
body. `body_chars: 0` = titles only (a cheap structural walk), up to 4000 = that
much on every chunk. `get_chunk` for a whole body.

**Steering the walk** (v1.128.0):

| arg | effect |
|---|---|
| `kind` / `kinds` | follow only these relation kinds (with their declared sub-kinds) — the best way to keep a walk on topic |
| `walk` | `declared` (default where the tenant declares walk kinds) follows those — citations, definitions, what implements what, never `mentions`/`about`; `all` follows everything. `kinds` overrides it |
| `direction` | `out`, `in` or `both` (default) |
| `include_hierarchy` | also step the document tree: `up` to the parent (`part_of`), `down` to children (`has_part`), `both`; default `none` |
| `include_proposed` | also follow relations awaiting review; such rows carry `via_status: proposed` |
| `decay` | with `budget_chars` only: hop *n* may spend at most `decay`^n of the budget, so far hops cannot crowd out near ones. 0 < decay ≤ 1; default 0.7 for a declared walk, else 1 |

A row reached over a relation carries `via_kind`, `via_id` and `via_quote` (the
relation's first evidence quote — cite it). `as_of` (unix nanos) answers what
was true at that instant — for facts, for chunks with their own dates, and for
the relations walked — so a fact corrected since still comes back. Retired
chunks are excluded unless `include_retired: true`, and facts a judge refused
unless `include_refuted: true`.

> `seed_ids`/`kinds` are arrays, `hops`/`as_of` integers, `include_retired` a
> boolean. If your MCP client sends them as strings you will get
> `cannot unmarshal string into Go struct field` — see the upgrade note below.

### `list_facts` — browse what is known about a subject

```
document { "op": "list_facts", "scope": "user", "about": "<the subject's root_chunk_id>", "claims_only": true }
→ { "facts": [{ "id", "document_id", "title", "type", "revision", "entity": { … } }], "count": 1, "truncated": false }
```

Newest first, metadata only. Since v1.77.0 a subject is its own document under
`/facts/<subject>` and its facts are that document's children; `about` returns
the facts filed under it **and** the facts elsewhere that point at it.
`claims_only: true` drops the subject name nodes and keeps only the claims —
turn it on for anything a person will read. Passages that only *mention* the
subject (a `[[name]]` link) come back separately as `mentioned_in`.
`across_scopes: true` (with `about`)
also finds the same subject in your other readable scopes. Filters: `type`
(includes subtypes), `class`, `document_id`, `source_run_id`, `as_of`,
`include_retired`, `include_refuted`; `limit` 50 by default, 200 at most.

### `remember` — a statement a person asked you to keep

```
document { "op": "remember", "scope": "user", "text": "Ada takes her coffee black, no sugar." }
→ { "id": "<chunk>", "natural_key": "memory/operator/ada-takes-her-coffee-black-no-sugar", "created": true }
```

Stores one self-contained sentence (at most 1000 characters) as a fact that
cites itself: the text is both the claim and its source span, filed
`evidential`. Optional `type` + `subject` (both or neither). The key is derived
from the start of the text, so the same sentence twice updates one fact — and
two sentences sharing their first 60 or so characters overwrite each other.
**Additive only; there is no "forget".**

---

## Types and the tenant ontology — the basic flow

**`define_type`** (`name`, optional `fields`, optional `document_id` for a
per-document type) writes down what a chunk type means so agents and people use
it the same way; `list_types` reads them back. It is a shared record, **not a
validator** — a chunk's `type` need not be defined first and its `fields` are
never checked against it. It is not the ontology.

**The tenant ontology** — the entity types `upsert_chunk` accepts with
`subject`, and since v1.128.0 also document classes, relation kinds, concept
schemes and instances, arranged in `@section`s — lives in a document at
**`/memory/ontology`** (tenant scope). Its sectioned form, `describe_ontology`,
grammars and the Web UI's ontology page are covered in
[knowledge-base.md](knowledge-base.md). Three things hold everywhere:

- **It is INERT until an operator confirms it.** The root chunk's `status` must
  be exactly `confirmed`; anything else (a typo included) leaves the deployment
  on the base seed — person / object / location / event / organization, plus
  `preference` and `fact` — with no error. Confirm through the Web UI's ontology
  page or `POST /v1/_ontology {"status":"confirmed"}`, not by hand-editing.
  `GET /v1/_ontology` creates the document as a draft on first read. Agents see
  the effective entity types through the `{{memory:ontology}}` placeholder.
- **A child chunk is a subclass** (v1.52.0) and inherits its parent's fields.
  `list_facts`, `query_chunks` and `search` filtered on a type also match its
  subtypes and report `type_expanded_to`. To subclass a standard type, first
  declare your own top-level copy (which overrides it wholesale), then nest
  under it. `preference` and `fact` always stay top-level.
- **An agent may SUGGEST, never decide** (v1.53.0). On the ontology document a
  run may only add a chunk with `status: proposed`; every other write is
  refused. Use the ops built for it — both need **no** tenant grant, because a
  suggestion changes nothing until an operator accepts it:

```json
{"op":"propose_entity","name":"outage","parent":"event",
 "body":"Seen 14 times on facts that are all service outages.\nExamples: \"the Tuesday checkout outage\".\n\n- `minutes_down`\n- `cause`"}
{"op":"propose_subject","subject":"Dave Kim","natural_key":"person:dave-kim",
 "body":"Named in 6 conversations as the shop's floor manager."}
```

`propose_entity` takes the parent **by name** and refuses a name already in
force, proposed or rejected; put your **evidence** (counts, example titles) in
the body. A rejection is a kept tombstone — do not refile it. Since v1.128.0
`section` (`classes` default, `relations`, `schemes`, `instances`) proposes into
the other sections. `propose_subject` suggests a shared tenant *subject* learned
in one scope (`natural_key` `<type>:<slug>` is used verbatim on adoption;
optional single-segment `path` under `/facts/`) → `{proposed, chunk_id,
natural_key, note}`, or `already: "<status>"` when filed before. Merging or
binding subjects is the MCP `ontology` tool, also in knowledge-base.md.

---

## Verified writes — quote a fact instead of generating one (v1.54.0)

A fact can carry **the span of source text it was drawn from**, and a judge can be
asked whether that span actually carries the claim. A fact that fails stops being
returned by the fact surfaces — it is never deleted.

**Pass the span when you write a fact.** `upsert_chunk` takes `source_quote`: the
sentence you drew the claim from, copied verbatim (plus `source_chunk_id` when it
came from a document passage). A fact with no span cannot be verified later.

```json
{"op":"upsert_chunk","scope":"user","natural_key":"fact:gh-username",
 "title":"The user's github username is denn.","body":"The user's github username is denn.",
 "type":"person","subject":"the user","source_quote":"my github username is denn"}
```

**Some facts are hidden from you, on purpose.** `list_facts` and `graph_recall` omit
facts a judge refused; pass `include_refuted: true` to see them with the judge's
reason. A fact with **no** verdict is not hidden — unjudged and refuted are
different states.

**Do not judge your own facts.** `judge_fact` (`id` or `natural_key`, `verdict`,
`reason` — all required) records `supported`, `unclear`, `mistyped` or
`unsupported`; only `unsupported` withholds, and the server owns the confidence
each maps to. Since v1.128.0 it also takes a relation's statement id. It exists
for a separate verification agent; an agent marking its own writes `supported` is
self-certification. Leave your own writes unjudged — *unverified* is honest.

**Prefer quoting over generating for lookup questions:**

```json
{"op":"verbatim_answer","scope":"user","query":"what is my github username"}
→ {"answered":true,"answer":"The user's github username is denn.",
   "source":"my github username is denn","chunk_id":"…","confidence":0.9,"score":0.94,
   "judged_at":1785424758000000000}
```

It refuses far more often than it answers, by design (`answered:false` +
`reason`: unverified, below `min_score` 0.6, or a tie). **Treat a refusal as
"answer normally", never as "there is nothing".** `verification_stats` reports
how much of a scope is verified (claims only, never subject name nodes).

---

## Finding things — search, neighbours, links, tags

**`search`** is the way in when you do not know which document holds the answer.
It matches free text against chunk **bodies** across every document in the scope
— by meaning, and by the words themselves where the server has a word index
(Postgres with pgvector). It runs the same search as `Memory op=search` over
`doc.chunk:`, so the two rank identically.

```json
{"op":"search","scope":"user","query":"how do we roll back a failed database migration","limit":5}
→ {"chunks":[{"chunk_id":"…","score":0.82,"rank_score":0.032,"title":"Rollback plan","document_id":"…"}]}
```

`rank_score` is what ordered the result (meaning and word matches combined);
`score` is the raw strength of whichever match found the chunk, so a chunk found
by its words can have a low `score` and still rank first. Compare within one
result, not against a fixed number. If every `rank_score` equals its `score`
there is no word index — an exact string not found may still be there (look with
`query_chunks` `sql`). No bodies are returned; `get_chunk` a hit. `limit` 10 by
default, 50 at most. With operator reranking a reply carries `reranked` (and
`rerank_reason` when false); a hit may carry `matched_unit: {kind, text}` when a
generated description of its document matched rather than its own words.

**Filtered search — aim it before it ranks.** Each retrieval leg keeps only a few
dozen candidates, so in a scope holding several corpora the pool can fill from
the wrong one. `search` and `related` take filters applied **inside every leg,
before its limit**: `under_path(s)`, `exclude_under_path(s)`, `document_id(s)`,
`exclude_document_ids`, `type(s)` (with subtypes), `status(es)`, `tag`,
`tag_prefix`, `as_of`, and since v1.128.0 **`concept` / `concept_prefix`** — only
chunks about a concept of the tenant's concept schemes (by chunk id, name or tag
such as `topics/risk-management`; in the tenant scope through a live `subject`
relation, elsewhere through the concept's tag). Kinds combine with AND, values
with OR. A filtered reply carries `filter: {applied, matched_documents,
matched_chunks, inverted, …}`; `matched_chunks: 0` means the filter matched
nothing (check the path/type), not that nothing was relevant. A filter too wide
to send is refused `filter_too_wide`, never silently post-filtered.

**`expand`** (v1.128.0) — `{kinds?, hops?, budget_chars?}` — adds, after ranking,
the chunks the top five hits are related to (one hop; `hops` may only be 1 — use
`graph_recall` to go further), within `budget_chars` (default 2000, at most 8000)
of titles and quotes. Each added row has no score and carries `expanded_via:
{kind, from_chunk_id, quote?}`. Without `kinds` it follows the tenant's declared
walk kinds, or everything but `about`/`mentions`. The filters apply to the added
chunks too. `expand: {}` takes the defaults.

**`with_projection: true`** (v1.135.0) adds `query_xyz`, the query's point on the
scope's 3D map (absent when the scope has none — see the projection section).

**The word leg's language — `memory.fulltext`** (v1.128.0, Postgres only). The
full-text leg used to be fixed to Postgres's `english` configuration, so on
another language an inflected term never matched its other forms:

```yaml
memory:
  fulltext:
    config: english   # any Postgres text search configuration, e.g. russian, simple
    unaccent: false   # strip diacritics on both sides (the unaccent extension)
```

One setting per server. A change **rebuilds the column at the next boot** (or
`loomcycle migrate up --config`), locking `memory_embeddings` while it runs; the
applying role must own that table, an unknown configuration fails the boot, and
across replicas it is last-writer-wins (change every replica's config first).

**Neighbours of a chunk you hold:**

| op | finds | reply |
|---|---|---|
| `backlinks` (`id`) | relations arriving **at** it — `link_chunks` and `[[name]]` links; proposals only with `include_proposed` | `{backlinks: [{from_id, kind, auto, from_title, from_document_id, …}]}` |
| `related` (`id`) | chunks whose bodies say similar things, linked or not (needs an embedder; same filters as `search`) | `{related: [{chunk_id, score, title, document_id}]}` |
| `related` (`related_to`) | its neighbours **by relation** (what it cites, what cites it, what defines it), `kind`/`kinds` to narrow; **no embedder needed**; with `id` too, both come back | `{linked: [{…, via_kind, via_quote}]}` |
| `unlinked_mentions` (`id`) | chunks whose body contains its **title** but do not link to it (literal match — useful only for a distinctive title) | `{unlinked_mentions: [{chunk_id, title, document_id}], truncated}` |

**Links are statements** (v1.128.0). `link_chunks` (`from_id`, `to_id`, `kind`)
**asserts** a relation that is live at once — optionally with verbatim
`evidence`, `valid_at`/`invalid_at`, `confidence` and `attributes`. Refused: a
quote that does not occur in its source, the runtime's own kinds (`supersedes`,
`references`, `mentions`, `derived_from`, `supported_by`), and — where the
confirmed ontology declares relation kinds — a link that does not fit them. When a relation was found in text and someone should check it, use
`propose_statement` instead — review, evidence and statement upkeep are in
[knowledge-base.md](knowledge-base.md). `unlink_chunks` removes a relation with
its evidence.

**`get_edges`** (`document_id`, not a chunk id) lists the relations in and out
of a whole document with both ends' titles, status, method and up to three
evidence rows. It **pages at 500** (`limit` up to 5000): `truncated: true` comes
with a `next_cursor` — pass it back as **`after`**. Filters: `direction`,
`kind(s)`, `as_of`, `include_proposed` (default true here), `include_refuted`,
`include_retired`. An unknown document id returns `{edges: []}`, not an error.

**Tags.** `add_tags` / `remove_tags` change tags incrementally and reply with the
full set afterwards; passing `tags` to `create_chunk` / `update_chunk` /
`upsert_chunk` / `create_document` **replaces** the whole set. They target a
chunk (`id`) or a document (`document_id`), and **a document's tags are separate
from its root chunk's**: `query_chunks` filters chunk tags (`tag`, `tag_prefix`),
`query_documents` filters document tags. Nest with a slash (`area/billing`).
`list_tags` with neither id returns every tag in the scope with counts — read it
before inventing a near-duplicate spelling.

---

## Body history — `history`, `get_version`, `diff`

Every write of a chunk's **body** is kept. `history` (`id`) lists the revisions
at which the body changed; `get_version` (`id`, `revision`) returns one exact
past body; `diff` (`id`, `from_revision`, `to_revision`) returns a unified diff.

```json
{"op":"diff","scope":"user","id":"<chunk>","from_revision":1,"to_revision":4}
```

A title-, status- or tag-only edit raises the chunk's `revision` without adding
a history entry, so **the `revision` from `get_chunk` may not be in the list** —
use the numbers `history` returns. This is the *chunk's* history; the `history`
*tool* is something else (past chats).

---

## Canvas — `export_canvas`, `import_canvas`

`export_canvas` (`document_id`, `id` or `path`) renders a document as a JSON
Canvas v1.0 object → `{canvas: {nodes, edges}, document_id}` — one text node per
chunk, one edge per link; the root and the hierarchy are not drawn.
`import_canvas` (`canvas` as a JSON object, not a string; optional `title`,
`path`) always builds a **new** document, every node a chunk under the root.
`export_md` → `import_md` is the round trip that keeps hierarchy.

---

## Federation — `set_remote`, `sync`, `diff_remote`

A document can be bound to a document on a **peer loomcycle** and reconciled
with it. The peer must be a *document source* the operator declared (or one
authored with the `documentsourcedef` tool) — you name the source; you cannot
point at a URL.

```json
{"op":"set_remote","scope":"user","path":"/docs/runbook","source":"hq-docs","remote_ref":"/docs/runbook"}
{"op":"diff_remote","scope":"user","path":"/docs/runbook"}
{"op":"sync","scope":"user","path":"/docs/runbook","direction":"pull"}
```

- **`set_remote`** only records the binding (`{document_id, source, remote_ref,
  bound: true}`); it contacts nobody. `remote_ref` is the document's **path on
  the peer**, not an id.
- **`diff_remote`** is the read-only dry run: `only_local`, `only_remote`,
  `diverged`, `retagged`, `reparented` (lists of `{natural_key, title}`) plus
  counts. Run it before `sync` to choose a direction.
- **`sync`** copies one way: `pull` (default) writes the peer's chunks into your
  document, `push` writes yours up to the peer. It replies with counts
  (`created`, `updated`, `unchanged`, `reparented`, `edges_added`,
  `excluded_unkeyed`, `excluded_withheld`, and the statement counts below).

**Only keyed chunks travel** — chunks carrying a `natural_key` (written with
`upsert_chunk`), matched across the two servers by that key. Chunks made with
`create_chunk` or `import_md` are skipped and counted in `excluded_unkeyed`.
Nothing is deleted on either side, an overwritten body stays in that chunk's
`history`, and facts a judge refused are not copied. A sync is not
all-or-nothing; running it again continues. A source authored at runtime reaches
only a host the operator allow-listed — the refusal names the env var, and
retrying does not help.

**Sync carries statements** (v1.128.0) between keyed chunks — `confidence`,
validity, `attributes` and evidence — **asserted ones only**: a proposal is one
side's review state, and a pull never undoes a local rejection
(`edges_skipped_rejected`). A pulled relation is asserted here with method
`sync`, the peer's method kept in `attributes.origin_method`. Every evidence
quote is re-checked against this side's text; one that cannot be is dropped
(`evidence_dropped`). A relation written or ruled on here keeps its own envelope
and only gains missing evidence (`edges_envelope_kept`).

---

## Off-run: callable directly from the plugin (MCP meta-tool)

Document is a first-class MCP meta-tool — call it through the thin client to
co-author the same documents agents build, without spawning a run:

```
document  { "op": "create_document", "scope": "user", "title": "Launch plan", "path": "/docs/launch" }
document  { "op": "create_chunk", "scope": "user", "document_id": "<id>", "parent_id": "<root>", "type": "decision", "title": "Ship date", "body": "## Ship date\n2026-07-01" }
document  { "op": "query_chunks", "scope": "user", "document_id": "<id>", "type": "decision", "status": "open" }
```

Called this way there is no run, so no agent's `memory_scopes` / `sql_scopes`
apply: the session acts as the token's principal, held to its access-control
rules. `scope: "agent"` is the session's own synthetic agent rather than any
agent you have in mind — use `user` or `tenant`.

Also on HTTP (`POST /v1/_document`), gRPC (`Document` RPC), and the TS/Python
adapters (`client.document(...)`). **Scope + tenant are resolved server-side from
the authenticated principal, never the wire**; an off-run `scope:"user"` op keys
on the principal's subject, so it interoperates with that user's agent runs.
Tenant-confined; no scope beyond a non-isolated token. `.mcp.json` needs no edit — the thin client
auto-advertises the tool. The knowledge-base side has two more MCP tools —
`ontology` (merge or bind subjects) and `review` (bulk statement review) — see
[knowledge-base.md](knowledge-base.md).

---

## ⚠️ After you upgrade the runtime, reload the plugin

The plugin ships **no tool schemas of its own** — `loomcycle mcp --upstream`
proxies the runtime's `tools/list`, and Claude Code caches it **once, at
connection**. After a deployment upgrade an open session keeps the old schema:
new ops still dispatch, but any argument the cached schema doesn't declare is
sent as a string and refused (`cannot unmarshal string into Go struct field
docInput.seed_ids of type []string`). That is a stale cache, not a runtime bug —
**reload the plugin (or restart the session)** and the new fields
(`to_scope`, `path_map`, `include`, `with_projection`, …) appear.

---

## Caveats

- **SQL Memory required** (`LOOMCYCLE_SQLMEM_ENABLED=1`) — the single most common
  "Document refused" cause.
- **Tenant scope needs both `memory_scopes` and `sql_scopes`** to include
  `tenant`; `agent`/`user` are ungated.
- **`upsert_chunk` on create still requires `title`** (it delegates to
  `create_chunk`), and the error says `create_chunk: missing required field:
  title` — naming an op you did not call.
- **`get_chunk` returns the fact metadata as an `entity` block** (`retired`, the
  time axes, `class`, `natural_key`, `confidence`, `source_quote`, `subject`, and
  the verdict fields once judged). A plain document chunk has no `entity`.
  `list_facts` returns the same block; times are unix nanoseconds.
- **The default scope is `user`**, and Path's is `agent`. Pass `scope` on both.
- **Unix nanoseconds here, RFC3339 on `memory`.** `valid_at`, `invalid_at`,
  `observed_at` and `as_of` are integers on this tool.
- **`set_path` adds a name; it is not a move.** To rename, use `path` `op=mv`.
- **`move_documents` keeps ids; `copy_documents` mints new ones.** Neither
  works within one scope as a rename: that is `path` `op=mv`.
- **Memory SQL refuses Document tables** since v1.128.0
  (`document_tables_reserved`) — use `query_chunks`.

Full runtime reference: the loomcycle `document` `Context op=help` topic and
`docs/DOCUMENTS.md`; the backing store is `docs/SQL_MEMORY.md`.
