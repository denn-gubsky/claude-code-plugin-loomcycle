---
name: loomcycle-memory
description: Operate loomcycle's memory over MCP — the four scopes, semantic recall vs vector search vs key/value, the ASYNCHRONOUS add path and background consolidation, per-scope SQL, the bi-temporal entity graph (valid_at/invalid_at, supersede-not-delete), chunked-graph Documents and the Path VFS on top of them, provenance, and the three-tier subject erasure. Use when the user wants to read, write, organise, inspect, repair or erase what a loomcycle agent remembers — including "what do we know about X", "why did the agent forget", "store this durably", "correct a fact", "what do you hold about this person", or SQL over an agent's own database.
allowed-tools: mcp__loomcycle__memory mcp__loomcycle__document mcp__loomcycle__path mcp__loomcycle__erasure mcp__loomcycle__context
---

# Operate loomcycle memory over MCP

loomcycle's memory is four planes reached through three tools. Knowing which
plane a question belongs to is most of the work; picking the op is the easy part.

| plane | tool | what lives there |
|---|---|---|
| key/value + vector | `memory` | facts, counters, small state, embeddings |
| per-scope SQL | `memory` (`sql_*`) | related tables, joins, aggregates, the entity graph |
| chunked-graph documents | `document` | structured prose: bodies in memory, structure in SQL |
| names | `path` | a Unix-like tree addressing all of the above |

## Scopes decide visibility — get this right first

`agent` (this agent, across runs and users) · `user` (this end-user, across
agents; needs a `user_id` on the run) · `tenant` (**shared by every user and agent
in the tenant**) · `run` (ephemeral, SQL only).

Two rules that cause most confusion:

- **`tenant` is a broadcast.** Anything written there is read by every agent and
  user in the tenant. Use it for curated reference material, never for anything
  derived from untrusted text.
- **`tenant` needs two grants**, `memory_scopes` AND `sql_scopes`, both including
  `tenant`. One without the other refuses in a way that looks like a bug.

The same logical scope is keyed differently by different planes, so do not try to
reconcile ids across them by hand — address things by `path` instead.

## `add` is asynchronous. Do not treat a pending reply as a failure

```json
{ "op": "add", "scope": "user", "messages": [{"role":"user","content":"…"}], "infer": true }
→ { "event_id": "pend_…", "status": "pending" }
```

The turns are **enqueued for a background consolidator**; extracted facts appear
later, not in this response. So:

- Do **not** report that the write failed because no facts came back.
- Do **not** immediately `recall` and conclude the memory was lost.
- If the user needs it readable *now*, use `set` with an explicit key instead —
  that is synchronous.

`infer: false` stores the turns verbatim as one row.

## Choosing a read

- **`recall`** — natural-language question over durable facts. Hybrid retrieval.
  Start here for "what do we know about X".
- **`search`** — vector similarity over key/value rows that were written with
  `embed: true`. Use when you want the *rows*, not distilled facts.
- **`get` / `list`** — you know the key or the prefix. Cheapest, exact.
- **`graph_recall`** (on `document`) — follows *relations* out from matching
  entities. Use when the question is about connections, not text.

## Provenance is what makes a fact erasable later

`set` accepts `provenance` (`class`, `source_session_id`, `source_run_id`). Record
it when writing a durable fact about a person.

A fact written **without** provenance cannot be traced back to the conversation it
came from, so **no erasure will ever find it** — it is not counted in any tier and
no mechanism reaches it. That is a decision you are making at write time, not a
gap someone can fix later.

## The entity graph is bi-temporal — correct, don't overwrite

Two independent time axes, and conflating them is the classic error:

- `valid_at` / `invalid_at` — when the fact was true **in the world**. Caller-set,
  and may be backdated *or* future-dated.
- `created_at` / `expired_at` — when the system **recorded** it. Never caller-set.

Consequences worth internalising:

- **A future `invalid_at` is still current.** "The contract runs until 2027" is
  true now. Do not read an end date as "ended".
- **Correct by `supersede_chunk`, not by editing.** The retired chunk stays
  queryable so a question about an earlier point in time still has an answer.
- **A chunk may be retired once.** Two different replacements superseding one fact
  is refused — it would leave two contradictory "current" answers. To correct a
  correction, supersede the *newer* chunk; the refusal names it for you.
- **`as_of` asks what was true then**, including facts since corrected.
  `include_retired` is different — it returns superseded rows as well.

## Documents and Path

`document` splits content from structure: chunk bodies live in memory, the
hierarchy and edges in SQL. So a document needs SQL Memory enabled, and the two
halves can disagree if something is repaired out of band.

- A chunk's parent must **exist and be in the same document**. Both are refused
  now, but a chunk parented to nothing is invisible to every tree walk while still
  occupying the scope — if a document is missing content, suspect reachability
  before suspecting deletion.
- `export_md` → `import_md` round-trips. Fenced code blocks are content, not
  structure, so a document containing Markdown samples survives the trip.
- Always give a document a `path` (or accept the default) — a document reachable
  only by id is invisible in the tree.

Use `path op=ls` to browse and `document op=get_document path:…` to open. Prefer
paths over ids in anything a human will read.

## Erasure — three tiers, and the one-shot residue

Use `mcp__loomcycle__erasure` (see `/loomcycle:erasure` for the full contract).
The two things to carry into any answer:

1. **It defaults to a dry run.** A live run needs `dry_run: false` AND `confirm`
   equal to the subject. Never pass those unless the user explicitly asked.
2. **Tier-3 residue is traceable only through the subject's chats, which a live
   run deletes.** Afterwards a report shows `residue: 0` while those facts remain,
   and the tool marks tier 3 `UNDETERMINABLE`. **The execute response is the only
   durable record of what was not reached** — print it and say to keep it.

## Diagnosing "the agent forgot"

Work down this list rather than guessing:

1. **Scope mismatch** — written to `agent`, read from `user`, or vice versa.
2. **`add` still pending** — consolidation is background; it may not have run.
3. **A future/absent `invalid_at`** hiding a row from a default read.
4. **Superseded** — the fact was corrected. `include_retired` shows it.
5. **Unreachable, not deleted** — a chunk whose parent is gone, or a document
   with no path.
6. **A grant** — `memory_scopes` / `sql_scopes` not covering the scope asked for.

Surface refusal text verbatim. Never silently retry a different scope or op to
make a call succeed — that turns a visible permission problem into a wrong answer.

## Before reaching for the queue ops

`cursor_*`, `supersede`, `pending_*` drive the background consolidator and sit
behind their own grant. `cursor_advance` moves the watermark deciding what has
already been processed, and holding the lease is required. Touch them only when
asked to inspect or repair the queue — not to hurry consolidation along.

Run `mcp__loomcycle__context` with `op=capabilities` when unsure what this
deployment actually supports, rather than calling something that will refuse.
