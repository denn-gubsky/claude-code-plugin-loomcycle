# Where settings live (v1.153.0+)

Checked against loomcycle **v1.156.0**. Authoritative sources in the loomcycle
repo: `docs/CONFIGURATION.md` (opens with a start page per profile and one table
of where each setting lives) and `docs/SETTINGS_MIGRATION.md` (the upgrade
guide, with the full per-variable table). This page is the short form; the
variable catalogue is [env-vars.md](env-vars.md).

Since **v1.153.0** every setting has one place. Before it, loomcycle read about
318 environment variables; 150 of them are no longer read. Policy and tuning
moved to the yaml, limits nobody changed became constants, and seven feature
switches are gone because the features are always on. The runtime names each
removed variable you still set, and refuses to start when ignoring it would
loosen the deployment or move its data (see the upgrade checklist below).

Print env lines for the operator; never write their env file, and never put a
secret value in a file.

## The three planes

| Plane | Holds | Why there |
|---|---|---|
| **Environment** | Secrets, the identity of this host and process, and security gates | A secret must not sit in a reviewed, layered or shared file; one yaml should serve hosts that listen and store differently; a gate has no yaml form so no config layer or preset can open it |
| **Yaml config** | Policy and tuning: routing, agents, retention, concurrency, provider options, timeouts, sampling | The same on every replica, reviewable, and carried by a preset |
| **Constants** | Values no deployment needed to change | Nothing to set; listed in [env-vars.md](env-vars.md#fixed-values-no-setting) |

### Environment: what stays there

- **Secrets.** `LOOMCYCLE_AUTH_TOKEN`, `LOOMCYCLE_SECRET_KEY`,
  `LOOMCYCLE_SECRET_KEY_PREVIOUS`, `LOOMCYCLE_OPERATOR_TOKEN_PEPPER` (legacy since
  v1.156.0, see below), the variables your `principals:` name in `token_env`,
  `LOOMCYCLE_PG_DSN`, `LOOMCYCLE_SQLMEM_PG_DSN`, provider keys
  (`ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `DEEPSEEK_API_KEY`, `GEMINI_API_KEY`,
  `OLLAMA_API_KEY`), tool keys (`BRAVE_API_KEY`, …), collector credentials
  (`OTEL_EXPORTER_OTLP_HEADERS` or `LOOMCYCLE_OTEL_EXPORTER_OTLP_HEADERS_FILE`),
  and the variables webhook and schedule definitions name.
- **Host and process identity.** Listeners (`LOOMCYCLE_LISTEN_ADDR`,
  `LOOMCYCLE_GRPC_ADDR`, `LOOMCYCLE_METRICS_LISTEN`), URLs
  (`LOOMCYCLE_PUBLIC_URL`, `LOOMCYCLE_A2A_PUBLIC_BASE_URL`, `OLLAMA_BASE_URL`),
  paths (`LOOMCYCLE_DATA_DIR`, `LOOMCYCLE_SQLMEM_ROOT`, `LOOMCYCLE_CONFIG_DIR`,
  `LOOMCYCLE_SKILLS_ROOT`, `LOOMCYCLE_AGENTS_ROOT`, `LOOMCYCLE_HELP_ROOT`,
  `LOOMCYCLE_CODE_AGENTS_ROOT`, `LOOMCYCLE_AUDIT_LOG_PATH`,
  `LOOMCYCLE_WEBUI_DIR`), which config is loaded (`LOOMCYCLE_PRESETS`,
  `LOOMCYCLE_CONFIG_STRICT`, `LOOMCYCLE_NO_DEFAULT_PROVIDERS`), cluster
  membership (`LOOMCYCLE_REPLICA_ID`, `LOOMCYCLE_REPLICAS_*`,
  `LOOMCYCLE_HEARTBEAT_STALE_MS`), the database pool and migration
  (`LOOMCYCLE_PG_*`, `LOOMCYCLE_PGVECTOR_ENABLED`), logging and tracing
  (`LOOMCYCLE_LOG_LEVEL`, `LOOMCYCLE_LOG_FORMAT`, `LOOMCYCLE_ENVIRONMENT`, the
  standard `OTEL_*`), and sizes that follow the host
  (`LOOMCYCLE_OLLAMA_LOCAL_NUM_CTX`, `LOOMCYCLE_AUDIO_MAX_INFLIGHT`,
  `LOOMCYCLE_EXTRACT_CONCURRENCY`, `LOOMCYCLE_BASHBOX_OVERLAY_MAX_BYTES`).
- **Security gates.** Off unless set (a few tighten instead):
  `LOOMCYCLE_ALLOW_OPEN_MODE`, `LOOMCYCLE_AUTH_MODE`, `LOOMCYCLE_ACL`,
  `LOOMCYCLE_UI_INSECURE_COOKIES`, `LOOMCYCLE_OPERATOR_KEY_RESTRICTION`,
  `LOOMCYCLE_TOKEN_AUTHORITY_INHERIT`, `LOOMCYCLE_LIMITS_ENFORCE`;
  `LOOMCYCLE_BASH_ENABLED` and the `LOOMCYCLE_BASHBOX_FALLBACK_*` trio;
  `LOOMCYCLE_MCP_ALLOW_PRIVILEGED_TOOLS`, `LOOMCYCLE_MCP_ALLOW_DYNAMIC_STDIO`,
  `LOOMCYCLE_MCP_ALLOW_PRIVATE_IPS`; the `LOOMCYCLE_HTTP_*` host lists;
  `LOOMCYCLE_GIT_SOURCE_HOSTS`, `LOOMCYCLE_GIT_PUSH_HOSTS`;
  `LOOMCYCLE_WEBHOOKS_ALLOW_UNAUTHENTICATED` and the two trigger env
  allow-lists; `LOOMCYCLE_A2A_SERVER_CARD`, `LOOMCYCLE_A2A_TENANCY_ROUTING`;
  `LOOMCYCLE_TENANT_TELEMETRY`, `LOOMCYCLE_MEMORY_TRACE_INDEX`,
  `LOOMCYCLE_MEMORY_CHANGES_ENABLED`, `LOOMCYCLE_REDACT_SECRETS`,
  `LOOMCYCLE_AUDIT_RETENTION_DAYS`; the SQL Memory data-keeping variables
  (`LOOMCYCLE_SQLMEM_SCOPE_TTL_MS`, `_TOTAL_MAX_BYTES`, `_QUOTA_BYTES`,
  `_AUDIT_MODE`, `_SHARED_SCHEMAS`); `LOOMCYCLE_MOCK_ENABLED`,
  `LOOMCYCLE_KMS_VAULT_ALLOW_HTTP`.

A few tuning values are still variables with no yaml key, for example
`LOOMCYCLE_INTERACTIVE_IDLE_TIMEOUT`, `LOOMCYCLE_BATCH_JOIN_TIMEOUT` and
`LOOMCYCLE_MAX_CONSOLIDATION_TARGETS`. The full list is [env-vars.md](env-vars.md).

### Yaml: the policy and tuning blocks

Besides routing (`providers:`, `models:`, `tiers:`, `provider_priority:`,
`user_tiers:` — see [routing.md](routing.md)), agents, `volumes:`, `auth:` and
`principals:`, these blocks hold what used to be environment variables:

| Block | Keys | Default |
|---|---|---|
| `storage:` | `backend` (pins the store), `sqlmem_enabled`, the SQL Memory limits `sqlmem_max_rows`, `sqlmem_statement_timeout_ms`, `sqlmem_max_result_bytes`, `sqlmem_txn_timeout_ms`, `sqlmem_max_open_txns`, `sqlmem_max_open_txns_per_tenant`, `sqlmem_max_txn_depth`, `sqlmem_gc_interval_ms`, `sqlmem_snapshot_max_scope_bytes` | inferred backend; 10000 rows; 30000 ms; 8 MiB; 30000 ms; 64; a quarter of the cap; 16; 1 h; 0 = no cap |
| `retention:` | `enabled`, `interval`, `export_dir`, families `chats`, `defs` (+ `keep_last_n`), `mem`, `mem_content`, `empty_dossier` (each `mode` + `max_age`), `usage_detail.max_age`, `trace.max_age` | `enabled: false`; `1h`; families `off`; `keep_last_n: 5`; usage detail and trace `30d` |
| `concurrency:` | `max_concurrent_runs`, `max_queue_depth`, `max_concurrent_runs_per_user`, `max_queued_runs_per_user`, `provider_queue_depth` | 8; 32; 0 = no per-user cap; 16 (0 = refuse at once over the cap); 0 = `max_queue_depth` |
| `providers.<id>.options` | `header_timeout_ms`, `idle_timeout_ms` (each provider its own), `num_ctx` (`ollama`, `ollama-local`), `num_gpu` (`ollama-local`), `deterministic`, `run_timeout_seconds`, `max_wall_seconds` (`code-js`) | 60000 / 90000 (`ollama-local` 600000 / 600000); `deterministic: false`, 120 s active, 86400 s wall |
| `timeout_scaling:` | `mode` (`measure` \| `off`), `reference.decode_tps`, `max_multiplier` | `measure`; 100; 8 |
| `memory.embedder` | `batch_size`, `timeout_ms` (beside `provider` and `model`) | 100; 30000 |
| `memory.projection` | `enabled`, `interval` (both are needed to run it) | off |
| `metrics:` | `enabled`, `collect_system` (Linux), `sample_interval` (at least `1s`) | `false`; `false`; `5s` |
| `observability:` | `tracing.tenant_sampler_ratios` (tenant → 0–1), `tenant_telemetry.allowed_hosts` | none |
| `auth:` | `login_origins` (one origin per list item), with `mode`, `gates`, `clients`, `trusted_proxies` | none |
| `hooks:` | `permit_host_widen.owners` (`[tenant:]name`), `private_host_allowlist` (hosts and CIDR ranges) | empty |
| `mcp_servers.<name>` | `binary_results_min_bytes` (v1.154.1; only with `binary_results: capture`, at least 128) | 4096 |
| `conversion:` | `mode`, `local.workers`, `local.memory_limit_mb`, `listen`, `tls`, `queue_wait_s`, `quarantine_ttl_s` | `local` on Linux, `inprocess` elsewhere (v1.154.0) |
| `interruption:` | `default_timeout_ms`, `max_timeout_ms`, `max_pending_per_run`, `heartbeat_interval_ms` | — |

Example, the blocks a server typically gains:

```yaml
storage:
  backend: postgres          # pin it; the connection strings stay in the environment

concurrency:
  max_concurrent_runs: 32
  max_queue_depth: 128
  max_concurrent_runs_per_user: 4
  max_queued_runs_per_user: 16

retention:
  enabled: true              # nothing is deleted without this
  interval: 24h
  export_dir: /data/retention-exports
  chats: { mode: export+prune, max_age: 90d }
  defs:  { mode: prune, max_age: 30d, keep_last_n: 5 }

timeout_scaling:
  mode: measure
  reference: { decode_tps: 100 }
  max_multiplier: 8

metrics:                     # the `server` preset already sets enabled + collect_system
  enabled: true
  collect_system: true

auth:
  login_origins:
    - https://landing.example.com

hooks:
  private_host_allowlist: [10.20.0.0/16]
```

Retention ages are durations (`30d`, `12h`, `1d12h`); a bare number other than
`0` is refused. A family whose `mode` deletes must set `max_age` (`0s` means
any age). `mem_content` takes `off` or `prune` only. The `retention:` block is
read at start: a reload reports it `restart_required`, and `GET /v1/_retention`
shows `"pending_restart": true` until the restart.

## Precedence: the environment wins

Where one setting has both an environment and a yaml form, **a variable that is
set replaces the yaml's value**. An empty variable is not set; for the numeric
ones, a value that is not a number is not set either. Two exceptions:

1. **`auth.mode` takes the stricter** of the yaml's value and
   `LOOMCYCLE_AUTH_MODE` (`strict` over `token`), so neither plane lowers the
   other. When they differ an advisory names the one that decided, and
   `loomcycle validate` prints an `Auth mode` line such as `strict (from LOOMCYCLE_AUTH_MODE)`.
   Before v1.153.0 a yaml value below the environment's stopped the load.
2. **A provider's endpoint comes from the yaml.** `providers.<id>.base_url` is
   used in place of that provider's `*_BASE_URL` variable (`OLLAMA_BASE_URL`,
   `OLLAMA_CLOUD_BASE_URL`, `DEEPSEEK_BASE_URL`, `GEMINI_BASE_URL`), which
   supplies the endpoint only when the yaml names none.

The settings that have both forms:

| Yaml key | Variable | When both are set |
|---|---|---|
| `presets:` | `LOOMCYCLE_PRESETS`, `--preset` | the flag, else the variable; the yaml's list is then not layered |
| `storage.pg_dsn`, `pg_max_open_conns`, `pg_min_idle_conns` | `LOOMCYCLE_PG_DSN`, `LOOMCYCLE_PG_MAX_OPEN_CONNS`, `LOOMCYCLE_PG_MIN_IDLE_CONNS` | the variable |
| `storage.pg_automigrate` | `LOOMCYCLE_PG_AUTOMIGRATE` | the variable, both ways: `1` on, `0` off; any other non-empty value stops the load |
| `storage.sqlmem_root`, `sqlmem_pg_dsn`, `sqlmem_quota_bytes`, `sqlmem_audit_mode`, `sqlmem_scope_ttl_ms`, `sqlmem_total_max_bytes`, `sqlmem_shared_schemas` | the `LOOMCYCLE_SQLMEM_*` variable of the same name | the variable |
| `providers.ollama-local.options.num_ctx` | `LOOMCYCLE_OLLAMA_LOCAL_NUM_CTX` | the variable (before v1.153.0 the yaml won); boot warns when they differ |
| `auth.mode` | `LOOMCYCLE_AUTH_MODE` | exception 1: the stricter |
| `providers.<id>.base_url` | the provider's `*_BASE_URL` | exception 2: the yaml |

Every other setting has one plane. Keep secrets out of the yaml even where a
key accepts one (`storage.pg_dsn`, `storage.sqlmem_pg_dsn`): use the variables.

## Inferred settings

Some settings are decided from another one; there is no switch:

| Setting | Rule | Override |
|---|---|---|
| **Store backend** | Postgres when `LOOMCYCLE_PG_DSN` or `storage.pg_dsn` is set (an empty value or an unexpanded `${NAME}` does not count), SQLite otherwise | `storage.backend: sqlite` or `postgres` always wins. Set it on every Postgres deployment, and on any SQLite one whose environment carries a DSN |
| **SQL Memory** (and with it Documents) | On with SQLite; on with Postgres when `LOOMCYCLE_SQLMEM_PG_DSN` (or `storage.sqlmem_pg_dsn`) is set. On Postgres without it, SQL Memory is off and boot warns | `storage.sqlmem_enabled: false` turns it off on either store; `true` on Postgres with no SQL Memory DSN stops the boot |
| **A2A** | Served when `LOOMCYCLE_A2A_SERVER_CARD` names a card (server surface mounted, outbound `a2a__*` tools registered); a name with no such card stops the boot | Unset the variable to keep A2A off; cards in the yaml do not turn it on |
| **Content directories** | With `LOOMCYCLE_CONFIG_DIR` set, its `agents/`, `skills/` and `help/` subdirectories are loaded when the matching `*_ROOT` variable is unset | Set the variable to the empty string to decline |
| **Audit stream** | On when a sign-in gate, `auth.mode: strict`, `LOOMCYCLE_ACL` other than `compat`, or more than one principal is configured | `LOOMCYCLE_AUDIT_STORE=1` turns it on elsewhere |
| **Tracing** | On when `OTEL_EXPORTER_OTLP_ENDPOINT` is set | `OTEL_SDK_DISABLED=true` |
| **Cluster mode** | On when `LOOMCYCLE_REPLICA_ID` is set (Postgres only) | — |
| **Open mode** | Every caller accepted when no token, principal or admin token exists; loopback only | Set `LOOMCYCLE_AUTH_TOKEN` or declare `principals:` |

Every start logs `store: backend chosen` with `backend` and `source` (`yaml`
or `inferred`). `loomcycle validate` prints the resolved backend in its first
lines.

## Presets and profiles

A **preset** is a named stack of yaml built into the binary; `loomcycle presets`
lists them and `loomcycle presets show <name>` prints one with the stack it
expands to. A **profile** is one of the two presets that stand for a whole
installation:

| Preset | Layers | Sets itself |
|---|---|---|
| `personal` | `base`, `local`, `chat`, `document-agent` | nothing: SQLite, SQL Memory on it and the loopback listener are already the defaults |
| `server` | `base`, `chat`, `document-agent`, `memory` | `metrics: {enabled: true, collect_system: true}` |

Neither sets a volume, a sign-in gate, retention, a listen address or a
secret, and no preset can turn on a gate: the agents they ship list `Bash`,
`HTTP` and `WebFetch`, which stay idle until `LOOMCYCLE_BASH_ENABLED` /
`LOOMCYCLE_HTTP_HOST_ALLOWLIST` are set in the environment. The `memory`
bundle's consolidation schedule ships disabled
(`scheduled_runs: { memory-consolidation: { enabled: true } }` turns it on).

The other presets: `base` (provider and tier matrix), `local` (Ollama first),
`oauth` (anthropic-oauth-dev first), `bedrock` (needs
`LOOMCYCLE_BEDROCK_REGION`), `loomboard` (an app sign-in client); bundles
`chat`, `document-agent`, `memory`, `system-channels`, `sandbox`, `dev-exec`,
`agent-teams`, `team-examples`, `doc-colorizer`, `knowledge-base`,
`skybits-sync`. Details: [routing.md](routing.md#embedded-presets-and-config-layering).

**Selecting presets.** The first of these that is set decides, and the others
are not layered:

1. `--preset <name>` (repeatable);
2. `LOOMCYCLE_PRESETS=personal` (comma-separated);
3. the `presets:` key of the primary config file:

   ```yaml
   presets: [personal]          # or [server], or [personal, memory]
   ```

When two would give different stacks, an advisory names both (boot,
`validate`, `doctor`). `presets:` is read from one file only — the last
`--config`, else the auto-discovered `loomcycle.yaml`, else `loomcycle.yaml` in
`LOOMCYCLE_CONFIG_DIR`; in any other file it stops the load. A preset named in
the file is trusted as the file is (it is yaml and can carry agents, MCP
servers or sign-in clients). `include:` works only inside a preset built into
the binary; in your own file it stops the load. A unit selected beside a preset
that already includes it is layered once (`local,personal` = `personal`).

**Layer order** (later wins): the presets, then every `*.yaml` in
`LOOMCYCLE_CONFIG_DIR` (lexical order), then each `--config` file in the order
given. A `loomcycle.yaml` also brings its `loomcycle.*.yaml` section siblings.
`LOOMCYCLE_CONFIG_FILES` is gone (v1.153.0): pass each file as `--config`, or
place it in the config directory. `validate`, `doctor`, `agents list`,
`migrate --config`, `tokens` and `audit` assemble the same stack the server
does and print its layers.

**Starting a config.**

| Command | Writes |
|---|---|
| `loomcycle init` | The `personal` profile's short yaml to `~/.config/loomcycle/loomcycle.yaml`: one active line, `presets: [personal]`, with commented blocks for what is yours |
| `loomcycle init --with-token` | The same, plus `auth.env` (mode `0600`) with a generated `LOOMCYCLE_AUTH_TOKEN`; loomcycle reads it at start for variables not already set |
| `loomcycle init --profile server` | The `server` profile's yaml |
| `loomcycle init --full` | The long, fully commented reference config, which names no preset (the pre-v1.153.0 behaviour) |

**`examples/profiles/`** in the loomcycle repo has a complete minimal
configuration per profile:

- `personal/` — `loomcycle.yaml`, `env.insecure.example` (`OLLAMA_BASE_URL`,
  commented opt-ins) and `env.local.example` (provider keys).
- `server/` — `loomcycle.yaml` (`presets: [server]`, a `dynamic_root` volume,
  a token gate, commented password / OIDC / external gates, retention and
  memory schedule), `env.insecure.example` (listen address, public URL, config
  and data dirs, audit log path, commented OTEL / ACL / opt-ins),
  `env.local.example` (auth token, secret key, the two DSNs, provider keys),
  `docker-compose.yaml` (runtime, one-shot migration, Postgres) and
  `postgres-init.sh` (the non-superuser role with `CREATEROLE` and its two
  databases).

Deployment postures built on these: [profiles.md](profiles.md).

## Conversion workers (v1.154.0)

With no `conversion.mode`, a Linux runtime now sends file conversion
(extraction, OCR page rendering, recording conversion, speech encoding, image
re-encoding, document rendering) to child worker processes with a memory limit;
other platforms stay `inprocess`. Write `conversion.mode: inprocess` to keep the
old behaviour. See [files.md](files.md).

## Upgrading from before v1.153.0 — checklist

Read loomcycle's `docs/SETTINGS_MIGRATION.md` for the full per-variable table
(tables A–E) and worked examples by area; this checklist does not copy it.

1. **Back up** the store (the SQLite data directory, or both Postgres databases
   when SQL Memory is on Postgres), the SQL Memory scope files, the yaml files
   and the environment files. Two changes decide which store opens and whether
   data is deleted.
2. **Collect the names** (never values) of the `LOOMCYCLE_*`, `SANDBOX_*`,
   `OTEL_*` and `OLLAMA_*` variables the deployment sets, e.g.
   `env | cut -d= -f1 | grep -E '^(LOOMCYCLE|SANDBOX|OTEL|OLLAMA)_' | sort`.
   Do not forget the compose file itself and the thin client's environment
   (the plugin's `.mcp.json` launches `loomcycle mcp --upstream`, which only
   advises).
3. **Ask the new binary first**, with the server's own environment and config
   layers (same `LOOMCYCLE_PRESETS`, `LOOMCYCLE_CONFIG_DIR`, files):

   ```sh
   loomcycle validate /path/to/loomcycle.yaml     # exit 2 on a refusal; prints Advisories then OK otherwise
   loomcycle doctor --config /path/to/loomcycle.yaml   # FAIL "Config parses" (exit 1) on a refusal; WARN "Config advisory" per advisory
   ```

   With no path both check what a bare `loomcycle` would load. In a container,
   run them in the new image, e.g.
   `docker compose run --rm --no-deps <service> validate /config/loomcycle.yaml`.
   Neither opens the store, so the inferred-Postgres refusal (below) shows only
   at the real start.
4. **Fix each item, then remove its line.** A removed variable is either
   *advised* (a warning; ignored) or *refused* (the boot stops; every refused
   name is listed at once, never with its value):
   - **Refused** when ignoring it would change the deployment: a feature switch
     set to anything but `1` (the empty value included — e.g. a compose line
     `LOOMCYCLE_BASHBOX_ENABLED: ""`); a cap lowered below the constant that now
     applies; `LOOMCYCLE_STORAGE_BACKEND` naming another backend than the
     inferred one; `LOOMCYCLE_SQLMEM_ENABLED` asking for something the store
     inference does not give; a setting that moved to the yaml, set to a
     non-default value while the yaml does not name the key (in either
     direction — a raised timeout too); `LOOMCYCLE_RETENTION_ENABLED`
     disagreeing with `retention.enabled`; a `LOOMCYCLE_HOOKS_*` list naming an
     entry the yaml list lacks; `LOOMCYCLE_CONFIG_FILES` set and non-empty;
     `LOOMCYCLE_READ_ROOT` / `WRITE_ROOT` / `BASH_CWD` set; the switches that
     decided which data is kept (`LOOMCYCLE_USAGE_SWEEPER=0`,
     `LOOMCYCLE_HEARTBEAT_SWEEPER=0`, `LOOMCYCLE_MEMORY_PROVISION_IDENTITY_DOCS`
     off, an internal-chat age other than 3 days); `LOOMCYCLE_SPEECH_MAX_INFLIGHT`
     / `LOOMCYCLE_TRANSCRIPTION_MAX_INFLIGHT` set lower than
     `LOOMCYCLE_AUDIO_MAX_INFLIGHT`; `LOOMCYCLE_DEADLINK_GC_MS` /
     `LOOMCYCLE_DEADLINK_GC_DRY_RUN` (now `LOOMCYCLE_DEADLINK_GC`). The full table
     is loomcycle's `docs/SETTINGS_MIGRATION.md`.
   - **Advised** otherwise: a switch set to `1`, a limit raised above the
     constant (the constant applies), a moved setting at its default or whose
     yaml key is named, the debug flags.
   - Write the yaml key **before** removing a moved variable: a variable you
     simply delete is not reported, and its default applies silently.
5. **Read the behaviour changes that have no variable to warn about:**
   - **Seven features are always on:** the scheduler, the inbound webhook
     receiver, channel hooks, code agents (`code-js`), code hooks, Bashbox and
     the resume of a fan-out parent. Definitions authored while a feature was
     off start working at the first boot — **audit every tenant's schedule,
     webhook, hook and agent definitions and channel `hooks:` blocks** and
     disable or delete what you do not want.
   - **Code agents and code hooks reach every tenant operator.** Anyone who may
     author an agent or hook definition can run JavaScript in the process,
     bounded in time but not in memory. To remove code agents, run with
     `LOOMCYCLE_NO_DEFAULT_PROVIDERS=1` and your own `providers:` without a
     `code-js` entry; code hooks have no switch — control who authors hook
     definitions.
   - **Bashbox is stripped from agents registered over MCP** (`register_agent`),
     like `Bash`, `Write` and `Edit`, unless
     `LOOMCYCLE_MCP_ALLOW_PRIVILEGED_TOOLS=1`.
   - **Retention needs `retention.enabled: true`.** Removing the old retention
     variables without writing the block stops deletion silently; a family
     `mode` without `enabled` deletes nothing (advisory). The legacy usage
     archiver is gone — use `retention.chats`. The usage rollup
     (`retention.usage_detail.max_age`, 30 days), heartbeat sweeper and fixed
     housekeeping always run.
   - **SQL Memory turns on for SQLite** instances: Documents start working and
     scope files appear under `<data dir>/sqlmem`. `storage.sqlmem_enabled:
     false` keeps it off.
   - **A DSN in the environment now selects Postgres.** When Postgres is
     inferred and the data directory holds a SQLite store (`loomcycle.db`),
     every command that opens the store stops and asks for `storage.backend`.
     Set `storage.backend: sqlite` to keep the SQLite store, or `postgres`
     (after `loomcycle migrate sqlite-to-postgres` to copy the data).
   - **A2A starts serving** when `LOOMCYCLE_A2A_SERVER_CARD` is set.
   - **Config-directory content is loaded:** `agents/`, `skills/` and `help/`
     under `LOOMCYCLE_CONFIG_DIR` are adopted when the root variable is unset.
   - **Container images set `LOOMCYCLE_DATA_DIR`** to
     `/home/nonroot/.local/share/loomcycle`. A container that kept its store at
     the old default (`./data` under the working directory) must set the
     variable to that path, or it starts on an empty store.
   - **The `base` preset routes to newer models:** `haiku` / `sonnet` / `opus`
     name `claude-haiku-5-5` / `claude-sonnet-5-5` / `claude-opus-5-5`,
     `cloud-kimi` names `kimi-k3`, and Gemini joins the provider priority and
     every tier (skipped without `GEMINI_API_KEY`). Since v1.154.1 the `oauth`
     preset's aliases match. Restate an alias in your own `models:` to keep a
     model; `GET /v1/_routing` shows what each tier resolves to.
   - **Debug flags became log lines:** `LOOMCYCLE_AUTH_VERBOSE`,
     `LOOMCYCLE_CHANNEL_DEBUG` and `LOOMCYCLE_OLLAMA_DEBUG_THINK` are gone; set
     `LOOMCYCLE_LOG_LEVEL=debug` while diagnosing.
   - **Loosened limits return to the constant**: e.g. a channel or Memory value
     over 64 KiB is refused, tool calls of one turn run 8 at once, sweeps you
     switched off with `0` run again, expired token rows are deleted after 7
     days.
   - **`loomcycle init`** writes the short profile config; `--full` for the long
     one. A stray top-level `include:`, or `presets:` outside the primary file,
     stops the load.
   - **Bad values stop the start** for `LOOMCYCLE_MCP_SPAWN_RUN_TIMEOUT_MS`,
     `LOOMCYCLE_OPERATOR_TOKEN_ROTATION_GRACE_SECONDS`,
     `LOOMCYCLE_AUTH_CACHE_TTL_SECONDS`, `LOOMCYCLE_USER_TOKEN_MAX_TTL_SECONDS`,
     `LOOMCYCLE_RUN_RATE_PER_MINUTE` / `_BURST`, `LOOMCYCLE_LIMITS_ENFORCE`,
     `LOOMCYCLE_GIT_SOURCE_HOSTS`, `LOOMCYCLE_DEADLINK_GC` and
     `LOOMCYCLE_PG_AUTOMIGRATE` (the error names the variable, never its value).
6. **Start**, and read the first screen of the boot log: any remaining advisory
   is a `WARN` line `config: warning`.

The sandbox builder sidecar refuses to start while any of its ten removed
`SANDBOX_*` limit variables is set to a non-empty value; remove them.

### After v1.155.0: the explicit token pepper is legacy

From v1.156.0, with both `LOOMCYCLE_OPERATOR_TOKEN_PEPPER` and
`LOOMCYCLE_SECRET_KEY` set, new tokens are hashed under the pepper derived from
the secret key; a token still under the explicit pepper logs in and is moved as
it is used. Keep both set, upgrade every replica together, and watch the boot
line `auth: LOOMCYCLE_OPERATOR_TOKEN_PEPPER is legacy: …` until it counts no row
left; then remove the variable. Web UI sessions end once at the switch; tokens
keep working. `loomcycle tokens rewrap` is refused while the legacy pepper is
set, and `loomcycle doctor` warns about it. Do not roll back once tokens have
moved.

## Quick troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| The server started on an empty store | It opened another backend, or the container's data directory moved | `storage.backend` in the yaml; check that `LOOMCYCLE_PG_DSN` reaches the process; check `LOOMCYCLE_DATA_DIR` |
| Retention stopped | No `retention.enabled: true`, no deleting `mode` with `max_age`, `export+prune` with no `export_dir`, or no restart after the edit | Write the block ([above](#yaml-the-policy-and-tuning-blocks)) and restart |
| Documents say SQL Memory is not enabled | Postgres store without `LOOMCYCLE_SQLMEM_PG_DSN`, or `storage.sqlmem_enabled: false` | Set the SQL Memory DSN (its role needs `CREATEROLE`) |
| The local model's context got small | `providers.ollama.options.num_ctx` / `ollama-local` `num_gpu` not written | Write the provider options; `LOOMCYCLE_OLLAMA_LOCAL_NUM_CTX` still works and wins |
| A schedule or webhook suddenly fires | The scheduler and webhook receiver are always on | Disable or delete the definition |
