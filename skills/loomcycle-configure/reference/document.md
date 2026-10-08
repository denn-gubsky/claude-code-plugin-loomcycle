# Document primitive reference (v1.4.0+), entity tier (v1.42.0), ontology hierarchy (v1.52.0), 47 ops as of v1.107.0

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
   `Document` call is refused with "not configured — requires the Store backend
   and SQL Memory". `search`, `related` and `verbatim_answer` also need an
   embedder.

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

> SQL Memory (loomcycle v1.2.0) is a per-scope SQL database that is a
> facet of the `Memory` tool — Document piggybacks on it for structure storage. At
> `agent`/`user` scope an agent that uses Document does **not** need `Memory`'s
> `sql_scopes` gate; the Document tool issues its own trusted SQL. **Tenant scope
> is the exception — see below.**

---

## Operations

The tool has **47 ops**. The `op` enum in the tool's input schema is the
authority; this table groups it the way the tool's own description does.

| group | ops |
|---|---|
| Documents (6) | `create_document`, `get_document`, `query_documents`, `documents_summary`, `delete_document`, `set_path` |
| Chunks (6) | `create_chunk` (`parent_id`/`position`/`after_id`), `get_chunk`, `update_chunk`, `delete_chunk`, `move_chunk`, `reorder_chunk` |
| Facts (8) | `upsert_chunk`, `supersede_chunk`, `graph_recall`, `list_facts`, `judge_fact`, `verbatim_answer`, `verification_stats`, `remember` |
| Ontology (2) | `propose_entity`, `propose_subject` — SUGGEST only; see the ontology section |
| Links (6) | `link_chunks`, `unlink_chunks`, `get_edges`, `backlinks`, `related`, `unlinked_mentions` |
| Tags (3) | `add_tags`, `remove_tags`, `list_tags` |
| History (3) | `history`, `get_version`, `diff` |
| Types (2) | `define_type`, `list_types` |
| Assets (2) | `set_asset`, `get_asset` (images) |
| Search (2) | `query_chunks` (by structure), `search` (by what bodies say) |
| Import / export (4) | `export_md`, `import_md`, `export_canvas`, `import_canvas` |
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
`path` (a space, or any character outside letters, digits, `.`, `_`, `-`) now
**fails the call and creates nothing** — it used to succeed with a
`path_warning` and leave a document outside the tree. `import_md` and
`import_canvas` likewise write nothing on a bad path. A path already in use is
taken over: the old resource keeps existing but loses that name, so two
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
with a `supersedes` edge. **The retired chunk stays readable** — that is the whole
point, so a question about an earlier instant still has an answer. `id` and
`supersedes_id` are separate named fields rather than a reused `from_id`/`to_id`
pair precisely because transposing them would invalidate the *new* fact and leave
the stale one current.

**A retired fact cannot be revived through the upsert**, deliberately. `invalid_at`
is world time and caller-settable; `expired_at` is **system** time, is never
caller-settable, and `retired` keys on the system axis — so pushing `invalid_at` into
the future changes when the fact stopped being true and leaves it retired.

That is the right shape for a bi-temporal store rather than a gap: system time is
append-only, and *"we stopped believing X at T"* is itself a historical fact. To
retract a correction, **record another one** — write a new fact and supersede the
superseder. Berlin → Hamburg → Berlin-again leaves one current answer with the whole
chain and its timestamps intact.

### `graph_recall` — walk the relations, time-aware

```
document {
  "op": "graph_recall", "scope": "user",
  "query": "on-call rotation",          // or "seed_ids": ["<chunk>", …]
  "hops": 2, "as_of": 1785424758000000000, "include_retired": false
}
→ { "chunks": [{ "id", "title", "type", "hop", "via_kind", "via_id", "valid_at", "retired" }, …],
    "seeds": 5, "hops": 2, "truncated": false, "seeded_by": "semantic" }
```

Expands bidirectionally from seeds (found by `query`, or named outright via
`seed_ids`, at most 500) up to `hops` — 0 to 6, default 1, each hop's frontier
capped at 500. **A hop is one edge**, so fact → subject → fact costs two: a
two-step question needs `hops: 2`, a three-step one `hops: 4`. With an embedder
the `query` seeds by meaning (`seeds`, default 5, picks how many); without one it
matches fact titles. `limit` is 50 by default, 200 at most. `budget_chars` caps
the answer on content instead of rows and backfills what the walk did not reach
(those rows carry `hop: -1`); bound a long walk with it rather than with fewer
hops. It returns titles, not bodies — `get_chunk` for those.

`as_of` (unix nanos) answers what was true at that instant, so a fact corrected
since still comes back. Retired chunks are excluded unless `include_retired:
true`, and facts a judge refused unless `include_refuted: true`.

> `seed_ids` is an array, `hops`/`as_of` integers, `include_retired` a boolean.
> If your MCP client sends them as strings you will get
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
turn it on for anything a person will read. `across_scopes: true` (with `about`)
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

### A child chunk is a subclass (v1.52.0)

Nesting in that document is a **type hierarchy**: one chunk is one entity, its
title names it, backticked bullets in its body declare its fields, and a **child
chunk is a subclass of its parent**. A subclass inherits its parent's fields and
adds its own, up to four levels deep.

This matters beyond tidiness, because retrieval expands it: `list_facts` and
`query_chunks` filtered on a type also match its subtypes, so `type=event` returns
`incident` and `outage` rows too. Storage keeps the concrete type only, so
re-parenting a type takes effect immediately and retroactively. The response
reports `type_expanded_to` when a filter widened.

Two rules worth knowing before you author one:

- To subclass a **standard** type, first declare it yourself as a top-level entity
  (which overrides the standard one **wholesale** — a field a later release adds to
  it will not reach your copy), then nest beneath your copy. The Settings panel has
  an **adopt** button that makes that copy for you, fields and all.
- `preference` and `fact` are the memory tier's own types and always stay top-level.
  You may nest types *under* them; nesting them under one of yours is ignored.

### An agent may SUGGEST a type, never decide one (v1.53.0)

**Your agent cannot edit the ontology document.** On that document alone, a tool
call from a run may only add a chunk whose `status` is `proposed`; updating,
deleting, moving, superseding, importing over it, re-homing it, or creating a live
entity are all refused. Resolving a suggestion is an operator action on a surface a
run cannot reach.

Use `propose_entity` — it resolves the ontology itself, takes the parent **by name**
(the names you were given in `{{memory:ontology}}`), stamps the inert status, and
refuses a name already in force, already proposed, or already rejected:

```json
{"op":"propose_entity","name":"outage","parent":"event",
 "body":"Seen 14 times on facts that are all service outages.\nExamples: \"the Tuesday checkout outage\".\n\n- `minutes_down`\n- `cause`"}
```

Put your **evidence** in the body — counts and a couple of example titles. The
operator decides from it, in Settings → Ontology, where each suggestion gets accept
and reject. Accepting clears the status in place, so the type lands exactly where you
filed it and inherits from the parent you chose. A rejection is **kept** as a
tombstone: if the tool tells you a name was already rejected, an operator has looked
at it and said no — do not file it again.

`propose_entity` needs **no** tenant grant, deliberately: a suggestion cannot change
what any run is told, so a curator does not need write authority over the tenant's
shared store to offer one.

The bundled **`memory/ontologist`** agent (in the `memory` bundle) does this as a
pass over one user's stored facts, on demand from the Settings panel.

### …and may SUGGEST a subject the tenant does not know yet (v1.79.0)

`propose_entity` suggests a *type*; `propose_subject` suggests a *subject* — a
person, place or thing learned in one scope that should become a shared subject
of the whole tenant. An unknown subject is never minted from a transcript; it is
proposed, and an operator adopts it.

```json
{"op":"propose_subject","subject":"Dave Kim","natural_key":"person:dave-kim",
 "body":"Named in 6 conversations as the shop's floor manager."}
```

→ `{proposed, chunk_id, natural_key, note}`, or `{proposed, already: "<status>",
note}` when it was filed before (not an error). `natural_key` is `<type>:<slug>`
and is used **verbatim** on adoption, so pass the key your facts already point
at. Optional `path` is a single segment, the name the subject gets under
`/facts/`. Like `propose_entity` it needs no tenant grant and changes nothing
until adopted — facts about the subject stay in the scope that learned them.

---

## Verified writes — quote a fact instead of generating one (v1.54.0)

A fact can carry **the span of source text it was drawn from**, and a judge can be
asked whether that span actually carries the claim. A fact that fails stops being
returned by the fact surfaces — it is never deleted.

This changes three things for you.

**Pass the span when you write a fact.** `upsert_chunk` takes `source_quote`: the
sentence you drew the claim from, copied verbatim from the source. A fact with no
span cannot be verified by anyone later, which makes it permanently second-class.

```json
{"op":"upsert_chunk","scope":"user","natural_key":"fact:gh-username",
 "title":"The user's github username is denn.","body":"The user's github username is denn.",
 "type":"person","subject":"the user","source_quote":"my github username is denn"}
```

**Some facts are hidden from you, on purpose.** `list_facts` and `graph_recall` omit
facts a judge refused. If you are diagnosing why something you remember writing is
not coming back, pass `include_refuted: true` — each refused fact comes back with the
judge's stated reason. A fact with **no** verdict is not hidden; unjudged and refuted
are different states, and only the second is withheld.

**Do not judge your own facts.** `judge_fact` (`id` or `natural_key`, `verdict`,
`reason` — all required) records `supported`, `unclear`, `mistyped` or
`unsupported`; only `unsupported` withholds the fact, and the server owns the
confidence each maps to. It exists for the verification pass, which
runs a separate agent that never wrote the claim it is checking. An agent marking its
own writes `supported` is self-certification and defeats the entire mechanism. If you
have written something you believe is well-evidenced, leave it unjudged — that reads
as *unverified*, which is honest, rather than as *checked*, which would be false.

**Prefer quoting over generating for lookup questions.** Before you compose an answer
to something like "what is my github username", ask:

```json
{"op":"verbatim_answer","scope":"user","query":"what is my github username"}
```

It returns the stored claim **verbatim** plus the span it was verified against, so
your answer carries a citation and no invented wording:

```json
{"answered":true,"answer":"The user's github username is denn.",
 "source":"my github username is denn","chunk_id":"…","confidence":0.9,"score":0.94,
 "judged_at":1785424758000000000}
```

It refuses far more often than it answers, and that is the design. `answered:false`
comes with a `reason` — the closest fact is unverified, or below the similarity floor
(`min_score`, default 0.6), or two facts match about equally well. **Treat a refusal as "answer normally", never as
"there is nothing".** It only works for lookup: "what is my github username" has a
verbatim answer, "how should I structure this migration" does not.

`verification_stats` reports how much of a scope is verified — mostly an operator's
number, useful to you if you are deciding how much to trust the store. It counts
claims only, never subject name nodes.

---

## Finding things — search, links, tags

**`search`** is the way in when you do not know which document holds the answer.
It matches free text against chunk **bodies** across every document in the scope
— by meaning, and by the words themselves where the server has a word index
(Postgres with pgvector).

```json
{"op":"search","scope":"user","query":"how do we roll back a failed database migration","limit":5}
```

```json
{"chunks":[{"chunk_id":"…","score":0.82,"rank_score":0.032,"title":"Rollback plan","document_id":"…"}]}
```

`rank_score` is what ordered the result (meaning and word matches combined);
`score` is the raw strength of whichever match found the chunk, so a chunk found
by its words can have a low `score` and still rank first. Compare within one
result, not against a fixed number. If every `rank_score` equals its `score`
there is no word index, and an exact string that was not found may still be
there — look with `query_chunks` and `sql`. No bodies are returned; `get_chunk`
a hit. `limit` is 10 by default, 50 at most. An agent whose operator switched on
reranking also sees `reranked` (and `rerank_reason` when false); a hit may carry
`matched_unit: {kind, text}` when it was found through a generated description
of its document rather than its own words.

Once you hold a chunk, three ops find its neighbours (all take the chunk `id`):

| op | finds | reply |
|---|---|---|
| `backlinks` | chunks that already link **to** it — `link_chunks` edges and `[[name]]` links in bodies | `{backlinks: [{from_id, kind, auto, from_title, from_document_id, …}]}` |
| `related` | chunks whose bodies say similar things, linked or not (needs an embedder) | `{related: [{chunk_id, score, title, document_id}]}` |
| `unlinked_mentions` | chunks whose body contains its **title** but do not link to it | `{unlinked_mentions: [{chunk_id, title, document_id}], truncated}` |

`unlinked_mentions` matches the title literally, so it is only useful for a
distinctive one. `get_edges` (`document_id`) returns every edge in and out of a
whole document.

**Tags.** `add_tags` / `remove_tags` change tags incrementally and reply with the
full set afterwards; passing `tags` to `create_chunk` / `update_chunk` /
`upsert_chunk` / `create_document` **replaces** the whole set. They target a
chunk (`id`) or a document (`document_id`), and **a document's tags are separate
from its root chunk's**: `query_chunks` filters chunk tags (`tag`, `tag_prefix`),
`query_documents` filters document tags. Nest with a slash (`area/billing`).
`list_tags` with neither id returns every tag in the scope with counts — read it
before inventing a near-duplicate spelling.

```json
{"op":"add_tags","scope":"user","id":"<chunk>","tags":["billing/invoices","q3"]}
```

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
Canvas v1.0 object — one text node per chunk, one edge per link — for a spatial,
board-style view or a tool that reads `.canvas` files. The root chunk and the
hierarchy are not drawn. `import_canvas` (`canvas` as a JSON object, not a
string; optional `title`, `path`) always builds a **new** document, every node a
chunk directly under the root.

```json
{"op":"export_canvas","scope":"user","path":"/docs/launch"}
```

→ `{canvas: {nodes: [...], edges: [...]}, document_id}`. For readable text use
`export_md`; `export_md` → `import_md` is the round trip that keeps hierarchy.

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
  `excluded_unkeyed`, `excluded_withheld`).

**Only keyed chunks travel** — chunks carrying a `natural_key` (written with
`upsert_chunk`), matched across the two servers by that key. Chunks made with
`create_chunk` or `import_md` are skipped and counted in `excluded_unkeyed`.
Nothing is deleted on either side, an overwritten body stays in that chunk's
`history`, and facts a judge refused are not copied. A sync is not
all-or-nothing; running it again continues. A source authored at runtime reaches
only a host the operator allow-listed — the refusal names the env var, and
retrying does not help.

---

## Off-run: callable directly from the plugin (MCP meta-tool)

Document is a first-class MCP meta-tool — call it through the thin client to
co-author the same documents agents build, without spawning a run:

```
document  { "op": "create_document", "scope": "user", "title": "Launch plan", "path": "/docs/launch" }
document  { "op": "create_chunk", "scope": "user", "document_id": "<id>", "parent_id": "<root>", "type": "decision", "title": "Ship date", "body": "## Ship date\n2026-07-01" }
document  { "op": "query_chunks", "scope": "user", "document_id": "<id>", "type": "decision", "status": "open" }
```

(`document` here is the MCP tool — in Claude Code it is exposed under the
plugin's or the project's MCP server prefix.) Called this way there is no run:
the session is the operator, so `scope: "tenant"` needs no agent grant, and
`scope: "agent"` is the session's own synthetic agent rather than any agent you
have in mind — use `user` or `tenant`.

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
- **`get_chunk` returns the fact metadata as an `entity` block** (`retired`, the
  time axes, `class`, `natural_key`, `confidence`, `source_quote`, `subject`, and
  the verdict fields once judged). A plain document chunk has no `entity`.
  `list_facts` returns the same block; times are unix nanoseconds.
- **The default scope is `user`**, and Path's is `agent`. Pass `scope` on both.
- **Unix nanoseconds here, RFC3339 on `memory`.** `valid_at`, `invalid_at`,
  `observed_at` and `as_of` are integers on this tool.
- **`set_path` adds a name; it is not a move.** To rename, use `path` `op=mv`.

Full runtime reference: the loomcycle `document` `Context op=help` topic and
`docs/DOCUMENTS.md`; the backing store is `docs/SQL_MEMORY.md`.
