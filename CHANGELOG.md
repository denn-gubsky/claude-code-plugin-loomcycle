# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/) and the project adheres to
[Semantic Versioning](https://semver.org/).

## [1.5.0] — 2026-06-23

**Auth: the plugin's `auth_token` is now a first-class tenant identity** —
tracking loomcycle `main` (RFC AG per-principal `/v1/_mcp` + RFC AO
config-declared principals, PRs #549–#555), **pending the next loomcycle tag**.
No new MCP meta-tools — this is an auth/route change. Also retires the legacy
`config_path` userConfig (#18). Version bump `1.4.0 → 1.5.0` (`plugin.json` +
`marketplace.json`).

### Changed

- **A `substrate:tenant` (or config-declared-principal) `auth_token` now drives
  the plugin (RFC AG).** loomcycle's `/v1/_mcp` route moved
  `substrate:admin → substrate:tenant`: previously the MCP transport ran as a
  global operator and the route required admin, so a tenant `lct_…` bearer was
  refused at the door; now it **opens the session** confined to its tenant. A
  per-tool gate withholds the admin-only meta-tools, so with a tenant token the
  run / fanout / runs / cancel / compact / memory / eval / steer commands work
  (tenant-confined) while **`/loomcycle:operator-token` and `/loomcycle:snapshot`
  require an admin token** (a refusal there is expected, not a bug).
- **README** — new *"Tenant & declared-principal tokens (RFC AG + AO)"*
  subsection; the `snapshot` command row + `auth_token` userConfig description
  now flag the admin-only / tenant-confinement behavior; a `1.5.0` compatibility
  row grounded against loomcycle `main` with the build-requirement caveat.
- **README troubleshooting** (#18) — rewrote the "MCP server won't connect"
  bullet, which gave stale advice ("check `config_path` points at a valid
  `loomcycle.yaml`"). The thin client reads no yaml; the bullet now points at the
  real failure modes (binary on PATH/`bin_path`, an upstream reachable at
  `base_url`, `auth_token`).

### Added

- **Declared-principal one-token pattern (RFC AO).** Documented in the README,
  `examples/README.md`, and `commands/operator-token.md`: declare a stable
  `(tenant, subject)` login in `loomcycle.yaml` (`principals:` block, secret in
  `.env.local` via `token_env`) and use the **same** token for both the loomcycle
  Web UI login and the plugin's `auth_token`, so a plugin-driven agent and the UI
  act as one identity — its user-scoped Memory/Documents/Paths line up by
  construction. A static alternative to runtime `operator-token` minting.

### Removed

- **`config_path` userConfig option** (#18) — dropped from
  `.claude-plugin/plugin.json` + the README userConfig table. It was self-titled
  "(legacy)" and reserved: since the plugin became a thin client
  (`mcp --upstream`, v0.21.0) it **loads no config of its own**, and `.mcp.json`
  never referenced it — the running upstream runtime owns its `loomcycle.yaml`.
  The field was a functional no-op; removing it leaves only the three live
  options (`bin_path`, `base_url`, `auth_token`).

### Compatibility

- ⚠️ **Requires a loomcycle build with the RFC AG route flip** for a tenant /
  declared-principal token to open `/v1/_mcp`. On an older build the route is
  still `substrate:admin` and a tenant token 403s — use an admin `auth_token`
  (the plugin's prior behavior, unchanged) or upgrade loomcycle.

## [1.4.0] — 2026-06-22

**Version-vector track to loomcycle v1.4.0** (the plugin tracked v1.1.1; this
catches up through loomcycle's v1.2.0 → v1.4.0 line by documenting the three new
primitives the operator configures + the two that are now directly callable as
MCP meta-tools). The MCP contract change is **additive** — the thin
`loomcycle mcp --upstream` client auto-advertises the new `path` / `document`
meta-tools, so `.mcp.json` needs **no edit**. Version bump
`1.1.1 → 1.4.0` (`plugin.json` + `marketplace.json`).

### Added

- **`reference/bashbox.md`** — the **Bashbox** primitive (RFC AJ, loomcycle
  v1.3.0): a TRUE in-process gbash sandbox (no OS process, no network, honors
  `ro` volumes via an in-RAM overlay), opt-in with `LOOMCYCLE_BASHBOX_ENABLED=1`
  + `allowed_tools:[Bashbox]`. Covers `Bash` vs `Bashbox`, volume binding, the
  operator host-command fallback (`LOOMCYCLE_BASHBOX_FALLBACK_COMMANDS` /
  `…_ALLOWED_ENV`, off by default), and gbash coverage caveats. In-band only — no
  MCP meta-tool.
- **`reference/path.md`** — the **Path** VFS primitive (RFC AL, loomcycle
  v1.4.0): the inode/dirent model, the six ops (`resolve`/`ls`/`stat`/`mkdir`/
  `mv`/`rm`), scopes + grammar, how resources opt into a name, and the direct
  **`mcp__loomcycle__path`** meta-tool. Gate: `allowed_tools:[Path]` (no env flag).
- **`reference/document.md`** — the **Document** primitive (RFC AK, loomcycle
  v1.4.0): chunked-graph documents (bodies in Memory, structure in SQL Memory),
  the 13 ops, optimistic `revision` concurrency, atomic/orphan-free deletes, and
  the direct **`mcp__loomcycle__document`** meta-tool. Two gates:
  `allowed_tools:[Document]` **and** `LOOMCYCLE_SQLMEM_ENABLED=1`.
- **`loomcycle-configure` SKILL.md** — three new primitive sections (Bashbox /
  Path / Document) + reference-file index entries; the skill `description` now
  triggers on Bashbox/Path/Document/SQL-Memory topics.

### Changed

- **`reference/env-vars.md`** — added `LOOMCYCLE_BASHBOX_ENABLED` +
  `LOOMCYCLE_BASHBOX_FALLBACK_COMMANDS` + `LOOMCYCLE_BASHBOX_FALLBACK_ALLOWED_ENV`
  to the built-in tool sandboxes table, and `LOOMCYCLE_SQLMEM_ENABLED` to the
  Memory section (the Document prerequisite).
- **`CLAUDE.md`** — `Current loomcycle version: v1.4.0`; added RFC AA / AJ / AL /
  AK notes.
- **`plugin.json` / `marketplace.json`** — version `1.4.0`; `plugin.json`
  description now mentions the Bashbox sandbox + the Path VFS + Documents.

## [1.1.1] — 2026-06-18

**Version-vector track to loomcycle v1.1.1** — RFC AI interactive agentic
sessions. A run started with `interactive: true` parks at `end_turn` awaiting
operator steering (`POST /v1/runs/{id}/input`) and is re-attachable
(`GET /v1/runs/{id}/stream`). There is **no MCP tool for steering** — it's an
HTTP op. Version bump `1.1.0 → 1.1.1` (`plugin.json` + `marketplace.json`).
*(Backfilled — the bump shipped without a CHANGELOG section at the time.)*

### Added

- **`/loomcycle:steer`** (`commands/steer.md`) — steer a live interactive run
  over HTTP (`POST /v1/runs/{id}/input`); the steering counterpart to `/run`.
- **`reference/interactive.md`** — the interactive-sessions reference: the
  `interactive: true` lifecycle (park at `end_turn` → steer → re-attach by
  `run_id`), the steering + re-attach HTTP ops, and why steering has no MCP tool.

### Changed

- **`commands/run.md`** — documents the `interactive` flag for starting a
  parked, steerable run.
- **`CLAUDE.md`** — `Current loomcycle version: v1.1.1`; RFC AI note.

## [1.1.0] — 2026-06-18

**Version-vector track to loomcycle v1.1.0** (the plugin jumped v0.32.0 →
v1.1.0). **RFC AH Volume primitive.** Phase 3 is a loomcycle **breaking change**:
`LOOMCYCLE_READ_ROOT` / `WRITE_ROOT` / `BASH_CWD` are now fatal config-load
errors — replaced by a `volumes:` block. Version bump `0.32.0 → 1.1.0`
(`plugin.json` + `marketplace.json`). *(Backfilled — the bump shipped without a
CHANGELOG section at the time.)*

### Added

- **`reference/volumes.md`** — the Volume primitive reference: migration table
  from the legacy jail vars, the `volumes:` block + field reference, the
  `VolumeDef` tool + its two gates (`volume_def_scopes` + a `dynamic_root`
  volume), Phase 2a/2b persistent + ephemeral volumes, spawn narrowing, the
  `defaults:` block for `loomcycle validate`, and the volume config-load errors.
- **`loomcycle-configure` SKILL.md** — a Volume primitive section (quick
  migration, VolumeDef gates, `defaults:` requirement) + `volumes.md` in the
  reference index.

### Changed

- **`reference/env-vars.md`** — `READ_ROOT` / `WRITE_ROOT` / `BASH_CWD` marked
  **RETIRED (v1.0.3+, fatal)** with a pointer to `volumes.md`.
- **`reference/routing.md`** — config-load-errors table extended with the Phase 3
  retirement error, volume-reference errors, and the `defaults:` /
  no-provider-resolved fix.
- **`CLAUDE.md`** — `Current loomcycle version: v1.1.0`; RFC AH retirement
  summary; `volumedef` added to the MCP meta-tools list; SSE-streaming caveat for
  `spawn_run`.
- **README Troubleshooting** — added a "wrong binary / stale `bin_path` after
  moving machines or switching OS" entry: the committed `.mcp.json` is a
  `${user_config.*}` placeholder resolved at install time into Claude Code's own
  settings, so a path baked on one machine is stale on another — fix via
  `/plugin` → Configure (`bin_path=loomcycle` for PATH) + restart, **not** by
  hand-editing the live resolved `.mcp.json`.

## [0.32.0] — 2026-06-12

**Version-vector track to loomcycle v0.32.0** (loomcycle jumped v0.25.1 →
v0.32.0). Verified by direct read of loomcycle source at HEAD. The MCP contract
change is **additive** (40 → 42 meta-tools) and the `mcp --upstream` thin-client
wiring is unchanged, so `.mcp.json` needs no edit. Version bump
`0.25.1 → 0.32.0` (`plugin.json` + `marketplace.json`).

### Added

- **`/loomcycle:fanout`** (`commands/fanout.md`) → the new **`spawn_runs`** tool
  (RFC Y, PR #464): fan out up to **32 fresh runs of one agent in a single
  call**, block until all settle, render the index-aligned envelope; a per-child
  failure is reported in-table and never fails the batch. Prefer over N serial
  `/loomcycle:run` calls.
- **`/loomcycle:compact`** (`commands/compact.md`) → the new **`compact_run`**
  tool (PR #465): summarize a **parked** run's history (`{compacted,
  before_tokens, after_tokens, applied}`; `applied ∈ live/marker/noop`). A
  mid-turn run is refused — surfaced as expected, not a bug.
- **`/loomcycle:run --compact`** — sets `spawn_run`'s new optional `compaction`
  field (`{enabled:true}`) for per-run auto-compaction.
- **Per-agent `sampling:` block** (`routing.md`, loomcycle v0.28.0/#447):
  `temperature`/`top_p`/`top_k`/`frequency_penalty`/`presence_penalty`/`seed`/
  `stop`; documents the Anthropic temperature/top_p ⊥ extended-thinking rule.
- **Per-agent `compaction:` block** (`routing.md`, v0.32.0): `enabled` /
  `target_percentage` / `keep_last_n` / `keep_first` / `autocompact_at_pct` /
  `model`; spawn-tree inheritance + the per-run override + `compact_run` trigger.
- **`LOOMCYCLE_RESUME_FANOUT`** (`env-vars.md`, v0.31.0/#457, default OFF) — new
  "Pause / resume" section: durable park+resume of a fan-out parent blocked in
  `parallel_spawn`.

### Fixed / Changed

- **`${}` interpolation deny-list corrected** (`routing.md` + `webhooks.md`,
  loomcycle v0.32.0/#462/exp7-C2): the docs wrongly listed **`PG_DSN`** as
  interpolatable. The real allowlist is any `LOOMCYCLE_`-prefixed name plus
  `BRAVE_API_KEY`/`GITHUB_TOKEN`/`SLACK_BOT_TOKEN`/`REDIS_URL`; `PG_DSN`,
  `LOOMCYCLE_PG_DSN`, and `LOOMCYCLE_AUTH_TOKEN` are now **explicitly denied**
  (infra-secret exfiltration guard), and `\r`/`\n` values are rejected.
- **F39 note** (`webhooks.md`, v0.25.3): runtime-authored stdio MCP servers now
  expand inner `${LOOMCYCLE_*}` at create/fork.
- README compatibility row + commands table; `SKILL.md` description/altitude now
  mention sampling + compaction. Prior version-grounding kept as history.
- **README gains an explicit Install + Update section** with the exact Claude
  Code commands: `/plugin marketplace add …` + `/plugin install loomcycle@loomcycle`,
  and the two-step update (`/plugin marketplace update loomcycle` →
  `/plugin update loomcycle@loomcycle`) with the stale-cache ordering caveat, the
  auto-update toggle, the restart note, and the `#<tag>` pin/rollback form.

## [0.25.1] — 2026-06-10

**Version-vector track to loomcycle v0.25.1** (loomcycle shipped v0.24.0 →
v0.25.0 → v0.25.1 since the plugin's 0.23.5 grounding). Docs-only; re-verified
by direct read of loomcycle source at the **v0.25.1 tag**. The MCP meta-tool
contract is unchanged — the only `internal/api/mcp/tools.go` diff is the
`channel` and `context` tool *descriptions* gaining the new ops below — so the
plugin's commands, skills, and the `mcp --upstream` thin-client wiring need no
behavior change. Version bump `0.23.5 → 0.25.1` (`plugin.json` +
`marketplace.json`).

### Added
- **`LOOMCYCLE_MCP_SPAWN_RUN_TIMEOUT_MS` + `LOOMCYCLE_MCP_MAX_CONCURRENT_CALLS`**
  (`env-vars.md`, new *MCP server (stdio thin client)* section) — the knobs that
  govern the `loomcycle mcp --upstream` process the **plugin itself** runs.
  **v0.24.0** made the `spawn_run` transport timeout (RFC P) finally apply to the
  HTTP / `--upstream` path — i.e. the plugin's exact topology; before that
  `/v1/_mcp` was unbounded. `MAX_CONCURRENT_CALLS` (RFC O, default 16) is the
  concurrent-dispatch slot count.
- **Per-tenant webhook route** (`webhooks.md`) — **v0.24.0 (RFC N)**:
  `POST /v1/_webhooks/{tenant}/{name}` resolves a webhook authored under a
  non-empty tenant (path-authoritative); bare `/{name}` stays shared `""`. With
  the operator action to register the `/{tenant}/` prefix at the sender.
- **RFC S fan-in/fan-out note** (`env-vars.md`, Channels) — **v0.25.0**:
  `Channel.await` / `Channel.broadcast` and `Context op=time` (auto-advertised on
  the MCP `channel`/`context` meta-tools), plus **F37 (v0.25.1)**: the scheduler's
  `on_complete: channel.publish` now publishes under the channel's **declared**
  scope, so a scheduler→channel fan-in can use a natural `scope: global` channel.

### Changed
- README compatibility row + skill version-grounding extended from the v0.23.5
  tag to the **v0.25.1** tag. Prior v0.23.x grounding kept as accurate history.

## [0.23.5] — 2026-06-09

**Re-verification + version-grounding pass against loomcycle's real release
tags, plus the v0.23.3–v0.23.5 findings.** Docs-only; every claim below was
confirmed by direct read of loomcycle source at the **v0.23.5 tag** (not the
experiment-era catalog, which still marks several of these "open"). The headline
correction: loomcycle shipped **v0.23.0 → v0.23.3 → v0.23.4 → v0.23.5 with no
`v0.23.1`/`v0.23.2` tag**, so the prior docs' "post-v0.23.0 `main`, ships next
release" hedging is replaced everywhere with the concrete tag + PR number.

Version-vector jump **0.23.2 → 0.23.5**, tracking loomcycle's latest tag.

### Added
- **Robust `anthropic-oauth-dev` setup walkthrough** (`routing.md`) — the
  experiment-validated technique end-to-end: enable
  (`LOOMCYCLE_ANTHROPIC_OAUTH_DEV_ENABLED=1`) → `loomcycle anthropic login`
  (token at `~/.config/loomcycle/anthropic-oauth.json`, `0600`, outside repo+DB)
  → route it **last** in `provider_priority` + pin per-agent → verify health with
  `loomcycle anthropic status --probe`. Documents the two **v0.23.3** robustness
  fixes: **F6/#392** (`--probe`/`--verify` does a free server-side refresh that
  rotates+heals; plain `status` is local-metadata-only and can read "valid" on a
  revoked token) and **F7/#391** (cross-process `flock` + reload-before-refresh,
  so concurrent loomcycle processes no longer corrupt the shared token →
  `invalid_grant` forced re-login). Both verified in
  `internal/providers/anthropic_oauth_dev/{refresh,lock_unix}.go` +
  `internal/cli/anthropic.go`.
- **`LOOMCYCLE_MCP_ALLOW_DYNAMIC_STDIO` row** (`env-vars.md`) — **v0.23.3, F31/#405**:
  runtime-authored (`mcpserverdef`) MCP servers may use `transport: stdio` only
  behind this default-OFF flag (it runs an arbitrary local command); http /
  static-yaml-stdio unaffected.
- **F30 note** (`webhooks.md`) — **v0.23.3/#403**: a `delivery: spawn` webhook can
  now resolve a **runtime-authored (AgentDef-substrate) agent**, not just a static
  yaml `agents:` entry (webhookdef stamps `tenant_id` from the run identity). Fixes
  the old `rejected_spawn_setup: unknown agent` on fully-dynamic loops. + gotcha row.
- **F33 note** (`webhooks.md`) — **v0.23.5/#409**: a single-tool "notifier" agent
  whose `allowed_tools` is only `mcp__server__*` now actually fires — dynamic-MCP
  tools are **advertised at run start**, so the model emits a real `tool_call`
  instead of inert `<function_calls>` text (the silent no-op). + gotcha row +
  the v0.23.3/v0.23.4 "add one native tool (`Context`)" workaround.
- **F32 secrets-at-rest security rule** (`SKILL.md` rule #5) — **v0.23.4**:
  loomcycle persists agent tool I/O; v0.23.4 masks secret-shaped values to
  `[redacted:<ENV_NAME>]` before persisting (value-based; keeps the env-var name).
  Still advise out-of-band secret passing; redaction is an at-rest guard only (a
  `Bash` child still inherits the live `LOOMCYCLE_*` env).

### Changed
- **Version grounding pinned to real tags** across `SKILL.md` / `routing.md` /
  `env-vars.md` / `webhooks.md` / `README.md`: F23 (#385), F24, F28, F18 (#388),
  F21 (#389), the `.env.local`/`.env.insecure` split (#399), F29 (#404), F30
  (#403), F31 (#405) → **v0.23.3**; F32 → **v0.23.4**; F33 → **v0.23.5**. The
  v0.23.0-brew fallback is kept explicit for each.
- **`anthropic-oauth-dev` provider row** (`routing.md`) + the oauth-dev block
  (`env-vars.md`) now cite v0.23.3/#391/#392 instead of "post-v0.23.0", and note
  the token's location keeps it clear of the F32 at-rest path.
- **F21 boot-warning re-verified as shipped** (was marked "open" in the
  experiment catalog) — `internal/config/config.go` emits it into `cfg.Warnings` /
  `loomcycle validate` as of v0.23.3/#389; `SKILL.md` rule #3 updated.
- **`webhooks.md` MCP section** corrected: the stale "stdio cannot be registered
  at runtime" line now reflects F31 (gated dynamic stdio).
- **`plugin.json` + `marketplace.json`** bumped 0.23.2 → 0.23.5 (kept in sync).

## [0.23.2] — 2026-06-08

**`loomcycle-configure` skill — inbound webhooks, third-party MCP servers, the
two-layer tool gate, and a reconciliation pass against loomcycle `main`.**
Docs-only; grounded in loomcycle **`main` (post-v0.23.0)** source + a hands-on
Gitea-webhook integration run. *(There is **no `v0.23.1` tag** — the
trigger/auth/env fixes below landed on `main` after the v0.23.0 tag and ship in
the next loomcycle release; the **v0.23.0 brew binary does not have them**. Each
is flagged inline so an operator knows which build they need.)*

Version-vector jump **0.21.0 → 0.23.2**, tracking loomcycle's 0.23 line. Also
**re-syncs `marketplace.json` (0.20.3 → 0.23.2)** with `plugin.json` — the two had
drifted since 0.21.0 (the marketplace manifest's version wasn't bumped then).

### Added
- **`skills/loomcycle-configure/reference/webhooks.md`** — reference for the
  `webhooks:` block (enable → `POST /v1/_webhooks/{name}`; the `enabled: true` +
  `delivery:` requirement + **post-v0.23.0 static-webhook boot-validation**, F24;
  the three-rule secret-resolution model — `LOOMCYCLE_*` verify auto-allow,
  static-yaml auto-trust, explicit `LOOMCYCLE_WEBHOOKS_ENV_ALLOWLIST` / scheduler
  twin, F23; `auth.kind: none` trusted-network ingress; `payload_mapping.goal`
  with the **post-v0.23.0 raw-body default**, F28 — no `goal` mapping now hands
  the agent the whole signed event instead of an empty prompt; `recent-deliveries`
  /`test` triage; `tenant_id` trust boundary; tailnet ingress) **and** the
  `mcp_servers:` block (stdio/http, `mcp__<server>__<tool>`, per-run
  `${run.credentials.*}` headers, the `${}` interpolation allowlist).

### Changed
- **Version grounding corrected.** A prior draft labeled the F23 fix "v0.23.1";
  no such tag exists. All trigger/auth/env fixes are relabeled **"post-v0.23.0
  `main`"** across webhooks.md / env-vars.md / SKILL.md / profiles.md / routing.md,
  with the v0.23.0-brew fallback kept explicit.
- **`.env.local` / `.env.insecure` split documented** (loomcycle #399): secrets
  in `.env.local`, non-secret operational config (incl. trigger-credential
  allowlist *names*) in `.env.insecure`, sourced insecure-first. SKILL.md safety
  rule #1 now permits reading/editing `.env.insecure` while keeping `.env.local`
  off-limits; env-vars.md intro carries the file-split table + `LOOMCYCLE_ENV_FILE`;
  profiles.md routes each var to its file.
- **The two-layer default-deny + post-v0.23.0 boot warnings** (SKILL.md rule #3,
  profiles.md §3): capability tools (`Memory`/`Channel`/`Evaluation`/
  `Interruption`/`AgentDef`/…) need an agent-level scope gate on top of
  `allowed_tools`; loomcycle now emits a boot `WARNING:` when a gate is missing
  (F21).
- **env-vars.md** — webhook secret-gate vars (`LOOMCYCLE_SCHEDULER_ENV_ALLOWLIST`
  + the `LOOMCYCLE_WEBHOOKS_ENV_ALLOWLIST` twin + `LOOMCYCLE_WEBHOOKS_ALLOW_UNAUTHENTICATED`);
  the `LOOMCYCLE_CHANNELS_LONGPOLL_CAP_MS` row gains the post-v0.23.0 `wait_ms`
  truncation warning + `max_iterations` interaction (F22); the metrics row notes
  `_COLLECT_SYSTEM` for host/co-tenant pressure (F19); the anthropic-oauth-dev
  note gains `anthropic status --probe` (F6) + the cross-process refresh lock (F7).
- **profiles.md** — file-tool relative-paths-resolve-against-process-CWD caveat
  (launch loomcycle from the jail root; F13) and the metrics `_COLLECT_SYSTEM` knob.
- **The `${}` YAML-interpolation allowlist** (routing.md + webhooks.md): only
  `LOOMCYCLE_`-prefixed names plus the hardcoded `BRAVE_API_KEY`/`GITHUB_TOKEN`/
  `SLACK_BOT_TOKEN`/`PG_DSN`/`REDIS_URL` expand; provider keys are deliberately
  **not** interpolable. Maps the common `FOO: "${LOOMCYCLE_FOO}"` workaround.
- **SKILL.md** — frontmatter description covers webhooks + third-party MCP so the
  skill auto-loads for those tasks.
- **README** — note that a `settings.json` env change (e.g. a new `LOOMCYCLE_*`
  for the MCP server) needs a **full Claude Code restart**, not `/reload-plugins`
  (F12).

### Notes
- loomcycle's MCP meta-tool surface grew on `main`: a new **`channeldef`** tool
  (channel CRUD over MCP — F20) and a fuller **`register_agent`** schema carrying
  `channels` / `evaluation_scopes` / `interruption` / `max_iterations` gates
  (F14). No plugin command wraps these yet — flagged for a later command/surface
  pass, not part of this docs round.

## [0.21.0] — 2026-06-06

**Thin-client MCP wiring — the plugin no longer boots a second loomcycle
runtime (loomcycle RFC R single-runtime invariant).**

Previously the plugin launched `loomcycle mcp --config … --no-http`, which booted
a *full second runtime* (listener muted) alongside your real one. Two runtimes
sharing one state each have their own in-process event bus, so a resolved
interruption or a cancel raised on one never wakes a run owned by the other —
the root of the "session wedged / interruption never resumes" failures, plus
accumulating rogue runtimes.

### Changed
- **`.mcp.json` now launches `loomcycle mcp --upstream ${base_url}`** — a thin
  stdio↔`/v1/_mcp` proxy to the loomcycle runtime already running at `base_url`.
  It boots **no runtime of its own** (no providers, scheduler, sweepers, port).
  The `auth_token` is sent to the upstream as `LOOMCYCLE_MCP_UPSTREAM_TOKEN`.
- **`base_url` is now required** (the upstream runtime the plugin proxies to);
  `config_path` is legacy/reserved (the thin client loads no config).
- **Multi-tenant is simpler:** the default stdio transport now routes through the
  principal-enforced `/v1/_mcp`, so authority is governed by the `auth_token`
  principal — set a scoped `lct_…` token to confine the plugin to one tenant; no
  `.mcp.json` swap needed. The HTTP example remains a valid alternative transport.

### Breaking
- **Requires a loomcycle build that supports `loomcycle mcp --upstream`** (RFC R).
  On an older build the flag is unknown and the server errors at launch — pin
  0.20.x or upgrade loomcycle.
- **A loomcycle instance must be running at `base_url`** — the plugin no longer
  starts one. Start it separately (`loomcycle` / `brew services` / Docker).

## [0.20.3] — 2026-06-04

**Fix: "Duplicate hooks file detected" on load.** Newer Claude Code builds
auto-load the standard `hooks/hooks.json`, then errored because `plugin.json`
*also* referenced it via `"hooks": "./hooks/hooks.json"` — loading the same file
twice. The plugin's commands/skills/MCP server still loaded, but the hooks
failed and the plugin showed a load error.

### Fixed

- **Removed the `"hooks": "./hooks/hooks.json"` field from `plugin.json`.** The
  standard `hooks/hooks.json` is discovered and loaded automatically; per Claude
  Code's guidance, `manifest.hooks` should reference *additional* hook files
  only, never the standard one. The PostToolUse hooks (`capture-run-telemetry`,
  `auto-snapshot-on-error`) are unchanged and still load — they remain env-gated
  no-ops unless `LOOMCYCLE_PLUGIN_TELEMETRY=1` / `LOOMCYCLE_PLUGIN_AUTO_SNAPSHOT=1`.

## [0.20.2] — 2026-06-04

**Fix: the bundled MCP server no longer grabs the default `127.0.0.1:8787`
port.** `loomcycle mcp` boots a full runtime that — by default — also binds the
HTTP/SSE listener on `LOOMCYCLE_LISTEN_ADDR` (default `127.0.0.1:8787`). Because
the plugin launches one such server per enabled session, it would collide with a
separately-running loomcycle instance on the same host (a real server started
via `loomcycle`/`brew services`, or another project's). The symptom: an
open-mode MCP runtime silently squatting on IPv4 `127.0.0.1:8787`, intercepting
traffic meant for the operator's authenticated instance — and it kept coming
back because the IDE session relaunches it.

### Fixed

- **`.mcp.json` now launches `loomcycle mcp … --no-http`.** The plugin drives
  the server entirely over **stdio**, so the runtime needs no TCP port. The
  `--no-http` flag (honoured only in `mcp` subcommand mode) suppresses the HTTP
  listener, so the MCP server binds **no port at all** — eliminating the
  collision with `8787` (and any other port) rather than just relocating it.
  Requires a loomcycle build that supports `--no-http`.

### Notes

- The optional `auto-snapshot-on-error` hook still talks to your **standalone**
  loomcycle server via `base_url` (default `http://127.0.0.1:8787`); that is a
  separate process from the plugin's stdio MCP server and is unaffected.

## [0.20.1] — 2026-06-04

**Fix: the plugin was not installable.** `/plugin marketplace add
denn-gubsky/claude-code-plugin-loomcycle` failed with *"Marketplace file not
found at …/.claude-plugin/marketplace.json"* (and the follow-on
`/plugin install loomcycle` → *"not found in any marketplace"*).

### Fixed

- **Moved `marketplace.json` → `.claude-plugin/marketplace.json`.** Claude Code
  requires the marketplace manifest under `.claude-plugin/` (alongside
  `plugin.json`); it was at the repo root, so the manifest was never found. This
  broke install for every user since the first release — the misplaced file had
  also escaped `claude plugin validate`, which only validates the marketplace
  manifest once it's in the canonical location.
- **`plugins[0].author` is now an object** (`{name, url}`), not a bare string —
  the marketplace schema requires an object. This second error surfaced only
  after the move (the validator could finally see the file). `claude plugin
  validate .` now passes clean, and `claude plugin marketplace add` succeeds.
- Added a top-level marketplace `description`.

### Changed

- CLAUDE.md corrected: it claimed *"ONLY `plugin.json` lives under
  `.claude-plugin/`"* — both JSON manifests do. Updated the structure +
  versioning sections so the mistake isn't reintroduced.

## [0.20.0] — 2026-06-03

**Version-vector track to loomcycle v0.20.0**, and the ship vehicle for the
`loomcycle-configure` skill (previously `[Unreleased]`). loomcycle advanced
v0.17.0 → v0.20.0 with runtime-side, back-compatible work: `MCPServerDef`
auto-discovery + idempotent create/rediscover (no version-spam) and inner
`${LOOMCYCLE_*}` expansion at dynamic create/fork; inline code-js `code_body`
ingestion via AgentDef (no host-FS bind); a non-secret run **metadata** channel
(run input + delivery, with WebHook/Scheduler sourcing); autonomous firing of
static yaml schedules; per-run advertisement of post-boot substrate tools; and
`init --with-token` + auto-loaded `auth.env` for tighter bootstrap.

**The MCP meta-tool surface is unchanged** — `internal/api/mcp/tools.go` is
byte-identical between v0.17.0 and v0.20.0 (40 tools). All plugin commands,
skills, and the spawn/segment shape were re-verified and need no change; this is
a pure tracking bump.

### Added

- **`loomcycle-configure` skill** — guided authoring of `loomcycle.yaml` +
  environment. Covers provider routing (`provider_priority` / `tiers` /
  `models:` aliases), `user_tiers` plan/privacy overlays, `fallback_on_error`,
  the grouped `LOOMCYCLE_*` env-var catalogue, and six deployment profiles
  (brew + in-system · containerized · true sandbox · server · multi-tenant ·
  cloud) as presets on a trust × scale grid. Progressive-disclosure layout: a
  lean `SKILL.md` plus `reference/{routing,profiles,env-vars}.md` read on
  demand. Enforces the plugin's secret discipline — it edits `loomcycle.yaml`
  but **never** reads/writes `.env*` (it prints the env lines for the operator)
  and never puts a key value in any file. Grounded in loomcycle's
  `docs/CONFIGURATION.md`, `docs/PROVIDERS.md`, `.env.example`, and the
  multi-replica / Docker docs at v0.17.0.

## [0.17.0] — 2026-06-02

**Version-vector track to loomcycle v0.17.0** — OSS multi-tenant authorization
(RFC L). loomcycle v0.17.0 mints per-principal bearer tokens
(`OperatorTokenDef`), each bound to an authoritative `{tenant_id, subject,
allowed_scopes}` resolved from the token. It exposes a new `operatortokendef`
MCP meta-tool; this release wraps it. All other v0.16.1 → v0.17.0 changes are
back-compatible — the existing seven commands and the spawn/segment shape were
re-verified against loomcycle's `internal/api/mcp/tools.go` at v0.17.0 and
needed no change.

### Added

- **`/loomcycle:operator-token <create|rotate|retire|get|list>`** — wraps the
  `operatortokendef` meta-tool. `create` mints a token bound to
  `{tenant_id (required), subject, scopes}`; `rotate` mints a replacement with
  a grace window; `retire` / `get` / `list` are metadata-only. The command
  enforces strict one-time-plaintext handling: `create` / `rotate` surface the
  secret **once** with a "store it now, not retrievable later" warning, never
  persist it to disk, and never re-echo it. Documents the `substrate:admin`
  scope requirement on the calling bearer and the default-deny `--scopes`
  posture.
- **`examples/mcp-http-tenant.json`** — a drop-in HTTP-transport config that
  points the `loomcycle` server at loomcycle's principal-enforced
  `POST /v1/_mcp` endpoint, so the plugin can run **confined to one tenant**
  under a scoped `lct_…` bearer (rather than the stdio transport's
  single-operator admin posture). A swap of the existing server, not a second
  server — the commands work unchanged under the token's principal.

### Documentation

- README gains a **Multi-tenant authorization, isolation & token rotation**
  section: the stdio-(admin) vs HTTP-(principal) trust model, when to use each,
  and a token-rotation runbook covering the legacy-`LOOMCYCLE_AUTH_TOKEN`
  disable on first admin token (which 401s the HTTP-authed auto-snapshot hook)
  and the MCP-restart needed to pick up a rotated bearer.

### Notes

- Operator-token ops are **operator-admin only**, but the posture is
  transport-dependent: over **stdio** (default) the MCP server is
  single-operator by construction and *always* has admin — no scope refusal
  regardless of `auth_token`. Over the **HTTP** transport the `lct_…` bearer's
  principal must carry `substrate:admin`; a narrow bearer gets a `scope` refusal
  (by design, not a bug). The earlier note implying stdio could refuse on scope
  was corrected.

## [0.16.1] — 2026-06-01

**Version-vector catch-up to loomcycle v0.16.1**, plus new memory surface. The
plugin had stayed at 0.12.8 while loomcycle advanced through v0.13–v0.16.1
(A2A, Input Webhooks, Memory ranking + `MemoryBackendDef`, the MemoryLayer, and
the synthetic `code-js` provider). Per the versioning convention the plugin
tracks loomcycle's vector — this release re-syncs it.

All v0.12.x → v0.16.x meta-tool additions are **back-compatible**, so the
existing six commands and the spawn/segment shape required no change. Every
`mcp__loomcycle__<tool>` reference was re-verified against loomcycle's
`internal/api/mcp/tools.go` at v0.16.1.

### Added

- **`/loomcycle:memory <recall|search|add|get|set|list>`** — wraps the `memory`
  meta-tool. Surfaces the v0.16 MemoryLayer (`add` conversation facts /
  natural-language `recall`) and v0.9 vector `search`, alongside plain
  key/value `get`/`set`/`list`. `--scope=agent|user` selects the keyspace
  (default `agent`). Documents the `capability_unsupported` refusal that
  `add`/`recall` return against the default (non-memory-layer) backend — a
  config signal, not a plugin bug.

### Changed

- **`loomcycle-diff-agentdefs` skill** now recognises `provider: code-js`
  (v0.16 RFC J synthetic code agents): such a version runs operator JavaScript
  at zero token cost, so its `model`/`effort`/`max_tokens` are inert, and a
  `provider` flip into/out of `code-js` is called out as a first-order change.
- Version bumped across `plugin.json`, `marketplace.json`, README compat row.

## [0.12.8] — 2026-05-29

**First release.** The Claude Code-side UX layer for loomcycle (RFC B). Wraps
loomcycle's `loomcycle mcp` stdio server and its meta-tools; zero loomcycle-side
code changes.

The plugin tracks loomcycle's version vector (0.12.x) during the v1.x RFC
batch; **v1.0.0 is reserved for the batch release** once the remaining RFCs land.

### Added

- **Pre-wired MCP server** (`.mcp.json` + manifest `mcpServers`) launching
  `loomcycle mcp --config <config_path>`. Install-time `userConfig` for
  `bin_path`, `config_path`, sensitive `auth_token` (OS keychain), `base_url`.
- **Marketplace** (`marketplace.json`) so the plugin installs from this repo via
  `/plugin marketplace add denn-gubsky/claude-code-plugin-loomcycle`.
- **6 slash commands** (`/loomcycle:connect|run|runs|cancel|snapshot|eval`)
  wrapping `spawn_run`, `list_runs`, `cancel_run`, the four snapshot tools, and
  `evaluation` (`op=submit`). Results render as operator-readable markdown.
- **4 skills** — `loomcycle-spawn-evaluator`, `loomcycle-replay-failed-run`,
  `loomcycle-diff-agentdefs`, `loomcycle-import-claude-code`.
- **2 opt-in PostToolUse hooks** — `capture-run-telemetry`
  (`LOOMCYCLE_PLUGIN_TELEMETRY=1`) and `auto-snapshot-on-error`
  (`LOOMCYCLE_PLUGIN_AUTO_SNAPSHOT=1`). Both no-op by default and always exit 0.

### Notable design decisions

- **Real Claude Code plugin spec, not npm.** The originating RFC assumed an
  npm-published `plugin.yaml` (mirroring `n8n-nodes-loomcycle`). Claude Code
  plugins are actually git-distributed markdown + JSON via a marketplace, with
  no build step — so this repo has no `package.json`, no `dist/`, no TypeScript.
  The RFC was corrected to match (see its 2026-05-29 revision note).
- **`spawn_run` takes `segments`, not a `prompt` string.** Commands and skills
  wrap operator text as `[{role:"user", content:[{type:"trusted-text", text}]}]`
  — the runtime's real `PromptSegment` shape.
- **Secrets stay out of the repo.** The API bearer is a `sensitive` userConfig
  (OS keychain); the auto-snapshot hook reads `LOOMCYCLE_AUTH_TOKEN` from the
  environment rather than from a substituted command string.
- **Hooks default-deny.** Both ship disabled and gate on an env var, mirroring
  loomcycle's own trust posture.

### Verified

- `claude plugin validate .` passes (one informational warning: the root
  `CLAUDE.md` is a dev guide, intentionally not loaded as plugin context).
- All JSON (`plugin.json`, `.mcp.json`, `marketplace.json`, `hooks.json`) parses
  under `jq`; every command/skill has valid frontmatter; hook scripts pass
  `bash -n`.
- All `mcp__loomcycle__<tool>` references cross-checked against loomcycle
  `internal/api/mcp/tools.go`.
