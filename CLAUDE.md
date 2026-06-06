# CLAUDE.md — claude-code-plugin-loomcycle

This file is loaded by Claude Code on every session in this repo. Read it cold; act from it without re-discovery.

## Project context

**claude-code-plugin-loomcycle** is the Claude Code-side UX layer for [loomcycle](https://github.com/denn-gubsky/loomcycle), a high-load agentic runtime. It is a **Claude Code plugin** — a git-distributed bundle of slash commands, skills, hooks, and a pre-wired MCP server config. It ships nothing executable of its own: since 0.21.0 it wires `loomcycle mcp --upstream <base_url>` as a **thin client** — a stdio↔`/v1/_mcp` proxy to a running loomcycle runtime that boots NO runtime of its own (loomcycle RFC R single-runtime invariant) — and exposes its meta-tools (`mcp__loomcycle__spawn_run`, `…__cancel_run`, `…__list_runs`, snapshot ops, `…__evaluation`, `…__agentdef`, etc.).

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
- `spawn_run` takes `segments` (array), not a `prompt` string — wrap the operator's text as one segment.
- `list_runs` requires `user_id` — commands must supply it (from `/loomcycle-connect` state or `--user`).
- **Versioning tracks loomcycle's vector through the v1.x batch** (not an independent plugin semver). First release is `v0.12.8`, matching loomcycle at ship time; bump alongside loomcycle's `v0.X.Y`. **`v1.0.0` is reserved for the v1.x batch release** once the remaining RFCs land — a lone plugin "1.0" would falsely signal the batch is done. Keep `.claude-plugin/plugin.json` + `.claude-plugin/marketplace.json` versions in sync, and tag releases `vX.Y.Z`. `marketplace.json` keeps `ref: main` during development (installs track latest); pin it to the release tag at v1.0.0.
- Commit subjects ≤72 chars, imperative, conventional prefix. Close with `Co-Authored-By` when Claude wrote substantial content.

## When in doubt

- The MCP tool contract is in loomcycle's `internal/api/mcp/tools.go` — read it, don't guess field names.
- The plugin spec is at https://code.claude.com/docs/en/plugins.md and `plugins-reference.md`.
- The RFC (`loomcycle-internal/doc-internal/rfcs/claude-code-plugin.md`) is the scope authority.
