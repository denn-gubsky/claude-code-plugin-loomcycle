---
name: loomcycle-memory
description: Operate loomcycle's memory over MCP — the four scopes, semantic recall vs vector search vs key/value, the ASYNCHRONOUS add path and background consolidation, per-scope SQL, the bi-temporal entity graph (valid_at/invalid_at, supersede-not-delete), chunked-graph Documents and the Path VFS on top of them, past chats (History), provenance, and the three-tier subject erasure. Use when the user wants to read, write, organise, inspect, repair or erase what a loomcycle agent remembers — including "what do we know about X", "why did the agent forget", "store this durably", "correct a fact", "what did we discuss before", "what do you hold about this person", or SQL over an agent's own database.
allowed-tools: mcp__loomcycle__memory mcp__plugin_loomcycle_loomcycle__memory mcp__loomcycle__document mcp__plugin_loomcycle_loomcycle__document mcp__loomcycle__path mcp__plugin_loomcycle_loomcycle__path mcp__loomcycle__history mcp__plugin_loomcycle_loomcycle__history mcp__loomcycle__erasure mcp__plugin_loomcycle_loomcycle__erasure mcp__loomcycle__context mcp__plugin_loomcycle_loomcycle__context
---

# Operate loomcycle memory over MCP

loomcycle's memory is four planes reached through three tools, plus the chats
those planes were distilled from. Knowing which plane a question belongs to is
most of the work; picking the op is the easy part.

| plane | tool | what lives there |
|---|---|---|
| key/value + vector | `memory` | facts, notes, counters, small state, embeddings |
| per-scope SQL | `memory` (`sql_*`) | related tables, joins, aggregates, the entity graph |
| chunked-graph documents | `document` | structured prose: bodies in memory, structure in SQL |
| names | `path` | a Unix-like tree addressing all of the above |
| past chats | `history` | conversation transcripts — what was actually said |

## Scopes decide visibility — get this right first

`agent` (this agent, across runs and users) · `user` (this end-user, across
agents; needs a `user_id` on the run) · `tenant` (**shared by every user and agent
in the tenant**) · `run` (ephemeral, SQL only).

Rules that cause most confusion:

- **One scope per call.** A `user` recall or search never sees `tenant`
  knowledge, and the reverse. To consult both, make two calls and merge by score.
- **`tenant` is a broadcast.** Anything written there is read by every agent and
  user in the tenant. Use it for curated reference material, never for anything
  derived from untrusted text.
- **For an agent, `tenant` needs two grants**, `memory_scopes` AND `sql_scopes`,
  both including `tenant`. One without the other refuses in a way that looks like
  a bug.
- **Unset grants are not deny-all any more.** An agent holding `Memory` with no
  `memory_scopes` resolves to its caller's own data: `user` (plus `tenant` for a
  non-isolated member of a tenant). Unset `sql_scopes` resolves to `user` only.
  A run with no `user_id` still gets nothing. The explicit deny `["-*"]` is
  accepted only on an `AgentDef` overlay; static config rejects it.
- **The defaults differ per tool.** `memory` requires `scope`; `document`
  defaults to `user`; `path` defaults to `agent`. A document created with no
  scope and then looked up in `path` with no scope is looked up in the wrong
  tree — pass `scope` on both.

**What "you" are when you call these tools directly.** A direct MCP call has no
run. The session is the operator: it holds `agent`, `user` and `tenant` on both
the memory and SQL planes (no `run` — there is no run to key it on). `user`
resolves to the subject of the token the session authenticated with, so it lines
up with that user's agent runs and the Web UI. `agent` resolves to the session's
own synthetic agent, **not to any agent you have in mind** — you cannot read a
named agent's `agent`-scope keyspace this way.

The same logical scope is keyed differently by different planes, so do not try to
reconcile ids across them by hand — address things by `path` instead.

## `add` is asynchronous. Do not treat a pending reply as a failure

```json
{ "op": "add", "scope": "user", "messages": [{"role":"user","content":"…"}], "infer": true }
→ { "status": "pending", "event_id": "…" }
```

The turns are **enqueued for a background consolidator**; extracted facts appear
later, not in this response. Until then the `add` has stored no retrievable row.
So:

- Do **not** report that the write failed because no facts came back.
- Do **not** immediately `recall` and conclude the memory was lost.
- If the user needs it readable *now*, use `set` with an explicit key instead —
  that is synchronous.

`infer: false` stores the turns verbatim as one row, immediately, and replies
`status: "done"`.

## Choosing a read

- **`recall`** — natural-language question over what is remembered. Start here
  for "what do we know about X".
- **`search`** — vector similarity over stored rows. Replies
  `{entries: [{key, kind, value, score, rank_score, …}]}`. A `set` row is only
  searchable if it was written with `embed: true`. Use it when you want the
  *rows*, need a key `prefix`, or want document chunks in the same result.
- **`get` / `list`** — you know the key or the prefix. Cheapest, exact.
- **`graph_recall`** (on `document`) — follows *relations* out from matching
  facts. Use when the question is about connections, not text.

### What `recall` returns

```json
{ "op": "recall", "scope": "user", "query": "where does Ada live",
  "when": { "from": "2026-05-01T00:00:00Z", "to": "2026-06-30T00:00:00Z" } }
→ { "memories": [ { "id": "memory/fact/ada-lives-in-cluj", "memory": "Ada lives in Cluj-Napoca.",
      "score": 0.83, "kind": "fact", "source": "I moved to Cluj-Napoca in May.",
      "source_session_id": "…", "source_run_id": "…", "observed_at": "2026-05-04T09:12:00Z" } ],
    "time_filter": { … } }
```

- The array is **`memories`**, not `facts` (renamed in v1.65.0, no alias). Each
  item is something *remembered*: `kind: "note"` is a remark an agent recorded,
  only `kind: "fact"` was distilled by a consolidator.
- **Default sources are facts + notes.** Document prose is excluded unless you
  pass `sources: ["facts","notes","documents"]`; `["traces"]` (raw conversation
  turns) must be asked for alone.
- `source` is the verbatim span the fact was distilled from, on by default
  (`include_source: false` drops it). `source_session_id` is the chat it came
  from — hand both to `history` `op=window` to read the surrounding turns.
- `include_turns: true` attaches the whole originating turn as `turn: {text,
  speaker}`; the reply then reports `turns_attached` (and
  `turns_dropped_for_budget`). Use it when the question turns on *when* or on
  exact wording.
- **Time predicates live in one `when` object.** `from` / `to` (RFC3339) narrow
  by when something was *said*; `slack` (default `"3d"`) and `missing`
  (`"prefer"` default, `"require"` drops undated rows) soften it. Give a generous
  window — a remark usually follows the event. `when.as_of` asks a different
  question: what was *true* at that instant (`[valid_at, invalid_at)`).
- `top_k` (default 10, max 50) and `threshold` (0..1 floor) bound the result.
- Reranking is something an operator switches on per agent; there is no tool
  parameter for it. An agent that has it sees `reranked` (and `rerank_reason`
  when false) on its results. A direct call is not reranked.

### Which scope does a fact belong in — `placement`

Before writing facts whose scope you are unsure of, ask. `placement` reads the
operator's per-type declarations on the tenant ontology and **decides without
writing anything**:

```json
{ "op": "placement", "scope": "user",
  "items": [ {"type": "service", "subject": "checkout-api"}, {"type": "person", "subject": "Dana Whitfield"} ] }
→ { "placements": [ { "type": "service", "subject": "checkout-api", "scope": "tenant", "moved": true, "reason": "…" },
                    { "type": "person", "subject": "Dana Whitfield", "scope": "user", "moved": false, "reason": "…" } ],
    "moved": 1, "caller_scope": "user", "granted_scopes": [ … ], "granted_sql_scopes": [ … ] }
```

Ask once per batch (up to 200 items), then write each fact to the `scope` it
names. Anything the declarations do not settle — no ontology, a draft ontology,
an undeclared type, a subject that is the user themselves — answers with the
scope you passed in, and `reason` says why. That is an answer, not an error.

## Provenance is what makes a fact erasable later

`set` accepts `provenance` (`class`, `source_session_id`, `source_run_id`). Record
it when writing a durable fact about a person.

A fact about someone that lives outside their own scope and was written
**without** provenance cannot be traced back to the conversation it came from, so
**no erasure will ever find it** — it is not counted as residue and no mechanism
reaches it. That is a decision you are making at write time, not a gap someone
can fix later.

## The entity graph is bi-temporal — correct, don't overwrite

Two independent time axes, and conflating them is the classic error:

- `valid_at` / `invalid_at` — when the fact was true **in the world**. Caller-set,
  and may be backdated *or* future-dated.
- `created_at` / `expired_at` — when the system **recorded** it. Never caller-set.

Consequences worth internalising:

- **A future `invalid_at` is still current.** "The contract runs until 2027" is
  true now. Do not read an end date as "ended".
- **Correct by `supersede_chunk`, not by editing.** Write the correction under a
  new `natural_key`, then supersede. The retired chunk stays queryable so a
  question about an earlier point in time still has an answer.
- **A chunk may be retired once.** Two different replacements superseding one fact
  is refused — it would leave two contradictory "current" answers. To correct a
  correction, supersede the *newer* chunk; the refusal names it for you.
- **`as_of` asks what was true then**, including facts since corrected.
  `include_retired` is different — it drops the time filter and returns
  superseded rows as well.
- **The time format differs by tool.** `document` takes and returns unix
  nanoseconds (integers); `memory` takes RFC3339 strings.

## Documents and Path

`document` splits content from structure: chunk bodies live in memory, the
hierarchy and edges in SQL. So a document needs SQL Memory enabled, and the two
halves can disagree if something is repaired out of band.

- A chunk's parent must **exist and be in the same document**. Both are refused
  now, and a chunk created with no `parent_id` goes under the document's root.
  If a document is missing content, suspect reachability before deletion.
- `export_md` → `import_md` round-trips. Fenced code blocks are content, not
  structure, so a document containing Markdown samples survives the trip.
- Every document gets a `path` — `/documents/<title>` when you pass none. A
  malformed `path` now **fails the create** and nothing is written (segments are
  letters, digits, `.`, `_`, `-`; no spaces).
- `document` `op=search` finds chunks by what their bodies say; `memory`
  `op=search` with `sources: ["documents"]` runs the same search.

Use `path op=ls` to browse (it pages: `limit`, then `cursor` = the previous
`next_cursor`) and `document op=get_document path:…` to open. Prefer paths over
ids in anything a human will read. `path op=rm` removes the *name* only — the
thing it pointed at still exists.

## History — what was actually said

The `history` tool reads past **chats** (a chat is one conversation session; it
can span several runs). Ops: `list`, `get`, `search`, `rename`, `annotate`,
`pin`, `archive`, `recap`, `resume`, `related`, `window`.

When to reach for it:

- **`history` versus `memory`.** Memory holds what was *distilled*; history
  holds the transcript it was distilled from. Recall first; when the recalled
  sentence dropped the specific you need (a date, a name, the reason), follow it
  back with `window`. Titles, tags and pins are labels on a conversation, never
  a place to store a fact.
- **`history` versus `list_runs` / `get_run`.** A chat groups runs. To find or
  read a conversation, use `history`; to inspect what one run did (status,
  output, usage), use the run tools.

```json
{ "op": "search", "scope": "user", "query": "moving the launch to a later date", "match": "content" }
→ { "scope": "user", "match": "content", "chats": [ { "session_id": "…", "title": "Planning sync", … } ],
    "matched_turns": [ { "session_id": "…", "speaker": "user", "text": "Let's push the launch to the 14th…", "score": 0.83 } ] }

{ "op": "window", "scope": "user", "session_id": "<the fact's source_session_id>",
  "quote": "<the fact's source, copied exactly>", "context": 2 }
→ { "matched": true, "matched_turn": 7, "turns": [ { "speaker", "text", "seq", "at" } ], "markdown": "…" }
```

Traps:

- **`search` matches the TITLE by default**, and titles are usually
  auto-generated. Pass `match: "content"` when you remember what was said. It
  needs an embedder and searches only the turns typed under your own user id.
- **`scope` is `self` / `user` / `tenant` / `global`, not the memory scopes.**
  `self` is this agent's chats with *every* user — wider than `user`. Omitted,
  it is `user` when granted. Pass it explicitly.
- A chat outside the scope you name reads as `not found`, exactly like one that
  does not exist.
- `get` pages by turns (`offset` / `limit`, `has_more`, `next_offset`);
  `format: "conversation"` returns only the user and assistant turns.
- `window`'s `quote` is the fact's `source` span, not the fact sentence.
  `matched: false` is a result, not an error.
- `recap` is a real model call and costs tokens. `resume` starts nothing — it
  returns the coordinates for continuing the chat in a new run.
- `related` only finds chats that have been recapped, renamed or annotated.

## Erasure — three tiers, and the one-shot residue

Use the `erasure` tool (see `/loomcycle:erasure` for the full contract).
The two things to carry into any answer:

1. **It defaults to a dry run.** A live run needs `dry_run: false` AND `confirm`
   equal to the subject. Never pass those unless the user explicitly asked.
2. **Tier-3 residue is traceable only through the subject's chats, which a live
   run deletes.** Afterwards a report shows `residue: 0` while those facts remain,
   and the tool marks tier 3 `UNDETERMINABLE`. **The execute response is the only
   durable record of what was not reached** — print it and say to keep it.

## Diagnosing "the agent forgot"

Work down this list rather than guessing:

1. **Scope mismatch** — written to `agent`, read from `user`, or vice versa; or
   the answer is in `tenant` and only `user` was read (one scope per call).
2. **`add` still pending** — consolidation is background; it may not have run.
3. **Wrong source** — it is document prose (recall excludes `documents` by
   default), or a `set` row written without `embed: true`.
4. **A past `invalid_at`** hiding a row from a default read, or a tight `when`
   window with `missing: "require"` dropping an undated one.
5. **Superseded** — the fact was corrected. `include_retired` shows it.
6. **Refuted** — a judge marked it unsupported. `include_refuted` shows it, with
   the reason.
7. **Unreachable, not deleted** — a document whose name was removed with
   `path op=rm` is still there by id.
8. **A grant** — `memory_scopes` / `sql_scopes` not covering the scope asked for.

Surface refusal text verbatim. Never silently retry a different scope or op to
make a call succeed — that turns a visible permission problem into a wrong answer.

## Before reaching for the queue ops

`cursor_*`, `supersede`, `pending_*` drive the background consolidator and sit
behind their own grant. `cursor_advance` moves the watermark deciding what has
already been processed, and holding the lease is required.

`supersede` (`key`, optional `superseded_by`) retires a fact in **both** planes
in one call — the key/value row that recall reads and its chunk in the fact
graph. Pass `superseded_by` (the replacing fact's key) when it is a correction;
omit it when the row was merely moved. It replies `{ok: true}`, plus `chunk_id`
and `retired_at` when the fact was in the graph. For an ordinary correction use
`document` `op=supersede_chunk` instead.

A direct MCP session **holds** the consolidation grant, so the grant will not
stop you. Touch these ops only when asked to inspect or repair the queue — not to
hurry consolidation along.

Run the `context` tool with `op=capabilities` when unsure what this deployment
actually supports, rather than calling something that will refuse. `op=help`
with a topic such as `Memory/recall`, `Document/sync` or `History/window` returns
the runtime's own article for one operation.
