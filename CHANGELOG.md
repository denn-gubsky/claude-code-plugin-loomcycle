# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/) and the project adheres to
[Semantic Versioning](https://semver.org/).

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
