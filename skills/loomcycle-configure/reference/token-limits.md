# Token budgets reference — RFC AW (v1.11.0+; checked against v1.126.0)

Per-scope **monthly token budgets**: a `soft` ceiling (warn, the run continues)
and a `hard` ceiling (refuse *new* runs at admission — or, with
`LOOMCYCLE_LIMITS_ENFORCE=strict`, also stop runs in flight) on a scope's
calendar-month token total. No budget row = unlimited (today's default). Enforcement is
**advisory** — each replica counts only its own calls (a hard ceiling can be
briefly overshot across replicas) and it is **fail-open** (a budgeting fault
never blocks the runtime).

- **Scopes:** `operator` (platform-wide), `tenant`, `user`. **Most-restrictive
  wins** — a run is refused if *any* of its scopes is over hard.
- **Window:** the calendar month in **UTC**; counters reset on the first call
  after a month boundary, seeded at boot from the RFC AV usage ledger.
- **Counted total:** `input + output + cache_creation + cache_read` tokens,
  **summed across all providers/models** for the scope (not per-model).
- **Requires a store** (the counters + limit rows persist).
- **Every way a run starts is covered** — HTTP, gRPC, MCP, schedules, webhooks
  (a delivery over a hard ceiling answers `429`). Since v1.113.0 a run that
  must wait is **queued**; the budget is checked before it may queue and again
  when it starts.
- **The raw model endpoints are metered (v1.112.0)** — `/v1/_llm/chat`,
  `/v1/chat/completions` and `/v1/embeddings` (scope `llm:gateway`) write usage
  rows, count against budgets and are refused at a hard ceiling. A gateway call
  that ends with no usage report is counted by a size estimate (it errs high,
  survives a restart, and stays out of the usage ledger).
- **Background calls count too (v1.126.0).** Compaction and recap summaries,
  Document unit generation and image description, and **every embedder call**
  (memory/document writes, search queries, re-embeds) are now billed and count
  against budgets like any call. An embedder call whose provider reported no
  token count counts nothing against the budget.

---

## Managed via the Web UI / HTTP — **no MCP CRUD tool** (like steering)

Budgets are **set** in the Web UI **Limits console** or over HTTP —
tenant-scoped `GET / PUT / DELETE /v1/_limits` (a `substrate:tenant` operator
manages only its own tenant + users; the operator-global and cross-tenant
budgets are admin-only). The `PUT` body is `{scope, scope_id, soft_limit,
hard_limit}` (plus `tenant_id`, which only an admin may point at another
tenant); `GET` returns each row with its month-to-date `used`. There is a gRPC
`TokenLimit` RPC and `listLimits()`/`setLimit()`/`deleteLimit()` on the TS/Python
adapters, but **deliberately no MCP tool for budgets** — like interactive
steering (`reference/interactive.md`). From the plugin, budgets are *observed*,
not authored.

The Web UI editors accept **K/M/G shorthand** — type `5M`, `500K`, `2G` and the
field shows the exact `= 5,000,000` it resolves to (v1.11.1).

---

## How budgets surface to the plugin (the MCP-tool side)

You don't set budgets over MCP, but you **feel** them on the run tools:

| situation | what you see |
|---|---|
| a `soft` ceiling crossed during a run | `spawn_run` / `spawn_runs` returns its result plus a **`limits`** array — each `{scope, severity:"soft", window:"month", used, limit, message}` — and a `limit` event on the run stream / transcript. The run completes. |
| a `hard` ceiling already crossed at admission | the run is **refused before it starts**: the MCP tool call errors with `token_limit_exceeded` (HTTP 429 / gRPC `ResourceExhausted`). Nothing was spent. |
| a `hard` ceiling crossed **mid-run** (default) | the in-flight run **warns but finishes** (no mid-run abort) — the crossing appears in `limits`; the *next* new run is what gets refused. |
| a `hard` ceiling crossed **mid-run** with `LOOMCYCLE_LIMITS_ENFORCE=strict` (v1.112.0) | the run is stopped at its next model call: it ends `failed` with `stop_reason` `token_limit` (error `token_limit_exceeded: …`); what it wrote is kept and the session can be continued once the budget allows. A sub-agent it tries to start is refused as the parent's tool error (no child row). A paused run is checked again on resume. Overshoot is bounded by one model call per run in flight. |

**Strict mode (v1.112.0).** `LOOMCYCLE_LIMITS_ENFORCE=strict` adds checks
before each model call of a run in flight, before each sub-agent starts, and
when a paused run resumes; any other value stops the server at boot. Not
checked one by one: a compaction summary and the model calls a tool makes on a
run's behalf (evaluation, decision, consolidation) — the run's own next call
is. Same per-replica counter as the default mode.

**Decision calls count too (v1.107.0).** A `decision` call made **inside** a
run is charged to that run. One made **outside** a run — the `decision` tool
called directly, `POST /v1/_decide`, or gRPC — is charged to the calling
principal's own tenant and subject on a usage row with no run. It counts against
the operator, tenant and user budgets and shows in `GET /v1/_usage` under the
caller's tenant. A caller already at a hard ceiling is refused with
`token_limit_exceeded` before any model is asked; the call that crosses a ceiling
completes.

**Cross-tenant privacy:** an `operator`-scope crossing delivered to a tenant's
run carries no `used`/`limit` numbers (they're platform-wide aggregates) — only
a generic "service budget reached" message. Tenant/user crossings carry their
own figures.

So a `/loomcycle:run` or `/loomcycle:fanout` may come back with budget warnings,
or be refused with `token_limit_exceeded` — the fix is to raise the ceiling in
the Limits console (or wait for the month to roll), not to retry.

---

## Relationship to usage/cost (RFC AV)

Budgets **count** what the RFC AV usage ledger **reports**. `GET /v1/_usage` (Web
UI **Usage** pages; also gRPC/TS/Python) breaks tokens + money cost down by
`group_by` dimensions: `tenant`, `user`, `provider`, `model`, `source` (the
operator-vs-tenant key split), `purpose`, `tier`, `user_tier`, `agent`
(per-call detail only) and `class`. Usage is **reporting only** — also not an
MCP tool. Set budgets against the numbers the Usage page shows.

**What each row was for (v1.123.0 / v1.126.0).** Every model call the runtime
makes on someone's behalf is a row with a `purpose`:

| class | purposes |
|---|---|
| **foreground** (a person or caller asked) | `chat` (an agent's own turns), `gateway` (`/v1/_llm/chat`, `/v1/chat/completions`) |
| **background** (the runtime asked, to serve them) | `consolidation` (an `internal:` agent's turns), `rerank`, `decision`, `compaction`, `recap`, `unit_generation`, `image_description`, `embedding`, `ocr`, `stt`, `tts` |

Each row also records the run's **`user_tier`** and, on an agent's own turns and
gateway calls, the model **`tier`** it resolved through (`pinned` when the
request named its model; empty on background calls). Speech-to-text rows carry
`audio_seconds`; text-to-speech and embedding rows carry `input_chars` (an
embedding is priced by tokens, else by `per_million_chars`, else left unpriced —
never free).

**Reports for charts (v1.126.0).** `GET /v1/_usage` also takes
`bucket=hour|day|week|month` (UTC periods; each row gains `period` — `hour` is
refused for a window older than `detail_since`), `top=N` (≤50) with
`top_by=cost|tokens|calls` (the rest folds into rows marked `"other": true`),
and a filter per dimension by its own name (`model=a,b`, `tier=high`,
`class=background`; values OR'd, dimensions AND'd — `tenant` stays the admin's
focus, not a filter). The Web UI Usage pages have tabs for overview, models,
providers, tiers, users, tenants (admin) and background.

Budgets and month-to-date usage travel in a snapshot: on restore a budget the
target already has is kept, and the carried usage is not counted twice. Usage
from an earlier month is not carried.

Runtime reference: `docs/DECISION-MODELS.md` in the loomcycle repo for how
decision calls are charged. The original budget release notes are on the v1.11.0
tag (`git show v1.11.0`); `REVISIONS.md` only goes back to v1.43.2.
