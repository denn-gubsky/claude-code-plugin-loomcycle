# Environment variable catalogue

The **posture** axis. Checked against loomcycle **v1.156.0**. Authoritative
sources: loomcycle `docs/CONFIGURATION.md` (§9l and the per-feature sections),
the embedded `.env.insecure.example` (one catalogue, with the code's defaults)
and `internal/config`. `loomcycle env-template` prints the annotated template on
any install.

> **Read [settings.md](settings.md) first.** Since **v1.153.0** the environment
> holds only secrets, host and process identity (listen addresses, directories,
> public URLs, replica id) and security gates. Policy and tuning live in the yaml
> (`storage:`, `retention:`, `concurrency:`, `providers.<id>.options`,
> `timeout_scaling:`, `metrics:`, …), unused limits are constants, and 150 old
> variables are no longer read. Where a setting has both forms the variable wins,
> except `auth.mode` (the stricter wins) and a provider's `base_url` (the yaml
> wins). The variables retired in v1.153.0 that this page used to list are in the
> [table at the end](#retired-in-v11530), with where each one went.

**Never have this plugin write the operator's *secret* env file; print the
secret lines for the operator.** Secrets (`*_API_KEY`, `LOOMCYCLE_AUTH_TOKEN`,
`LOOMCYCLE_OPERATOR_TOKEN_PEPPER`, `LOOMCYCLE_SECRET_KEY`, any DSN, any
`token_env` value) are referenced by name only.

> **Where the secrets live depends on the install path** (CONFIGURATION.md,
> "The secrets file"): `auth.env` beside `loomcycle.yaml` for `loomcycle init
> --with-token` (the only file loomcycle reads itself — at start, for variables
> not already set); `env.local` beside `env.insecure` in `examples/profiles/`;
> `.env.local` after `.env.insecure` for a source checkout's `loomcycle.sh` /
> `loomcycle-mcp.sh` launcher (`LOOMCYCLE_ENV_FILE=<path>` collapses the pair
> into one file); `.env` for the compose examples; `.env.secure` for the cloud
> kit. The seam is **name vs value**: a webhook's `signing_secret_env:
> LOOMCYCLE_X` *name* is non-secret config; the value lives in the secrets file.

## Identity, listen, auth

| Var | Default | Purpose |
|---|---|---|
| `LOOMCYCLE_LISTEN_ADDR` | `127.0.0.1:8787` | HTTP/SSE listen. Use `0.0.0.0:8787` inside a container so port-mapping works; keep `127.0.0.1` on a host you don't want exposed. |
| `LOOMCYCLE_AUTH_TOKEN` | (empty) | Bearer for every `/v1/*` route. **Empty, with no config `principals:` and no admin operator token = open mode** — every route, token minting included, unauthenticated. **(v1.119.0)** Open mode is refused at boot on any listener beyond loopback (see `LOOMCYCLE_ALLOW_OPEN_MODE`); on loopback it warns every 10 minutes. Declaring config `principals:` alone also turns auth on. `openssl rand -hex 32`, or `loomcycle init --with-token`. |
| `LOOMCYCLE_ALLOW_OPEN_MODE` | off | **(v1.119.0)** `1` lets open mode start on a listener beyond loopback. Throwaway test harness on a private network only. |
| `LOOMCYCLE_AUTH_MODE` | `token` | **(v1.123.0)** `token` (paste-a-token Web UI sign-in) or `strict` (a person signs in only through a gate in `auth.gates`). **Since v1.153.0 the effective mode is the stricter** of this and the yaml `auth.mode`; an advisory names the one that decided, and `loomcycle validate` prints the mode with its source. See [identity.md](identity.md). |
| `LOOMCYCLE_UI_INSECURE_COOKIES` | off | **(v1.123.0)** `1` lets strict mode start Web UI sessions over plain HTTP (e.g. a tailnet). Behind a TLS terminator set an `https://` `LOOMCYCLE_PUBLIC_URL` instead. |
| `LOOMCYCLE_GRPC_ADDR` | (unset) | gRPC listen address (optional second transport). |
| `LOOMCYCLE_PUBLIC_URL` | (unset) | The instance's externally reachable URL (`Context op=self` `server.url`, links in rendered documents, gate redirects and invites). An `https://` value makes the session cookie `__Host-lc_session` and adds HSTS. Required by `external`, `device` and `passkey` gates (the passkey relying party is its host). See [identity.md](identity.md). |
| `LOOMCYCLE_PUBLIC_CONFIG` | off | `1` lets `GET /v1/config` be read with **no bearer**, returning a narrowed public view. An invalid bearer still `401`s. |
| `LOOMCYCLE_MAX_REQUEST_BYTES` | 16 MiB | Run-ingest request body cap; over it → `413`. |
| `LOOMCYCLE_WEBUI_DIR` | (unset) | **(v1.122.0)** Serve the Web UI from an unpacked UI bundle (built SPA + `manifest.json` with per-file SHA-256) instead of the built-in UI. Keep the directory operator-writable only. |
| `LOOMCYCLE_WEBUI_BUNDLE_URL` / `LOOMCYCLE_WEBUI_BUNDLE_SHA256` | (unset) | **(v1.122.0)** Instead of a directory: an `https` URL of a Web UI release archive, verified against the SHA-256 and cached under `LOOMCYCLE_DATA_DIR/webui`. A failed fetch never stops the boot. |

## Config sources (presets + layering)

| Var | Default | Purpose |
|---|---|---|
| `LOOMCYCLE_PRESETS` | (unset) | Comma-separated embedded presets layered as the base of the config stack. The profiles `personal` and `server` (v1.153.0) each stand for a whole stack; the units are `base`, `oauth`, `local`, `bedrock`, `loomboard` and the bundles `chat`, `document-agent`, `memory`, `system-channels`, `dev-workspace`, `agent-teams`, `team-examples`, `doc-colorizer`, `knowledge-base`, `skybits-sync`. `--preset` wins over it, and it wins over the primary file's `presets:` key (an advisory names both when they differ). An unknown name is fatal. See [settings.md](settings.md#presets-and-profiles). |
| `LOOMCYCLE_CONFIG_DIR` | (unset) | A directory whose `*.yaml`/`*.yml` layer in lexical order, above the presets and below `--config`. **Since v1.153.0** its `agents/`, `skills/` and `help/` subdirectories are also loaded when the matching `*_ROOT` variable is unset. Set-but-missing is fatal. |
| `LOOMCYCLE_CONFIG_STRICT` | off | `1` makes any cross-layer conflict a **fatal** load error (otherwise each override is logged at startup). Recommended in production. |
| `LOOMCYCLE_NO_DEFAULT_PROVIDERS` | off | `1` drops the built-in provider layer so only your own `providers:` exist — e.g. local-only, or no `code-js` provider (the only way to keep code agents unavailable since v1.153.0). |
| `LOOMCYCLE_BEDROCK_REGION` | (unset) | **(v1.119.0)** Region the `bedrock` preset's providers call; required when that preset is selected. Credentials come from the standard AWS chain. See [routing.md](routing.md). |

Layer order, base → top: presets → `LOOMCYCLE_CONFIG_DIR` → each `--config`
(repeatable). Details and the merge rule: [routing.md](routing.md).

## Storage

The store is **inferred** (v1.153.0): Postgres when `LOOMCYCLE_PG_DSN` (or yaml
`storage.pg_dsn`) is set, SQLite otherwise; yaml `storage.backend` pins it.

| Var | Default | Purpose |
|---|---|---|
| `LOOMCYCLE_DATA_DIR` | `./data` (the server images set `/home/nonroot/.local/share/loomcycle`, v1.153.0) | SQLite store + transient state dir. |
| `LOOMCYCLE_PG_DSN` | (unset) | **Secret** — Postgres DSN (`postgres://…?sslmode=require`); **its presence selects Postgres**. Set `storage.backend` too: an inferred Postgres beside an existing SQLite `loomcycle.db` refuses to open. |
| `LOOMCYCLE_PG_AUTOMIGRATE` | yaml `storage.pg_automigrate` | `1` runs schema migrations at boot, `0` keeps them off whatever the yaml says (v1.153.0: read both ways). Any other non-empty value stops the load. Off, boot refuses a database behind the binary until `loomcycle migrate up`. |
| `LOOMCYCLE_PG_MAX_OPEN_CONNS` | 32 | Pool size per replica (session-locked continuations pin one conn each). Wins over `storage.pg_max_open_conns`. |
| `LOOMCYCLE_PG_MIN_IDLE_CONNS` | 4 | Idle pool floor. Wins over `storage.pg_min_idle_conns`. |
| `LOOMCYCLE_PGVECTOR_ENABLED` | off | `1` uses pgvector on Postgres (vector memory; also needed for full-text in `Document op=search`). Boot fails if the extension is missing. |
| `LOOMCYCLE_SQLITE_VEC_PATH` | (unset) | Path to the sqlite-vec extension library (binaries built with the `sqlite_vec` tag). |

## Built-in tool sandboxes and egress

File tools need a `volumes:` block ([volumes.md](volumes.md)). Commands run
in a workspace, turned on in yaml with `workspace.mode`, not by an env switch
([workspaces.md](workspaces.md)). `Bash` and Bashbox were **removed in
v1.172.0**: their variables now refuse the start (see
[Retired in v1.172.0](#retired-in-v11720--refuse-the-start)).

| Var | Default | Purpose |
|---|---|---|
| `LOOMCYCLE_HTTP_HOST_ALLOWLIST` | (unset = refuse all) | `HTTP`+`WebFetch`: comma-separated **suffix-match** host allowlist; `*` allows any public host. Private and CGNAT addresses are hard-blocked at connect regardless. Env-only: a reload cannot change it. |
| `LOOMCYCLE_HTTP_PRIVATE_HOST_ALLOWLIST` | (unset) | Hosts that may resolve to private IPs at dial (a localhost callback). An entry may be a **CIDR range** (`100.64.0.0/10` for a tailnet). Also the only way a runtime-authored remote memory backend, document source or tenant MCP server reaches a private host. |
| `LOOMCYCLE_HTTP_PRIVATE_HOST_ALLOWLIST_MODE` | (unset) | **(v1.142.0)** `cidr_only` refuses host names in the private-host lists (this one and the yaml `hooks.private_host_allowlist`), puts the operator's MCP servers behind the guard (list their addresses as CIDRs), and makes `LOOMCYCLE_MCP_ALLOW_PRIVATE_IPS=1` fail startup. |
| `LOOMCYCLE_HTTP_CALLER_AUTHORITATIVE` | off | `1` = a request's `allowed_hosts` is the whole policy for that run. A restricted token can only narrow, even with this set. |
| `BRAVE_API_KEY` / `SERPER_API_KEY` / `EXA_API_KEY` / `TAVILY_API_KEY` | (unset) | **Secrets** — `WebSearch` provider keys (SearXNG is keyless, configured in yaml `search_providers:`). |
| `LOOMCYCLE_WEBSEARCH_PROVENANCE` | off | `1` appends a `(via <provider>)` footer to each search result. |
| `LOOMCYCLE_REDACT_SECRETS` | on | Tool inputs/outputs are scanned for secret-shaped substrings and masked before they are persisted. `0` disables. The live SSE stream is not redacted. |
| `LOOMCYCLE_MCP_ALLOW_PRIVILEGED_TOOLS` | off | `1` lets agents registered through MCP `register_agent` keep `Write`, `Edit` and `Workspace`; otherwise they are stripped. Only for a trusted MCP client. |
| `LOOMCYCLE_MCP_ALLOW_DYNAMIC_STDIO` | off | `1` lets a runtime-authored MCP server (`mcpserverdef`) use `transport: stdio` — it **runs a local command**. Static yaml `mcp_servers:` are unaffected. |
| `LOOMCYCLE_MCP_ALLOW_PRIVATE_IPS` | on | `0` enables a dial-time DNS-rebinding block for the MCP-HTTP client (operator yaml and admin-saved servers; a **tenant's** runtime MCP server always dials through the egress guard). |
| `LOOMCYCLE_MCP_REFUSE_UNATTRIBUTED_ENV` | refuse | A stored runtime MCP server def holding a `${NAME}` env reference without an admin-save record is refused (v1.113.0). `0` keeps the old warn-and-dial while re-saves are pending. |
| `LOOMCYCLE_MCP_MAX_FRAME_BYTES` | 16 MiB | **(v1.122.0)** Largest single MCP response read from a mounted server (a stdio line or an HTTP body). |
| `LOOMCYCLE_KMS_VAULT_ALLOW_HTTP` | off | **(v1.116.0)** `1` admits a plain-`http` (dev) Vault for a crypto key in Vault Transit. |

The hooks' private-host and permit-widen lists are yaml only since v1.153.0
(`hooks.private_host_allowlist`, `hooks.permit_host_widen.owners`) — see
[hooks.md](hooks.md). Crypto caps are constants (1 MiB per data argument, 100
calls per run).

## Files from tools, extraction and conversion

A file a tool returns is kept in the run tree's **inbox** volume (needs a
volume marked `dynamic_root: true`). See [files.md](files.md).

| Var | Default | Purpose |
|---|---|---|
| `LOOMCYCLE_FILE_MAX_BYTES` | 64 MiB | **(v1.122.0)** One kept or downloaded file. |
| `LOOMCYCLE_FILE_INBOX_MAX_BYTES` | 1 GiB | **(v1.122.0)** A run tree's whole inbox. |
| `LOOMCYCLE_EXTRACT_CONCURRENCY` | the CPU count | **(v1.142.0)** File extractions (extract, import, OCR page cuts) the process runs at once. With conversion workers, it still bounds `op=import`. |
| `LOOMCYCLE_HELPER_WRAPPER` | (unset) | **(v1.142.0)** A sandbox command (e.g. `bwrap …`) every helper program (ffmpeg, pdftoppm) runs under. |
| `LOOMCYCLE_AUDIO_MAX_INFLIGHT` | 2 | **(v1.153.0)** Engine requests each audio route (`/v1/audio/speech`, `/v1/audio/transcriptions`) keeps in flight; one value sizes both queues. |
| `LOOMCYCLE_WORKER_TOKEN` | (unset) | **Secret (v1.153.0)** — required (≥ 32 characters) on the runtime and the workers when `conversion.mode` is `remote` or `local+remote`. `local` mode makes its own. |

The base64 capture minimum is per MCP server since v1.154.1
(`mcp_servers.<name>.binary_results_min_bytes`, default 4096). Conversion
workers are the yaml `conversion:` block — default `local` on Linux since
v1.154.0; the worker process's own `LOOMCYCLE_WORKER_*` variables are in
CONFIGURATION.md §9n. OCR, speech-to-text and text-to-speech are yaml
(`transcription:`, `speech:`).

## Git (sources and the Git tool)

Off unless hosts are listed. Size, time and history limits are constants since
v1.153.0. See [git.md](git.md).

| Var | Default | Purpose |
|---|---|---|
| `LOOMCYCLE_GIT_SOURCE_HOSTS` | (unset = off) | **(v1.113.0)** Hosts a repository may be fetched from — git-sourced volumes and the `Git` tool's clone / fetch / pull. Host names only (a URL stops the load). |
| `LOOMCYCLE_GIT_PUSH_HOSTS` | (unset = no push) | **(v1.122.0)** Hosts the `Git` tool may push to. |
| `LOOMCYCLE_GIT_AUTHOR_NAME` / `LOOMCYCLE_GIT_AUTHOR_EMAIL` | the agent's name / `<agent>@loomcycle.invalid` | **(v1.122.0)** Author and committer of the `Git` tool's commits. |

## Filesystem roots (discovery)

| Var | Default | Purpose |
|---|---|---|
| `LOOMCYCLE_AGENTS_ROOT` | `<LOOMCYCLE_CONFIG_DIR>/agents` when it exists | Dir of `<name>.md` agent files. In an adopted config-dir `agents/`, a `.md` with no frontmatter is skipped. Set to the empty string to decline the default. |
| `LOOMCYCLE_SKILLS_ROOT` | `<LOOMCYCLE_CONFIG_DIR>/skills` when it exists | Dir of `<name>/SKILL.md` skills. Operator-trusted content. |
| `LOOMCYCLE_HELP_ROOT` | `<LOOMCYCLE_CONFIG_DIR>/help` when it exists | `<name>.md` topics for `Context op=help`; a `tools/` subdirectory holds operator tool articles. |
| `LOOMCYCLE_CODE_AGENTS_ROOT` | `./agent_code` | Where code-js agents live (`<root>/<name>/index.js`). |

Inline `skills:` and `agents:` in yaml (and the embedded bundles) need no root.
Code agents (`provider: code-js`) and code hooks are always available since
v1.153.0; the code-js budgets are `providers.code-js.options`
(`run_timeout_seconds` 120, `max_wall_seconds` 86400, `deterministic` false).

## Memory, documents and SQL Memory

| Var | Default | Purpose |
|---|---|---|
| `LOOMCYCLE_MEMORY_MAX_SCOPE_BYTES` | 1 MiB | Per-(scope, scope_id) byte cap; an agent's `memory_quota_bytes` overrides. `0` = no cap. |
| `LOOMCYCLE_MEMORY_PENDING_DRAINED_TTL_MS` | 7 d | **(v1.101.0)** Drained consolidation-queue rows are deleted after this long; `0` keeps them. |
| `LOOMCYCLE_MEMORY_CHANGES_ENABLED` | off | `1` records the memory change feed that change subscriptions and the document feed deliver from. |
| `LOOMCYCLE_MEMORY_TRACE_INDEX` | off | `1` (or `true`) indexes each user turn so past conversations are searchable. How long: yaml `retention.trace.max_age` (30 d). |
| `LOOMCYCLE_MEMORY_TRACE_ASSISTANT` | off | `1` also indexes assistant turns. |
| `LOOMCYCLE_DEADLINK_GC` | `on` | **(v1.153.0)** The hourly collection of unreachable chunk references: `on` deletes, `dry-run` only counts and logs, `off` does not run. Any other value stops the boot. |
| `LOOMCYCLE_MAX_CONSOLIDATION_TARGETS` | 32 | Consolidation targets one fan-out tick dispatches; the rest defer. |
| `LOOMCYCLE_MAX_CONSOLIDATION_CONCURRENCY` | 4 | Parallel consolidation children on a non-local model (a local model is always serial). |
| `LOOMCYCLE_RERANKER_API_KEY` / `LOOMCYCLE_UNIT_GENERATOR_API_KEY` / `LOOMCYCLE_CLASSIFIER_API_KEY` | — | The credential name a tenant or user credential uses to key `memory.reranker` / `memory.unit_generator` / `memory.classifier` when its block sets `base_url` without `api_key_env`. See [routing.md](routing.md). |

**SQL Memory** (the `sql_query`/`sql_exec` facet of `Memory`, and the
prerequisite for Documents) has **no on-switch since v1.153.0**: it is on with a
SQLite store, and on with a Postgres store when `LOOMCYCLE_SQLMEM_PG_DSN` is
set; `storage.sqlmem_enabled: false` turns it off. Its query limits (rows,
result bytes, statement / transaction timeouts, open transactions, savepoint
depth, GC cadence, snapshot scope cap) are `storage.sqlmem_*` yaml keys. See
[document.md](document.md).

| Var | Default | Purpose |
|---|---|---|
| `LOOMCYCLE_SQLMEM_PG_DSN` | (unset) | **Secret** — a separate database for the Postgres tier; **its presence turns SQL Memory on with Postgres**. Its role needs `CREATEROLE` (per-scope login roles; a scope holding documents gets a second `sqlmem_dr_…` role — `pg_hba` must admit it, see [profiles.md](profiles.md)). |
| `LOOMCYCLE_SQLMEM_ROOT` | `<data dir>/sqlmem` | Directory of the per-scope sqlite files. |
| `LOOMCYCLE_SQLMEM_QUOTA_BYTES` | 0 = none | Size cap of one scope; an agent's `sql_quota_bytes` overrides. |
| `LOOMCYCLE_SQLMEM_AUDIT_MODE` | `full` | `full` audits each statement (redacted); `metadata` only op, scope and row counts. |
| `LOOMCYCLE_SQLMEM_SCOPE_TTL_MS` | 0 = off | Drops agent and user scopes idle this long (deletes data). |
| `LOOMCYCLE_SQLMEM_TOTAL_MAX_BYTES` | 0 = off | Over this total, the largest idle scopes are dropped (deletes data). |
| `LOOMCYCLE_SQLMEM_SHARED_SCHEMAS` | (unset) | Postgres tier: read-only schemas added to every scope's `search_path`, visible to every tenant. |

Each of these seven also has a `storage.sqlmem_*` yaml key; the variable wins.
Embedder batch size and timeout are `memory.embedder.batch_size` /
`timeout_ms`; the document projection is `memory.projection.enabled` +
`interval` (yaml).

> **`memory_scopes` is an agent-yaml gate, not an env var — and since v1.82.0
> unset is no longer deny.** An agent with `Memory` in `tools` and **no**
> `memory_scopes:` list resolves to what the caller already owns: `user`, plus
> `tenant` for a non-isolated member. A declared list is authoritative. To grant
> nothing in a static agent, leave `Memory` out of `tools:`. The same default
> applies to `history_scope` (`user`), `sql_scopes` (`["user"]`) and
> `evaluation_scopes` (`["submit_self"]`).

## Channels and teams

| Var | Default | Purpose |
|---|---|---|
| `LOOMCYCLE_CHANNELS_LONGPOLL_CAP_MS` | 30000 | Server cap on a `Channel.subscribe` `wait_ms`; a larger value is truncated (logged once per channel). **Each re-subscribe consumes one `max_iterations`**, so raise the cap (e.g. `180000`) and/or the agent's `max_iterations` for agents that block waiting for a signal. `0` disables long-polling. |
| `LOOMCYCLE_TEAM_SUBSCRIPTIONS` | off | **(v1.77.0)** `1` arms team subscriptions: a promoted team whose source has work is started by the runtime. Swept every 15 s (constant). |

Channel hooks always run since v1.153.0 (a channel's `hooks:` are always
applied); the channel payload cap (64 KiB), deferred-publish timers and
hook-worker sizes are constants.

## MCP (the plugin's thin client and the runtime's `/v1/_mcp`)

| Var | Default | Purpose |
|---|---|---|
| `LOOMCYCLE_MCP_SPAWN_RUN_TIMEOUT_MS` | 0 = none | Operator default transport timeout for `spawn_run`: the run is cancelled and `status:"timeout"` returned. A per-call `timeout_ms` can narrow it. Applies to `/v1/_mcp` (the plugin's topology). Set in the **runtime's** environment. A non-integer or negative value stops the load. |
| `LOOMCYCLE_MCP_UPSTREAM_TOKEN` | (unset) | **Secret** — the bearer `loomcycle mcp --upstream` presents. Set in the *thin client's* environment. **(v1.126.0)** Unset, the thin client uses the token `loomcycle login` stored in the OS keychain (no Windows support). |
| `LOOMCYCLE_MCP_RECIPES_ROOT` | (unset) | Directory overlay of MCP server recipes for `loomcycle mcp-registry` / `import --emit-recipes`. |

The thin client's header timeout (60 s; long-running tools exempt) and
reconnect attempts (5) are constants since v1.153.0, and so is the stdio
server's dispatch width (16 calls). The thin client loads no config: a retired
variable in its environment is only advised (a `WARN` at start). Since v1.107.0
a member token's MCP session is held to its scopes; full map:
[../../../reference/mcp-tools.md](../../../reference/mcp-tools.md).

## Runs and sub-agents

Run concurrency and queueing are the yaml `concurrency:` block
(`max_concurrent_runs` 8, `max_queue_depth` 32, `max_concurrent_runs_per_user`
0, `max_queued_runs_per_user` 16, `provider_queue_depth` 0 = `max_queue_depth`)
— see [routing.md](routing.md#the-run-queue-v11130--v11140).

| Var | Default | Purpose |
|---|---|---|
| `LOOMCYCLE_MAX_LIVE_CHILDREN_PER_RUN` | 32 | **(v1.105.0)** Children one run has alive at once; a spawn past it is refused whole. |
| `LOOMCYCLE_MAX_INTERACTIVE_CHILDREN` | 8 | Resident (`Agent op=open`) children one run holds open. |
| `LOOMCYCLE_MAX_CONFIGURED_RUNS_PER_USER` | 100 | **(v1.93.0)** Draft runs one (tenant, user) may hold; `0` = no cap. |
| `LOOMCYCLE_CONFIGURED_RUN_TTL_MS` | 24 h | **(v1.93.0)** How long a draft run is kept; `0` keeps them. |
| `LOOMCYCLE_INTERACTIVE_IDLE_TIMEOUT` | `1h` | **(v1.119.0)** How long a top-level interactive run parked for its operator waits before ending (`idle_timeout`; its session is kept). `0` waits forever; unparsable refuses startup. |
| `LOOMCYCLE_BATCH_JOIN_TIMEOUT` | `1h` | **(v1.120.0)** How long a `join`-mode batch (`spawn_runs`) waits when the request gives no `timeout_ms`; no child is cancelled. `0` = no server bound. |
| `LOOMCYCLE_SHUTDOWN_PAUSE_TIMEOUT_MS` | 7000 | **(v1.119.0)** On SIGTERM in-flight runs park for up to this long (capped at 5 min) and resume after restart. Raise it with the platform's stop grace period. A fan-out parent always keeps its children (resume is always on since v1.153.0). |

Resident-child idle reaping (30 min; `idle_ttl_seconds` on `open` overrides per
child), the resident turn cap (2 h), the poll wait cap (60 s), no ceiling on a
spawn's `timeout_ms`, the registered-agent TTL (24 h) and the definition size
caps are constants — see [Fixed values](#fixed-values-no-setting).

## Providers

| Var | Default | Purpose |
|---|---|---|
| `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `DEEPSEEK_API_KEY`, `GEMINI_API_KEY`, `OLLAMA_API_KEY` | (unset) | **Secrets** — a provider with no key is skipped. |
| `OLLAMA_BASE_URL` | `http://localhost:11434` | Local Ollama endpoint (`disabled` opts out). A yaml `providers.ollama-local.base_url` wins over it. |
| `OLLAMA_CLOUD_BASE_URL`, `DEEPSEEK_BASE_URL`, `GEMINI_BASE_URL` | provider default | Endpoint overrides; a yaml `base_url` wins. |
| `LOOMCYCLE_OLLAMA_LOCAL_NUM_CTX` | (unset) | Context window for **all** `ollama-local` models. **Since v1.153.0 it wins over** `providers.ollama-local.options.num_ctx` (boot warns when they differ). Unset, the yaml option, else the window Ollama reports, else Ollama's 4096. A per-agent `max_context_tokens` wins over it. |
| `LOOMCYCLE_FALLBACK_PIN_AFTER_SUCCESS` | off | `1` keeps a run on its provider after one successful turn (see routing.md). |
| `LOOMCYCLE_MOCK_ENABLED` (+ `_LATENCY_MS` 50, `_LATENCY_JITTER_MS` 25, `_429_RATE` 0, `_500_RATE` 0) | off | `1` enables the `mock` / `mock-stable` providers for cost-free load tests. |

Stream timeouts, hosted `num_ctx`, local `num_gpu` and the code-agent budgets
are `providers.<id>.options` since v1.153.0; model-speed measurement is the
yaml `timeout_scaling:` block. Provider re-probe runs every 15 min (constant);
`POST /v1/_resolve/probe` forces one. See [routing.md](routing.md).

## Triggers: schedules, webhooks, A2A

The scheduler and the inbound webhook receiver are **always on** since
v1.153.0: a schedule fires unless its definition is disabled, and a webhook
answers while its definition exists. See [webhooks.md](webhooks.md).

| Var | Default | Purpose |
|---|---|---|
| `LOOMCYCLE_SCHEDULER_TICK_SECONDS` | 30 | Poll cadence for due schedules. Every replica may run the scheduler; each slot is fired by the one replica that claims it. |
| `LOOMCYCLE_SCHEDULER_ENV_ALLOWLIST` | (unset) | Env-var NAMES the scheduler (and, merged, the webhook receiver and mem9 backend) may resolve as secrets/bearers. |
| `LOOMCYCLE_WEBHOOKS_ENV_ALLOWLIST` | (unset) | The webhook-specific twin, merged (union) with the scheduler list. Often unnecessary: a `LOOMCYCLE_*`-named verification secret is auto-allowed, and a static (yaml) webhook's own names are auto-trusted. Full rules: [webhooks.md](webhooks.md). |
| `LOOMCYCLE_WEBHOOKS_ALLOW_UNAUTHENTICATED` | off | `1` admits `auth.kind: none` ingress, for a receiver reachable only over an already-authenticated network. Off, such a webhook answers `503`. |
| `LOOMCYCLE_A2A_SERVER_CARD` | (unset) | Name of the active server card. **Setting it turns A2A on** (v1.153.0): the server surface is mounted and outbound `a2a__*` tools are registered. A name with no such card stops the boot. |
| `LOOMCYCLE_A2A_PUBLIC_BASE_URL` | (unset) | Base URL advertised in the agent card. |
| `LOOMCYCLE_A2A_TENANCY_ROUTING` | `none` | `none` \| `host` \| `path`. |

## Multi-tenant authorization

| Var | Default | Purpose |
|---|---|---|
| `LOOMCYCLE_OPERATOR_TOKEN_PEPPER` | (unset) | Explicit token-hash pepper. Unset, a pepper is derived from `LOOMCYCLE_SECRET_KEY` (v1.119.0). **Since v1.156.0, set beside `LOOMCYCLE_SECRET_KEY` it is legacy:** new tokens use the derived pepper, old ones move as they log in; remove it when the boot line `auth: LOOMCYCLE_OPERATOR_TOKEN_PEPPER is legacy: …` counts no row. See [settings.md](settings.md#after-v11550-the-explicit-token-pepper-is-legacy). |
| `LOOMCYCLE_AUTH_CACHE_TTL_SECONDS` | 30 | Per-replica token-resolution cache TTL; `0` = immediate revocation. A bad value stops the load. |
| `LOOMCYCLE_OPERATOR_TOKEN_ROTATION_GRACE_SECONDS` | 86400 | Rotation grace window; `0` or unset = 24 h. |
| `LOOMCYCLE_USER_TOKEN_MAX_TTL_SECONDS` | (unset = no cap) | **(v1.112.0)** Longest lifetime a per-user token may be minted with; `0` is refused. |
| `LOOMCYCLE_TOKEN_AUTHORITY_INHERIT` | off | **(v1.126.0)** `1` mints per-user and gate-issued tokens with authority `inherit` (scopes follow the user's current `access_mode`). |
| `LOOMCYCLE_RUN_RATE_PER_MINUTE` / `LOOMCYCLE_RUN_RATE_BURST` | (unset) | **(v1.112.0)** Default rate for run starts, steers and A2A starts for a token that carries no `rate` (1–60000; burst defaults to the rate). Operators are never bound by it. |
| `LOOMCYCLE_LIMITS_ENFORCE` | (unset) | **(v1.112.0)** `strict` makes a hard token budget also stop runs in flight and refuse sub-agents. See [token-limits.md](token-limits.md). |
| `LOOMCYCLE_ACL` | `compat` | **(v1.122.0)** Access-control mode: `compat` → `shadow` → `enforce`. See [access-control.md](access-control.md). |
| `LOOMCYCLE_ACL_CACHE_TTL_SECONDS` | 5 | **(v1.122.0)** How long a replica trusts a compiled ACL set (`0` = every request). |
| `LOOMCYCLE_ACL_LIVE` | off | **(v1.126.0)** `1` makes a run in flight follow its caller's access-control rules as they change (only ever narrowing). |
| `LOOMCYCLE_OPERATOR_KEY_RESTRICTION` | off | **(v1.12.0)** `1` = a run whose principal lacks `providers:operator-key` may not fall back to the operator's provider key. |
| `LOOMCYCLE_AUDIT_STORE` | inferred | `1` turns on the store-backed, hash-chained audit stream where the posture does not already require it (a sign-in gate, strict mode, `LOOMCYCLE_ACL` other than `compat`, or more than one principal does); `0` is refused where it is required. Needs `LOOMCYCLE_SECRET_KEY`. |
| `LOOMCYCLE_AUDIT_RETENTION_DAYS` | 0 = forever | **(v1.142.0)** How long the store-backed audit stream keeps rows; older rows are pruned behind a signed anchor. |
| `LOOMCYCLE_AUDIT_LOG_PATH` | (unset) | JSONL mirror of the audit trail (token create/rotate/retire, erasure, …). |

The closed scope catalog a token may carry: `substrate:admin`,
`substrate:tenant`, `substrate:user`, `runs:create`, `runs:read`,
`runs:delete`, `channel:publish`, `channel:read`, `providers:operator-key`,
`llm:gateway`, `auth:manage`, `scim:provision`, and `metrics:read` (v1.148.0 —
`/metrics` only). **Minting requires an explicit scope list** (v1.87.0) — see
[profiles.md](profiles.md) and the `/loomcycle:operator-token` command.

## Credentials

| Var | Default | Purpose |
|---|---|---|
| `LOOMCYCLE_SECRET_KEY` | (unset) | **Secret** — base64 32-byte key for the encrypted `CredentialDef` store, sessions, the audit chain and the derived token pepper. **Fail-closed:** unset ⇒ the credential store is disabled. Required with more than one principal. `openssl rand -base64 32`. See [credentials.md](credentials.md). |
| `LOOMCYCLE_SECRET_KEY_PREVIOUS` | (unset) | **Secret** — the prior key during rotation. |

Token **budgets** have no env var — set in the Web UI Limits console /
`PUT /v1/_limits`; see [token-limits.md](token-limits.md). What is deleted with
age is the yaml `retention:` block ([settings.md](settings.md)); the usage
rollup always runs (`retention.usage_detail.max_age`, 30 d).

## Cluster / multi-replica (Postgres required)

| Var | Default | Purpose |
|---|---|---|
| `LOOMCYCLE_REPLICA_ID` | (unset) | Unique per replica; turns on cluster mode and labels metrics. **SQLite refuses to start when this is set.** |
| `LOOMCYCLE_HEARTBEAT_STALE_MS` | 600000 (10 min) | A run with no heartbeat this long is swept (the sweeper always runs, every 60 s). |
| `LOOMCYCLE_REPLICAS_STALE_AFTER_MS` / `LOOMCYCLE_REPLICAS_SWEEP_INTERVAL_MS` | 90000 / 60000 | A replica silent this long is reaped (its runs failed, quota reclaimed) / the reaper cadence. |

## Observability

Tracing uses the **standard `OTEL_*` variables** since v1.148.0. Full detail
(sampling per tenant, `/metrics` series, tenant telemetry export):
[observability.md](observability.md).

| Var | Default | Purpose |
|---|---|---|
| `LOOMCYCLE_LOG_LEVEL` | `info` | **(v1.119.0)** `debug`, `info`, `warn`, `error`. Since v1.153.0 the old debug flags are debug lines here. |
| `LOOMCYCLE_LOG_FORMAT` | `text` | **(v1.119.0)** `text` or `json`. |
| `LOOMCYCLE_ENVIRONMENT` | (unset) | The `deployment.environment.name` resource attribute. |
| `OTEL_EXPORTER_OTLP_ENDPOINT` (+ `OTEL_EXPORTER_OTLP_PROTOCOL`, `OTEL_SERVICE_NAME`, `OTEL_TRACES_SAMPLER`, `OTEL_TRACES_SAMPLER_ARG`, …) | (unset = tracing off) | **(v1.148.0)** Standard OpenTelemetry configuration; the endpoint is a URL with its scheme. |
| `OTEL_EXPORTER_OTLP_HEADERS` / `LOOMCYCLE_OTEL_EXPORTER_OTLP_HEADERS_FILE` | (unset) | **Secret** collector headers, or a file holding them (not both). |
| `LOOMCYCLE_OTEL_INBOUND_CONTEXT` | `parent` | **(v1.148.0)** What an authenticated caller's `traceparent` does: `parent`, `link`, `ignore`. |
| `LOOMCYCLE_OTEL_RAW_USER_ID` | off | **(v1.148.0)** `1` also puts the raw user id on spans beside `loomcycle.user_hash`. |
| `LOOMCYCLE_TRACE_URL_TEMPLATE` | (unset) | **(v1.148.0)** An http(s) URL with `{trace_id}`; the Web UI links each traced run there. |
| `LOOMCYCLE_METRICS_LISTEN` | (unset) | **(v1.148.0)** A second, **unauthenticated** listener serving only `/metrics` (user-labelled series omitted). |
| `LOOMCYCLE_METRICS_RETENTION_DAYS` | 7 | Days of process-metrics samples kept; `0` keeps them all. The sampler itself is yaml `metrics:`. |
| `LOOMCYCLE_METRICS_CARDINALITY_LIMIT` / `LOOMCYCLE_METRICS_AGENT_LABEL` | 2000 / off | **(v1.148.0)** Series per `/metrics` instrument; `1` adds an `agent` label. |
| `LOOMCYCLE_TENANT_TELEMETRY` (+ `_ALLOW_HTTP`, `_MAX_RATIO`), `LOOMCYCLE_TENANT_CONTENT_CAPTURE` | off | **(v1.151.0)** Per-tenant trace and metric export to the tenant's own collector; allowed hosts are yaml `observability.tenant_telemetry.allowed_hosts`. |

## anthropic-oauth-dev (research/dev only — never production)

`LOOMCYCLE_ANTHROPIC_OAUTH_DEV_ENABLED=1` to expose the provider, then
`loomcycle anthropic login`. `LOOMCYCLE_ANTHROPIC_OAUTH_CALLBACK_PORT` (default
53692) and `LOOMCYCLE_CLAUDE_CODE_VERSION` are the related knobs.
Single-machine, single-operator, no SLA, ToS risk; excluded from multi-tenant
and multi-replica by design. The token lives at
`~/.config/loomcycle/anthropic-oauth.json` (mode `0600`), outside the repo and
the loomcycle DB. `loomcycle anthropic status` prints local token-file metadata;
`--probe` confirms server-side. Its timeouts are fixed (60 s headers, 90 s in a
stream) since v1.153.0. Setup: [routing.md](routing.md).

## Fixed values (no setting)

Constants since v1.153.0 (each is the old default; a deployment that never set
the variable sees no change). From CONFIGURATION.md "Fixed limits".

| What | Value |
|---|---|
| Agent definition / description / inline code body | 128 KiB / 8 KiB / 256 KiB |
| Team definition | 1 MiB |
| Skill body / description | 128 KiB / 8 KiB |
| Evaluation judgement / rationale | 32 KiB / 8 KiB |
| Git clone: bytes / object / file / files / time / history / concurrency | 256 MiB / 64 MiB / 5 MiB / 100000 / 120 s / 500 commits / 1 per replica |
| Git push | 100 MiB |
| Crypto data argument / calls per run | 1 MiB / 100 |
| Document image and `/v1/_document` body | 8 MiB |
| Document search filter | 50000 chunk ids (`filter_too_wide`) |
| Document feed streams per principal | 4 |
| Relation evidence quotes | 32 |
| Memory value / channel message | 64 KiB / 64 KiB |
| Deferred-publish timers | 10000 |
| Channel-hook worker / per channel / fail-closed wait | 16 / 4 / 15 min |
| Tool calls of one turn run at once | 8 |
| Registered (MCP) agent lifetime | 24 h unless `ttl_seconds` |
| Resident child idle / resident turn / `Agent op=poll` wait | 30 min / 2 h / 60 s |
| Spawn `timeout_ms` ceiling | none |
| Client-tool call / frame / connections | 60 s / 1 MiB / 8 per principal |
| Pause wait / cancel ack / pause-state cache | 30 s / 5 s / 1 s |
| Token limit reload | 1 min |
| Expired token rows | deleted 7 days after expiry |
| stdio MCP dispatch / thin-client header wait / retries | 16 / 60 s / 5 |
| Change feed kept / delivered | 24 h / every 5 s |
| Tenant telemetry queue / pipelines | 512 spans / 256 |
| Sweeps: run heartbeat, ephemeral volumes / expired Memory, channel messages, dynamic agents, metrics samples, provider re-probe, session locks / usage rollup / team subscriptions / SSE keepalive | 60 s / 15 min / 5 min (idle 10 min) / 1 h / 15 s / 20 s |
| Chats of internal agents (when chat retention is on) | deleted after 3 days |

## Retired in v1.172.0 — refuse the start

Removed with the `Bash` tool, Bashbox and its host-command fallback. **Each one
set to a non-empty value stops the server at start**, with a line naming it
(set but empty, it is reported as a dead line; `loomcycle doctor` lists them
under "Removed"). Never print one as a live setting. Replacements are in
[workspaces.md](workspaces.md) and loomcycle `docs/MIGRATING-FROM-BASH.md`.

| Retired variable | Now |
|---|---|
| `LOOMCYCLE_BASH_ENABLED` | `workspace.mode` (yaml) + the `Workspace` tool with a `workspace` grant |
| `LOOMCYCLE_BASH_ALLOWED_CREDS` | An egress route with a credential (`workspace.egress.routes`, or an `EgressRouteDef`) |
| `LOOMCYCLE_BASHBOX_ENABLED` | Nothing — Bashbox is gone; use a workspace |
| `LOOMCYCLE_BASHBOX_FALLBACK_COMMANDS`, `LOOMCYCLE_BASHBOX_FALLBACK_ALLOWED_ENV` | Run the commands in a workspace whose worker image carries them; a session gets no host variable |
| `LOOMCYCLE_BASHBOX_FALLBACK_ALLOWED_CREDS` | An egress route with a credential, or for git a git workspace opened with a credential (or the `Git` tool) |
| `LOOMCYCLE_BASHBOX_OVERLAY_MAX_BYTES` | Nothing — a workspace has a disk quota (`workspace.disk_quota_mb`) |

The `sandbox` and `dev-exec` values of `LOOMCYCLE_PRESETS` refuse the start the
same way: select `dev-workspace`.

## Retired in v1.153.0

Variables this page listed before v1.153.0 that are **no longer read**. Do not
set them; a set one is reported at boot (and by `validate` / `doctor`), and some
values refuse the boot until acted on — see [settings.md](settings.md#upgrading-from-before-v11530--checklist).
Per-variable rules: loomcycle `docs/SETTINGS_MIGRATION.md` §7, tables A–E.

| Retired variable(s) | Now |
|---|---|
| `LOOMCYCLE_STORAGE_BACKEND` | Inferred from `LOOMCYCLE_PG_DSN`; pin with yaml `storage.backend` |
| `LOOMCYCLE_SQLMEM_ENABLED` | Inferred (on with SQLite; on with Postgres when `LOOMCYCLE_SQLMEM_PG_DSN` is set); off with `storage.sqlmem_enabled: false` |
| `LOOMCYCLE_SQLMEM_MAX_ROWS`, `_STATEMENT_TIMEOUT_MS`, `_TXN_TIMEOUT_MS`, `_MAX_OPEN_TXNS`, `_MAX_TXN_DEPTH`, `_GC_INTERVAL_MS` (all `LOOMCYCLE_SQLMEM_*`) | yaml `storage.sqlmem_max_rows`, `…_statement_timeout_ms`, `…_txn_timeout_ms`, `…_max_open_txns`, `…_max_txn_depth`, `…_gc_interval_ms` |
| `LOOMCYCLE_CONFIG_FILES` | Gone; pass each file as `--config`, or place it in `LOOMCYCLE_CONFIG_DIR` (set and non-empty, it refuses the boot) |
| `LOOMCYCLE_SCHEDULER_ENABLED`, `LOOMCYCLE_WEBHOOKS_ENABLED`, `LOOMCYCLE_CHANNEL_HOOKS`, `LOOMCYCLE_CODE_AGENTS_ENABLED`, `LOOMCYCLE_CODE_HOOKS_ENABLED`, `LOOMCYCLE_RESUME_FANOUT` | Always on (any value but `1` refuses the boot) |
| `LOOMCYCLE_A2A_ENABLED` | Inferred: A2A is on when `LOOMCYCLE_A2A_SERVER_CARD` is set |
| `LOOMCYCLE_HEARTBEAT_SWEEPER`, `LOOMCYCLE_USAGE_SWEEPER`, `LOOMCYCLE_MEMORY_PROVISION_IDENTITY_DOCS` | Always on (`0` / off refuses the boot) |
| `LOOMCYCLE_RETENTION_ENABLED` and the `LOOMCYCLE_RETENTION_*` interval, export dir, family modes, ages and keep-last-N | yaml `retention:` (`enabled`, `interval`, `export_dir`, `<family>.mode` / `max_age`, `defs.keep_last_n`) |
| `LOOMCYCLE_USAGE_DETAIL_RETENTION_MS` | yaml `retention.usage_detail.max_age` |
| `LOOMCYCLE_USAGE_RUN_RETENTION_MS`, `LOOMCYCLE_USAGE_RUN_RETENTION_MODE`, `LOOMCYCLE_USAGE_EXPORT_DIR` | The usage archiver is gone; yaml `retention.chats` + `retention.export_dir` |
| `LOOMCYCLE_MAX_CONCURRENT_RUNS_PER_USER`, `LOOMCYCLE_MAX_QUEUED_RUNS_PER_USER`, `LOOMCYCLE_PROVIDER_QUEUE_DEPTH` | yaml `concurrency.max_concurrent_runs_per_user`, `.max_queued_runs_per_user`, `.provider_queue_depth` |
| `LOOMCYCLE_PROVIDER_HEADER_TIMEOUT_MS`, `LOOMCYCLE_PROVIDER_IDLE_TIMEOUT_MS` | yaml `providers.<id>.options.header_timeout_ms` / `idle_timeout_ms`, per provider |
| `LOOMCYCLE_OLLAMA_LOCAL_HEADER_TIMEOUT_MS`, `LOOMCYCLE_OLLAMA_LOCAL_IDLE_TIMEOUT_MS`, `LOOMCYCLE_OLLAMA_LOCAL_NUM_GPU` | yaml `providers.ollama-local.options.header_timeout_ms` / `idle_timeout_ms` / `num_gpu` |
| `LOOMCYCLE_OLLAMA_NUM_CTX` | yaml `providers.ollama.options.num_ctx` |
| `LOOMCYCLE_CODE_AGENTS_RUN_TIMEOUT_SECONDS`, `LOOMCYCLE_CODE_AGENTS_MAX_WALL_SECONDS`, `LOOMCYCLE_CODE_AGENTS_DETERMINISTIC` | yaml `providers.code-js.options.run_timeout_seconds` / `max_wall_seconds` / `deterministic` |
| `LOOMCYCLE_TIMEOUT_SCALING`, `LOOMCYCLE_TIMEOUT_SCALING_REFERENCE_TPS`, `LOOMCYCLE_TIMEOUT_SCALING_MAX_MULTIPLIER` | yaml `timeout_scaling.mode`, `.reference.decode_tps`, `.max_multiplier` |
| `LOOMCYCLE_MEMORY_EMBED_BATCH_SIZE`, `LOOMCYCLE_MEMORY_EMBED_TIMEOUT_MS` | yaml `memory.embedder.batch_size` / `timeout_ms` |
| `LOOMCYCLE_DOCUMENT_PROJECTION_INTERVAL` | yaml `memory.projection.interval` **and** `memory.projection.enabled: true` |
| `LOOMCYCLE_METRICS_ENABLED`, `LOOMCYCLE_METRICS_COLLECT_SYSTEM`, `LOOMCYCLE_METRICS_SAMPLE_INTERVAL_MS` | yaml `metrics.enabled`, `.collect_system`, `.sample_interval` (the `server` preset sets the first two) |
| `LOOMCYCLE_METRICS_SWEEP_INTERVAL_MS` | Constant (15 min); keep-days stays `LOOMCYCLE_METRICS_RETENTION_DAYS` |
| `LOOMCYCLE_UI_LOGIN_ORIGINS` | yaml `auth.login_origins` (a list, one origin per item) |
| `LOOMCYCLE_HOOKS_PRIVATE_HOST_ALLOWLIST`, `LOOMCYCLE_HOOKS_PERMIT_HOST_WIDEN_OWNERS` | yaml `hooks.private_host_allowlist`, `hooks.permit_host_widen.owners` (the yaml list is the whole list) |
| `LOOMCYCLE_FILE_BASE64_MIN_BYTES` | yaml `mcp_servers.<name>.binary_results_min_bytes` (v1.154.1) |
| `LOOMCYCLE_DEADLINK_GC_MS`, `LOOMCYCLE_DEADLINK_GC_DRY_RUN` | `LOOMCYCLE_DEADLINK_GC` = `on` \| `dry-run` \| `off`; cadence fixed at 1 h |
| `LOOMCYCLE_AUTH_VERBOSE`, `LOOMCYCLE_OLLAMA_DEBUG_THINK` | `LOOMCYCLE_LOG_LEVEL=debug` |
| `LOOMCYCLE_OTEL_EXPORTER_OTLP_ENDPOINT`, `LOOMCYCLE_OTEL_EXPORTER_OTLP_HEADERS`, `LOOMCYCLE_OTEL_SERVICE_NAME`, `LOOMCYCLE_OTEL_TRACES_SAMPLER_RATIO` | Already unread since v1.148.0: `OTEL_EXPORTER_OTLP_ENDPOINT` (with scheme), `OTEL_EXPORTER_OTLP_HEADERS` or `LOOMCYCLE_OTEL_EXPORTER_OTLP_HEADERS_FILE`, `OTEL_SERVICE_NAME`, `OTEL_TRACES_SAMPLER=parentbased_traceidratio` + `OTEL_TRACES_SAMPLER_ARG` |
| `LOOMCYCLE_READ_ROOT`, `LOOMCYCLE_WRITE_ROOT`, `LOOMCYCLE_BASH_CWD` | Dead since v1.1.0 (a `volumes:` block); any non-empty value refuses the boot |
| `LOOMCYCLE_SSE_KEEPALIVE_MS`, `LOOMCYCLE_TOOL_PARALLELISM`, `LOOMCYCLE_RESOLVE_PROBE_INTERVAL_MS`, `LOOMCYCLE_EPHEMERAL_VOLUME_SWEEP_MS`, `LOOMCYCLE_MEMORY_SWEEP_MS`, `LOOMCYCLE_CHANNELS_SWEEP_MS`, `LOOMCYCLE_HEARTBEAT_SWEEP_INTERVAL_MS`, `LOOMCYCLE_USAGE_SWEEP_INTERVAL_MS`, `LOOMCYCLE_SESSION_LOCK_GC_INTERVAL_MS`, `LOOMCYCLE_SESSION_LOCK_MAX_IDLE_MS`, `LOOMCYCLE_TEAM_SUBSCRIPTIONS_TICK_SECONDS`, `LOOMCYCLE_EXPIRED_TOKEN_RETENTION_SECONDS` | Constants (cadences and periods above) |
| `LOOMCYCLE_MEMORY_MAX_VALUE_BYTES`, `LOOMCYCLE_CHANNELS_MAX_VALUE_BYTES`, `LOOMCYCLE_CHANNELS_MAX_PENDING_DEFERRED` | Constants (a lowered value refuses the boot) |
| `LOOMCYCLE_CHANNEL_HOOKS_CONCURRENCY`, `LOOMCYCLE_CHANNEL_HOOKS_PER_CHANNEL`, `LOOMCYCLE_CHANNEL_HOOKS_MAX_WAIT` | Constants (a set value only warns) |
| `LOOMCYCLE_AGENT_DEF_MAX_DEFINITION_BYTES`, `LOOMCYCLE_AGENT_DEF_MAX_CODE_BYTES`, `LOOMCYCLE_TEAM_DEF_MAX_DEFINITION_BYTES`, `LOOMCYCLE_DYNAMIC_AGENT_DEFAULT_TTL_SECONDS` | Constants |
| `LOOMCYCLE_INTERACTIVE_CHILD_IDLE_TTL_MS`, `LOOMCYCLE_RESIDENT_MAX_TURN_SECONDS`, `LOOMCYCLE_AGENT_CHILD_MAX_TIMEOUT_MS`, `LOOMCYCLE_AGENT_POLL_WAIT_CAP_MS` | Constants (30 min idle, `idle_ttl_seconds` on `open` per child; 2 h turn; no ceiling; 60 s) |
| `LOOMCYCLE_PAUSE_DEFAULT_TIMEOUT_MS`, `LOOMCYCLE_PAUSE_CACHE_TTL_MS`, `LOOMCYCLE_CANCEL_ACK_TIMEOUT_MS` | Constants (30 s, 1 s, 5 s) |
| `LOOMCYCLE_MCP_MAX_CONCURRENT_CALLS`, `LOOMCYCLE_MCP_UPSTREAM_HEADER_TIMEOUT_MS`, `LOOMCYCLE_MCP_UPSTREAM_RECONNECT_ATTEMPTS` | Constants (16, 60 s, 5) |
| `LOOMCYCLE_CRYPTO_MAX_BYTES`, `LOOMCYCLE_CRYPTO_MAX_OPS_PER_RUN` | Constants (1 MiB, 100) |
| `LOOMCYCLE_GIT_SOURCE_MAX_BYTES`, `_MAX_OBJECT_BYTES`, `_MAX_FILE_BYTES`, `_MAX_FILES`, `_TIMEOUT_SECONDS`, `_MAX_HISTORY`, `_MAX_CONCURRENT` (all `LOOMCYCLE_GIT_SOURCE_*`), `LOOMCYCLE_GIT_PUSH_MAX_BYTES` | Constants (table above) |
| `LOOMCYCLE_DOCUMENT_SEARCH_FILTER_MAX_IDS`, `LOOMCYCLE_DOCUMENT_EVIDENCE_MAX_PER_EDGE`, `LOOMCYCLE_DOCUMENT_FEED_MAX_STREAMS` | Constants (50000, 32, 4) |

Also removed earlier and still unread: `LOOMCYCLE_PROVIDER_QUEUE_TIMEOUT_MS`
(v1.113.0) and `LOOMCYCLE_SCHEDULER_FIRE_TIMEOUT_SECONDS` (v1.105.0).
