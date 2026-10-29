# Environment variable catalogue

The **posture** axis. Authoritative source: loomcycle `.env.insecure.example` +
`.env.local.example` + `internal/config`, checked against **v1.126.0**. Where the
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
| `LOOMCYCLE_AUTH_TOKEN` | (empty) | Bearer for every `/v1/*` route. **Empty, with no config `principals:` and no admin operator token = open mode** — every route, token minting included, unauthenticated. **(v1.119.0)** Open mode is refused at boot on any listener beyond loopback (see `LOOMCYCLE_ALLOW_OPEN_MODE`); on loopback it warns every 10 minutes and the Web UI shows an "unauthenticated" banner. Declaring config `principals:` alone also turns auth on. Always set in any shared/server deployment. `openssl rand -hex 32`. |
| `LOOMCYCLE_ALLOW_OPEN_MODE` | off | **(v1.119.0)** `1` lets open mode start on a listener beyond loopback (`LOOMCYCLE_LISTEN_ADDR` or `LOOMCYCLE_GRPC_ADDR` binding anything but `127.0.0.0/8`, `::1` or `localhost` — `:8787`, `0.0.0.0` and `::` count as public). Without it such a boot exits with an error. Throwaway test harness on a private network only. |
| `LOOMCYCLE_AUTH_MODE` | `token` | **(v1.123.0)** Fleet default for the yaml `auth.mode`: `token` (paste-a-token Web UI sign-in) or `strict` (a person signs in only through a gate in `auth.gates`). A config may raise it, never lower it. See [identity.md](identity.md). |
| `LOOMCYCLE_UI_INSECURE_COOKIES` | off | **(v1.123.0)** `1` lets **strict** mode start Web UI sessions over plain HTTP (a cookie without `Secure`) — e.g. on a tailnet. Behind a TLS terminator set an `https://` `LOOMCYCLE_PUBLIC_URL` instead. Warned at boot. |
| `LOOMCYCLE_GRPC_ADDR` | (unset) | gRPC listen addr (optional second transport). |
| `LOOMCYCLE_PUBLIC_URL` | (unset) | The instance's externally reachable URL, reported to agents in `Context op=self` (`server.url`). Non-secret. **(v1.123.0)** An `https://` value with a matching `Host` makes the Web UI session cookie `__Host-lc_session` behind a TLS terminator. **(v1.126.0)** Required by `external` and `device` sign-in gates (assertions are addressed to it), and the OAuth authorization-server metadata answers `404` until it is set. |
| `LOOMCYCLE_PUBLIC_CONFIG` | off | `1` lets `GET /v1/config` be read with **no bearer**, returning a narrowed public view (version, features, live providers/models). An invalid bearer still `401`s. |
| `LOOMCYCLE_MAX_REQUEST_BYTES` | 16777216 (16 MiB) | Run-ingest request body cap; over it → `413`. |
| `LOOMCYCLE_SSE_KEEPALIVE_MS` | 20000 | SSE comment-ping cadence (clamped 1 s – 5 min; `0` or negative disables). |
| `LOOMCYCLE_WEBUI_DIR` | (unset) | **(v1.122.0)** Serve the Web UI from an unpacked UI bundle (built SPA + `manifest.json` with per-file SHA-256 and supported API levels) instead of the built-in UI, so a UI fix ships without a new binary. Read once at startup; a bundle failing any check is logged and the built-in UI served (`/healthz` reports `ui_bundle`). The bundle runs with the signed-in operator's session — keep the directory operator-writable only. |
| `LOOMCYCLE_WEBUI_BUNDLE_URL` / `LOOMCYCLE_WEBUI_BUNDLE_SHA256` | (unset) | **(v1.122.0)** Instead of a directory: an `https` URL of a Web UI release archive (`.tar.gz`), fetched once through the egress guard, verified against the SHA-256 (64 lowercase hex, of the archive bytes — required with the URL) and cached under `LOOMCYCLE_DATA_DIR/webui`. Not together with `LOOMCYCLE_WEBUI_DIR`. A failed fetch never stops the boot; the built-in UI is served. |

## Config sources (presets + layering)

| Var | Default | Purpose |
|---|---|---|
| `LOOMCYCLE_PRESETS` | (unset) | Comma-separated, ordered embedded presets/bundles layered as the **base** of the config stack (`base`, `oauth`, `local`, `bedrock` (v1.119.0); bundles `chat`, `document-agent`, `memory`, `system-channels`, `sandbox`, `dev-exec`, `agent-teams`, `team-examples`, `doc-colorizer`). Opt-in; an unknown name is fatal. `--preset` (repeatable) overrides it. `loomcycle presets` lists them. |
| `LOOMCYCLE_CONFIG_DIR` | (unset) | A directory whose `*.yaml`/`*.yml` layer in lexical filename order, above the presets. Set-but-missing is fatal. |
| `LOOMCYCLE_CONFIG_FILES` | (unset) | `:`-separated config files layered left→right, above `CONFIG_DIR` and below explicit `--config` flags. |
| `LOOMCYCLE_CONFIG_STRICT` | off | `1` makes any cross-layer conflict a **fatal** load error (otherwise each override is logged at startup). Recommended in production. |
| `LOOMCYCLE_NO_DEFAULT_PROVIDERS` | off | `1` drops the built-in provider layer so only your own `providers:` entries exist — e.g. to stay local-only on `LOOMCYCLE_PRESETS=base,local`. |
| `LOOMCYCLE_BEDROCK_REGION` | (unset) | **(v1.119.0)** Region the `bedrock` preset's providers sign for and call (`LOOMCYCLE_PRESETS=base,bedrock` adds `bedrock-claude` and `bedrock-openai`); required when that preset is selected. Credentials are **not** set here — they come from the standard AWS chain (instance / task / pod role, or `AWS_PROFILE` / `AWS_ACCESS_KEY_ID` with the keys in `.env.local`). See [routing.md](routing.md). |

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
| `LOOMCYCLE_BASHBOX_OVERLAY_MAX_BYTES` | **(v1.119.0)** Bytes one `Bashbox` call may write into memory (a read-only volume's overlay writes and the shadowed `dynamic_root`). Past it writes fail with "no space left on device". Default 64 MiB; under 1 MiB is raised to 1 MiB. |
| ~~`LOOMCYCLE_BASH_CWD`~~ | **⚠️ RETIRED — v1.1.0+ (RFC AH Phase 3). Fatal config-load error if set.** Was: Bash working dir. Now the Bash cwd is the volume root — the `path:` of the bound `rw` volume. |
| `LOOMCYCLE_HTTP_HOST_ALLOWLIST` | `HTTP`+`WebFetch`: comma-separated **suffix-match** host allowlist (`example.com` matches `api.example.com`, not `evilexample.com`). Private IPs (RFC1918, loopback, link-local incl. 169.254.169.254, **CGNAT `100.64.0.0/10`** and other non-public ranges) are **hard-blocked at connect** regardless. Loopback aliases on this list are stripped at startup — use the private list below. Unset = refuse all outbound. Env-only: a YAML reload cannot change it. |
| `LOOMCYCLE_HTTP_PRIVATE_HOST_ALLOWLIST` | Exception list: hosts here may resolve to private IPs at dial (e.g. a localhost app callback). A hostname entry must ALSO be on the main allowlist; this only lifts the IP-private rejection. **(v1.101.0)** An entry may be a **CIDR range** (`100.64.0.0/10`, `100.101.102.103/32`) admitting only resolved addresses inside it — Tailscale peers need one; a malformed range fails startup. Also the only way a runtime-authored remote memory backend or document source may reach a private host, and the A2A client honours it. |
| `LOOMCYCLE_HTTP_CALLER_AUTHORITATIVE` | `1` = caller's per-request `allowed_hosts` is the sole policy (operator list is a default). Unset = caller can only *narrow* the operator's static list. **(v1.115.0)** A restricted caller (a token limited to some agents) can only narrow, even with this set. |
| `BRAVE_API_KEY` / `SERPER_API_KEY` / `EXA_API_KEY` / `TAVILY_API_KEY` | **Secrets** — `WebSearch` provider keys (SearXNG is keyless, configured in the yaml `search_providers:` block). With no `search_providers:` block, `WebSearch` uses Brave when `BRAVE_API_KEY` is set. |
| `LOOMCYCLE_WEBSEARCH_PROVENANCE` | `1` appends a `(via <provider>)` footer to each search result so a provider fallover is visible. |
| `LOOMCYCLE_REDACT_SECRETS` | Default **ON**: tool inputs/outputs are scanned for secret-shaped substrings and masked before they are persisted (events store, snapshots, audit API). `0` disables. The live SSE stream is not redacted. |
| `LOOMCYCLE_MCP_ALLOW_PRIVILEGED_TOOLS` | `1` lets **dynamically-registered** agents request privileged builtins (`Bash`/`Write`/`Edit`); stripped silently otherwise. Only flip on when the MCP client is trusted (operator-launched stdio = trusted; remote HTTP MCP = NOT). |
| `LOOMCYCLE_EPHEMERAL_VOLUME_SWEEP_MS` | Reaper cadence for run-scoped (ephemeral) volumes. Default 60000; `0` or negative disables the sweep. |
| `LOOMCYCLE_MCP_REFUSE_UNATTRIBUTED_ENV` | A runtime MCP server def may hold a `${NAME}` env reference only when an admin saved it. **Since v1.113.0 a stored def holding one without that record is refused by default** (boot `mcp_server_defs: WARNING:` lines list them); an admin acting in that tenant re-saves or retires it. `0` keeps the old warn-and-dial while re-saves are pending; any other value, or none, refuses. |
| `LOOMCYCLE_MCP_ALLOW_PRIVATE_IPS` | Default **on** (MCP servers are commonly on localhost / a private network). `0` enables a dial-time DNS-rebinding block for the MCP-HTTP client; `LOOMCYCLE_HTTP_PRIVATE_HOST_ALLOWLIST` then exempts specific internal MCP hosts. **(v1.119.0)** Applies only to operator yaml servers and admin-saved definitions: a **tenant's** runtime MCP server always dials through the egress guard, whatever this says — one on a private address is refused unless its host is on `LOOMCYCLE_HTTP_PRIVATE_HOST_ALLOWLIST` or an admin re-saves the definition outside a run. |
| `LOOMCYCLE_MCP_MAX_FRAME_BYTES` | **(v1.122.0)** Largest single MCP response loomcycle reads from a mounted server — a stdio JSON-RPC line or an MCP HTTP body. Default 16 MiB. |
| `LOOMCYCLE_CRYPTO_MAX_BYTES` / `LOOMCYCLE_CRYPTO_MAX_OPS_PER_RUN` | **(v1.116.0)** `Crypto` tool caps: bytes per data argument (default 1048576) and calls per run (default 100). Crypto keys are CredentialDefs, so the tool needs `LOOMCYCLE_SECRET_KEY`; an agent uses keys only from its `crypto_scopes`. |
| `LOOMCYCLE_KMS_VAULT_ALLOW_HTTP` | **(v1.116.0)** `1` admits a plain-`http` (dev) Vault for a crypto key held in Vault Transit. Otherwise Vault must be `https`, and its host must be on `LOOMCYCLE_HTTP_HOST_ALLOWLIST` or `LOOMCYCLE_HTTP_PRIVATE_HOST_ALLOWLIST`. |
| `LOOMCYCLE_HOOKS_PRIVATE_HOST_ALLOWLIST` | **(v1.92.0)** Private hosts a **tenant** hook callback may dial (tenant hook callbacks go through the private-address guard). Also settable as yaml `hooks.private_host_allowlist`. |
| `LOOMCYCLE_HOOKS_PERMIT_HOST_WIDEN_OWNERS` | Comma-separated hooks permitted to widen a call's host allowlist (appended to yaml `hooks.permit_host_widen.owners`). Since v1.97.0 each entry names `[tenant:]hook-name`. |
| `LOOMCYCLE_MCP_ALLOW_DYNAMIC_STDIO` | **(v0.23.3, F31/#405)** `1` lets a **runtime-authored** MCP server (`POST /v1/_mcpserverdef` / the `mcpserverdef` tool) use `transport: stdio` — which **runs an arbitrary local command**, so it is **off by default** and refused with an explicit error otherwise. `http`/`streamable-http` dynamic servers need no flag (mediated by the outbound host allowlist); **static `mcp_servers:` stdio in yaml is operator-trusted and unaffected**. Only set on a host where the MCP-authoring principal is trusted to name local commands. |

## Files from tools (the run inbox)

**(v1.122.0)** A file a tool returns (an MCP attachment or image, a binary HTTP /
`WebFetch` response) is kept in the run tree's **inbox** volume and the model gets
a one-line reference instead of the bytes. Needs a volume marked
`dynamic_root: true`; without one the file is refused, not passed through. A bad
value refuses the boot. See [files.md](files.md) and [volumes.md](volumes.md).

| Var | Default | Purpose |
|---|---|---|
| `LOOMCYCLE_FILE_MAX_BYTES` | 67108864 (64 MiB) | One kept or downloaded file. |
| `LOOMCYCLE_FILE_INBOX_MAX_BYTES` | 1073741824 (1 GiB) | A run tree's whole inbox (a resumed tree counts what it already holds). |
| `LOOMCYCLE_FILE_BASE64_MIN_BYTES` | 4096 | Shortest base64 string kept as a file from an MCP server with `binary_results: capture`. |

OCR, speech-to-text and text-to-speech are configured in yaml (`transcription:`,
`speech:`), not by env var — see [routing.md](routing.md).

## Git (sources and the Git tool)

Off unless hosts are listed. See [git.md](git.md).

| Var | Default | Purpose |
|---|---|---|
| `LOOMCYCLE_GIT_SOURCE_HOSTS` | (unset = off) | **(v1.113.0)** Hosts a repository may be fetched from — for a volume filled with one commit (`VolumeDef op=create ephemeral:true source:{git:…}`, fetched inside the runtime so no agent holds the token; the agent needs `source:git` in `volume_def_scopes`) and, since v1.122.0, the `Git` tool's clone / fetch / pull. A credential it names must be restricted (`allowed_urls`) to a URL covering the repository. |
| `LOOMCYCLE_GIT_SOURCE_MAX_BYTES` | 268435456 (256 MiB) | **(v1.113.0)** Bytes fetched, and bytes written, per clone; a request may ask for less. |
| `LOOMCYCLE_GIT_SOURCE_MAX_OBJECT_BYTES` | 67108864 (64 MiB) | **(v1.113.0)** Largest single object once inflated — this bounds memory. A larger one fails the clone. |
| `LOOMCYCLE_GIT_SOURCE_MAX_FILE_BYTES` | 5242880 (5 MiB) | **(v1.113.0)** Largest file written; a larger one is left out and listed in `_meta/omitted.json`. |
| `LOOMCYCLE_GIT_SOURCE_MAX_FILES` | 100000 | **(v1.113.0)** Files, links and submodule directories per clone. |
| `LOOMCYCLE_GIT_SOURCE_TIMEOUT_SECONDS` | 120 | **(v1.113.0)** Time for one clone, waiting for a slot included. |
| `LOOMCYCLE_GIT_SOURCE_MAX_CONCURRENT` | 1 | **(v1.113.0)** Clones running at once per replica. |
| `LOOMCYCLE_GIT_SOURCE_MAX_HISTORY` | 500 | **(v1.113.0)** Commits deep a clone looks for its commit or a diff's merge base. |
| `LOOMCYCLE_GIT_PUSH_HOSTS` | (unset = no push) | **(v1.122.0)** Hosts the `Git` tool may push to. |
| `LOOMCYCLE_GIT_PUSH_MAX_BYTES` | 104857600 (100 MiB) | **(v1.122.0)** Bytes one `Git` push may send. |
| `LOOMCYCLE_GIT_AUTHOR_NAME` / `LOOMCYCLE_GIT_AUTHOR_EMAIL` | the agent's name / `<agent>@loomcycle.invalid` | **(v1.122.0)** Author and committer of the `Git` tool's commits. |

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
| `LOOMCYCLE_DOCUMENT_SEARCH_FILTER_MAX_IDS` | 50000 | **(v1.123.0)** `Document op=search` / `op=related` filters (`under_path`, `type`, `status`, `tag`, `as_of`, …) resolve to a chunk-id list sent into every search leg; a filter needing more is refused (`filter_too_wide`) rather than post-filtered. |
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
> widened. To grant nothing in a static agent, leave `Memory` out of `tools:`:
> `["-*"]` fails config load there and is accepted only on an `AgentDef`
> create/fork overlay. The same default applies to `history_scope` (`user`),
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

| `LOOMCYCLE_MCP_UPSTREAM_TOKEN` | (unset) | **Secret** — the bearer the thin client presents to the upstream runtime. Set in the *thin client's* environment; `.env.local` only. **(v1.126.0)** When unset, `loomcycle mcp --upstream` uses the token `loomcycle login` stored in the OS keychain (macOS `security`, Linux `secret-tool`; Windows has no keychain support — set this var). |
| `LOOMCYCLE_MCP_UPSTREAM_HEADER_TIMEOUT_MS` | client default | Thin client: max wait for upstream response headers (stall guard). Agent-run tools (`spawn_run`, `spawn_runs`, `compact_run`, `evaluation`) are exempt so a slow run is not retried into a double execution. |
| `LOOMCYCLE_MCP_UPSTREAM_RECONNECT_ATTEMPTS` | client default | Thin client: reconnect tries after a transport error (`0` = off). |

> **MCP tool set (v1.126.0).** Since v1.107.0 the meta-tool catalogue gained
> `list_team_channels` / `peek_team_channel` / `release_team_channel`
> (v1.108.0), `delete_run_tree` and `retention_override` (v1.112.0), `crypto`
> (v1.116.0), `file` and the access-control tools `groupdef` / `acldef` /
> `aclbinding` / `authz` (v1.122.0), and `identity`, which **replaces
> `directory` with no alias** (v1.126.0). None changes the `--upstream` wiring.
> Since v1.107.0 a member token's MCP session is held to its scopes: run tools
> need `runs:create`, read tools `runs:read`, channel tools `channel:publish` /
> `channel:read` (stdio, admin, legacy and `substrate:tenant` sessions are
> unchanged). Full map: [../../../reference/mcp-tools.md](../../../reference/mcp-tools.md).

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
| `LOOMCYCLE_INTERACTIVE_IDLE_TIMEOUT` | `1h` | **(v1.119.0)** How long a top-level interactive run parked for its operator waits for a message before it ends (stop reason `idle_timeout`; its session is kept, so the next message continues it). Go duration; `0` waits forever; an unparsable value refuses startup. |
| `LOOMCYCLE_BATCH_JOIN_TIMEOUT` | `1h` | **(v1.120.0)** How long a `join`-mode batch (`spawn_runs`, `POST /v1/runs:batch`) waits for its children when the request gives no `timeout_ms`. Past it the join only stops waiting — no child is cancelled; each still-going child comes back running (or queued) with its `run_id`. A request's own `timeout_ms` replaces it. `0` = no server bound. |
| `LOOMCYCLE_SHUTDOWN_PAUSE_TIMEOUT_MS` | 7000 | **(v1.119.0)** On SIGTERM a replica's in-flight runs pause (park) for up to this long, so they resume elsewhere or after restart (capped at 5 min). Raise it together with the platform's stop grace period (`stop_grace_period`, `terminationGracePeriodSeconds`, `TimeoutStopSec`). `0` restores the old abandon-to-sweeper shutdown. A fan-out parent keeps its children only with `LOOMCYCLE_RESUME_FANOUT=1`. |

## Pause / resume

| Var | Default | Purpose |
|---|---|---|
| `LOOMCYCLE_PAUSE_DEFAULT_TIMEOUT_MS` | 30000 | How long a pause waits for in-flight runs to park when the request names no `timeout_ms` (capped at 5 min). |
| `LOOMCYCLE_RESUME_FANOUT` | off (0) | **(v0.31.0, RFC X Phase 3)** `1` enables durable park+resume of a **fan-out parent** blocked in `Agent.parallel_spawn` — loomcycle captures spawn-ledger events so a parent quiesced by pause (or a crashed/restarted replica) re-dispatches its in-flight children from the transcript instead of stranding them. Default OFF keeps the pre-v0.31 pause/resume/snapshot paths byte-identical; opt in for long fan-out orchestrations that must survive a restart. (Single-run cross-instance resume needs no flag — v0.30.0.) |

## Concurrency, fairness, provider timeouts

| Var | Default | Purpose |
|---|---|---|
| `LOOMCYCLE_MAX_CONCURRENT_RUNS_PER_USER` | 0 (unlimited) | Per-user fairness cap (cluster-wide on Postgres). **Since v1.113.0 a run over it is queued, not refused** — see the next row and [routing.md](routing.md). |
| `LOOMCYCLE_MAX_QUEUED_RUNS_PER_USER` | 16 | **(v1.113.0)** Runs one (tenant, user) may have waiting on that cap; with no per-user cap, the places one user holds in the shared queue. Past it `429 backpressure`. `0` = refuse at once over the cap. (The whole queue is bounded by yaml `concurrency.max_queue_depth`, default 32.) |
| `LOOMCYCLE_TOOL_PARALLELISM` | 8 | Max concurrent tool calls within one assistant turn (capped at 64; `1` forces serial). |
| `LOOMCYCLE_PROVIDER_QUEUE_DEPTH` | 0 (= `max_queue_depth`) | Since v1.115.0 bounds only requests sent **outside any run** that wait on a capped provider — the LLM gateway and OpenAI-compatible routes, `/v1/embeddings`, `/v1/_decide`, image-describe — refused `provider_concurrency_exhausted` (HTTP 429) past it. A run's calls always wait. **`LOOMCYCLE_PROVIDER_QUEUE_TIMEOUT_MS` was removed in v1.113.0** (admitted work never times out on a provider) — drop it from your env. |
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
| `LOOMCYCLE_OPERATOR_TOKEN_PEPPER` | (unset) | Mixed into the token hash, so someone who can write the database cannot insert a row for a token of their choosing. **(v1.119.0) Optional:** unset, a pepper is derived from `LOOMCYCLE_SECRET_KEY`; with neither, tokens are hashed with no pepper and the server warns at boot when auth is on. Changing an explicit pepper invalidates every token. Upgrading from before v1.119.0 straight to a later release: run `loomcycle tokens rewrap` once (v1.120.0) or pre-pepper tokens stop working — see [profiles.md](profiles.md) §5. |
| `LOOMCYCLE_AUTH_CACHE_TTL_SECONDS` | 30 | Per-replica token-resolution cache TTL. `0` = direct lookup / immediate revocation. |
| `LOOMCYCLE_USER_TOKEN_MAX_TTL_SECONDS` | (unset = no cap) | **(v1.112.0)** Longest lifetime a per-user token may be minted with. When set, a mint asking for more is refused and a mint asking for none gets this one. Gate-issued tokens are held to it too. |
| `LOOMCYCLE_EXPIRED_TOKEN_RETENTION_SECONDS` | 604800 (7 d) | **(v1.112.0)** How long an expired token's row is kept before deletion (`0` keeps them). Only rows that carry an expiry are ever deleted. |
| `LOOMCYCLE_TOKEN_AUTHORITY_INHERIT` | off | **(v1.126.0)** `1` mints per-user and gate-issued tokens with authority `inherit`: their scopes follow the user's **current** `access_mode` on every request, so a promotion or demotion needs no re-mint. Default: `frozen` at mint. Operator tokens and config principals are always frozen; existing tokens keep their mode. |
| `LOOMCYCLE_RUN_RATE_PER_MINUTE` / `LOOMCYCLE_RUN_RATE_BURST` | (unset = no default) | **(v1.112.0)** Default rate for run starts (and, since v1.115.0, steers and A2A starts) for a caller whose token carries no `rate`. Admin, tenant-operator and legacy tokens are not bound by the default; a rate set on such a token still applies. |
| `LOOMCYCLE_LIMITS_ENFORCE` | (unset) | **(v1.112.0)** `strict` makes a hard token budget also stop runs in flight and refuse sub-agents. Unset = checked only when a run starts. See [token-limits.md](token-limits.md). |
| `LOOMCYCLE_ACL` | `compat` | **(v1.122.0)** Access-control rollout mode. `compat`: scope gates decide as before, and an explicit ACL **deny** bound to the caller is honoured on top. `shadow`: scope gates decide; every divergence from the ACL engine is logged and audited (`acl_shadow_diverged`). `enforce`: the engine decides — a question no rule allows is `403 acl_denied`, unreadable rules `503 acl_unavailable`. Built-in baseline lists reproduce each token class's reach, so `enforce` with nothing authored behaves like `compat`. See [access-control.md](access-control.md). |
| `LOOMCYCLE_ACL_CACHE_TTL_SECONDS` | 5 | **(v1.122.0)** How long a replica trusts a principal's compiled ACL set before re-reading the tenant's `acl_version` (`0` = every request). Writes also invalidate over the cluster bus; this is the worst-case lag if a bus message drops. |
| `LOOMCYCLE_ACL_LIVE` | off | **(v1.126.0)** `1` makes a run in flight follow its caller's access-control rules as they change (re-read before each model and tool call). Whatever is no longer allowed is taken away for the rest of the run; a run never gains more than it started with. Default: a run keeps the rules it started with. |
| `LOOMCYCLE_OPERATOR_TOKEN_ROTATION_GRACE_SECONDS` | 86400 | Default rotation grace window (old token valid this long after rotate). |
| `LOOMCYCLE_AUDIT_LOG_PATH` | (unset) | JSONL audit of every token create/rotate/retire (never a token or hash). **Since v1.55.0 subject erasure also writes here and is DISABLED without it** — it will not delete without a durable record of who asked. |
| `LOOMCYCLE_AUTH_VERBOSE` | off | `1` logs a server-side reason on a rejected bearer (the wire 401 stays opaque). |
| `LOOMCYCLE_OPERATOR_KEY_RESTRICTION` | off | **(v1.12.0)** `1` = a run whose principal lacks the `providers:operator-key` scope may not fall back to the operator's host provider key: it routes only to providers the tenant can key itself (a CredentialDef) and is refused `403 operator_key_restricted` if none. Also governs decision calls and consolidation sweeps. Off ⇒ nothing changes for existing tokens. |
| `LOOMCYCLE_UI_LOGIN_ORIGINS` | (unset) | Comma-separated first-party origins the Web UI login may accept a bearer handoff from. Empty = cross-origin handoff disabled. |

The closed scope catalog a token may carry: `substrate:admin`,
`substrate:tenant`, `substrate:user`, `runs:create`, `runs:read`,
`channel:publish`, `channel:read`, `providers:operator-key`, `runs:delete`
(v1.112.0 — delete a run tree; tenant-implied, granted to a member only by name),
`llm:gateway` (v1.112.0 — the raw model endpoints `/v1/_llm/chat`,
`/v1/chat/completions`, `/v1/embeddings`; tenant-implied and admitted for a
non-isolated member, but an isolated user needs it by name) and `auth:manage`
(v1.123.0 — a website's user-management token; must be the token's only scope).
**Minting requires an explicit scope list** (v1.87.0) — see
[profiles.md](profiles.md) §5.

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
| `LOOMCYCLE_LOG_FORMAT` | **(v1.119.0)** `text` (default — the familiar line, with `WARN`/`ERROR`/`DEBUG` before the message and fields appended as `key=value`) or `json` (one object per line, with `run_id`/`tenant`/`agent`/`user` and `trace_id`/`span_id` where a line belongs to a run). |
| `LOOMCYCLE_LOG_LEVEL` | **(v1.119.0)** `debug`, `info` (default), `warn` or `error`. **Since v1.122.0 every runtime line is levelled**, so `warn` or `error` also hides Info lines such as "listening on"; fatal and startup errors log at `ERROR` and show at every level. An unknown value warns and uses `info`. |
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
