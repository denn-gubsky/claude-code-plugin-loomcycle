<p align="center">
  <img src=".github/social-preview.png" alt="loomcycle plugin for Claude Code" width="720">
</p>

# loomcycle plugin for Claude Code

Drive a [loomcycle](https://github.com/denn-gubsky/loomcycle) agentic runtime
from inside Claude Code — spawn and cancel runs, list them, snapshot the
runtime, submit evaluations, inspect agent memory, and import `.claude/` repos
— all through slash commands and skills, with no JSON pasting.

This plugin is the **UX layer** over loomcycle's `loomcycle mcp` stdio server.
loomcycle exposes its primitives as MCP meta-tools (`spawn_run`, `cancel_run`,
`list_runs`, snapshot ops, `evaluation`, `agentdef`, …); this plugin pre-wires
that server and wraps the common workflows in operator-friendly commands.

> **Why a plugin and not just `loomcycle mcp install`?** The MCP server is
> plumbing — you'd still have to discover each tool, compose the right `op`
> discriminator, and remember each input schema. The plugin is the kitchen:
> installed once, it pre-wires the server and gives you `/loomcycle:run`,
> `/loomcycle:runs`, etc.

## Prerequisites

- **loomcycle on PATH** (or set `bin_path` at install). The plugin does **not**
  bundle or start the loomcycle binary — install it separately (Homebrew /
  Docker / release binary) and have an instance reachable.
- **A `loomcycle.yaml`** the `loomcycle mcp` server will load.
- Claude Code v2.1+ (plugin support).

## Install

Run these in Claude Code (the marketplace registers under the name `loomcycle`,
declared in `marketplace.json`):

```text
/plugin marketplace add denn-gubsky/claude-code-plugin-loomcycle
/plugin install loomcycle@loomcycle
```

`loomcycle@loomcycle` reads as "the **loomcycle** plugin from the **loomcycle**
marketplace" — the `@loomcycle` suffix disambiguates if you have other
marketplaces installed (the bare `/plugin install loomcycle` also works when
it's unambiguous).

At install you'll be prompted for:

| userConfig | Purpose | Default |
|---|---|---|
| `bin_path` | Path to the loomcycle binary | `loomcycle` (PATH lookup) |
| `base_url` | **Upstream runtime URL** the plugin proxies to — a loomcycle instance must be running here | `http://127.0.0.1:8787` |
| `auth_token` | Bearer sent to the upstream (as `LOOMCYCLE_MCP_UPSTREAM_TOKEN`); its principal governs what the plugin can do. OS keychain, **never** the repo | — |
| `config_path` | *Legacy / reserved* — the thin client loads no config of its own | `loomcycle.yaml` |

The bundled MCP server entry (`.mcp.json`) launches
`loomcycle mcp --upstream <base_url>` automatically when the plugin is enabled.
This is a **thin client** (loomcycle RFC R): it runs a stdio↔`/v1/_mcp` proxy to
the loomcycle runtime already running at `base_url` and **boots no runtime of its
own** — no providers, scheduler, sweepers, or port to bind.

> **Single-runtime invariant.** Earlier versions launched
> `loomcycle mcp --config … --no-http`, which booted a *full second runtime*
> (listener muted) next to your real one. Two runtimes sharing one state each
> have their own in-process event bus, so a resolved interruption or a cancel
> raised on one never wakes a run owned by the other — the source of the
> "session wedged / interruption never resumes" failures. The thin client fixes
> this structurally: there is exactly one runtime, and the plugin is its client.
> **You must have a loomcycle instance running at `base_url`** (start it
> separately via `loomcycle`/`brew services`/Docker); the plugin no longer
> starts one. Requires a loomcycle build that supports `loomcycle mcp --upstream`.

## Update

The marketplace tracks `main`, so updating is two steps — **refresh the
marketplace cache from git, then update the installed plugin**:

```text
/plugin marketplace update loomcycle
/plugin update loomcycle@loomcycle
```

- The first command re-pulls `marketplace.json` + the plugin from GitHub; the
  second installs the new version. **Run them in this order** — `/plugin update`
  alone won't see a new release until the marketplace cache is refreshed (a stale
  cache is also why a fresh `add` can appear to "do nothing" after a release).
- Re-running `/plugin install` on an already-installed plugin does **not**
  upgrade it — use `/plugin update`.
- Prefer hands-off? Open `/plugin` → **Marketplaces** → select `loomcycle` →
  enable **auto-update**, and it pulls new releases at startup.
- After updating, **restart Claude Code** so the bundled `.mcp.json` (the
  `loomcycle mcp --upstream` server) is relaunched with any wiring changes.

To pin or roll back to an exact release, add the marketplace at a tag and
reinstall:

```text
/plugin marketplace add denn-gubsky/claude-code-plugin-loomcycle#v0.32.0
/plugin install loomcycle@loomcycle
```

## Commands

All commands are namespaced under the plugin name: `/loomcycle:<command>`.

| Command | Wraps | Purpose |
|---|---|---|
| `/loomcycle:connect [--user=<id>] [--bearer=<tok>] [--base-url=<url>] [--persist]` | (session state) | Set the active loomcycle identity reused by later commands. The bearer is the per-run `user_bearer`, not the API token. |
| `/loomcycle:run <agent> [--user=<id>] [--compact] <prompt…>` | `spawn_run` | Spawn a run; the result (final text + `agent_id` cancel handle + `run_id`) streams back. `--compact` turns on per-run context-compaction (≥ v0.32). |
| `/loomcycle:fanout <agent> [--count=N] [--user=<id>] <prompt…>` | `spawn_runs` | Fan out up to 32 concurrent runs of one agent in a single call; renders the index-aligned results table (≥ v0.32). |
| `/loomcycle:compact <agent_id> [--reason=<text>]` | `compact_run` | Summarize a **parked** run's history to free context, then continue (≥ v0.32). |
| `/loomcycle:runs [--user=<id>] [--status=<s>] [--limit=<n>]` | `list_runs` | List recent runs as a table. `user_id` is required (set it once via connect). |
| `/loomcycle:cancel <agent_id> [--reason=<text>]` | `cancel_run` | Cancel a running agent; cascades to sub-agents; idempotent. |
| `/loomcycle:snapshot <create\|list\|restore\|delete> [id]` | the 4 snapshot tools | Runtime snapshot ops from the IDE. Restore/delete confirm first. **Admin token only** — runtime-global, withheld from a `substrate:tenant` session (RFC AG). |
| `/loomcycle:eval <run_id> <score> [--rationale=<text>]` | `evaluation` (`op=submit`) | Record an evaluation against a completed run. loomcycle never auto-promotes on score. |
| `/loomcycle:memory <recall\|search\|add\|get\|set\|list> [--scope=agent\|user] [args…]` | `memory` | Inspect/edit an agent's memory: semantic `recall`/`search`, `add` conversation facts, or plain key/value. `add`/`recall` need a memory-layer backend (v0.16). |
| `/loomcycle:operator-token <create\|rotate\|retire\|get\|list> [--name=<n>] [--tenant=<id>] [--subject=<s>] [--scopes=a,b]` | `operatortokendef` | Mint/rotate/retire per-principal bearer tokens (RFC L multi-tenant auth, loomcycle ≥ v0.17). Operator-admin only; create/rotate show the plaintext **once**. |

## Skills

Skills load automatically when their description matches what you're doing:

| Skill | What it does |
|---|---|
| `loomcycle-spawn-evaluator` | Spawn an independent evaluator agent to score the current transcript or a named run, then offer to record the score. |
| `loomcycle-replay-failed-run` | `get_run` → diagnose the failure → re-spawn with the smallest fix. Stops after a repeat failure and recommends an operator-side config fix. |
| `loomcycle-diff-agentdefs` | Diff two AgentDef versions by `def_id` (`system_prompt` / `allowed_tools` / `max_tokens` / lineage). Descriptive only. |
| `loomcycle-import-claude-code` | Guided wrapper over `loomcycle import claude-code` (RFC C2): dry-run → review the lossy report → `--write` → `validate`. |
| `loomcycle-configure` | Author/tune `loomcycle.yaml` + env: providers, model tiers, `user_tiers`, fallbacks, the env-var catalogue, six deployment profiles (brew/in-system · containerized · true sandbox · server · multi-tenant · cloud), and the runtime primitives — filesystem **Volumes** (RFC AH), the **Bashbox** in-process sandbox (RFC AJ), the **Path** VFS (RFC AL), and chunked-graph **Documents** (RFC AK). Never writes the env file — prints the lines. |

## Optional hooks

Both hooks ship **disabled** — they no-op unless you opt in with an env var.

| Hook | Enable with | Action |
|---|---|---|
| capture-run-telemetry | `LOOMCYCLE_PLUGIN_TELEMETRY=1` | Append `{ts, run_id, agent_id}` to `${CLAUDE_PLUGIN_DATA}/run-telemetry.jsonl` after each `spawn_run`. |
| auto-snapshot-on-error | `LOOMCYCLE_PLUGIN_AUTO_SNAPSHOT=1` | On a state-mutating tool error, run `loomcycle snapshot --description pre-error-<ts>`. Needs `LOOMCYCLE_AUTH_TOKEN` (and optionally `LOOMCYCLE_BASE_URL`) exported in the shell that launches Claude Code — the hook reads the bearer from the environment, never from a substituted command string. |

## Multi-tenant authorization, isolation & token rotation

loomcycle v0.17.0 (RFC L) adds per-principal bearer tokens (`OperatorTokenDef`,
`lct_…`), each bound to an authoritative `{tenant_id, subject, scopes}` resolved
**from the token**. How much of that the plugin enforces depends entirely on
**which transport** the bundled MCP server uses:

Since 0.21.0 the default stdio transport is a **thin client** that proxies to the
runtime's `POST /v1/_mcp` — the **same principal-enforced path** as the direct
HTTP transport. So the plugin's authority is governed by the **token's principal
on the upstream**, regardless of transport:

| Transport | What the plugin is | Isolation / scopes |
|---|---|---|
| **stdio thin client** (default `.mcp.json`: `loomcycle mcp --upstream`) | a proxy to the runtime's `/v1/_mcp` | **Principal-enforced by `auth_token`.** An admin token (or an open-mode runtime) → full authority; a scoped `lct_…` token → confined (`applyPrincipal` overrides wider wire values; under-scoped calls get a `scope` refusal; reads tenant-filtered). |
| **HTTP** (`POST /v1/_mcp` direct, see [examples/mcp-http-tenant.json](examples/mcp-http-tenant.json)) | same `/v1/_mcp`, direct transport (no local stdio process) | Same principal enforcement. |

**To confine the plugin to one tenant**, just set `auth_token` to a scoped
`lct_…` bearer in the default config — no `.mcp.json` swap needed any more, since
the default already routes through the principal-enforced `/v1/_mcp`. (The
[HTTP example](examples/mcp-http-tenant.json) remains a valid alternative
transport if you'd rather not run the stdio proxy process.)

### Tenant & declared-principal tokens (loomcycle RFC AG + AO)

A recent loomcycle line (RFC AG + AO, post-v1.4.0) makes the `auth_token` you
hand the plugin a **first-class tenant identity**, not just an admin key:

- **`/v1/_mcp` is now a `substrate:tenant` route (RFC AG).** Earlier the
  loomcycle MCP transport ran as a *global operator* and the route required
  `substrate:admin`, so a tenant `lct_…` bearer was refused at the door — the
  plugin effectively needed an admin token. Now a `substrate:tenant` token
  **opens the session** and everything inside is confined to its tenant. (On an
  older loomcycle build without the flip, a tenant token still 403s at the
  route — see the Compatibility note.)
- **A per-tool gate withholds the admin-only meta-tools.** Inside a
  `substrate:tenant` session, the runtime-global / minting tools are hidden from
  `tools/list` and refused on `tools/call`. Concretely, with a tenant token:
  - ✅ **work, tenant-confined:** `/loomcycle:run`, `/loomcycle:fanout`,
    `/loomcycle:runs`, `/loomcycle:cancel`, `/loomcycle:compact`,
    `/loomcycle:memory`, `/loomcycle:eval`, `/loomcycle:steer`.
  - 🔒 **need an admin token:** `/loomcycle:operator-token` (token minting) and
    `/loomcycle:snapshot` (runtime-global). A refusal here is *expected*, not a
    plugin bug — a confined tenant key is meant to be unable to mint or snapshot.
- **Declared principals (RFC AO) — one token for the UI *and* the plugin.**
  Instead of minting an `OperatorTokenDef`, the operator can **declare** a stable
  login in `loomcycle.yaml` and bind it to a secret in `.env.local`:
  ```yaml
  principals:
    marketing: { tenant: acme, subject: marketing, scopes: [runs:create, runs:read, substrate:tenant], token_env: LOOMCYCLE_TOKEN_MARKETING }
  ```
  Put that same token in the plugin's `auth_token` **and** use it to log into the
  loomcycle Web UI (`/ui/login`). Both resolve to the same `(tenant, subject)`,
  so anything the plugin's agents write in **user scope** (Memory, Documents,
  Paths) shows up under the identity the Web UI reads — no synthetic-operator
  mismatch. This is the simplest way to make a plugin-driven agent and the Web UI
  act as one identity.

### Token rotation runbook

`/loomcycle:operator-token rotate` mints a replacement valid alongside the old
one for the grace window. Two sharp edges to know:

1. **Creating the first admin `OperatorTokenDef` disables the legacy
   `LOOMCYCLE_AUTH_TOKEN`** for inbound HTTP (loomcycle fails closed onto the
   substrate). If `auth_token` is still that legacy value, the HTTP-using
   **auto-snapshot hook** (and the HTTP transport above) will start returning
   401 — update `auth_token` to a valid `lct_…` admin bearer.
2. **A running `loomcycle mcp` captured its token at launch.** After updating
   the `auth_token` userConfig, **restart Claude Code** so the MCP server picks
   up the new bearer. Rotate within the grace window to avoid a gap.

The stdio command surface keeps working across a rotation regardless (stdio is
operator-trust) — only the HTTP-authed paths (the snapshot hook, or the HTTP
transport) depend on a currently-valid bearer.

## Local development

```bash
git clone https://github.com/denn-gubsky/claude-code-plugin-loomcycle
claude --plugin-dir ./claude-code-plugin-loomcycle      # load for one session
claude plugin validate ./claude-code-plugin-loomcycle   # validate before publishing
# optional: shellcheck hooks/scripts/*.sh
```

## Compatibility

| This plugin | loomcycle | Claude Code |
|---|---|---|
| 1.5.0 | Same runtime requirement as 0.21.0 (`loomcycle mcp --upstream` thin client; an instance running at `base_url`). Tracks loomcycle **`main`** — the **RFC AG** per-principal `/v1/_mcp` transport (PRs #549–#553) + **RFC AO** config-declared principals (#554–#555), **pending the next loomcycle tag (v1.5.0)**. **The MCP tool contract is UNCHANGED** — this is an auth/route change, not new meta-tools: `/v1/_mcp` moves `substrate:admin → substrate:tenant` (a tenant or config-declared-principal `auth_token` can now drive the plugin, confined to its tenant), and a per-tool gate withholds the admin-only meta-tools (`/loomcycle:operator-token` + `/loomcycle:snapshot` need an admin token). RFC AO lets the operator declare a `(tenant, subject)` login in `loomcycle.yaml` and use one token for both the Web UI and the plugin. ⚠️ **Requires a loomcycle build with the RFC AG route flip** for a tenant token to open `/v1/_mcp`; on an older build a tenant token 403s at the route (use an admin token, or upgrade loomcycle). | ≥ 2.1 |
| 1.4.0 | Same runtime requirement as 0.21.0 (`loomcycle mcp --upstream` thin client; an instance running at `base_url`). Version-vector track through loomcycle's **v1.2.0 → v1.4.0** line, grounded against source at the **v1.4.0 tag**. **MCP contract is additive — adds the `path` (RFC AL) + `document` (RFC AK) meta-tools** (the thin client auto-advertises them, so `.mcp.json` needs no edit). Skill grounding adds the three new primitives an operator configures: **Bashbox** (RFC AJ, v1.3.0 — `LOOMCYCLE_BASHBOX_ENABLED` + the host-command fallback), **Path** (RFC AL — `allowed_tools:[Path]`), and **Documents** (RFC AK — `allowed_tools:[Document]` + `LOOMCYCLE_SQLMEM_ENABLED`, the SQL Memory prerequisite, RFC AA v1.2.0). Thin-client `--upstream` wiring unchanged. | ≥ 2.1 |
| 1.1.1 | Same runtime requirement as 0.21.0 (`loomcycle mcp --upstream` thin client; an instance running at `base_url`). Tracks loomcycle **v1.1.1** — **RFC AI interactive agentic sessions**: a run with `interactive: true` parks at `end_turn` for operator steering (`POST /v1/runs/{id}/input`) and is re-attachable (`GET /v1/runs/{id}/stream`). Adds `/loomcycle:steer` (HTTP — there is **no MCP steering tool**) + `reference/interactive.md`; `/loomcycle:run` documents the `interactive` flag. MCP tool contract unchanged. *(Documented retroactively in the 1.4.0 changelog backfill.)* | ≥ 2.1 |
| 1.1.0 | Same runtime requirement as 0.21.0. Tracks loomcycle **v1.1.0** (plugin jumped v0.32.0 → v1.1.0) — the **RFC AH Volume primitive**. ⚠️ loomcycle **breaking change**: `LOOMCYCLE_READ_ROOT` / `WRITE_ROOT` / `BASH_CWD` are fatal config-load errors, replaced by a `volumes:` block. Adds `reference/volumes.md` (migration, `volumes:` fields, `VolumeDef` + gates, ephemeral volumes, spawn narrowing) + the Volume section in `loomcycle-configure`; the `volumedef` meta-tool is now documented. *(Documented retroactively in the 1.4.0 changelog backfill.)* | ≥ 2.1 |
| 0.32.0 | Same runtime requirement as 0.21.0 (`loomcycle mcp --upstream` thin client; an instance running at `base_url`). Re-grounded against loomcycle source at the **v0.32.0 tag** (loomcycle shipped v0.25.1 → v0.32.0). **MCP contract grew 40 → 42 tools** (both additive): `spawn_runs` (RFC Y external fan-out, ≤32 runs/call → `/loomcycle:fanout`) and `compact_run` (summarize a parked run → `/loomcycle:compact`); `spawn_run` gained an optional `compaction` field (→ `/loomcycle:run --compact`). Skill grounding adds the per-agent `sampling:` (v0.28.0) + `compaction:` (v0.32.0) blocks, `LOOMCYCLE_RESUME_FANOUT` (v0.31.0), and the corrected `${}` deny-list (`PG_DSN`/`LOOMCYCLE_PG_DSN`/`LOOMCYCLE_AUTH_TOKEN` never interpolated, v0.32.0/#462). Thin-client `--upstream` wiring unchanged. | ≥ 2.1 |
| 0.25.1 | Same runtime requirement as 0.21.0 (`loomcycle mcp --upstream` thin client). **Docs-only**, re-grounded against loomcycle source at the **v0.25.1 tag** (loomcycle shipped v0.24.0 → v0.25.0 → v0.25.1). MCP tool contract unchanged (the `channel`/`context` descriptions gained the new ops). Adds: **`LOOMCYCLE_MCP_SPAWN_RUN_TIMEOUT_MS` now applies to the `--upstream`/`/v1/_mcp` path** the plugin uses (v0.24.0); the **per-tenant webhook route** `POST /v1/_webhooks/{tenant}/{name}` (v0.24.0, RFC N); the **RFC S fan-in/fan-out primitives** (`Channel.await`/`broadcast`, `Context op=time`, ScheduleDef `max_fires` — v0.25.0); and the **F37** scheduler `channel.publish` declared-scope fix (v0.25.1). No plugin command/skill behavior change — pure version-grounding. | ≥ 2.1 |
| 0.23.5 | Same runtime requirement as 0.21.0 (`loomcycle mcp --upstream` thin client; an instance running at `base_url`). **Docs-only**, re-verified against loomcycle source at the **v0.23.5 tag**. Replaces the prior "post-v0.23.0 `main`" hedging with concrete tags now that they exist (loomcycle went **v0.23.0 → v0.23.3 → v0.23.4 → v0.23.5**, no v0.23.1/v0.23.2): **robust `anthropic-oauth-dev`** (`status --probe` F6/#392 + cross-process refresh lock F7/#391, both **v0.23.3**); the dynamic substrate (webhook→AgentDef-agent spawn F30/#403, gated dynamic-stdio MCP F31/#405, both v0.23.3); **secret redaction at rest** (F32, **v0.23.4**); and **dynamic-MCP tools advertised at run start** so single-tool notifier agents fire (F33, **v0.23.5**). Each post-v0.23.0 feature is still flagged with its v0.23.0-binary fallback, so the docs hold whether the operator runs v0.23.0 or v0.23.5. | ≥ 2.1 |
| 0.23.2 | Same runtime requirement as 0.21.0. Docs-only — `loomcycle-configure` reconciled against loomcycle `main` (then-unreleased post-v0.23.0): inbound webhooks, third-party MCP, the two-layer tool gate, and the `.env.local`/`.env.insecure` split. *(Superseded by 0.23.5, which pins those fixes to the v0.23.3 tag.)* | ≥ 2.1 |
| 0.21.0 | **Requires a loomcycle build with `loomcycle mcp --upstream`** (RFC R thin client). The plugin no longer boots a runtime — a loomcycle instance must be running at `base_url`. On a build without `--upstream`, the flag is unknown and the server errors at launch — pin 0.20.x or upgrade loomcycle. | ≥ 2.1 |
| 0.20.2 | as 0.20.1, **plus** the `loomcycle mcp --no-http` flag (verified on v0.22.0). On an older build that doesn't recognise `--no-http`, the server errors at launch — pin 0.20.1 or upgrade loomcycle. | ≥ 2.1 |
| 0.20.1 | ≥ v0.12.x (`loomcycle mcp` + meta-tools); memory `add`/`recall` need ≥ v0.16; `operator-token` needs ≥ v0.17 | ≥ 2.1 |

The plugin's version tracks loomcycle's version vector through the v1.x batch.
All tool contracts are re-verified against loomcycle's `internal/api/mcp/tools.go`
each release — the v0.12.x → v0.16.x meta-tool additions are back-compatible,
so the existing commands work unchanged against any loomcycle ≥ v0.12.x.

The plugin consumes loomcycle's MCP tools verbatim. If a capability is missing,
it's a feature request on the loomcycle repo — the plugin ships no workarounds.

## Troubleshooting

- **MCP server won't connect** — check `loomcycle` is on PATH (or `bin_path` is
  correct) and that `config_path` points at a valid `loomcycle.yaml`. Claude
  Code spawns MCP servers with a sparse environment; if your yaml uses
  `${...}` env placeholders, populate them or wrap the binary in a script that
  sources your env first.
- **Wrong binary / "command not found" after moving machines or switching OS**
  (e.g. a Linux `bin_path` carried onto macOS) — the committed `.mcp.json` is a
  *template* (`${user_config.bin_path}` / `${user_config.base_url}`); Claude Code
  resolves those to concrete values **at install time** and stores them in its
  own settings, **not** in this repo, so a path baked on one machine is stale on
  another. Fix it where it lives: `/plugin` → manage **loomcycle** → **Configure**
  → set `bin_path` to `loomcycle` (PATH lookup — most portable) or the platform
  path (`/opt/homebrew/bin/loomcycle` on Apple Silicon, `/usr/local/bin/loomcycle`
  on Intel), confirm `base_url`, then **restart Claude Code**. Don't hand-edit the
  resolved `.mcp.json` in your live config — that's the plugin's running MCP
  startup config and editing it is correctly blocked; reconfigure via `/plugin`
  instead (reinstalling re-prompts for these fields too).
- **An `env` change in `settings.json` / `settings.local.json` didn't take
  effect** — the respawned `loomcycle mcp` server inherits the environment Claude
  Code itself started with, so a `/reload-plugins` does **not** re-read
  `settings`-supplied env (e.g. `LOOMCYCLE_LISTEN_ADDR`,
  `LOOMCYCLE_MCP_ALLOW_PRIVILEGED_TOOLS`). Only a **full Claude Code restart**
  picks up a changed `settings` `env`. (Exporting the var in the shell that
  launches Claude Code, then restarting, is the reliable path.)
- **`list_runs` errors** — it requires `user_id`. Set one via
  `/loomcycle:connect --user=<id>` or pass `--user=` on the command.
- **Bearer / auth** — the API bearer lives in your OS keychain via the
  `auth_token` userConfig, never in the repo. The per-run bearer set by
  `/loomcycle:connect` is a separate, session-scoped value.
- **Multi-replica loomcycle** — the plugin talks to whatever instance its
  `loomcycle mcp` server is configured against; cluster-mode is transparent.

## What this plugin does NOT do

- Start, stop, or health-check loomcycle (lifecycle is the operator's job).
- Bundle the loomcycle binary.
- Push agent definitions *into* loomcycle (that's `loomcycle import claude-code`
  — RFC C2 — the data-movement direction; this plugin moves runtime control).

## License

Apache-2.0. See [LICENSE](LICENSE).
