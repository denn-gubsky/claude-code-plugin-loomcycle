# CLAUDE.md — claude-code-plugin-loomcycle

This file is loaded by Claude Code on every session in this repo. Read it cold; act from it without re-discovery.

## Project context

**claude-code-plugin-loomcycle** is the Claude Code-side UX layer for [loomcycle](https://github.com/denn-gubsky/loomcycle), a high-load agentic runtime. It is a **Claude Code plugin** — a git-distributed bundle of slash commands, skills, hooks, and a pre-wired MCP server config. It ships nothing executable of its own: since 0.21.0 it wires `loomcycle mcp --upstream <base_url>` as a **thin client** — a stdio↔`/v1/_mcp` proxy to a running loomcycle runtime that boots NO runtime of its own (loomcycle RFC R single-runtime invariant) — and exposes its meta-tools (`mcp__loomcycle__spawn_run`, `…__cancel_run`, `…__list_runs`, snapshot ops, `…__evaluation`, `…__agentdef`, `…__volumedef`, etc.).

**Current loomcycle version: v1.42.0.**

> ⚠️ **The plugin ships NO tool schemas.** `loomcycle mcp --upstream` proxies the runtime's own `tools/list` (generated from each builtin's canonical input schema), and Claude Code caches that **once, at connection** — it is never refreshed mid-session. So after upgrading a deployment, an already-open session keeps the OLD schema: ops the runtime gained still dispatch (string arguments pass straight through) but any argument the cached schema doesn't declare is serialized as a string and the server rejects it (`cannot unmarshal string into Go struct field …`). **Reload the plugin after upgrading the runtime.** This is the failure most likely to be misread as "the plugin's schema is stale" — there is no schema in this repo to fix.

> ⚠️ **Config key rename.** loomcycle v1.13.0 renamed the agent (and `mcp_servers.*`) key `allowed_tools:` → **`tools:`**. The old spelling is **silently ignored** — `loomcycle validate` still prints `OK` while the agent gets an empty allowlist, which fails closed to *no tools at all*. Every yaml example in this repo used the old key until the v1.7.0 pass; keep new examples on `tools:`.

**Documented here (the MCP-reachable + config surface).** The runtime moved from v1.11.1 → v1.42.0 in ~31 minor releases; this repo's skills cover the primitives below. Surface known to be NOT yet documented, listed so nobody assumes coverage: the **History** tool (`mcp__loomcycle__history`, v1.20.0), **TeamDef** orchestration (`mcp__loomcycle__teamdef`, v1.17–1.19), the **sandbox** toolbox (`mcp__sandbox__*`, v1.23–1.24), **client-executed tools** over WebSocket (v1.16.0), **search providers** (v1.15.0), **resident/interactive sub-agents** (v1.26–1.28), the **RFC BM retention sweeper** (v1.32.0), `Context op=capabilities` (v1.34.0), the per-agent **`skills:`** allowlist (v1.14.0), and `{{tool:…}}` prompt expansion (v1.40.0).
- **RFC AH** (Volume primitive, v1.0.3+): `volumes:` block replaces the legacy jail. `LOOMCYCLE_READ_ROOT/WRITE_ROOT/BASH_CWD` are fatal config-load errors. See `skills/loomcycle-configure/reference/volumes.md`.
- **RFC AI** (Interactive agentic sessions, v1.1.1): runs can be started with `interactive: true` — they park at `end_turn` awaiting operator steering via `POST /v1/runs/{id}/input`; re-attach via `GET /v1/runs/{id}/stream`. **No MCP tool for steering** — use `/loomcycle:steer` (HTTP). See `skills/loomcycle-configure/reference/interactive.md`.
- **RFC AA** (SQL Memory, v1.2.0): a per-scope SQL database facet of the `Memory` tool, enabled by `LOOMCYCLE_SQLMEM_ENABLED=1`. The **prerequisite for Documents** (RFC AK stores chunk structure there). Noted in `reference/env-vars.md` + `reference/document.md`.
- **RFC AJ** (Bashbox, v1.3.0): `Bashbox` — a TRUE in-process gbash sandbox (no OS process, no network, honors `ro` volumes), opt-in via `LOOMCYCLE_BASHBOX_ENABLED=1` + `tools:[Bashbox]`, with an operator host-command fallback. **In-band only — no MCP meta-tool.** See `reference/bashbox.md`.
- **RFC AL** (Path VFS, v1.4.0): name Memory/Volume/Document resources by paths over a `dirents` table; `tools:[Path]`. **Direct MCP meta-tool `mcp__loomcycle__path`.** See `reference/path.md`.
- **RFC AK** (Document, v1.4.0): chunked-graph documents (bodies in Memory, structure in SQL Memory); `tools:[Document]` + `LOOMCYCLE_SQLMEM_ENABLED=1`. **Direct MCP meta-tool `mcp__loomcycle__document`.** ~24 ops now, incl. image assets (v1.30.0), `reorder_chunk` (v1.31.0) and Markdown round-trip. See `reference/document.md`.
- **RFC CC** (Verified writes, v1.54.0): a fact carries `source_quote` (the span it was drawn from); `judge_fact` records a verdict (`supported`/`unclear`/`mistyped`/`unsupported`) which SETS the fact's `confidence` — the server owns the mapping. Below 0.25 a fact is withheld from `list_facts`/`graph_recall` and readable with `include_refuted`; **never deleted**, and an unjudged fact (NULL confidence) stays visible so a judge outage degrades verification rather than emptying memory. `verbatim_answer` quotes a verified fact + its span for lookup questions with no generation; `verification_stats` reports coverage. Enabled per deployment with `memory.consolidation.verify_writes`. The skill reference must NOT cite RFC letters — use version tags there.
- **RFC BL P4b** (Tenant scope for Memory / SQL Memory / Documents, v1.41.0): `scope: tenant` — one keyspace shared by every user and agent in the tenant. **Default-deny and needs TWO grants** (`tenant` in *both* `memory_scopes` and `sql_scopes`), because a document spans both planes and half a document is structure with no text. Also fixed `sql_*` over MCP, which had never worked since v1.2.0. See `reference/document.md`.
- **RFC BL P4c/P4d** (Entity tier + ontology + content retention, v1.42.0): `upsert_chunk` (write by `natural_key`, unique per scope, no `revision`, preserves unspecified fields), `supersede_chunk` (retire without deleting — the old fact stays readable), `graph_recall` (bidirectional ≤2-hop walk, `as_of` time filter). Bi-temporal: `valid_at`/`invalid_at` = world time, `created_at`/`expired_at` = system time. `class: evidential` is exempt from retention pruning. The tenant **ontology** at `/memory/ontology` (tenant scope) is `base seed ⊕ tenant layer` and **inert until an operator confirms it** — flip it in Web UI → Settings → Ontology, or `POST /v1/_ontology`. See `reference/document.md`.
  - ⚠️ Exactly **v1.42.0** has a re-upsert bug: an upsert that omits a field wiped the sidecar, silently un-retiring a superseded fact and downgrading `class: evidential`. Fixed immediately after — recommend v1.42.1+ before relying on the entity tier.
- **RFC AR** (Tenant credentials, v1.10.0): encrypted per-tenant/user secret store; **`LOOMCYCLE_SECRET_KEY` fail-closed gate**. **Direct MCP meta-tool `mcp__loomcycle__credentialdef`** (create/get/list/delete; get/list metadata-only). Consumed as `$cred:<name>` in MCP env/headers + a provider-key override by env-var name. See `reference/credentials.md`.
- **RFC AV** (Usage & cost attribution, v1.10.0) + **RFC AW** (Token budgets, v1.11.0): per-scope monthly soft/hard budgets + a token/cost ledger. **No MCP CRUD tool** — set in the Web UI / `/v1/_limits`, reported via `/v1/_usage` — but a budget crossing surfaces on `spawn_run`/`spawn_runs` (`limits` array; a hard-over run refuses with `token_limit_exceeded`). See `reference/token-limits.md`.
- **RFC AT** (Multimodal image input, v1.7.0): `spawn_run`/`spawn_runs` `segments` accept an `image` content block (`media_type` png/jpeg/gif/webp + base64 `data`, user segment only), gated by model vision support. See `commands/run.md`.

This realises RFC B of loomcycle's v1.x batch — the **UX-movement** counterpart to RFC C's **data-movement** (`loomcycle import claude-code`). C moves authoring content into loomcycle; this plugin moves *runtime control* into the IDE.

**Where it sits in the stack:**

| Repo | Role |
|---|---|
| `loomcycle` (Go) | The runtime; the plugin runs `loomcycle mcp --upstream` as a thin client of it (proxies to `/v1/_mcp`, no second runtime) |
| **this repo** | Claude Code plugin: commands / skills / hooks / MCP wiring |
| `loomcycle-internal` (Gitea) | RFCs / design history — `doc-internal/rfcs/claude-code-plugin.md` is the spec |
| `n8n-nodes-loomcycle` | Sibling integration; the repo-hygiene template this repo borrows from |

## What a Claude Code plugin actually is (NOT npm)

A Claude Code plugin is **markdown + JSON files in a git repo** — there is **no build step, no npm publish, no TypeScript**. (An earlier draft of the RFC assumed npm; that was corrected — see the RFC's 2026-05-29 revision note.) Structure:

- `.claude-plugin/plugin.json` — the plugin manifest (JSON).
- `.claude-plugin/marketplace.json` — self-marketplace so `/plugin marketplace add denn-gubsky/claude-code-plugin-loomcycle` works against this repo directly. **Must live under `.claude-plugin/`** — Claude Code looks for `.claude-plugin/marketplace.json` and errors "Marketplace file not found" if it's at the repo root. So `.claude-plugin/` holds BOTH JSON manifests.
- `.mcp.json` — bundled MCP server config (the loomcycle stdio server). Lives at the repo root (referenced by `plugin.json`'s `mcpServers` path).
- `commands/*.md` — slash commands (frontmatter + body; `$ARGUMENTS`, `$1`, `$2` for args).
- `skills/<name>/SKILL.md` — skills (frontmatter `description` drives auto-invocation).
- `hooks/hooks.json` — hooks (PostToolUse, matched against `mcp__loomcycle__<tool>`).

Distribution: users run `/plugin marketplace add denn-gubsky/claude-code-plugin-loomcycle` then `/plugin install loomcycle`. No npm in the loop.

## Development workflow

1. **Architect** — read the RFC + the loomcycle MCP tool schemas (`internal/api/mcp/tools.go` in the loomcycle repo) before wiring a command/skill. Tool field names are authoritative there, not in the RFC.
2. **Plan** — for anything beyond a one-line fix, write a plan with a verification step.
3. **Feature branch** — `feature-<short>` off `main`. Never commit to `main` directly.
4. **Code** — small, focused, individually-reviewable commits.
5. **Validate** — `claude plugin validate .` must pass. JSON files parse under `jq`; every command/skill has valid frontmatter. (`--strict` flags one accepted false-positive: this `CLAUDE.md` is the repo dev guide, not plugin-runtime context — it auto-loads when you develop the repo and is inert for end-users.)
6. **Tool-name cross-check** — every `mcp__loomcycle__<tool>` reference must match a real tool in loomcycle's `tools.go`. No PREVIEW-only tools.
7. **Self-review** — read the diff cold. No secrets, no dead files.
8. **PR** — one branch, one PR. Title = what it does, ≤72 chars. Body = why → what → tested.
9. **Human review** — wait; never self-merge.

## Security rules — non-negotiable

1. **Never commit secrets.** Bearer tokens / API keys / `LOOMCYCLE_AUTH_TOKEN` are referenced by env-var name or `${user_config.*}` only — never by value. The auth token is a `sensitive` userConfig field (OS keychain), never a repo file.
2. **Never read or write `.env*`** — gitignored. To set a var, tell the user the exact line to add.
3. **Hooks are opt-in.** Both bundled hooks no-op unless their env var is set (`LOOMCYCLE_PLUGIN_TELEMETRY=1`, `LOOMCYCLE_PLUGIN_AUTO_SNAPSHOT=1`). Defaults stay quiet — mirrors loomcycle's default-deny posture.
4. **Targeted git adds.** Never `git add -A` when uncertain; `.env`, `*.pem`, `*.key` must not sweep in.
5. **The plugin never auto-starts or manages loomcycle's lifecycle** and never bundles the binary — it expects `loomcycle` on PATH / `${user_config.bin_path}`.

## Conventions

- Commands take operator-friendly named args; they render results as markdown (tables for lists), not raw JSON.
- Commands/skills are thin: they describe the MCP tool call and the rendering. No logic the runtime should own.
- `spawn_run` takes `segments` (array), not a `prompt` string — wrap the operator's text as one segment. The `/v1/runs` endpoint is SSE (`text/event-stream`); the MCP thin client handles streaming transparently, but direct HTTP clients must keep the connection open for the run to proceed.
- `list_runs` requires `user_id` — commands must supply it (from `/loomcycle-connect` state or `--user`).
- **Versioning tracks loomcycle's vector through the v1.x batch** (not an independent plugin semver). Current version is `v1.1.1`, matching loomcycle. Bump alongside loomcycle's `v0.X.Y` / `v1.X.Y`. Keep `.claude-plugin/plugin.json` + `.claude-plugin/marketplace.json` versions in sync, and tag releases `vX.Y.Z`. `marketplace.json` keeps `ref: main` during development (installs track latest); pin it to the release tag at stable milestones.
- Commit subjects ≤72 chars, imperative, conventional prefix. Close with `Co-Authored-By` when Claude wrote substantial content.

## When in doubt

- The MCP tool contract is in loomcycle's `internal/api/mcp/tools.go` — read it, don't guess field names.
- The plugin spec is at https://code.claude.com/docs/en/plugins.md and `plugins-reference.md`.
- The RFC (`loomcycle-internal/doc-internal/rfcs/claude-code-plugin.md`) is the scope authority.
