# Environment variable catalogue

The **posture** axis. Authoritative source: loomcycle `.env.example` +
`internal/config`. Set these in the operator's environment (e.g. `.env.local`
sourced by `loomcycle.sh`, container `-e` flags, or systemd unit) — **never have
this plugin write the env file; print the lines for the operator.**

Secrets (`*_API_KEY`, `LOOMCYCLE_AUTH_TOKEN`, `LOOMCYCLE_OPERATOR_TOKEN_PEPPER`)
are referenced by name only and live in the operator's secret store / keychain,
never in a repo file.

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
| `LOOMCYCLE_SCHEDULER_ENABLED` / `_TICK_SECONDS` / `_FIRE_TIMEOUT_SECONDS` / `_ENV_ALLOWLIST` | Scheduled runs (RFC E). Env-allowlist gates which env vars schedules may reference. |
| `LOOMCYCLE_WEBHOOKS_ENABLED` | Inbound webhooks (RFC H). Off by default. |
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
| `LOOMCYCLE_METRICS_SAMPLE_INTERVAL_MS` / `_RETENTION_DAYS` / `_SWEEP_INTERVAL_MS` / `_COLLECT_SYSTEM` | Sampler tuning (defaults: 5s / 7d / 15m; `_COLLECT_SYSTEM=1` reads /proc on Linux). |

## anthropic-oauth-dev (research/dev only — never production)

`LOOMCYCLE_ANTHROPIC_OAUTH_DEV_ENABLED=1` to expose the provider, then
`loomcycle anthropic login`. `LOOMCYCLE_ANTHROPIC_OAUTH_CALLBACK_PORT` and
`LOOMCYCLE_CLAUDE_CODE_VERSION` (User-Agent self-patch on drift) are the related
knobs. Single-machine, single-operator, no SLA. Excluded from multi-tenant and
multi-replica by design (tokens at `~/.config/loomcycle/anthropic-oauth.json`).
