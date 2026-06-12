# Environment variable catalogue

The **posture** axis. Authoritative source: loomcycle `.env.insecure.example` +
`.env.local.example` + `internal/config`. Set these in the operator's environment
(the two env files below, container `-e` flags, or a systemd unit) — **never have
this plugin write the *secret* env file; print the secret lines for the operator.**

Secrets (`*_API_KEY`, `LOOMCYCLE_AUTH_TOKEN`, `LOOMCYCLE_OPERATOR_TOKEN_PEPPER`)
are referenced by name only and live in the operator's secret store / keychain,
never in a repo file.

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

## Storage

| Var | Default | Purpose |
|---|---|---|
| `LOOMCYCLE_STORAGE_BACKEND` | `sqlite` | `sqlite` or `postgres`. Postgres required for multi-replica. |
| `LOOMCYCLE_DATA_DIR` | `./data` | SQLite store + transient state dir. |
| `LOOMCYCLE_PG_DSN` | (unset) | Postgres DSN — required when backend is postgres (`postgres://…?sslmode=require`). |
| `LOOMCYCLE_PG_AUTOMIGRATE` | — | Run migrations on boot. |
| `LOOMCYCLE_PG_MAX_OPEN_CONNS` | pool default | Set to `MaxConcurrentRuns × 1.5` per replica (session-locked continuations pin one conn each). |
| `LOOMCYCLE_PG_MIN_IDLE_CONNS` | — | Idle pool floor. |
| `LOOMCYCLE_PGVECTOR_ENABLED` / `LOOMCYCLE_SQLITE_VEC_PATH` | — | Vector memory backends. |

## Built-in tool sandboxes (default-deny — each tool refuses until set)

| Var | Purpose |
|---|---|
| `LOOMCYCLE_READ_ROOT` | `Read` tool: agents may read files **inside this dir only**. Symlinks resolved before the check (no escape). Unset = Read refuses every call. |
| `LOOMCYCLE_WRITE_ROOT` | `Write`+`Edit` tools: same shape; atomic tempfile+rename. Unset = refuse. |
| `LOOMCYCLE_BASH_ENABLED` | `1` to enable `Bash`. **Not a true sandbox** — cwd-restricted, env-scrubbed (only PATH leaks), output-bounded (1 MiB), time-capped (30s default, 5min max). Containerize if exposed to untrusted prompts. |
| `LOOMCYCLE_BASH_CWD` | Working dir Bash runs in. |
| `LOOMCYCLE_HTTP_HOST_ALLOWLIST` | `HTTP`+`WebFetch`: comma-separated **suffix-match** host allowlist (`example.com` matches `api.example.com`, not `evilexample.com`). Private IPs (RFC1918/loopback/link-local incl. 169.254.169.254) are **hard-blocked at connect** regardless. Unset = refuse all outbound. |
| `LOOMCYCLE_HTTP_PRIVATE_HOST_ALLOWLIST` | Exception list: hosts here may resolve to private IPs at dial (e.g. a localhost app callback). Must ALSO be on the main allowlist. Only lifts the IP-private rejection. |
| `LOOMCYCLE_HTTP_CALLER_AUTHORITATIVE` | `1` = caller's per-request `allowed_hosts` is the sole policy (operator list is a default). Unset = caller can only *narrow* the operator's static list. |
| `BRAVE_API_KEY` | `WebSearch` tool (Brave Search; 2k/mo free tier). |
| `LOOMCYCLE_MCP_ALLOW_PRIVILEGED_TOOLS` | `1` lets **dynamically-registered** agents request privileged builtins (`Bash`/`Write`/`Edit`); stripped silently otherwise. Only flip on when the MCP client is trusted (operator-launched stdio = trusted; remote HTTP MCP = NOT). |
| `LOOMCYCLE_MCP_ALLOW_DYNAMIC_STDIO` | **(v0.23.3, F31/#405)** `1` lets a **runtime-authored** MCP server (`POST /v1/_mcpserverdef` / the `mcpserverdef` tool) use `transport: stdio` — which **runs an arbitrary local command**, so it is **off by default** and refused with an explicit error otherwise. `http`/`streamable-http` dynamic servers need no flag (mediated by the outbound host allowlist); **static `mcp_servers:` stdio in yaml is operator-trusted and unaffected**. Only set on a host where the MCP-authoring principal is trusted to name local commands. |

## Filesystem roots (discovery)

| Var | Purpose |
|---|---|
| `LOOMCYCLE_AGENTS_ROOT` | Dir of `<name>.md` agent files (frontmatter + system-prompt body). |
| `LOOMCYCLE_SKILLS_ROOT` | Dir of `<name>/SKILL.md` skills. Operator-trusted content — don't point at an untrusted-writable dir. Unset = agents may not list skills. |
| `LOOMCYCLE_HELP_ROOT` | Optional override dir for `Context.help` topics. |

## code-js synthetic provider (operator JavaScript agents)

| Var | Purpose |
|---|---|
| `LOOMCYCLE_CODE_AGENTS_ENABLED` | `1` to allow `provider: code-js` agents (operator JS via goja; `eval`/`Function` deleted, no ambient fetch/fs). Off by default — operator-trust posture like Bash. |
| `LOOMCYCLE_CODE_AGENTS_ROOT` | Dir holding `<name>/index.js`. Missing/unparsable file fails loud at startup. Path-traversal agent names refused. |
| `LOOMCYCLE_CODE_AGENTS_RUN_TIMEOUT_SECONDS` | Whole-run wall-clock bound (code-js agents are exempt from MaxIterations). |
| `LOOMCYCLE_CODE_AGENTS_DETERMINISTIC` | `1` freezes clock+seed for snapshot equality. |

## Memory

| Var | Default | Purpose |
|---|---|---|
| `LOOMCYCLE_MEMORY_MAX_VALUE_BYTES` | 65536 | Per-write value cap (set/incr). 0 disables. |
| `LOOMCYCLE_MEMORY_MAX_SCOPE_BYTES` | 1048576 | Per-(scope,scope_id) byte cap; per-agent `memory_quota_bytes` overrides. |
| `LOOMCYCLE_MEMORY_SWEEP_MS` | 900000 | TTL reaper cadence. Read paths filter expired rows even when off. |

> **`memory_scopes` is default-deny (an agent-yaml gate, not an env var).** These
> env vars only tune limits — they do **not** grant access. An agent with
> `Memory` in `allowed_tools` but **no** `memory_scopes:` list sees every Memory
> call refused. Give it `memory_scopes: [agent]` (and/or `user`) to enable it
> (the second default-deny layer — see SKILL.md safety rule #3).

## Channels

| Var | Default | Purpose |
|---|---|---|
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

> **MCP tool set (v0.32.0):** the meta-tool catalogue grew to 42 — two new
> tools the plugin wraps as `/loomcycle:fanout` and `/loomcycle:compact`:
> **`spawn_runs`** (RFC Y external fan-out — ≤32 fresh runs in one call,
> index-aligned envelope, per-child failures don't fail the batch) and
> **`compact_run`** (summarise a *parked* run's history). `spawn_run` also gained
> an optional per-run `compaction` override. None changes the `--upstream` wiring.

## Pause / resume

| Var | Default | Purpose |
|---|---|---|
| `LOOMCYCLE_RESUME_FANOUT` | off (0) | **(v0.31.0, RFC X Phase 3)** `1` enables durable park+resume of a **fan-out parent** blocked in `Agent.parallel_spawn` — loomcycle captures spawn-ledger events so a parent quiesced by pause (or a crashed/restarted replica) re-dispatches its in-flight children from the transcript instead of stranding them. Default OFF keeps the pre-v0.31 pause/resume/snapshot paths byte-identical; opt in for long fan-out orchestrations that must survive a restart. (Single-run cross-instance resume needs no flag — v0.30.0.) |

## Concurrency, fairness, provider timeouts

| Var | Default | Purpose |
|---|---|---|
| `LOOMCYCLE_MAX_CONCURRENT_RUNS_PER_USER` | — | Per-user fairness cap (cluster-wide on Postgres). |
| `LOOMCYCLE_TOOL_PARALLELISM` | — | Max concurrent tool calls within a run. |
| `LOOMCYCLE_PROVIDER_HEADER_TIMEOUT_MS` | 60000 | Per-attempt time-to-first-byte cap. |
| `LOOMCYCLE_PROVIDER_IDLE_TIMEOUT_MS` | 90000 | Max gap between streamed body bytes. |
| `LOOMCYCLE_RESOLVE_PROBE_INTERVAL_MS` | 900000 (15m) | Provider re-probe cadence. `POST /v1/_resolve/probe` forces an immediate one. |
| `LOOMCYCLE_FALLBACK_PIN_AFTER_SUCCESS` | off | `1` suppresses cross-provider fallback after ≥1 successful turn (see routing.md). |

## Scheduler / Webhooks / A2A (off by default)

| Var | Purpose |
|---|---|
| `LOOMCYCLE_SCHEDULER_ENABLED` / `_TICK_SECONDS` / `_FIRE_TIMEOUT_SECONDS` | Scheduled runs (RFC E). |
| `LOOMCYCLE_SCHEDULER_ENV_ALLOWLIST` | Comma-separated env-var NAMES the **scheduler** (and, merged, the webhook receiver + mem9 backend) may resolve as secrets/bearers. The shared trigger-credential gate. For webhooks, prefer the better-named twin below; this one still works (union). |
| `LOOMCYCLE_WEBHOOKS_ENV_ALLOWLIST` | **(v0.23.3, F23/#385)** The webhook-specific, correctly-named twin — comma-separated secret/cred env NAMES, merged (union) with the scheduler list. **Often unnecessary:** a `LOOMCYCLE_*`-named *verification* secret is auto-allowed, and a *static* (yaml) webhook's own secret/cred names are auto-trusted. You only need this for a **non-`LOOMCYCLE_`-named** secret, or an **agent-reachable** `user_credentials_from_env` on a **runtime**-authored (`webhookdef`-tool) def. Full rules: [webhooks.md](webhooks.md). (v0.23.0 brew binary: only `LOOMCYCLE_SCHEDULER_ENV_ALLOWLIST` was read, with no auto-allow — the original F23 trap.) |
| `LOOMCYCLE_WEBHOOKS_ENABLED` | Inbound webhooks (RFC H). `1` mounts `POST /v1/_webhooks/{name}`. Off by default. Full config in [webhooks.md](webhooks.md). |
| `LOOMCYCLE_WEBHOOKS_ALLOW_UNAUTHENTICATED` | **(v0.23.3, F23/#385)** `1` opts into `auth.kind: none` ingress (skip HMAC for a receiver only reachable over an already-authenticated transport — WireGuard/tailnet, mTLS). Default OFF — a `none`-auth webhook `503`s `unauthenticated_mode_disabled`. Only set on a genuinely private listen surface. |
| `LOOMCYCLE_A2A_ENABLED` / `_SERVER_CARD` / `_PUBLIC_BASE_URL` / `_TENANCY_ROUTING` | Agent2Agent protocol (RFC G). `_TENANCY_ROUTING=host|path` for per-route tenancy. |

## Multi-tenant authorization (RFC L)

| Var | Default | Purpose |
|---|---|---|
| `LOOMCYCLE_OPERATOR_TOKEN_PEPPER` | (unset) | Mixed into the token hash; a stolen DB dump without it yields no usable lookup. **Set for any multi-tenant deployment.** |
| `LOOMCYCLE_AUTH_CACHE_TTL_SECONDS` | 30 | Per-replica token-resolution cache TTL. `0` = direct lookup / immediate revocation. |
| `LOOMCYCLE_OPERATOR_TOKEN_ROTATION_GRACE_SECONDS` | 86400 | Default rotation grace window (old token valid this long after rotate). |
| `LOOMCYCLE_AUDIT_LOG_PATH` | (unset) | JSONL audit of every token create/rotate/retire (never a token or hash). |
| `LOOMCYCLE_AUTH_VERBOSE` | off | `1` logs a server-side reason on a rejected bearer (the wire 401 stays opaque). |

See the `/loomcycle:operator-token` command and the README's multi-tenant
section for the token lifecycle + the legacy-token-disable gotcha.

## Cluster / multi-replica (Postgres required)

| Var | Purpose |
|---|---|
| `LOOMCYCLE_REPLICA_ID` | Unique per replica (`^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$`). **SQLite refuses to start when this is set** — Postgres only. |
| `LOOMCYCLE_HEARTBEAT_SWEEPER` / `_STALE_MS` / `_SWEEP_INTERVAL_MS` | Replica heartbeats + dead-replica reaping (90s stale default). |
| `LOOMCYCLE_REPLICAS_STALE_AFTER_MS` / `_SWEEP_INTERVAL_MS` | Replica TTL reaping. |
| `LOOMCYCLE_CANCEL_ACK_TIMEOUT_MS` | 5000 | Cross-replica cancel ack timeout. |
| `LOOMCYCLE_PAUSE_CACHE_TTL_MS` | 1000 | Cluster-wide pause-state cache lag. |
| `LOOMCYCLE_SESSION_LOCK_GC_INTERVAL_MS` / `_MAX_IDLE_MS` | Session-continuation advisory-lock GC. |

## Observability

| Var | Purpose |
|---|---|
| `LOOMCYCLE_OTEL_EXPORTER_OTLP_ENDPOINT` | OTLP endpoint for distributed traces; unset = tracing off. |
| `LOOMCYCLE_OTEL_EXPORTER_OTLP_HEADERS` / `_SERVICE_NAME` / `_TRACES_SAMPLER_RATIO` | OTEL tuning. |
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
