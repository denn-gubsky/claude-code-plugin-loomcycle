# Token budgets reference — RFC AW (v1.11.0+; checked against v1.107.0)

Per-scope **monthly token budgets**: a `soft` ceiling (warn, the run continues)
and a `hard` ceiling (refuse *new* runs at admission) on a scope's calendar-month
token total. No budget row = unlimited (today's default). Enforcement is
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
  (a delivery over a hard ceiling answers `429`).

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
| a `hard` ceiling crossed **mid-run** | the in-flight run **warns but finishes** (no mid-run abort) — the crossing appears in `limits`; the *next* new run is what gets refused. |

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
UI **Usage** page; also gRPC/TS/Python) breaks month-to-date tokens + money cost
down by tenant / user / provider / model / credential-source (the
operator-vs-tenant split). Usage is **reporting only** — also not an MCP tool.
Set budgets against the numbers the Usage page shows.

Budgets and month-to-date usage travel in a snapshot: on restore a budget the
target already has is kept, and the carried usage is not counted twice. Usage
from an earlier month is not carried.

Runtime reference: `docs/DECISION-MODELS.md` in the loomcycle repo for how
decision calls are charged. The original budget release notes are on the v1.11.0
tag (`git show v1.11.0`); `REVISIONS.md` only goes back to v1.43.2.
