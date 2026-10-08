# Environment variable catalogue

The **posture** axis. Authoritative source: loomcycle `.env.insecure.example` +
`.env.local.example` + `internal/config`, checked against **v1.107.0**. Where the
template and the code disagree on a default, the default below is the code's. Set
these in the operator's environment (the two env files below, container `-e`
flags, or a systemd unit) — **never have this plugin write the *secret* env file;
print the secret lines for the operator.** `loomcycle env-template` prints the
annotated non-secret template on any install.

Secrets (`*_API_KEY`, `LOOMCYCLE_AUTH_TOKEN`, `LOOMCYCLE_OPERATOR_TOKEN_PEPPER`,
`LOOMCYCLE_SECRET_KEY`, any DSN, any `token_env` value) are referenced by name
only and live in the operator's secret store / keychain, never in a repo file.

> **Two env files (v0.23.3 split — loomcycle #399, `docs/CONFIGURATION.md`
> §9c).** The launcher (`loomcycle.sh` / `loomcycle-mcp.sh`) sources
> **`.env.insecure` first, then `.env.local`** (config first, secrets last):
>
> | File | Holds | Safe to read/edit? |
> |---|---|---|
> | **`.env.insecure`** | Non-secret operational config — listen addr, data dir, sandbox roots, host allowlists, feature flags, timeouts, and the trigger-credential allowlist **names** (`LOOMCYCLE_WEBHOOKS_ENV_ALLOWLIST`, …). | **Yes** — nothing here is a secret. |
> | **`.env.local`** | Secrets — `*_API_KEY`, `LOOMCYCLE_AUTH_TOKEN`, the operator-token pepper, and the secret **values** behind allowlisted trigger-credential names. git-ignored. | **No** — name-only; never read/print it. |
>
> The seam is **allowlist-name vs. secret-value**: a webhook's
> `signing_secret_env: LOOMCYCLE_X` *name* is non-secret config (`.env.insecure`);
> the HMAC *value* lives in `.env.local`. Set `LOOMCYCLE_ENV_FILE=<path>` to
> collapse the pair back into one explicit file (the pre-split single-file flow).
> The **v0.23.0 brew binary** ships only `.env.local` (no split) — there, treat
> the whole file as secret-bearing. Each table below notes which file a var
> belongs in only where it isn't obvious from sensitivity.

## Identity, listen, auth

| Var | Default | Purpose |
|---|---|---|
| `LOOMCYCLE_LISTEN_ADDR` | `127.0.0.1:8787` | HTTP/SSE listen. Use `0.0.0.0:8787` inside a container so port-mapping works; keep `127.0.0.1` on a host you don't want exposed. |
| `LOOMCYCLE_AUTH_TOKEN` | (empty) | Bearer for every `/v1/*` route. **Empty = dev-mode unauthenticated** (loomcycle warns loudly at boot). Always set in any shared/server deployment. `openssl rand -hex 32`. |
| `LOOMCYCLE_GRPC_ADDR` | (unset) | gRPC listen addr (optional second transport). |
| `LOOMCYCLE_PUBLIC_URL` | (unset) | The instance's externally reachable URL, reported to agents in `Context op=self` (`server.url`). Non-secret. |
| `LOOMCYCLE_PUBLIC_CONFIG` | off | `1` lets `GET /v1/config` be read with **no bearer**, returning a narrowed public view (version, features, live providers/models). An invalid bearer still `401`s. |
| `LOOMCYCLE_MAX_REQUEST_BYTES` | 16777216 (16 MiB) | Run-ingest request body cap; over it → `413`. |
| `LOOMCYCLE_SSE_KEEPALIVE_MS` | 20000 | SSE comment-ping cadence (clamped 1 s – 5 min; `0` or negative disables). |

## Config sources (presets + layering)

| Var | Default | Purpose |
|---|---|---|
| `LOOMCYCLE_PRESETS` | (unset) | Comma-separated, ordered embedded presets/bundles layered as the **base** of the config stack (`base`, `oauth`, `local`; bundles `chat`, `document-agent`, `memory`, `system-channels`, `sandbox`, `dev-exec`, `agent-teams`, `team-examples`, `doc-colorizer`). Opt-in; an unknown name is fatal. `--preset` (repeatable) overrides it. `loomcycle presets` lists them. |
| `LOOMCYCLE_CONFIG_DIR` | (unset) | A directory whose `*.yaml`/`*.yml` layer in lexical filename order, above the presets. Set-but-missing is fatal. |
| `LOOMCYCLE_CONFIG_FILES` | (unset) | `:`-separated config files layered left→right, above `CONFIG_DIR` and below explicit `--config` flags. |
| `LOOMCYCLE_CONFIG_STRICT` | off | `1` makes any cross-layer conflict a **fatal** load error (otherwise each override is logged at startup). Recommended in production. |
| `LOOMCYCLE_NO_DEFAULT_PROVIDERS` | off | `1` drops the built-in provider layer so only your own `providers:` entries exist — e.g. to stay local-only on `LOOMCYCLE_PRESETS=base,local`. |

Precedence, base → top: presets → `CONFIG_DIR` → `CONFIG_FILES` → `--config`.
Details and the merge rule: [routing.md](routing.md).

## Storage

| Var | Default | Purpose |
|---|---|---|
| `LOOMCYCLE_STORAGE_BACKEND` | `sqlite` | `sqlite` or `postgres`. Postgres required for multi-replica. |
| `LOOMCYCLE_DATA_DIR` | `./data` | SQLite store + transient state dir. |
| `LOOMCYCLE_PG_DSN` | (unset) | Postgres DSN — required when backend is postgres (`postgres://…?sslmode=require`). |
| `LOOMCYCLE_PG_AUTOMIGRATE` | off | `1` runs schema migrations on boot. |
| `LOOMCYCLE_PG_MAX_OPEN_CONNS` | pool default | Set to `MaxConcurrentRuns × 1.5` per replica (session-locked continuations pin one conn each). |
| `LOOMCYCLE_PG_MIN_IDLE_CONNS` | — | Idle pool floor. |
| `LOOMCYCLE_PGVECTOR_ENABLED` | off | `1` uses pgvector on the Postgres backend (vector memory; also needed for full-text in `Document op=search`). |
| `LOOMCYCLE_SQLITE_VEC_PATH` | (unset) | Path to the sqlite-vec extension when it is not auto-found. |

## Built-in tool sandboxes (default-deny — each tool refuses until set)

> **RFC AH Volume primitive (v1.1.0+)** replaces `READ_ROOT` / `WRITE_ROOT` / `BASH_CWD` with a
> `volumes:` block in `loomcycle.yaml`. All three vars are **fatal config-load errors** in v1.1.0+
> (Phase 3 breaking change) — remove them before upgrading. Use `volumes: default: {path: <dir>,
> mode: rw, default: true}` instead. Full migration guide: [volumes.md](volumes.md).

| Var | Purpose |
|---|---|
| ~~`LOOMCYCLE_READ_ROOT`~~ | **⚠️ RETIRED — v1.1.0+ (RFC AH Phase 3). Fatal config-load error if set.** Was: `Read` tool dir root. Replace with `volumes: default: {path: <dir>, mode: ro}` in `loomcycle.yaml`. |
| ~~`LOOMCYCLE_WRITE_ROOT`~~ | **⚠️ RETIRED — v1.1.0+ (RFC AH Phase 3). Fatal config-load error if set.** Was: `Write`+`Edit` tool dir root. Replace with `volumes: default: {path: <dir>, mode: rw}`. |
| `LOOMCYCLE_BASH_ENABLED` | `1` to enable `Bash`. **Not a true sandbox** — cwd-restricted, env-scrubbed (only PATH leaks), output-bounded (1 MiB), time-capped (30s default, 5min max). Needs a bound `rw` volume (it runs in the volume root). Containerize if exposed to untrusted prompts. |
| `LOOMCYCLE_BASH_ALLOWED_CREDS` | Comma-separated **CredentialDef names** (e.g. `GITHUB_TOKEN`) injected into the `Bash` child env, resolved per run for its own (tenant, user, agent) — a tenant's own token instead of one shared host var. Needs `LOOMCYCLE_SECRET_KEY`. Empty (default) = none. |
| `LOOMCYCLE_BASHBOX_ENABLED` | **(v1.3.0+, RFC AJ)** `1` to enable `Bashbox` — a **TRUE in-process gbash sandbox**: no OS process, no network, paths rooted at the bound volume. Unlike `Bash` it **honors `ro` volumes** (writes hit an in-RAM overlay). Per-agent `tools:[Bashbox]` still required. Prefer over `Bash` for untrusted/read-only work. See [bashbox.md](bashbox.md). |
| `LOOMCYCLE_BASHBOX_FALLBACK_COMMANDS` | **(v1.3.0+, RFC AJ §13, OFF by default)** Comma-separated host commands gbash lacks (`git,gh`) that may fall through to the **real host shell** — **only** those names escape the sandbox (no smuggling); requires a `rw` volume; a loud boot `WARNING:` fires. Names only, safe in `.env.insecure`. |
| `LOOMCYCLE_BASHBOX_FALLBACK_ALLOWED_ENV` | **(v1.3.0+)** Comma-separated env-var **names** the fallback host commands may see (`GH_TOKEN,HOME,SSH_AUTH_SOCK`) — injected into the host child **only**, never the sandbox env (model-invisible). Names here, values stay in `.env.local`. |
| `LOOMCYCLE_BASHBOX_FALLBACK_ALLOWED_CREDS` | The per-tenant counterpart: comma-separated **CredentialDef names** resolved for the run's own identity and injected into fallback commands (overrides a same-named host var). Needs `LOOMCYCLE_SECRET_KEY`. |
| ~~`LOOMCYCLE_BASH_CWD`~~ | **⚠️ RETIRED — v1.1.0+ (RFC AH Phase 3). Fatal config-load error if set.** Was: Bash working dir. Now the Bash cwd is the volume root — the `path:` of the bound `rw` volume. |
| `LOOMCYCLE_HTTP_HOST_ALLOWLIST` | `HTTP`+`WebFetch`: comma-separated **suffix-match** host allowlist (`example.com` matches `api.example.com`, not `evilexample.com`). Private IPs (RFC1918, loopback, link-local incl. 169.254.169.254, **CGNAT `100.64.0.0/10`** and other non-public ranges) are **hard-blocked at connect** regardless. Loopback aliases on this list are stripped at startup — use the private list below. Unset = refuse all outbound. Env-only: a YAML reload cannot change it. |
| `LOOMCYCLE_HTTP_PRIVATE_HOST_ALLOWLIST` | Exception list: hosts here may resolve to private IPs at dial (e.g. a localhost app callback). A hostname entry must ALSO be on the main allowlist; this only lifts the IP-private rejection. **(v1.101.0)** An entry may be a **CIDR range** (`100.64.0.0/10`, `100.101.102.103/32`) admitting only resolved addresses inside it — Tailscale peers need one; a malformed range fails startup. Also the only way a runtime-authored remote memory backend or document source may reach a private host, and the A2A client honours it. |
| `LOOMCYCLE_HTTP_CALLER_AUTHORITATIVE` | `1` = caller's per-request `allowed_hosts` is the sole policy (operator list is a default). Unset = caller can only *narrow* the operator's static list. |
| `BRAVE_API_KEY` / `SERPER_API_KEY` / `EXA_API_KEY` / `TAVILY_API_KEY` | **Secrets** — `WebSearch` provider keys (SearXNG is keyless, configured in the yaml `search_providers:` block). With no `search_providers:` block, `WebSearch` uses Brave when `BRAVE_API_KEY` is set. |
| `LOOMCYCLE_WEBSEARCH_PROVENANCE` | `1` appends a `(via <provider>)` footer to each search result so a provider fallover is visible. |
| `LOOMCYCLE_REDACT_SECRETS` | Default **ON**: tool inputs/outputs are scanned for secret-shaped substrings and masked before they are persisted (events store, snapshots, audit API). `0` disables. The live SSE stream is not redacted. |
| `LOOMCYCLE_MCP_ALLOW_PRIVILEGED_TOOLS` | `1` lets **dynamically-registered** agents request privileged builtins (`Bash`/`Write`/`Edit`); stripped silently otherwise. Only flip on when the MCP client is trusted (operator-launched stdio = trusted; remote HTTP MCP = NOT). |
| `LOOMCYCLE_EPHEMERAL_VOLUME_SWEEP_MS` | Reaper cadence for run-scoped (ephemeral) volumes. Default 60000; `0` or negative disables the sweep. |
| `LOOMCYCLE_MCP_REFUSE_UNATTRIBUTED_ENV` | **(v1.101.1)** A runtime MCP server def may hold a `${NAME}` env reference only when an admin saved it. A stored def holding one without that record still dials (boot `WARNING` + one per dial); `1` refuses to dial those now. The runtime docs say the next release refuses them by default — an admin re-save keeps one working. |
| `LOOMCYCLE_MCP_ALLOW_PRIVATE_IPS` | Default **on** (MCP servers are commonly on localhost / a private network). `0` enables a dial-time DNS-rebinding block for the MCP-HTTP client; `LOOMCYCLE_HTTP_PRIVATE_HOST_ALLOWLIST` then exempts specific internal MCP hosts. |
| `LOOMCYCLE_HOOKS_PRIVATE_HOST_ALLOWLIST` | **(v1.92.0)** Private hosts a **tenant** hook callback may dial (tenant hook callbacks go through the private-address guard). Also settable as yaml `hooks.private_host_allowlist`. |
| `LOOMCYCLE_HOOKS_PERMIT_HOST_WIDEN_OWNERS` | Comma-separated hooks permitted to widen a call's host allowlist (appended to yaml `hooks.permit_host_widen.owners`). Since v1.97.0 each entry names `[tenant:]hook-name`. |
| `LOOMCYCLE_MCP_ALLOW_DYNAMIC_STDIO` | **(v0.23.3, F31/#405)** `1` lets a **runtime-authored** MCP server (`POST /v1/_mcpserverdef` / the `mcpserverdef` tool) use `transport: stdio` — which **runs an arbitrary local command**, so it is **off by default** and refused with an explicit error otherwise. `http`/`streamable-http` dynamic servers need no flag (mediated by the outbound host allowlist); **static `mcp_servers:` stdio in yaml is operator-trusted and unaffected**. Only set on a host where the MCP-authoring principal is trusted to name local commands. |

## Filesystem roots (discovery)

| Var | Purpose |
|---|---|
| `LOOMCYCLE_AGENTS_ROOT` | Dir of `<name>.md` agent files (frontmatter + system-prompt body). |
| `LOOMCYCLE_SKILLS_ROOT` | Dir of `<name>/SKILL.md` skills. Operator-trusted content — don't point at an untrusted-writable dir. Unset = agents may not list skills. |
| `LOOMCYCLE_HELP_ROOT` | Optional dir of `<name>.md` help topics for `Context op=help` (a same-named file overrides a bundled topic). **(v1.93.0)** A `tools/` subdirectory holds operator tool articles: `tools/<Tool>.md`, `tools/<Tool>/<op>.md` — including MCP tools as `tools/mcp__<server>__<tool>.md`. |

Inline `skills:` and `agents:` in yaml (and the embedded bundles) need neither
root.

## code-js synthetic provider (operator JavaScript agents)

| Var | Purpose |
|---|---|
| `LOOMCYCLE_CODE_AGENTS_ENABLED` | `1` to allow `provider: code-js` agents (operator JS via goja; `eval`/`Function` deleted, no ambient fetch/fs). Off by default — operator-trust posture like Bash. |
| `LOOMCYCLE_CODE_AGENTS_ROOT` | Dir holding `<name>/index.js` (default `./agent_code`). Missing/unparsable file fails loud at startup. Path-traversal agent names refused. |
| `LOOMCYCLE_CODE_AGENTS_RUN_TIMEOUT_SECONDS` | Budget of **active** time for a code-js run (default 120; code-js agents are exempt from MaxIterations). Since v1.105.0 time spent waiting (on children, channels, a pause) is not counted. |
| `LOOMCYCLE_CODE_AGENTS_MAX_WALL_SECONDS` | **(v1.105.0)** Lifetime limit, waits included (default 86400 = 24 h). A run that only waits ends with stop reason `code_agent_wall_limit`. |
| `LOOMCYCLE_CODE_AGENTS_DETERMINISTIC` | `1` freezes clock+seed for snapshot equality. |
| `LOOMCYCLE_CODE_HOOKS_ENABLED` | **(v1.94.0)** `1` lets a hook body be JavaScript (a code hook) instead of a webhook. Separate from the code-agent gate; tenant operators may author code hooks under this flag alone. Off by default. |

## Memory

| Var | Default | Purpose |
|---|---|---|
| `LOOMCYCLE_MEMORY_MAX_VALUE_BYTES` | 65536 | Per-write value cap (set/incr). 0 disables. |
| `LOOMCYCLE_MEMORY_MAX_SCOPE_BYTES` | 1048576 | Per-(scope,scope_id) byte cap; per-agent `memory_quota_bytes` overrides. |
| `LOOMCYCLE_MEMORY_SWEEP_MS` | 900000 | TTL reaper cadence. Read paths filter expired rows even when off. |
| `LOOMCYCLE_MEMORY_PENDING_DRAINED_TTL_MS` | 604800000 (7 d) | **(v1.101.0)** Drained consolidation-queue rows (which keep the raw chat they were banked from) are deleted after this long. Undrained rows are never pruned. `0` disables. |
| `LOOMCYCLE_MEMORY_PROVISION_IDENTITY_DOCS` | on | **(v1.68.0)** Provision the user-root / tenant-root identity documents at token mint and at boot for config principals. `0` = lazy-only. |
| `LOOMCYCLE_MEMORY_CHANGES_ENABLED` | off | `1` enables the memory change-data-capture feed (opt-in). |
| `LOOMCYCLE_MEMORY_EMBED_BATCH_SIZE` / `_EMBED_TIMEOUT_MS` | 64 / 30000 | Embed batch size and per-embed-call timeout. |
| `LOOMCYCLE_DEADLINK_GC_MS` | 3600000 (1 h) | Dead-link sweeper cadence; `0` disables. `LOOMCYCLE_DEADLINK_GC_DRY_RUN=1` reports without deleting. (Before v1.97.0 this sweeper could delete live chunk bodies in a scope past 10,000 chunks — upgrade, or disable/dry-run it on an older binary.) |
| `LOOMCYCLE_MAX_CONSOLIDATION_TARGETS` | 32 | Consolidation targets one fan-out tick dispatches; the rest defer to the next tick. |
| `LOOMCYCLE_MAX_CONSOLIDATION_CONCURRENCY` | 4 | Parallel consolidation children on a non-local model (a local model runtime is always serial). Since v1.101.0 it applies to code-js consolidators too. |
| `LOOMCYCLE_RERANKER_API_KEY` | (unset) | **Secret** — the key a `memory.reranker` answers to when its block points it at its own endpoint (`base_url`) without naming an `api_key_env`. See [routing.md](routing.md). |
| `LOOMCYCLE_UNIT_GENERATOR_API_KEY` | (unset) | **Secret** — the `memory.unit_generator` counterpart. |
| `LOOMCYCLE_SQLMEM_ENABLED` | off | **(v1.2.0+, RFC AA)** `1` enables **SQL Memory** — a per-scope SQL database facet of the `Memory` tool (`sql_query`/`sql_exec`, gated per-agent by `sql_scopes`). **Also the prerequisite for the `Document` primitive** (RFC AK) — chunk structure lives in SQL Memory, so `Document` refuses without this flag. See [document.md](document.md). |
| `LOOMCYCLE_SQLMEM_PG_DSN` | (unset) | **Secret** — Postgres tier for SQL Memory. Its role needs `CREATEROLE` (per-scope login-role isolation). `.env.local` only. |

Other `LOOMCYCLE_SQLMEM_*` guardrails (`_ROOT`, `_QUOTA_BYTES`, `_MAX_ROWS`
default 10000, `_STATEMENT_TIMEOUT_MS` default 30000, `_TXN_TIMEOUT_MS` default
30000, `_MAX_OPEN_TXNS` default 64, `_MAX_TXN_DEPTH` default 16,
`_TOTAL_MAX_BYTES`, `_SCOPE_TTL_MS`, `_GC_INTERVAL_MS`) are in the env template.

> **`memory_scopes` is an agent-yaml gate, not an env var — and since v1.82.0
> unset is no longer deny.** These env vars only tune limits. An agent with
> `Memory` in `tools` and **no** `memory_scopes:` list resolves to what the
> caller already owns: `user`, plus `tenant` for a non-isolated member (and to
> nothing for a run with no user id). A declared list is authoritative and never
> widened. To grant nothing, say so: `memory_scopes: ["-*"]` (an empty list
> cannot mean that). The same default applies to `history_scope` (`user`),
> `sql_scopes` (`["user"]`) and `evaluation_scopes` (`["submit_self"]`).
> `loomcycle validate` prints an advisory for an unset gate.

## Channels

| Var | Default | Purpose |
|---|---|---|
| `LOOMCYCLE_CHANNELS_MAX_VALUE_BYTES` | 65536 | Per-message payload cap (`0` disables). |
| `LOOMCYCLE_CHANNELS_SWEEP_MS` | 900000 | Expired-message reaper cadence. |
| `LOOMCYCLE_CHANNELS_MAX_PENDING_DEFERRED` | 10000 | Cap on the deferred-publish scheduler's live timers. Excess deferred messages are still stored; subscribers see them on their next long-poll wake. `0` = no cap. |
| `LOOMCYCLE_CHANNEL_HOOKS` | off | **(v1.99.0)** `1` enables hooks on the `channel_publish` event (`release` / rewrite / `drop` / `hold`). Without it a channel's `hooks:` never fire. |
| `LOOMCYCLE_CHANNEL_HOOKS_CONCURRENCY` / `_PER_CHANNEL` / `_MAX_WAIT` | 16 / 4 / `15m` | Channel-hook evaluations in flight per replica / per channel, and the longest a publish waits on its hooks (`_MAX_WAIT` is a Go duration string, e.g. `15m`). |
| `LOOMCYCLE_TEAM_SUBSCRIPTIONS` | off | **(v1.77.0)** `1` arms team subscriptions: a promoted team whose source has work is started by the runtime — the only part of the runtime that starts agent runs unprompted. `LOOMCYCLE_TEAM_SUBSCRIPTIONS_TICK_SECONDS` (default 15) is its poll cadence. |
| `LOOMCYCLE_CHANNELS_LONGPOLL_CAP_MS` | 30000 | Server cap on a `Channel.subscribe` `wait_ms`. A `wait_ms` **larger than the cap is silently truncated** to it (**v0.23.3**, F22/#390: logged once per channel as a runtime `WARNING:` on first truncation). The default 30 s forces a parked subscriber to re-subscribe every 30 s, and **each re-subscribe consumes one `max_iterations`** — so a too-low cap can exhaust a long-idle agent's iteration budget before any message arrives. Raise the cap (e.g. `180000`) and/or the agent's `max_iterations` for webhook/event-driven agents that block waiting for a signal. (Channel access itself is gated per-agent by the `channels:` publish/subscribe ACL — default-deny.) |

> **Fan-in / fan-out primitives (v0.25.0, RFC S).** The `Channel` tool gained
> `await` (multi-channel fan-in barrier — `any`/`all`/`at_least N` or timeout,
> non-committing) and `broadcast` (one payload → N channels, atomic ACL
> pre-flight); `Context` gained `op=time` (an in-run agent clock). These are
> agent/tool-runtime ops (no `loomcycle.yaml` knob), auto-advertised on the MCP
> `channel`/`context` meta-tools. **v0.25.1 (F37)** fixed the scheduler's
> `on_complete: channel.publish` to publish under the channel's **declared**
> scope — so a scheduler→channel fan-in can use a natural `scope: global`
> channel instead of the old `scope: user` workaround.

## MCP server (stdio thin client)

These govern the `loomcycle mcp --upstream` process the **plugin itself**
launches (the thin-client proxy to the runtime's `/v1/_mcp`). Set them in the
*upstream runtime's* environment — they shape how its `/v1/_mcp` endpoint
behaves under the plugin's calls.

| Var | Default | Purpose |
|---|---|---|
| `LOOMCYCLE_MCP_SPAWN_RUN_TIMEOUT_MS` | off (0) | Operator default transport timeout for `spawn_run` (RFC P): the run is cancelled and `status:"timeout"` returned instead of blocking the call forever. A per-call `timeout_ms` can *narrow* it (not exceed). **v0.24.0 made this apply to the HTTP / `--upstream` path** — i.e. the plugin's topology; before that only the stdio `New` carried it, so `/v1/_mcp` was unbounded. Distinct from the run's own `run_timeout_seconds` budget. |
| `LOOMCYCLE_MCP_MAX_CONCURRENT_CALLS` | 16 | Bounded slot count for long-running `tools/call` dispatch (RFC O, v0.23.0). Cheap/control tools (`cancel_run`, `list_runs`) stay responsive even when every slot is occupied. stdio-transport only by design. |

| `LOOMCYCLE_MCP_UPSTREAM_TOKEN` | (unset) | **Secret** — the bearer the thin client presents to the upstream runtime. Set in the *thin client's* environment; `.env.local` only. |
| `LOOMCYCLE_MCP_UPSTREAM_HEADER_TIMEOUT_MS` | client default | Thin client: max wait for upstream response headers (stall guard). Agent-run tools (`spawn_run`, `spawn_runs`, `compact_run`, `evaluation`) are exempt so a slow run is not retried into a double execution. |
| `LOOMCYCLE_MCP_UPSTREAM_RECONNECT_ATTEMPTS` | client default | Thin client: reconnect tries after a transport error (`0` = off). |

> **MCP tool set (v1.107.0).** Since v1.54 the meta-tool catalogue gained
> `retune_run` (v1.83.0), `configured_run` and `review_run` (v1.93.0), `hookdef`
> (v1.96.0) and `decision` (v1.107.0), and **lost `register_hook` /
> `list_hooks` / `delete_hook`** (v1.97.0 — hooks now live on the agent
> definition). `spawn_runs` accepts `mode: "detach"` (v1.105.0). None changes the
> `--upstream` wiring. Since v1.107.0 a member token's MCP session is
> held to its scopes: run tools need `runs:create`, read tools `runs:read`,
> channel tools `channel:publish` / `channel:read` (stdio, admin, legacy and
> `substrate:tenant` sessions are unchanged).

## Runs, sub-agents and definition size caps

| Var | Default | Purpose |
|---|---|---|
| `LOOMCYCLE_MAX_LIVE_CHILDREN_PER_RUN` | 32 | **(v1.105.0)** Children one run has alive at once, across every `Agent` op that starts one; a spawn past it is refused whole. Per run, not per tree. |
| `LOOMCYCLE_MAX_INTERACTIVE_CHILDREN` | 8 | Resident (`Agent op=open`) children one run holds open. |
| `LOOMCYCLE_INTERACTIVE_CHILD_IDLE_TTL_MS` | 1800000 (30 min) | Idle time (no send) after which a resident child is reaped. |
| `LOOMCYCLE_RESIDENT_MAX_TURN_SECONDS` | 7200 (2 h) | **(v1.105.0)** A resident child whose current turn runs longer is reaped. No unlimited setting. |
| `LOOMCYCLE_AGENT_CHILD_MAX_TIMEOUT_MS` | 0 (no ceiling) | **(v1.105.0)** Ceiling on a spawn's `timeout_ms`; a larger value is refused, not clamped. |
| `LOOMCYCLE_AGENT_POLL_WAIT_CAP_MS` | 60000 | **(v1.105.0)** Longest one `Agent op=poll` with `wait` `any`/`all` blocks; a larger `wait_ms` is cut to it. |
| `LOOMCYCLE_MAX_CONFIGURED_RUNS_PER_USER` | 100 | **(v1.93.0)** Draft (configured, not started) runs one (tenant, user) may hold; past it `429 configured_run_cap`. `0` = no cap. |
| `LOOMCYCLE_CONFIGURED_RUN_TTL_MS` | 86400000 (24 h) | **(v1.93.0)** How long a draft run is kept before the expiry sweep discards it. `0` disables the sweep. |
| `LOOMCYCLE_AGENT_DEF_MAX_DEFINITION_BYTES` | 131072 | Cap on one agent definition (measured without a code-js body). Since v1.104.0 it no longer bounds teams. `0` disables. |
| `LOOMCYCLE_TEAM_DEF_MAX_DEFINITION_BYTES` | 1048576 | **(v1.104.0)** Cap on one team definition, its own agents included. `0` or negative disables. |
| `LOOMCYCLE_AGENT_DEF_MAX_CODE_BYTES` | 262144 | Cap on a code-js agent's source. |
| `LOOMCYCLE_DYNAMIC_AGENT_DEFAULT_TTL_SECONDS` | 86400 | Default TTL of an agent registered with `register_agent`. |

## Pause / resume

| Var | Default | Purpose |
|---|---|---|
| `LOOMCYCLE_PAUSE_DEFAULT_TIMEOUT_MS` | 30000 | How long a pause waits for in-flight runs to park when the request names no `timeout_ms` (capped at 5 min). |
| `LOOMCYCLE_RESUME_FANOUT` | off (0) | **(v0.31.0, RFC X Phase 3)** `1` enables durable park+resume of a **fan-out parent** blocked in `Agent.parallel_spawn` — loomcycle captures spawn-ledger events so a parent quiesced by pause (or a crashed/restarted replica) re-dispatches its in-flight children from the transcript instead of stranding them. Default OFF keeps the pre-v0.31 pause/resume/snapshot paths byte-identical; opt in for long fan-out orchestrations that must survive a restart. (Single-run cross-instance resume needs no flag — v0.30.0.) |

## Concurrency, fairness, provider timeouts

| Var | Default | Purpose |
|---|---|---|
| `LOOMCYCLE_MAX_CONCURRENT_RUNS_PER_USER` | 0 (unlimited) | Per-user fairness cap (cluster-wide on Postgres). |
| `LOOMCYCLE_TOOL_PARALLELISM` | 8 | Max concurrent tool calls within one assistant turn (capped at 64; `1` forces serial). |
| `LOOMCYCLE_PROVIDER_QUEUE_DEPTH` / `LOOMCYCLE_PROVIDER_QUEUE_TIMEOUT_MS` | inherit the global queue knobs | Queue for the per-provider `providers.<id>.max_concurrent` gate; on timeout → `429 provider_concurrency_exhausted`. |
| `LOOMCYCLE_PROVIDER_HEADER_TIMEOUT_MS` | 60000 | Per-attempt time-to-first-byte cap. |
| `LOOMCYCLE_PROVIDER_IDLE_TIMEOUT_MS` | 90000 | Max gap between streamed body bytes. |
| `LOOMCYCLE_OLLAMA_LOCAL_HEADER_TIMEOUT_MS` / `LOOMCYCLE_OLLAMA_LOCAL_IDLE_TIMEOUT_MS` | 600000 / 600000 | `ollama-local` only — its own, longer pair for slow cold loads. The yaml `providers.<id>.options.header_timeout_ms` / `idle_timeout_ms` win over these. |
| `LOOMCYCLE_OLLAMA_LOCAL_NUM_CTX` | (unset) | Context window (`options.num_ctx`) for **all** `ollama-local` models. Unset → the driver echoes the window Ollama reports the model loaded with, else Ollama's 4096 default applies (and silently truncates a longer prompt). A per-agent `max_context_tokens` wins over it. `LOOMCYCLE_OLLAMA_NUM_CTX` is the same for hosted `ollama`. |
| `LOOMCYCLE_OLLAMA_LOCAL_NUM_GPU` | (unset) | `options.num_gpu` for `ollama-local` — force GPU offload where Ollama's auto-detection falls back to CPU. |
| `LOOMCYCLE_OLLAMA_DEBUG_THINK` | off | `1` logs each Ollama request's model / effort / think flag. |
| `LOOMCYCLE_TIMEOUT_SCALING` | `measure` | **(v1.101.2)** Model-speed measurement mode: `measure` records and reports only (no timeout changes); `off` stops measuring; `on` is refused. Wins over the yaml `timeout_scaling.mode`. |
| `LOOMCYCLE_TIMEOUT_SCALING_REFERENCE_TPS` | 100 | Reference output tokens/s that count as slowdown 1 (`timeout_scaling.reference.decode_tps`). |
| `LOOMCYCLE_TIMEOUT_SCALING_MAX_MULTIPLIER` | 8 | Ceiling on the multiplier (`timeout_scaling.max_multiplier`). |
| `LOOMCYCLE_RESOLVE_PROBE_INTERVAL_MS` | 900000 (15m) | Provider re-probe cadence (clamped 60 s – 60 min). `POST /v1/_resolve/probe` forces an immediate one. |
| `LOOMCYCLE_FALLBACK_PIN_AFTER_SUCCESS` | off | `1` suppresses cross-provider fallback after ≥1 successful turn (see routing.md). |

## Scheduler / Webhooks / A2A (off by default)

| Var | Purpose |
|---|---|
| `LOOMCYCLE_SCHEDULER_ENABLED` / `_TICK_SECONDS` | Scheduled runs (RFC E). `_TICK_SECONDS` (default 30) is the poll cadence for due schedules. Since v1.105.0 every replica may run the scheduler (each slot is fired by the one replica that claims it). **`LOOMCYCLE_SCHEDULER_FIRE_TIMEOUT_SECONDS` is no longer read (v1.105.0)** — remove it from your env. |
| `LOOMCYCLE_SCHEDULER_ENV_ALLOWLIST` | Comma-separated env-var NAMES the **scheduler** (and, merged, the webhook receiver + mem9 backend) may resolve as secrets/bearers. The shared trigger-credential gate. For webhooks, prefer the better-named twin below; this one still works (union). |
| `LOOMCYCLE_WEBHOOKS_ENV_ALLOWLIST` | **(v0.23.3, F23/#385)** The webhook-specific, correctly-named twin — comma-separated secret/cred env NAMES, merged (union) with the scheduler list. **Often unnecessary:** a `LOOMCYCLE_*`-named *verification* secret is auto-allowed, and a *static* (yaml) webhook's own secret/cred names are auto-trusted. You only need this for a **non-`LOOMCYCLE_`-named** secret, or an **agent-reachable** `user_credentials_from_env` on a **runtime**-authored (`webhookdef`-tool) def. Full rules: [webhooks.md](webhooks.md). (v0.23.0 brew binary: only `LOOMCYCLE_SCHEDULER_ENV_ALLOWLIST` was read, with no auto-allow — the original F23 trap.) |
| `LOOMCYCLE_WEBHOOKS_ENABLED` | Inbound webhooks (RFC H). `1` mounts `POST /v1/_webhooks/{name}`. Off by default. A team that declares its own webhooks is refused while this is off (v1.104.0). Full config in [webhooks.md](webhooks.md). |
| `LOOMCYCLE_WEBHOOKS_ALLOW_UNAUTHENTICATED` | **(v0.23.3, F23/#385)** `1` opts into `auth.kind: none` ingress (skip HMAC for a receiver only reachable over an already-authenticated transport — WireGuard/tailnet, mTLS). Default OFF — a `none`-auth webhook `503`s `unauthenticated_mode_disabled`. Only set on a genuinely private listen surface. |
| `LOOMCYCLE_A2A_ENABLED` / `_SERVER_CARD` / `_PUBLIC_BASE_URL` / `_TENANCY_ROUTING` | Agent2Agent protocol (RFC G). `_SERVER_CARD` is the **name of the active server card** and is required when A2A is enabled (startup fails without it); a card whose active version is retired no longer serves (v1.104.0). `_TENANCY_ROUTING` is `none` \| `host` \| `path`. |

## Multi-tenant authorization (RFC L)

| Var | Default | Purpose |
|---|---|---|
| `LOOMCYCLE_OPERATOR_TOKEN_PEPPER` | (unset) | Mixed into the token hash; a stolen DB dump without it yields no usable lookup. **Set for any multi-tenant deployment.** |
| `LOOMCYCLE_AUTH_CACHE_TTL_SECONDS` | 30 | Per-replica token-resolution cache TTL. `0` = direct lookup / immediate revocation. |
| `LOOMCYCLE_OPERATOR_TOKEN_ROTATION_GRACE_SECONDS` | 86400 | Default rotation grace window (old token valid this long after rotate). |
| `LOOMCYCLE_AUDIT_LOG_PATH` | (unset) | JSONL audit of every token create/rotate/retire (never a token or hash). **Since v1.55.0 subject erasure also writes here and is DISABLED without it** — it will not delete without a durable record of who asked. |
| `LOOMCYCLE_AUTH_VERBOSE` | off | `1` logs a server-side reason on a rejected bearer (the wire 401 stays opaque). |
| `LOOMCYCLE_OPERATOR_KEY_RESTRICTION` | off | **(v1.12.0)** `1` = a run whose principal lacks the `providers:operator-key` scope may not fall back to the operator's host provider key: it routes only to providers the tenant can key itself (a CredentialDef) and is refused `403 operator_key_restricted` if none. Also governs decision calls and consolidation sweeps. Off ⇒ nothing changes for existing tokens. |
| `LOOMCYCLE_UI_LOGIN_ORIGINS` | (unset) | Comma-separated first-party origins the Web UI login may accept a bearer handoff from. Empty = cross-origin handoff disabled. |

The closed scope catalog a token may carry: `substrate:admin`,
`substrate:tenant`, `substrate:user`, `runs:create`, `runs:read`,
`channel:publish`, `channel:read`, `providers:operator-key`. **Minting requires
an explicit scope list** (v1.87.0) — see [profiles.md](profiles.md) §5.

See the `/loomcycle:operator-token` command and the README's multi-tenant
section for the token lifecycle + the legacy-token-disable gotcha.

## Credentials, usage & budgets (RFC AR / AV / AW)

| Var | Default | Purpose |
|---|---|---|
| `LOOMCYCLE_SECRET_KEY` | (unset) | **Secret** — base64 32-byte KEK for the encrypted `CredentialDef` store (RFC AR). **Fail-closed: unset ⇒ the credential store is disabled** (`create` refused, never plaintext). Per-tenant HKDF key derived from it; AES-256-GCM at rest. `openssl rand -base64 32`. `.env.local` only. See [credentials.md](credentials.md). |
| `LOOMCYCLE_SECRET_KEY_PREVIOUS` | (unset) | **Secret** — the prior KEK during rotation: decrypt-old, re-encrypt-on-write. Drop it once every row has been rewritten under the new key. |
| `LOOMCYCLE_USAGE_SWEEPER` | on | The usage rollup-and-prune sweeper: `token_usage` rows older than the detail retention are folded into the day-bucketed `usage_archive` and deleted (totals preserved). `0` disables. |
| `LOOMCYCLE_USAGE_DETAIL_RETENTION_MS` | 2592000000 (30 d) | How long per-call `token_usage` detail is kept before rollup. |
| `LOOMCYCLE_USAGE_SWEEP_INTERVAL_MS` | 3600000 (1 h) | Sweep cadence. |
| `LOOMCYCLE_USAGE_RUN_RETENTION_MS` / `_RUN_RETENTION_MODE` / `LOOMCYCLE_USAGE_EXPORT_DIR` | 0 (off) / `off` / (unset) | Opt-in **destructive** old-run archiver: completed runs older than the cutoff are deleted. Mode is `off` \| `prune` \| `export+prune`; `export+prune` needs the export dir. |

A broader opt-in retention sweeper (`LOOMCYCLE_RETENTION_ENABLED=1` plus the
`LOOMCYCLE_RETENTION_*` mode / max-age knobs for retired defs, chats, memory and
empty dossiers) is documented in the env template and readable at
`GET /v1/_retention`.

Token **budgets** (RFC AW, `token_limits`) have **no env var** — they're set in
the Web UI Limits console / `PUT /v1/_limits` and require only a persistent store.
See [token-limits.md](token-limits.md).

## Cluster / multi-replica (Postgres required)

| Var | Default | Purpose |
|---|---|---|
| `LOOMCYCLE_REPLICA_ID` | (unset) | Unique per replica (`^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$`). **SQLite refuses to start when this is set** — Postgres only. |
| `LOOMCYCLE_HEARTBEAT_SWEEPER` | on | The stale-**run** sweeper (marks a run whose heartbeat stopped as failed). On by default; `0` disables it. Not cluster-specific. |
| `LOOMCYCLE_HEARTBEAT_STALE_MS` / `LOOMCYCLE_HEARTBEAT_SWEEP_INTERVAL_MS` | 600000 (10 min) / 60000 | A run with no heartbeat this long is swept / the sweep cadence. |
| `LOOMCYCLE_REPLICAS_STALE_AFTER_MS` / `LOOMCYCLE_REPLICAS_SWEEP_INTERVAL_MS` | 90000 / 60000 | Dead-**replica** reaping: a replica silent this long is reaped (its runs failed, quota slots reclaimed) / the reaper cadence. |
| `LOOMCYCLE_CANCEL_ACK_TIMEOUT_MS` | 5000 | Cross-replica cancel ack timeout. |
| `LOOMCYCLE_PAUSE_CACHE_TTL_MS` | 1000 | Cluster-wide pause-state cache lag. |
| `LOOMCYCLE_SESSION_LOCK_GC_INTERVAL_MS` / `LOOMCYCLE_SESSION_LOCK_MAX_IDLE_MS` | 300000 / 600000 | Session-continuation lock GC cadence / idle cutoff. |

## Observability

| Var | Purpose |
|---|---|
| `LOOMCYCLE_OTEL_EXPORTER_OTLP_ENDPOINT` | OTLP endpoint for distributed traces; unset = tracing off. |
| `LOOMCYCLE_OTEL_EXPORTER_OTLP_HEADERS` / `LOOMCYCLE_OTEL_SERVICE_NAME` / `LOOMCYCLE_OTEL_TRACES_SAMPLER_RATIO` | OTEL tuning: collector headers (may carry auth — treat as **secret**), service name (default `loomcycle`), sample fraction 0–1 (default 1.0). |
| `LOOMCYCLE_METRICS_ENABLED` | `1` enables the CPU/mem sampler → `/v1/_metrics/*`. |
| `LOOMCYCLE_METRICS_SAMPLE_INTERVAL_MS` / `_RETENTION_DAYS` / `_SWEEP_INTERVAL_MS` / `_COLLECT_SYSTEM` | Sampler tuning (defaults: 5s / 7d / 15m). `_COLLECT_SYSTEM=1` also reads `/proc/stat`+`/proc/meminfo` for **system-wide** CPU%/mem (Linux only). Without it, co-tenant **host** pressure — a hypervisor balloon, ZFS ARC eating RAM in a shared VM — is **invisible** to loomcycle's own metrics (the sampler only sees its own process, and only while a run is active; F19). It is not a substitute for an external host monitor. |

## anthropic-oauth-dev (research/dev only — never production)

`LOOMCYCLE_ANTHROPIC_OAUTH_DEV_ENABLED=1` to expose the provider, then
`loomcycle anthropic login`. `LOOMCYCLE_ANTHROPIC_OAUTH_CALLBACK_PORT` and
`LOOMCYCLE_CLAUDE_CODE_VERSION` (User-Agent self-patch on drift) are the related
knobs. Single-machine, single-operator, no SLA, ToS risk. Excluded from
multi-tenant and multi-replica by design. The token lives at
`~/.config/loomcycle/anthropic-oauth.json` (mode `0600`) — **outside the repo and
the loomcycle DB**, so it never commits and never reaches the F32 at-rest
transcript path. Full setup + routing walkthrough: [routing.md](routing.md).

`loomcycle anthropic status` prints only **local token-file metadata** (it can
read "valid" while Anthropic has already revoked the token). **v0.23.3** (F6/#392)
adds **`--probe`** (alias `--verify`) to confirm server-side — it does a free
token refresh and reports `✓ valid` (exit 0, rotating + persisting a fresh token
on success) / `✗ INVALID` (exit 1). **v0.23.3** (F7/#391) also makes concurrent
loomcycle processes share the token file safely — a cross-process `flock` +
reload-before-refresh — so the oauth-dev provider no longer corrupts its token
(`invalid_grant`, forced re-login) under parallel runs. On a **v0.23.0** binary
neither exists: `status` is local-only and a single process must own the token.
