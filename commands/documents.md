---
description: Work on whole sets of loomcycle documents — copy or move them between scopes with their relations, take a scope-wide snapshot of a corpus, or classify a document against the tenant ontology.
argument-hint: "copy|move <to_scope> (--under=<path>… | --ids=a,b) [--scope=user|agent|tenant] [--map=/from:/to,…] [--drop-dangling] [--confirm] | snapshot [--scope=…] [--under=<path>] [--proposed] [--projection] | classify <document_id|path> [--scope=…] [--propose]"
allowed-tools: mcp__loomcycle__document mcp__plugin_loomcycle_loomcycle__document
---

# loomcycle documents

Set-level operations on the Document tool that would otherwise take one call per
document. Wraps the `document` tool of the loomcycle MCP server. For one
document's chunks, facts and search, call `document` directly or use
`/loomcycle:memory`.

Every call names **one** scope: `user` (default), `agent` or `tenant`. A
document id from one scope is "no such document" in another. Off-run, what the
token may read and write in a scope is decided by its access-control rules
(`/loomcycle:access check read document:tenant:/kb`).

Parse `$ARGUMENTS`. The first token picks the sub-command.

---

## `copy` — copy documents into another scope

```json
{ "op": "copy_documents", "scope": "<from>", "to_scope": "<to>",
  "under_path": "/loomcycle", "under_paths": ["…"], "document_ids": ["…"],
  "path_map": {"/loomcycle": "/kb/loomcycle"}, "dry_run": true }
```

- `<to_scope>` is required. `--scope` is where the documents are (default
  `user`). Copying into the **same** scope makes duplicates and needs `--map`.
- Select with `--under=<path>` (repeatable: the first is `under_path`, the rest
  `under_paths`) and/or `--ids=a,b` (`document_ids`). They combine; a document
  named twice is copied once. **At most 500 per call**: split a larger set by
  subtree.
- `--map=/from:/to,/a:/b` becomes `path_map` (the longest matching prefix wins;
  a name no prefix matches keeps its path).
- **Always run the dry run first** (`dry_run` omitted, so `true`). Send
  `dry_run: false` only when the user passed `--confirm`, **after** they saw the
  dry run.

The copy keeps what `export_md` + `import_md` would lose: chunk hierarchy,
types, statuses and validity, bodies with their history, tags, images, derived
search units, and **the relations between the copied documents** with their
evidence. Each copy gets new ids, and its root records
`copied_from: {scope, document_id}`. The source is unchanged.

**Render the dry run** as:
1. counts: documents, chunks, statements, revisions, assets;
2. a table of the documents with their target paths;
3. `refused` as a table (document, code, detail), explaining each code:

   | code | meaning |
   |---|---|
   | `is_ontology` | the tenant ontology is edited in place, never copied |
   | `is_subject` / `holds_facts` | subjects and facts have their own identity (a natural key) and do not move between scopes this way |
   | `path_collision` | the target name is taken in `to_scope`, or two documents of the set would take one name. Fix with `--map` |
   | `key_collision` | `to_scope` already holds this work key or identity key |
   | `forbidden` | access rules deny read on the source or write on the target name |
   | `not_found` | no such document in `scope` |
   | `write_failed` | (real copy only) this document's rows could not be written; nothing of it was left behind. See `detail` |

4. **`dangling`**: relations that will **not** travel, because one end, or an
   evidence quote, is outside the set (`outside`: `from`, `to` or `evidence`).
   Show `dangling_count`. Usually the fix is to widen the set so related
   documents are copied together.

The lists are capped at 200 entries; `refused_count` and `dangling_count` stay
exact.

**After a real copy**, show `new_id` per document and report any
`body_failures`, `name_failures`, `statements_failed` / `statement_error`.
Each copy is announced on the target scope's `documents/ingested` queue (reason
`copied`), so a deployment running the knowledge-base links agent will process
them.

### Copy or move?

`copy` mints **new ids** and leaves the source alone. If the documents should
*live* in the other scope, and anything holds their ids (notes, memory,
statements, links), use `move` instead.

---

## `move` — move documents into another scope, keeping their ids

```json
{ "op": "move_documents", "scope": "<from>", "to_scope": "<to>",
  "under_path": "/loomcycle", "path_map": {"/loomcycle": "/kb/loomcycle"},
  "dangling": "refuse", "dry_run": true }
```

`move_documents` shipped on loomcycle main after v1.135.0. On a runtime that
lacks it the op is refused as unknown. Then fall back to `copy`, check the
result, and delete each source with `document` `op=delete_document`, after the
user confirms and knowing the ids change.

- Same selection flags as `copy` (at most 500). `<to_scope>` **must differ**
  from `--scope`; to rename within one scope use the `path` tool's `mv`.
- Every id is kept: documents, chunks, and the relations between moved
  documents with their statuses, rulings and evidence. The source scope no
  longer holds them.
- **A relation cannot span two scopes.** If a moved document has a relation to
  one outside the set, the dry run reports `blocked_by: "dangling_relations"`
  and lists them under `dangling`. Offer two ways out: widen the set to include
  the other documents (preferred), or `--drop-dangling` (`dangling: "drop"`),
  which deletes those relations with the source. Never pick `drop` for the user.

**Always two calls.** First the dry run. Render:
- counts and the document table, as for `copy`;
- `refused`: the copy codes, plus `id_collision` (the target already holds that
  id). A move also needs **write** on each source, so `forbidden` can appear
  where a copy would pass;
- `dangling` and `blocked_by`;
- `to_finish`: documents an earlier, interrupted move already took out of the
  source.

Then, only with `--confirm` (or the user's yes after seeing it):

```json
{ "op": "move_documents", …same…, "dry_run": false,
  "expect_count": <counts.documents from the dry run> }
```

A changed set is refused (`the set now holds N documents to move, not the M
expected`) and nothing moves. Run the dry run again.

**After the move**, render `moved`, `dropped` if any, and **`unfinished`**:
documents written to the target but not finished, each with a code
(`verify_failed`, `source_not_removed`, `marker_not_cleared`). Their sources are
kept. **Running the same call again resumes** the interrupted move (rows marked
`resumed`), so tell the user to do that rather than cleaning up by hand. A scope
held by a links-agent lease refuses until the lease ends; retry later.

Each moved document is announced on the target scope's `documents/ingested`
queue with reason `moved`.

---

## `snapshot` — what a scope holds, in one pass

```json
{ "op": "graph_snapshot", "scope": "<scope>", "under_path": "/kb",
  "include": ["documents", "chunks", "edges"], "page_documents": 1000,
  "include_proposed": false }
```

`graph_snapshot` returns a scope's structure (documents, chunk trees,
relations, Path names, fact flags) as **parallel columns**: position `i` of each
array describes one item. `*_code` columns index `codes` (`types`, `statuses`,
`kinds`, `fact_classes`, `methods`; `-1` = none), and `*_idx` columns index
another section. It carries titles and metadata, **never bodies**.

- `--under=<path>` → `under_path`. `--proposed` → `include_proposed: true`
  (also count relations waiting for review). `--projection` adds `projection` to
  `include`.
- **Page** until `page.next_cursor` is absent, passing it back as `after`.
  Stop after 20 pages and say the scope is larger than this summary read.
- Decode the columns and render a **summary**, not the arrays:
  - documents: total, then a table by type and by top-level path;
  - chunks: total, facts among them (`is_fact`);
  - relations: total, and a table by kind × status;
  - `edges.truncated` or `page.clamped_to`: say the page was cut, and by what;
  - with `--projection`: `model` and `basis_version`. `0` means the scope has
    no 3D map yet: the operator enables `memory.projection` and builds one with
    `POST /v1/_document/project`. Report the `missing` count.

Access-control rules apply as for a listing: a document the token may not read
is left out entirely, with its relations. A short corpus may be a confined
view, not a small one.

This is the same export the Web UI's **universe** view draws (the `stars`
switch in the documents explorer): documents as constellations of chunk stars,
or, with a projection, chunks placed by meaning. Point the user there to
*look* at the corpus.

---

## `classify` — what is this document?

```json
{ "op": "classify", "document_id": "<id>", "scope": "<scope>", "write": "report" }
```

- The target is a document id, or a Path name (sent as `path`).
- **Default to `write: "report"`**, which writes nothing. Send
  `write: "propose"` only with `--propose`. Then an unambiguous rule match is
  applied and everything else is filed for review.
- Render:
  - `result`: `classified`, `proposed`, `kept` (a type set by hand stays) or
    `unclassified`;
  - the class, `work_key` and identity `fields`;
  - `issued_by` and `concepts` with their shares;
  - `steps`: which of rules, neighbourhood vote and model decided, with the
    quote a rule matched.
- `classify` needs a **confirmed** tenant ontology with document classes (a draft
  answers `unclassified` with a reason). `unclassified` with
  no rule candidates usually means the ontology has no class whose
  `@title_pattern` fits. See the `loomcycle-configure` skill's
  `reference/knowledge-base.md`.
- A pending classification is accepted by an operator: `accept_classification`,
  or **Accept** in the Web UI document viewer. In the tenant scope, `propose`
  also files statements: concepts as proposals (reviewed with
  `/loomcycle:kb-review`), and `issued_by` asserted when the class was applied
  by rule.

If the sub-command is missing or unrecognised, list the four and stop rather
than guessing.
