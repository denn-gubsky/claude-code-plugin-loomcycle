# Knowledge base reference — statements, ontology, review, annotations (v1.128.0+; checked against v1.156.0)

A **knowledge base** is not a separate tool. It is the Document tool used for more
than text: documents hold the source material, **facts** record claims about
**subjects**, **statements** record how two passages relate (with the quoted text that
shows it), and the tenant **ontology** says which classes and relation kinds exist.
This page is for the operator who configures one and runs it. Core documents, the
entity tier, search, `copy_documents` and `graph_snapshot` are in
[document.md](document.md).

For call sequences an agent follows (answer citing a regulation, file a relation,
find what cites an act, record a fact, after a new edition), read the runtime's own
guide instead of copying it: `Context op=help topic=knowledge-base` in a run, or the
MCP `context` tool with `{"op": "help", "topic": "knowledge-base"}`. Typical
*questions* and the calls that answer each are `topic: "knowledge-base-questions"`.
Each op has its own article, `topic: "Document/<op>"`. An agent prompt can pull an
article's call examples in with **`{{help:<topic>}}`** (v1.153.0; refused at
authoring if the topic is missing, has no examples or exceeds 8 KiB), so the
prompt's samples stay in step with the tool's help.

| Piece | What it is | Made with | Read with |
|---|---|---|---|
| document | a tree of chunks with a title and a Path name | `create_document`, `import_md`, `File op=import` | `get_document`, `export_md` |
| chunk | one part (article, clause, section) | `create_chunk`, `import_md` | `get_chunk`, `search`, `query_chunks` |
| fact | a chunk with fact metadata (`natural_key`, dates, `source_quote`, confidence) | `upsert_chunk`, `remember` | `list_facts`, `graph_recall` |
| subject | a document whose root carries a `natural_key` (`person:ada-lovelace`) | `create_document`, adoption | `get_document`, `list_facts about` |
| statement | a directed relation `from_id` → `to_id` of a `kind`, with status and evidence | `link_chunks`, `propose_statement`, `upsert_chunk relation` | `get_edges`, `get_edge`, `backlinks`, `list_statements` |
| evidence | the verbatim quote a statement rests on, and where it is | the `evidence` argument | `get_edge` |
| ontology | the tenant vocabulary: classes, relation kinds, schemes, instances, review policy | an operator edits and confirms it | `describe_ontology` |
| annotation | a brief and an abstract about a section, document or folder (tenant scope) | `kb/annotator`, or an operator | `get_annotation`, `with_summary`, `lineage` |

A shared knowledge base is almost always the **`tenant` scope**: every call passes
`"scope": "tenant"`, and a chunk id from one scope is "no such chunk" in another. It
needs SQL Memory (on by default with SQLite; with Postgres only when
`LOOMCYCLE_SQLMEM_PG_DSN` is set — see [document.md](document.md)) and `tenant` in
**both** `memory_scopes` and `sql_scopes` of any agent that works on it.

---

## Statements

Since v1.128.0 every relation between two chunks is a **statement**: a row that says
who or what made the claim, from which text, since when, and whether anyone checked it.
Existing edges were rebuilt in place on first use and read back `asserted` with no
evidence (`wikilink` for a `[[name]]` link, `manual` otherwise).

| Field | Meaning |
|---|---|
| `id` | the statement's own id; every review and upkeep op takes it |
| `from_id` / `to_id` / `kind` | the relation; direction matters |
| `status` | `asserted`, `proposed` or `rejected` |
| `method` | how it was made, stamped by the server (below) |
| `confidence` | the writer's own 0..1; recorded, **never** hides the statement |
| `valid_at` / `invalid_at` | world time (unix ns) the relation held; unset `invalid_at` = still holds |
| `attributes` | qualifiers, a JSON object of at most 4 KiB |
| verdict | `verdict_confidence`, `judged_at`, `judge_reason`, `judged_by`; only a verdict withholds |
| `operator_ruled_at`, `ruled_by` | set by a ruling: `operator:<subject>`, `bulk:<ruling_id>`, `policy:<rule>@<version>`, `judge:<run_id>` |

**One statement per relation**, identified by `from_id`, `to_id`, `kind`, `valid_at`
and, where the kind declares one, a discriminating qualifier. Linking the same relation
again adds any new evidence to the existing row.

**Statuses.**
- **asserted** is live: every reader shows and follows it.
- **proposed** waits for review: `get_edges` and the queue show it; `backlinks`
  and `graph_recall` leave it out unless asked (`include_proposed`), and `search`
  `expand` never follows it.
- **rejected** is kept, never deleted, and withheld from every reader. **A person's
  rejection is a tombstone:** proposing the same relation again, at any `valid_at`, is
  refused `statement_rejected`, and `link_chunks` of it is refused at the same
  `valid_at`, where only an operator's own `link_chunks` can re-assert it. A policy's or
  a judge's rejection is **not** a tombstone (see Review).

An asserted statement is never rejected. It leaves the live set by `unlink_chunks`
(deleted with its evidence), `judge_fact` with the statement id and `unsupported`
(withheld, shown with `include_refuted`) or `maintain_statement action: expire` (shown
with `include_retired`).

**Methods** (stamped by the server; none of the fixed ones is accepted from the wire):

| Method | Written by |
|---|---|
| `manual` | `link_chunks`, and `propose_statement` without a method, by a **person outside a run** |
| `agent` | the same ops from **inside a run** (v1.142.0): a model's or code's own write, the run's agent as `actor`. In the tenant scope it is filed `proposed` unless the agent holds `statement_methods: [link]` — as are a run's fact `relation`, `import_md` / `import_canvas` edges and statements a copy or move carries in. A review-policy rule for `method:manual` no longer matches a run's proposals |
| `wikilink` | a `[[name]]` link in a body |
| `import` | `import_md` (its `loom-edges` block, and an edition's `amends`) |
| `sync` / `canvas` | a link pulled by `sync` (arrives `proposed` unless the source is `trust: asserted`) / `import_canvas` |
| `runtime` / `consolidator` | the runtime's own links / a fact's `relation` |
| `ontology` | a relation the ontology's Instances section declares |
| `rule:<name>` / `extractor:<name>` | a code agent holding `statement_methods`; code found it, or a model the code drives found it |

`about`, `supersedes`, `references`, `mentions`, `derived_from` and `supported_by` are
**reserved**: a caller's write is refused `kind_reserved` (`link_chunks` still accepts
`about` from a fact). `attributes` may not name `judge`, `review_route` or
`classified_by` (`attribute_reserved`, v1.133.0).

**Evidence.** Each row has one source: `{chunk_id, quote}`, `{session_id, event_seq,
quote}` (a chat turn), or `{scope, natural_key, quote}` (another scope's fact, kept as
written and never ground for a verdict). For a chunk or a chat turn the server finds the
quote at write time and records `char_start` / `char_end`; **a quote that does not
occur is refused** (`evidence_quote_not_found`), never stored.
- A quote is at most 4,000 characters; a statement keeps at most 32 rows (a
  fixed limit since v1.153.0), past which a write reports `evidence_capped: true`.
- `part: "title"` (v1.144.0) quotes a chunk's **title** instead of its body.
- A row whose source the caller may not read is withheld from every answer.
- `stale: true` marks a quote no longer in its source.

**Vocabulary.** Where the ontology declares relation kinds, a person's `link_chunks`
that does not fit is refused; every other writer's statement is filed with
`ontology_valid: false` and `warnings` for the reviewer.

### Who may do what

| Act | Who | How |
|---|---|---|
| assert a relation | anyone with `link` on both ends — from a run in the tenant scope only with `statement_methods: [link]` (else it is filed `proposed`) | `link_chunks` (refuses a `method`) |
| propose a relation | anyone with `propose` | `propose_statement` (an existing proposal gains the evidence; an asserted one is refused `statement_asserted` — pass its `id` to propose a correction beside it, `attributes.revision_of`) |
| accept / reject one | never a run. The operator plane in any scope of its tenant; a member or isolated user in its own user scope; a member in the tenant scope only with `review` on the statement's from-document. Another user's scope is the operator's | `accept_statement`, `reject_statement` (needs a `reason`) — MCP `document`, or `POST /v1/_document` |
| rule in bulk | operator plane, or a member with `review` (tenant scope or its own user scope) | MCP `review` (below) |
| upkeep (verify, expire, demote, merge, re-point evidence, flag) | a code agent with `statement_methods: [rule\|extractor]`, or an operator session | `maintain_statement` |
| mark an import's source gone | the same | `mark_source` |
| record a judge's verdicts | a code agent with `statement_methods: [judge]` | `judge_statements` |

- **Access-control actions on documents** (v1.128.0 / v1.133.0): `link` covers
  `link_chunks`, `unlink_chunks`, the single rulings and `maintain_statement`
  `expire` / `demote` / `merge`; `propose` covers `propose_statement`, every
  `maintain_statement` action, `lease` and `release`; `read` covers the readers.
  `review` is held only by a rule that names it — no member baseline grants it and it
  implies nothing else. A principal with only `read` + `propose` cannot add evidence
  to an asserted statement.
- **Operator plane vs member (v1.140.0).** The operator plane is an admin, the
  legacy token, open mode or a `substrate:tenant` token in its own tenant, calling
  from **outside a run**. Only it confirms the ontology, writes the review policy,
  defines a tenant-wide type, rules in another user's scope, holds a lease outside
  its own user scope, and grants `statement_methods`. A member's single ruling in
  the tenant scope needs `review` on the statement's from-document (v1.134.0; an
  unknown id gets the same refusal). A ruling also needs `link` on both ends; of
  two concurrent rulings the second gets `statement_changed`.
- **A ruling respects relation characteristics** (v1.154.0). Accepting — by hand,
  in bulk, by policy or by the judge — runs the `@functional` / `@asymmetric`
  checks `link_chunks` runs, refusing with **`characteristic_violation`** (the
  statement stays proposed). Accepting a correction (a proposal with
  `attributes.revision_of`) retires the original in the same write; reverting the
  ruling restores both.
- **Operator rulings survive machine paths.** A reimport, a sync pull, a run's upkeep
  and a fact's retirement never undo an operator's ruling or retire a person's
  statement. A `manual` statement — and a ruled one, from inside a run — takes only
  `verify` and `flag` (`statement_manual`, `statement_operator_ruled`).
- `accept_statement` also reverses a rejection made in error, overrules a judge's
  `unsupported`, and confirms a judge's acceptance (see the audit sample).

---

## The sectioned ontology

The tenant ontology is a document (tenant scope, conventionally `/memory/ontology`). A
top-level heading whose first line is `@section <kind>` says what nesting under it
means. An ontology with no sections reads as before (v1.128.0).

| Section | Holds |
|---|---|
| `@section classes` | document and chunk classes with typed fields, identity keys, directives; `grammar:<name>` chunks |
| `@section relations` | relation kinds with `@domain` / `@range`; declaring it switches on the standard kinds |
| `@section schemes` | concept schemes: topics, ranks, file plans |
| `@section instances` | the real organisations, units and posts, adopted as subjects on confirm |
| `@section review` | the review policy (v1.133.0, see Review) |

**A draft governs nothing.** Until the operator plane confirms it — Web UI →
Settings → Ontology (one tab per section since v1.129.0), or `POST /v1/_ontology`;
a member cannot, since v1.140.0 — only the standard classes apply, `classify` classifies nothing, `extract_citations` finds
nothing and no review policy runs. Revise the confirmed document **in place**:
replacing it with a new document gives every concept a new chunk, so filed statements
point at the old concepts and the next classify files duplicates. Since v1.140.0
the ontology's document id is recorded and every reader resolves by it, so moving
the `/memory/ontology` name onto another document does not swap the vocabulary;
that name, `/memory/entities` and `/memory/tenant_root` are the operator's.

```markdown
# Tenant Ontology

## Classes
@section classes

### Document
- `title` text @required
- `number` text @identity

#### NormativeAct
@identifier_pattern (?P<number>\d+-[IVX]+)
@citation_grammar law-ua
@definitions (?i)визначення термінів
@boilerplate (?i)^набирає чинності

##### grammar:law-ua
pattern: Закон України № ?(?P<number>\d+-[IVX]+)
resolve: work_key=law:{number}

##### Law
@title_pattern ^Закон України

## Relations
@section relations

### stricter_than
@domain NormativeAct
@range NormativeAct
@inverse looser_than
@qualifiers aspect(security|privacy)
@discriminator aspect

### uses_term
@walk

## Schemes
@section schemes

### topics
#### Risk Management
@notation RM
##### outsourcing
@alt аутсорсинг

## Instances
@section instances

### Verkhovna Rada
@a organization
@alt Верховна Рада
```

### Classes

- **Fields:** `` - `name` type `` with types `text`, `number`, `date`, `enum(…)`,
  `concept(scheme)`, `ref(Class)`, `anchor`, and markers `@required`, `@unique`,
  `@identity`. Field problems are warnings on the write, never refusals; an identity
  another chunk already holds is refused (`identity_collision`). `@identity` fields
  build the `natural_key` / work key for you.
- **Document classes** are the classes under `Document`; they govern document roots'
  types and never reach an agent's prompt.
- **Directives**, inherited from the nearest declaring ancestor:

| Directive | Does |
|---|---|
| `@identifier_pattern <re>` | named groups fill the identity fields from the title |
| `@title_pattern <re>` | the rule `classify` matches against the title, import source title and first section titles |
| `@citation_grammar a, b` | grammars `extract_citations` applies; where two match the same text the earlier match wins |
| `@anchor_grammar <name>` | one grammar that keys parts on import (anchors stick once assigned) |
| `@definitions <re>` | chunk titles of definitions passages; `get_chunk` / `query_chunks` mark them `definitional: true` |
| `@boilerplate <re>` | (v1.129.0) paragraphs no relation is drawn from; one line per kind, joined as alternatives; `get_chunk` reports `boilerplate: [[start, end], …]` rune spans |
| `@exclude` | listed among a class's directives by `describe_ontology` |
| `@norm` | (v1.148.0) marks a document class — and its subclasses — as a norm; `describe_ontology` reports `norm_classes`, and the links agent's L4 compares against them by default |
| `@annotate <slot>; <slot>` | (v1.148.0) the slots a class's annotations fill ("the problem; the decisions taken"); the root field `annotation_language` fixes one language for all annotations |

**Grammar chunks** (`grammar:<name>`, in the classes section) are lines:
- `pattern: <regex>` and `resolve: work_key=…, anchor=…, kind=…` — a citation's
  matches and the templates each fills (`{group}` = a named group). As an anchor
  grammar, the deepest heading a pattern matches fills `anchor=`.
- `scope: <regex> => <alt> | <alt>` — a heading it matches is a scope whose segment
  prefixes every part inside it.
- `anchor: <regex> => <alt> | <alt>` — keys a part by its own heading or the nearest
  one above it within its scope.

The first alternative whose `{group}`s all matched is used; the line splits on its last
` => `. Patterns are **RE2**: `\b` is ASCII-only and never matches after a Cyrillic
letter, so end a word with `(?:\s|$)`. After changing an anchor grammar, re-import the
documents it governs. A grammar that cannot be read carries an `issue` and is disabled.

### Relations, schemes, instances

- **Relation kinds.** Declaring a Relations section switches on the standard kinds
  (`cites`, `amends`, `implements`, `subject`, `issued_by`, `defines`, …) plus the
  tenant's own. Directives: `@domain`, `@range`, `@inverse`, characteristics such as
  `@functional`, `@irreflexive`, `@asymmetric`, `@qualifiers name(a|b)`,
  `@discriminator`, `@walk` (followed by `graph_recall walk: declared` and `search
  expand` by default), `@auto_assert`, `@renamed_from`. A nested heading is a sub-kind.
  Only kinds the tenant declares are listed to agents.
- **Concept schemes**: nested headings are concepts, with `@notation`, `@alt` labels,
  `@ordered` for a rank, and mirror tags `<scheme>/<path>` (e.g.
  `topics/risk-management`). `search` and `related` take **`concept`** /
  **`concept_prefix`**: in the tenant scope a chunk matches through a live `subject`
  statement to the concept; in a user or agent scope, by carrying the concept's tag
  (`filter.applied.concept_matched_by` says which). File-plan `@retention` and `@acl`
  are parsed and shown, **not enforced**: **`effective_policy`** (v1.151.0,
  `document_id`) reports what they come to for one document — its concepts (via
  an accepted `subject` / `classified_as` statement, or a tag outside the tenant
  scope), the longest retention, every required group, and `issues` — always
  with `enforced: false`. `describe_ontology` adds each concept's effective
  retention and groups and a `policy` block.
- **Instances** (`@a <class>`, `@alt <label>`) are adopted into the entity registry
  **on confirm**, under the key the memory consolidator uses, and announced `adopted`
  on `memory/subjects`. An instance without a declared class is never adopted.

**`describe_ontology`** (Document op; ignores `scope`) returns what is **in force** as
data: `{exists, status, confirmed, version, sections, partial?, classes, relations,
grammars, schemes, instances, norm_classes, policy?, review?, issues?}`. Read it before writing into an
unfamiliar knowledge base and after every confirm, and check `issues`. Agents suggest
additions with `propose_entity` (`section: relations | schemes | instances`) and
`propose_subject`; an agent never edits the ontology document.

---

## Editions

An amended law, standard or contract is imported **onto** the work it amends, not as a
new document and not over it.

- **Work keys** (`law:ua/2297-vi`) are claimed on the root by the first keyed import or
  derived from the class identity; unique per scope (`identity_collision`).
- **`import_md` with `reimport: true`** and `document_id` or `work_key` reconciles part
  by part, by anchor and text: unchanged parts keep their id, statements and tags; a
  moved or renumbered part keeps its id and takes the new anchor; a changed part is
  **superseded** (the old version closes at `edition_date`, a new one opens, joined by
  `supersedes`); a missing part closes; a new part opens. Nothing is deleted.
- Statements follow a superseded part where their evidence still holds; the rest stay
  on the old version, marked `proposed`. A person's statement and an operator-ruled one
  always follow, with their ruling — a rejection stays a rejection.
- **`edition_date`** (unix ns, default now): import editions in date order; an earlier
  date than the edition in force is refused before anything is written.
- **`amending_document_id`** (with `work_key`): each renumbered or moved part gets one
  `amends` statement (`method: import`, `attributes.mod_type: renumbering`).
- The response's `reimport` block counts `unchanged`, `superseded`, `moved`, `closed`,
  `created`, `statements_copied`, `statements_proposed`; `changed_chunk_ids` names what
  changed. Re-running is idempotent and completes an interrupted reimport.
- **`resolve_anchor`** finds a work by `work_key` and a part by `anchor` as of `as_of`;
  `create_placeholder: true` files an empty `unresolved` document for a cited work not
  held yet, which the first keyed import fills in.
- **`File op=import`** takes the same `reimport`, `work_key`, `edition_date` and
  `amending_document_id`, so an extracted PDF of a new edition reconciles the same way.

---

## Classify

`Document op=classify {document_id | path, write?: propose | report, scope}` says what a
document is, from the **confirmed** ontology, in up to three steps reported in `steps`:

1. **Rules** (no model): each document class's `@title_pattern` (or a lone
   `@identifier_pattern`) against the title, source title and first section titles;
   named groups fill identity fields, so the work key. An issuer is an instance whose
   name or `@alt` appears as a whole phrase.
2. **Neighbourhood vote** (no model, needs an embedder): readable, already-classified
   documents most like this one in the same Path folder.
3. **Model** (`memory.classifier`), only when the class is still open: a decision model
   first, a chat model when there is none or it is unsure. Always a proposal. With
   more than 20 concepts (v1.138.1) it asks the concept tree **level by level** — the
   top concepts, then the children of each yes, at most 20 a call and 12 calls —
   and keeps the most specific yes on each branch.

Exactly **one class matched by rule is applied** (type, identity fields, an
`issued_by` to an adopted instance). Everything else is a proposal kept in the root's
`classification` field and, in the tenant scope, filed as proposed `subject`,
`classified_as` and `issued_by` statements. A type set by hand is never replaced
(`kept`); `write: report` writes nothing. **`accept_classification`** is the operator's
ruling (refused inside a run; `nothing_pending` if none). Since v1.134.0 a concept tag
decided by the vote is **not** `rule:matched`. Operational documents (root type
`SourceStub`, `SyncReport`, `Annotation`) are `skipped` — they are not knowledge, and
the linker and judge skip them too.

```yaml
memory:
  classifier:                         # no default model; either alone is valid
    decision: { provider: ollama-local, model: nimble }        # Ollama provider only
    chat:     { provider: ollama-local, model: local-medium, effort: low }
    min_probability: 0.6              # provisional thresholds
    min_margin: 0.2
```

With neither model, classify reports the document `unclassified`. Calls are charged to
the classifying run under usage purpose `classify`.

---

## Review

### Bulk review — the MCP `review` tool (v1.133.0)

| Op | Does | Key fields |
|---|---|---|
| `queue` | lists statements of `filter.status` (default `proposed`), newest first; `summarize: true` counts by kind × method × from-path prefix × judge verdict | `filter`, `summarize`, `limit` (500, max 5000), `after`, `order: created\|verified` |
| `rule` | accept or reject many, by `ids` or `filter` (not both; an empty filter is the whole queue) | `action`, `reason` (required to reject), `dry_run`, `expect_count`, `max` (≤1000) |
| `revert` | returns each statement of a ruling to its prior status if nothing changed it since; a reverted rejection drops its tombstone | `ruling_id` |
| `rulings` | past rulings and reverts, newest first | `limit` (20, max 100), `after` |
| `apply_policy` | runs the ontology's Review section over the waiting queue | `filter` (status only `proposed`), `dry_run`, `expect_count`, `max` |

Common: `scope: tenant` (default) or `user` — a member its own; another subject's
`scope_id` is the operator plane's; `tenant` (admin only).
Filters include `kind(s)`, `method` (exact prefix), `actor`, `document_id`,
`under_path`, `from_/to_document_id`, `from_/to_under_path`, `min_confidence`,
`created_before/after` (unix ns or RFC 3339), `has_judge_verdict`, `judge_verdict`,
`method_exact`, `kind_exact`, `from_path_prefix`, `from_unfiled`, `review_route: judge`,
`judge_audit: pending|confirmed|overturned`. Each summary group carries a `filter`
selecting exactly that group: pass it to `rule` unchanged.

**The dry-run flow** (`rule` and `apply_policy`):
1. Call with no `dry_run` (default **true**): read `matched`, the 20-row `sample`, the
   breakdown (or, for a policy, the per-rule counts and accept / reject / judge /
   human). Nothing changes.
2. Call again with `dry_run: false` and `expect_count` = the dry run's `matched`. If the
   queue changed in between: `queue_changed`, nothing ruled — dry-run again.
3. Over 1000 matches, each call rules the next 1000. Keep the `ruling_id` (or find it
   with `rulings`) to `revert`.

Each statement is ruled exactly as the single op would rule it, with a per-item result
(`not_a_proposal`, `statement_changed`, `not_found`, `failed`; an acceptance can also
fail `characteristic_violation`). A bulk ruling rules only a statement still in the
status its selection read, and a bulk accept by `ids` never reverses a rejection
(v1.148.0; use `filter.status: rejected` for that). Every real call writes one audit
record (`statement_ruling`, `statement_ruling_revert`, `statement_policy_ruling`) to
the audit trail (and the `LOOMCYCLE_AUDIT_LOG_PATH` mirror when set). Refusal codes everywhere:
`invalid_request`, `forbidden`, `queue_changed`, `ruling_not_found`, `unavailable`.

**Who:** an admin, or a tenant operator in its own tenant (`write` on the
from-document, `link` on both ends); a member only where a rule grants `review` on the
from-document's path, plus `read` to see rows — e.g. `{"effect":"allow",
"actions":["review"], "resources":["document:tenant:/board/**"]}`. Isolated users,
agent-limited tokens and runs are refused. **`apply_policy` is operator-only**, even for
a member holding `review`. HTTP twins: `GET /v1/_statements/review`, `POST
/v1/_statements/rule | revert | apply_policy`, `GET /v1/_statements/rulings`.

### Review policies (the ontology's Review section)

```markdown
## Review
@section review
judge_floor: 0.85
judge_audit: 0.1

- accept kind:cites,repeals method:rule:citation when quotes:resolved self:false target:held|placeholder
- accept kind:subject method:classify when rule:matched
- reject kind:elaborates method:extractor:relate when confidence<0.6
- judge  kind:elaborates,uses_term floor:0.9 mode:recommend
- human  *
```

- **Grammar:** `<action> <selectors> [when <conditions>] [options]`. Actions `accept`,
  `reject`, `judge` (leave for the judge, `attributes.review_route: judge`), `human`.
  Selectors `kind:a,b` (exact; sub-kinds not included), `method:<m>` (exact, or prefix
  ending `*`), `*`. Conditions: `quotes:resolved`, `self:true|false`,
  `target:held|placeholder|subject|concept`, `rule:matched`, `confidence<x` / `<=` /
  `>` / `>=`. `judge` options `floor:<0..1>`, `mode:rule|recommend`.
- **First match decides**; no match waits for a person. One unreadable rule, an empty
  section, a bad `judge_floor` / `judge_audit` (`0` is refused) or a chunk under the
  section leaves the **whole policy unapplied** — check `describe_ontology` →
  `review.applied` and `issues`.
- **When it runs:** as a proposal is filed (`propose_statement`, `classify`; a
  correction with `id` is never policy-ruled), recorded `ruled_by:
  policy:<rule>@<version>`, one undoable ruling per run; and on demand via
  `apply_policy`.
- **A policy's ruling is not a person's:** no `operator_ruled_at`, and a policy
  rejection is a verdict, not a tombstone — a later proposal is evaluated again.
- With a Review section, `@auto_assert` no longer applies (reported as an issue).
  Without one, `@auto_assert` means `accept kind:<kind> method:rule:* when
  quotes:resolved`.

### The judge

`kb/judge` (knowledge-base bundle, code-js, `statement_methods: [judge]`) reads each
proposal routed to it — both ends, evidence **read back from the cited chunks**, the
kind's meaning, domain and range — asks `kb/judge-verdict` (tool-less, tier `middle`)
for `accept` / `reject` / `unsure` with confidence and one sentence, and hands verdicts
to **`judge_statements`**. The op, not the agent, decides:

- it **rules** only a proposal routed to the judge now, in `rule` mode, at or above the
  rule's floor (`floor:`, else `judge_floor`, default 0.85), where the run may rule —
  `ruled_by: judge:<run_id>`, no operator mark, rejection not a tombstone;
- otherwise it **records** the verdict on `attributes.judge` (`below_floor`, `unsure`,
  `not_permitted`, `recommend`, `not_routed`) and the proposal waits;
- it **refuses** `operator_ruled`, `not_a_proposal`, `already_judged` (judged once),
  `not_found`;
- all rulings of one run are **one ruling**, undone together by `review op=revert`.

**Topics `classify` proposes** (v1.139.1). A classifier model's `subject` proposal
carries no quote; the judge now rules on it from the document's **opening** (root
and first sections, about 2,000 characters) beside the topic's meaning, instead of
skipping it as `no_evidence`. Any other proposal without evidence is still skipped.
So a policy line `judge kind:subject method:classify` now actually gets verdicts.

**Sampled audit:** each run marks a share of its acceptances (`judge_audit`, default
0.1, at least one) `attributes.judge.audited: pending`. Find them with `review op=queue`
`filter: {status: asserted, judge_audit: pending}`; `accept_statement` **confirms**,
`reject_statement` (with a reason) **overturns** — a person's tombstone.
**`GET /v1/_statements/agreement`** (v1.134.0, operator only, no MCP twin) counts per
kind `accepted`, `sampled`, `pending`, `confirmed`, `overturned` and `agreement` =
confirmed ÷ (confirmed + overturned); only the sample counts.

kb/judge input: `scope`, `write: rule|recommend|report` (default `rule`),
`max_judgements` (50), `max_verdict_calls` (50), `filter` (`routed: false` only ever
recommends). Run `write: report` first.

**Web UI:** the **Review** page (`/ui/review`) groups the queue by summary, runs every
action dry-run first, offers Undo and recent rulings, and (v1.134.0) a judge-audit
filter, Confirm / Overturn and a Judge agreement table (hidden from members). It is
shown only to operators and members holding `review` somewhere.

---

## Subjects: merge, bind, events

Both are operator acts on the MCP **`ontology`** tool — never Document ops. It needs
`substrate:tenant` (a member token is refused on every transport) plus `write` on the
document(s).

| Op | Fields | Refusal codes |
|---|---|---|
| `merge_subjects` | `duplicate`, `survivor` (document id or natural key), `tenant` (admin) | `same_subject`, `not_a_subject`, `subject_not_in_scope`, `already_merged`, `principal_conflict`, `forbidden`, `merge_conflict` |
| `bind_principal` | `subject` (doc id, root chunk id or key), `principal` (user subject id; `""` clears; **required**), `tenant` | `subject_not_found`, `not_a_subject`, `binding_conflict`, `principal_not_found`, `forbidden`, `invalid_request`, `unavailable` |

- **A merge cannot be undone.** In one transaction the duplicate's facts move under the
  survivor, each live statement is copied onto the survivor (`attributes.revision_of`)
  and the original expired; one the caller may not `link` is left (`statements_left`)
  for the linker. The duplicate keeps its key and path with `fields.merged_into` and
  status `merged`. A bound duplicate's binding moves to the survivor; a survivor bound
  to someone else refuses (`principal_conflict`).
- **Binding:** one user per subject, one subject per user. The user must have a row in
  the tenant's users table (any status) — register with `POST /v1/_users` first. Agents
  can never set `fields.principal` (`principal_binding_operator_only`).
- **Erasure** reports bound subjects (`bound_subjects`), and a live erasure clears each
  binding and keeps the subject; deleting it stays the operator's call.

**`memory/subjects`** (tenant, `publisher: system`) carries `{op, subject_natural_key,
scope, document_id, root_chunk_id, …}`:

| `op` | When |
|---|---|
| `adopted` | a subject proposal accepted, or an ontology instance adopted on confirm (v1.130.0) |
| `retyped` | a subject root's `type` changed (`old_type`, `new_type`) |
| `removed` | the subject's document deleted |
| `merged` | folded into another (`surviving_key`, `surviving_document_id`) |
| `erased` | the bound user erased; the binding cleared, the user never named |

An event (here or on `documents/ingested`) is withheld when the caller's access rules
hide part of the scope from reading; the result's `not_announced` says why.

---

## Annotations — briefs and abstracts (v1.148.0)

An **annotation** is two short texts *about* one part of the tenant knowledge base: a
**brief** (one sentence, ≤240 characters, for choosing) and an **abstract** (one
paragraph, ≤2000, standing in for reading). Three levels: `branch` (a section with
parts of its own, or a long one), `document` (on the root chunk) and `path` (a Path
folder, kept on a `<folder>/_annotation` document of type `Annotation`, made on the
first write). They are kept **beside** the content — writing one changes no body,
history, export or sync — and only in the **tenant scope**.

| Op | Who | Does |
|---|---|---|
| `annotation_inputs` | operator plane, or a code agent with `statement_methods: [annotate]` | what the target's annotation is written from (its text, its children's annotations, its identity, relations for a document) and `inputs_sha256` |
| `set_annotation` | the same | writes `brief` + `abstract` with that hash; refused `annotation_inputs_changed` if the text moved. The operator may write by hand with `manual: true` (no hash, never overwritten by the pass) |
| `get_annotation` | any reader | a chunk's / document's / folder's records, each with `stale` computed now |
| `list_annotations` | any reader | pages filtered by `level`, `document_id`, `under_path`, `stale`, `manual`; `summarize: true` counts per level |
| `delete_annotation` | operator plane; the grant for driver-written ones | removes one record (`level` required) |

- **Bottom-up and only what changed.** The hash covers a part's own text and its
  children's annotations, so a change climbs exactly as far as the text changed; a
  record whose inputs changed reads `stale: true` and is still shown, marked.
- **Repairs on write** (v1.152.0), reported in `repaired`: a code of the class's
  `@identifier_pattern` shape that is not the document's own (`identity_mismatch`), and
  a folder brief that only repeats the folder name or is under 20 characters.
- **A folder's annotation is withheld** from a caller who may not read every document
  it covers.
- **Reading them:** `with_summary: true` on `get_document`, `get_chunk`, `search`,
  `related`, `graph_recall`, `documents_summary`, `query_documents` and Path `ls`; `search`
  `annotations: "include"` fuses them with passages, `"only"` (with `annotation_levels`,
  e.g. `["path","document"]`) answers a question about the corpus as a whole. **`lineage`**
  (`id`, a chunk) steps up from a hit: its sections, document and folders, each with its
  brief, in one call.
- **The ontology's say:** `@annotate` slots per class, `annotation_language` on the root.
- **Written by** `kb/annotator` (below). The prompt version moved to 2 in v1.152.0 and
  relation naming changed in v1.149.0 — each made every affected annotation stale once,
  so run the annotator with `write: report` first to see the cost.

---

## Finding things in a knowledge base

- **`search` `facets`** (v1.153.0) — `["type","folder","concept"]` counts the
  documents behind the nearest matches (`facet_window` chunks, default 100, at most
  500) per class, folder and ontology concept, with `complete`. Many documents in
  several folders means the top hits are not the whole answer. Details in
  [document.md](document.md).
- **`query_documents`** by `title_contains`, `created_after` / `created_before`
  (v1.153.0), for a document known by name.
- **Cite answers** as `[title](loom:doc/<id>)` / `[title](loom:chunk/<id>)` (v1.138.0,
  help topic `Document/citing`).
- **Read-only agents — `tool_modes`** (v1.153.0). On an agent definition,
  `tool_modes: {Document: read, Path: read}` holds those tools to their read ops: a
  write is refused before it runs, at dispatch and in the tool. It is authority, not
  content (outside the content signature), carries down the spawn tree, and a fork
  may add a read mode but never remove one; since v1.154.0 it holds across the
  agent's whole version history. Give it to anything that reads untrusted document
  text.

```yaml
agents:
  kb/reader:
    tools: [Document, Path]
    tool_modes: { Document: read, Path: read }
```

---

## Sources that keep changing — provenance, removals, duplicates

An imported document records where it came from (`provenance` on the root, a
`source/<kind>` tag). Since v1.144.0 imports also take `source.revision` and
`source.updated_at` (and kind `skybits`), and a **re-import refreshes the provenance**
as a revision of the root, so `history` / `get_version` / `diff` show earlier ones.

- **`mark_source`** (v1.144.0) — `{id | path, status: present | removed | trashed}`
  records that the source no longer holds the document **instead of deleting it**:
  `source_status` in its provenance and the tag `source/removed` while gone (filter
  on it). Never touches a body; refused on a document that was never imported
  (`not_imported`). Operator plane, or a run whose agent holds `statement_methods`
  `rule` or `extractor`.
- **`find_duplicates`** (v1.143.0) — over `document_ids` / `under_path(s)` (≤5000), no
  model: `sha256` (same normalised text, confidence 1.0) and `title` (same title once
  `Copy of `, ` (1)`, ` - Copy`, … are stripped, same kind; 0.7). Each copy points at
  its original (in a title match where only one title has a copy marker, that one
  is the copy; otherwise the earlier by `source_updated_at`, then creation). A **report** unless `propose: true`, which files
  one `duplicate_of` proposal per pair, both titles quoted as evidence (`part:
  "title"`). A pair already joined by `duplicate_of` in any status is skipped. Nothing
  is merged, hidden or deleted — a reviewer decides.
- **`effective_policy`** (v1.151.0) — the retention and groups a document's file-plan
  concepts declare; reported, never enforced (see Schemes above).

### The `skybits-sync` bundle (v1.145.0)

Keeps tenant Documents under a Path root (`/skybits` by default) in step with one
Skybits account: `skybits/sync` (code-js, `statement_methods: [rule]`) lists and
diffs the account, `skybits/import` imports one item (OCR for images, speech-to-text
for recordings), `skybits/structure` (tier `middle`) proposes headings. Edits re-import
into the same document; removed or trashed items get `mark_source`; copies become
`duplicate_of` proposals; items that cannot be text get a `SourceStub`, and each run
adds to a monthly `SyncReport`. It only reads the account. It needs an MCP server
named **`skybits`** in the tenant (an `oauth` credential), SQL Memory, and an
overlay giving `skybits/sync` and `skybits/import` `memory_scopes` / `sql_scopes:
[tenant]`. Start with `{"mode":"plan","full":true}`, then `{"mode":"apply"}`; it
installs no schedule. See the runtime's `bundles/skybits-sync/README.md`.

---

## The knowledge-base bundle

```bash
LOOMCYCLE_PRESETS=base,knowledge-base loomcycle    # or presets: [base, knowledge-base] in the yaml
```

Code agents are always on since v1.153.0 (the old switch is retired), so `code-js`
is registered whenever the config declares it — the default providers layer does.

| Agent | Provider / tools | Role |
|---|---|---|
| `kb/linker` | code-js; `Document`, `Agent`, `Channel`, `Context` (time only); `statement_methods: [rule, extractor]` | builds and maintains statements by rule |
| `kb/verdict` | tier `low`, no tools | one bounded relation verdict per call (L4, L5, rejudge) |
| `kb/judge` | code-js; `Document`, `Agent`; `statement_methods: [judge]` | rules on proposals routed to the judge |
| `kb/judge-verdict` | tier `middle`, no tools | one accept / reject / unsure per proposal |
| `kb/annotator` | code-js; `Document`, `Agent`, `Channel`; `statement_methods: [annotate]` | writes annotations bottom-up (above) |
| `kb/annotate` | tier `middle`, no tools | one part in, `{brief, abstract, language}` out |
| `kb/ask` | code-js; `Decision`, `Agent` | **the one entry point for a question** (below) |
| `kb/classify` | tier `low`, no tools | is this an overview question? `YES` / `NO` |
| `kb/search` | tier `middle`; `Document` read-only | flat search with summaries; ends `COVERAGE: complete \| partial` |
| `kb/survey` | code-js; `Document` read-only, `Agent` | answers overview questions ("what do we hold on X") |
| `kb/screen` | tier `middle`; `Document` read-only | sorts one slice of the survey's candidates by their briefs |
| `kb/walker` | tier `middle`; `Document`, `Path` read-only | composes the survey's reply; walks the tree by summaries after a partial search |

**Asking — `kb/ask`** (v1.153.0, routing refined through v1.156.0). A request for *the*
overview, guide or full picture of one known thing goes straight to `kb/search`
(v1.156.0). Otherwise it asks a decision model whether the question wants an
overview (`kb/classify` when the score is in between or the call fails): an overview
runs **`kb/survey`** (v1.155.0), anything else `kb/search`, and a search that reports
partial coverage or did not complete goes on to `kb/walker` with the ids found,
unless the request was a known-item lookup (it keeps its partial answer) or the
classifier said no (a decision score of 0.1 or less, or `kb/classify`'s no). The
question travels to each child by reference, still untrusted; the caller's trusted
framing ("answer in one paragraph") is forwarded beside it (v1.154.0).
`kb/survey` gathers candidates in code (several searches, one per clause, one hop of
relations; at most 120 documents, plus up to 24 sections of large guides), has
`kb/screen` sort them by their briefs in slices of 12 — ids only, never text — and
`kb/walker` compose the answer; code writes the `COVERAGE` line, `complete` only when
every candidate was sorted, none was cut, and the facet count was reached.
`kb/walker` alone widens an overview until the facet counts are covered (v1.154.0).
An overview costs five to seven times a lookup. The readers hold their tools
read-only (`tool_modes`), so a stored document cannot talk them into writing.

**Linker input** (the run prompt, a JSON object; an unknown field refuses the run):

| `mode` | Over | Layers |
|---|---|---|
| `document` (default) | `document_id` or `path` | L0, L1, L2, L3, L6 (+ L4 with `corpus_paths`) |
| `maintain` | `document_id` or `path` | L6 |
| `drain` | `queue: documents` (`documents/ingested`, user or tenant) or `subjects` (`memory/subjects`, tenant); up to `max_messages` (10, ≤100) | document layers / L6 per subject |
| `subject` | the subject's document (optional `merged_into`) | L6 |
| `sweep` | statements with an end under `path`, least recently verified first | L6 + purge report (`purge: true` only with `write: propose`) |

**Layers:** L0 `classify` (and with `file: {root}`, a name under `<root>/<Class>/`); L1
anchors (report only); L2 citations from the class's citation grammar (`rule:citation`);
L3 `uses_term` / `defines` from the `terms_scheme` (tenant scope only); L4 relate
(opt-in, `extractor:relate`); L5 check-against, a report document, never statements
(opt-in); L6 upkeep. L0, L2 and L3 need a confirmed ontology (L2/L3 with relation
kinds). `uses_term` is not a seed kind — declare it.

**L4, narrowed to what measured true** (v1.148.0). It files only kinds the tenant
ontology declares itself; `elaborates`, `conflicts_with` and `stricter_than` are
**reported, never filed** (and `implements` / `alternate_of` stay report-only). It
compares against the **`@norm`** classes by default (`target_types` overrides;
`target_types_from` says which applied), drops the document's own copies and
versions (the `find_duplicates` rule plus `duplicate_of` / `revision_of` / … relations),
skips headings, contents lines, legends, short passages and quotes, and stops between
verdicts at `time_budget_seconds` (default 1500). A pass whose verdicts all fail ends
`failed`. A tenant that forked `kb/linker` keeps its old code until it re-forks.

**Write modes:** `report` (default) issues read ops only, takes no lease, acks nothing,
and counts `would_write`. **Run it first.** `propose` takes the scope's `linker`
**lease** (`lease` / `release`, named, `ttl_ms` default 60 s, max 1 h; a busy lease ends
the run `status: busy`) and writes only through `propose_statement` and
`maintain_statement`.

**Tenant overlay** — the bundle leaves tenant grants out on purpose (a tenant Document
grant is a tenant write grant):

```yaml
agents:
  kb/linker:    { memory_scopes: [tenant], sql_scopes: [tenant] }
  kb/judge:     { memory_scopes: [tenant], sql_scopes: [tenant] }
  kb/annotator: { memory_scopes: [tenant], sql_scopes: [tenant] }
channels:
  documents/ingested:
    scope: tenant          # the bundle declares user; re-declare when documents live in the tenant
```

Then drain with `{"mode":"drain","scope":"tenant","queue":"documents","write":"propose"}`
(v1.132.0). The bundle installs **no schedule**: add `scheduled_runs` in yaml or a
ScheduleDef (MCP `scheduledef op=create` with an `overlay` naming `agent: kb/linker`,
`schedule`, `concurrency_policy: forbid` and a `trusted-text` prompt holding the JSON
input). Schedule `kb/judge` and `kb/annotator` (`{"mode":"drain","write":"annotate"}`,
plus a weekly `sweep`) after the drain. The annotator reads `documents/ingested`
without acknowledging it — the queue's position belongs to the linker. Under
`LOOMCYCLE_ACL=enforce` the starter needs `propose` on the documents, and `link` on
both ends for `maintain` expire / demote / merge.

**`statement_methods`** (agent definition, yaml or AgentDef): `rule`, `extractor`,
`judge`, `annotate` — **code-js only**, refused at config load and AgentDef create /
fork for any other provider — and, for any provider, `link` (a run's tenant
relations are asserted rather than filed for review) and `remember` (a run may call
`remember`), both v1.142.0. A fork narrows, never widens; not per-run overridable; a
sub-agent holds only its own grant; not part of `content_sha256`. A method outside the
grant is `method_not_granted`. Without it a run's relations are method `agent`. It is
operator-grade: an agent a **member** authors must leave it unset (v1.140.0).

---

## Security and upgrade

- **Memory SQL refuses the Document tables** (v1.128.0): `sql_query` / `sql_exec` naming
  `documents`, `chunks`, `chunk_tags`, `chunk_edges`, … are refused
  `document_tables_reserved` — an agent could otherwise accept its own proposal with an
  `UPDATE`. Use `Document op=query_chunks`. An agent whose **own** tables carry one of
  those names must rename them; a view, trigger or function naming one blocks Memory SQL
  on that scope until dropped.
- **Postgres document plane:** each scope gets a second schema and login role for the
  Document tables (`sqlmem_d_<h>` / `sqlmem_dr_<h>`, beside `sqlmem_s_<h>` /
  `sqlmem_r_<h>`). The first Document op on an older scope copies its rows (up to 10
  minutes per scope). **`pg_hba` must admit the `sqlmem_dr_…` roles** wherever it lists
  `sqlmem_r_…` roles individually. `query_chunks` raw `sql` now runs as the Document role
  and cannot read the agent's own tables.
- **SQLite document plane** (v1.142.0): each scope's Document tables move once, at
  the first boot, into their own `<scope>.doc.db` beside `<scope>.db`, so agent SQL
  cannot reach them. **Back up every `*.db` under the sqlmem root first**; rolling
  back past v1.142.0 needs that backup.
- **Snapshot before upgrading** to v1.128.0+: `POST /v1/_snapshot` includes SQL Memory;
  a non-superuser `pg_dump` cannot capture it, and the upgrade rewrites it.
- **Settings (v1.153.0):** SQL Memory and code agents are no longer switched on by
  environment variables (`LOOMCYCLE_SQLMEM_ENABLED`, `LOOMCYCLE_CODE_AGENTS_ENABLED`
  and the evidence-cap variable are retired — still set, `loomcycle validate` and the
  boot name them, and refuse those that disagree with the new behaviour). On Postgres
  set `LOOMCYCLE_SQLMEM_PG_DSN` or Documents are off. Run `loomcycle validate` /
  `doctor` from the new binary before the real start.
- **Who decides changed in v1.140.0:** a member no longer confirms the ontology,
  writes the review policy, rules outside its own user scope (bar a `review` grant in
  the tenant), holds the tenant lease, or authors agents with `statement_methods`.
  Leases the old shared owner held expire on their TTL.
- **Run relations changed in v1.142.0:** a run's tenant relations and pulled `sync`
  links arrive `proposed` unless granted `link` / declared `trust: asserted`; a run's
  `remember` needs the `remember` grant; a run's proposals are method `agent`, so a
  policy rule written for `method:manual` no longer matches them.
- **Upgrade all replicas together:** an older replica writes documents into the agent
  schema, and those writes are dropped once a newer replica moved the scope.
- **Legacy-token deployments:** an ontology confirmed on the Settings page before
  v1.128.0 never reached runs — confirm it again.
- The judge's and verdict agents' input is document text: prompts carry quotes as data
  blocks and replies are read only as `{verdict, confidence, rationale}`; a hostile
  document can at worst get one proposal accepted, bounded by the floor, the policy's
  kinds, the one-ruling undo and the audit sample.
- **Reload the plugin after upgrading the runtime**: the `review` and `ontology` tools
  and new `document` ops and fields (annotations, `lineage`, `facets`, …) appear only
  in a fresh `tools/list`.
- **The question agents read document text:** they hold `Document` / `Path`
  read-only (`tool_modes`), and `kb/survey` hands its children ids, never text, so a
  hostile document cannot steer a write or reach a trusted prompt.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `statement_rejected` on propose | a person rejected the relation (tombstone) | `accept_statement` if rejected in error, or `review op=revert` the bulk ruling |
| `evidence_quote_not_found` | the quote is not verbatim in its source | quote the chunk's text exactly (`get_chunk`) |
| `statement_asserted` | the relation already holds | propose a correction with its `id`, or `judge_fact` it |
| `kind_reserved` / `attribute_reserved` | a runtime-only kind or attribute | use a tenant kind; drop `judge` / `review_route` / `classified_by` |
| `method_not_granted` | no `statement_methods`, or not code-js | grant `[rule, extractor]` on a code-js definition |
| linker `propose` run fails at its lease | missing method grant | as above; the config must declare a `code-js` provider (the default providers layer does) |
| L2 / L3 `skipped` | ontology draft, or no Relations section | add relation kinds and confirm |
| L3 counts `hits_no_kind` | `uses_term` not declared | add `### uses_term` under Relations |
| drain `failed`, `scope_mismatch` | channel scope differs from the drain's | re-declare `documents/ingested` `scope: tenant` (or drain at `user`) |
| `queue_changed` (409) | queue moved between dry run and real call | dry-run again, pass the new `matched` |
| member gets `forbidden` ruling | no `review` grant on the from-document path (single rulings too since v1.134.0), or another user's scope | bind an ACL rule with action `review`, plus `read`; another user's scope is the operator's |
| `characteristic_violation` on accept | the acceptance would break `@functional` / `@asymmetric` (v1.154.0) | retire the existing statement, or propose a revision of it |
| a run's `link_chunks` in the tenant comes back `proposed` | no `statement_methods: [link]` (v1.142.0) | grant `link`, or rule on the proposals |
| `remember` refused inside a run | no `statement_methods: [remember]` | grant it, or `upsert_chunk` with a real `source_quote` |
| every Document op refused on Postgres | SQL Memory off: no `LOOMCYCLE_SQLMEM_PG_DSN` (boot `WARN`) | set the DSN of a separate database |
| `annotation_inputs_changed` | the text moved between read and write | read `annotation_inputs` again |
| `set_annotation` refused | not tenant scope, or no operator plane / `annotate` grant | pass `scope: tenant`; run it from `kb/annotator` |
| `mark_source` → `not_imported` | the document was never imported with a source | nothing to mark |
| `kb/ask` answer says `COVERAGE: partial` | the candidates outnumbered the cap, or a slice failed | narrow the question or the folder; read `UNCOVERED` |
| `apply_policy` → `invalid_request` | no confirmed ontology, or Review section issues | `describe_ontology`, fix `issues`, confirm |
| policy rules nothing | `review.applied: false` — one bad line voids the policy | fix the line; check `issues` |
| concept tags stopped auto-accepting (v1.134.0) | vote-decided tags are not `rule:matched` | rule on them, or route them to `judge` |
| ontology edits have no effect | still a draft | confirm in Settings → Ontology or `POST /v1/_ontology` (operator plane) |
| `ontology` tool missing from the session | token lacks `substrate:tenant`, or a stale tool list | use an operator token; reload the plugin |
| `principal_not_found` on bind | the user has no row in the tenant | `POST /v1/_users`, then bind |
| `principal_conflict` on merge | the two subjects are bound to different users | clear one binding first |
| `document_tables_reserved` | Memory SQL names a Document table | use `Document op=query_chunks`; rename own tables |
| Document ops fail on Postgres after upgrade | `pg_hba` does not admit `sqlmem_dr_…` | add the roles to `pg_hba` |
| result carries `not_announced` | ACL hides part of the scope; event withheld | the change was made; fix the rules or run as an operator |
