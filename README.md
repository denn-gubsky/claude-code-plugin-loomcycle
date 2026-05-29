# loomcycle plugin for Claude Code

Drive a [loomcycle](https://github.com/denn-gubsky/loomcycle) agentic runtime
from inside Claude Code — spawn and cancel runs, list them, snapshot the
runtime, submit evaluations, and import `.claude/` repos — all through slash
commands and skills, with no JSON pasting.

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

```text
/plugin marketplace add denn-gubsky/claude-code-plugin-loomcycle
/plugin install loomcycle
```

At install you'll be prompted for:

| userConfig | Purpose | Default |
|---|---|---|
| `bin_path` | Path to the loomcycle binary | `loomcycle` (PATH lookup) |
| `config_path` | Path to your `loomcycle.yaml` | `loomcycle.yaml` (project dir) |
| `auth_token` | `LOOMCYCLE_AUTH_TOKEN` bearer (stored in your OS keychain, **never** the repo) | — |
| `base_url` | loomcycle base URL for the optional auto-snapshot hook | `http://127.0.0.1:8787` |

The bundled MCP server entry (`.mcp.json`) then launches
`loomcycle mcp --config <config_path>` automatically when the plugin is enabled.

## Commands

All commands are namespaced under the plugin name: `/loomcycle:<command>`.

| Command | Wraps | Purpose |
|---|---|---|
| `/loomcycle:connect [--user=<id>] [--bearer=<tok>] [--base-url=<url>] [--persist]` | (session state) | Set the active loomcycle identity reused by later commands. The bearer is the per-run `user_bearer`, not the API token. |
| `/loomcycle:run <agent> [--user=<id>] <prompt…>` | `spawn_run` | Spawn a run; the result (final text + `agent_id` cancel handle + `run_id`) streams back. |
| `/loomcycle:runs [--user=<id>] [--status=<s>] [--limit=<n>]` | `list_runs` | List recent runs as a table. `user_id` is required (set it once via connect). |
| `/loomcycle:cancel <agent_id> [--reason=<text>]` | `cancel_run` | Cancel a running agent; cascades to sub-agents; idempotent. |
| `/loomcycle:snapshot <create\|list\|restore\|delete> [id]` | the 4 snapshot tools | Runtime snapshot ops from the IDE. Restore/delete confirm first. |
| `/loomcycle:eval <run_id> <score> [--rationale=<text>]` | `evaluation` (`op=submit`) | Record an evaluation against a completed run. loomcycle never auto-promotes on score. |

## Skills

Skills load automatically when their description matches what you're doing:

| Skill | What it does |
|---|---|
| `loomcycle-spawn-evaluator` | Spawn an independent evaluator agent to score the current transcript or a named run, then offer to record the score. |
| `loomcycle-replay-failed-run` | `get_run` → diagnose the failure → re-spawn with the smallest fix. Stops after a repeat failure and recommends an operator-side config fix. |
| `loomcycle-diff-agentdefs` | Diff two AgentDef versions by `def_id` (`system_prompt` / `allowed_tools` / `max_tokens` / lineage). Descriptive only. |
| `loomcycle-import-claude-code` | Guided wrapper over `loomcycle import claude-code` (RFC C2): dry-run → review the lossy report → `--write` → `validate`. |

## Optional hooks

Both hooks ship **disabled** — they no-op unless you opt in with an env var.

| Hook | Enable with | Action |
|---|---|---|
| capture-run-telemetry | `LOOMCYCLE_PLUGIN_TELEMETRY=1` | Append `{ts, run_id, agent_id}` to `${CLAUDE_PLUGIN_DATA}/run-telemetry.jsonl` after each `spawn_run`. |
| auto-snapshot-on-error | `LOOMCYCLE_PLUGIN_AUTO_SNAPSHOT=1` | On a state-mutating tool error, run `loomcycle snapshot --description pre-error-<ts>`. Needs `LOOMCYCLE_AUTH_TOKEN` (and optionally `LOOMCYCLE_BASE_URL`) exported in the shell that launches Claude Code — the hook reads the bearer from the environment, never from a substituted command string. |

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
| 0.12.8 | ≥ v0.12.x (`loomcycle mcp` + meta-tools) | ≥ 2.1 |

The plugin consumes loomcycle's MCP tools verbatim. If a capability is missing,
it's a feature request on the loomcycle repo — the plugin ships no workarounds.

## Troubleshooting

- **MCP server won't connect** — check `loomcycle` is on PATH (or `bin_path` is
  correct) and that `config_path` points at a valid `loomcycle.yaml`. Claude
  Code spawns MCP servers with a sparse environment; if your yaml uses
  `${...}` env placeholders, populate them or wrap the binary in a script that
  sources your env first.
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
