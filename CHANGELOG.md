# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/) and the project adheres to
[Semantic Versioning](https://semver.org/).

## [Unreleased]

**`loomcycle-configure` skill — inbound webhooks, third-party MCP servers, and
the second tool-gating layer.** Docs-only; grounded in loomcycle **v0.23.1**
source + a hands-on Gitea-webhook integration run.

### Added
- **`skills/loomcycle-configure/reference/webhooks.md`** — new reference for the
  `webhooks:` block (enable → `POST /v1/_webhooks/{name}`; the
  `enabled: true` + `delivery:` requirement; the **v0.23.1** three-rule
  secret-resolution model — `LOOMCYCLE_*` verify auto-allow, static-yaml
  auto-trust, explicit `LOOMCYCLE_WEBHOOKS_ENV_ALLOWLIST` / scheduler twin — and
  the new `auth.kind: none` trusted-network ingress; `payload_mapping.goal`
  incl. `goal: "$"` to deliver the whole signed body; `recent-deliveries`/`test`
  triage; `tenant_id` trust boundary; tailnet ingress with no relay) **and** the
  `mcp_servers:` block (stdio/http, `mcp__<server>__<tool>`, per-run
  `${run.credentials.*}` headers).

### Changed
- **The `${}` YAML-interpolation allowlist is now documented** (routing.md +
  webhooks.md): only `LOOMCYCLE_`-prefixed names plus the hardcoded
  `BRAVE_API_KEY`/`GITHUB_TOKEN`/`SLACK_BOT_TOKEN`/`PG_DSN`/`REDIS_URL` expand;
  provider keys are deliberately **not** interpolable. Maps the common
  `FOO: "${LOOMCYCLE_FOO}"` workaround for non-prefixed MCP secrets.
- **The two-layer default-deny is now explicit** (SKILL.md safety rule #3 +
  profiles.md §3): capability tools (`Memory`/`Channel`/`AgentDef`/…) need an
  agent-level scope list (`memory_scopes`/`channels`/`agent_def_scopes`) **on top
  of** `allowed_tools` and the operator tool-enable.
- **env-vars.md** — the webhook secret-gate vars documented for **v0.23.1**:
  `LOOMCYCLE_SCHEDULER_ENV_ALLOWLIST` (shared trigger gate) plus the new
  `LOOMCYCLE_WEBHOOKS_ENV_ALLOWLIST` twin and `LOOMCYCLE_WEBHOOKS_ALLOW_UNAUTHENTICATED`;
  added `LOOMCYCLE_CHANNELS_LONGPOLL_CAP_MS` and a `memory_scopes` default-deny note.
- **SKILL.md** — frontmatter description now covers webhooks + third-party MCP so
  the skill auto-loads for those tasks.

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
