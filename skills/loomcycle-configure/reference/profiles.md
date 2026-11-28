# Deployment profiles

Six postures on a **trust × scale** grid, checked against loomcycle
**v1.156.0**. Profiles are cumulative — 5 layers on 4, 6 layers on 5. Pick the
*lowest-trust* one that does the job.

**Start from the two embedded profiles (v1.153.0).** loomcycle ships two
presets that each stand for a whole installation, with ready files under
`examples/profiles/` in the loomcycle repo:

| Embedded profile | Layers | Postures here | Start with |
|---|---|---|---|
| `personal` | `base`, `local`, `chat`, `document-agent`; sets nothing itself (SQLite, SQL Memory on it, loopback are already the defaults) | 1, 2, 3 | `loomcycle init` (writes `presets: [personal]`), or `examples/profiles/personal/` |
| `server` | `base`, `chat`, `document-agent`, `memory`; turns the metrics sampler on | 4, 5, 6 | `loomcycle init --profile server`, or `examples/profiles/server/` (with compose + Postgres) |

Each posture below is that profile **plus** what you decide: environment
switches (secrets, addresses, security gates) and yaml blocks (volumes, sign-in
gates, retention, concurrency). Neither preset sets a volume, a sign-in gate,
retention, a listen address or a secret, and **no preset can turn on a gate**
(`LOOMCYCLE_HTTP_HOST_ALLOWLIST`, `LOOMCYCLE_MCP_ALLOW_PRIVILEGED_TOOLS`, …) — those exist only
in the environment. Where each setting lives: [settings.md](settings.md);
every variable: [env-vars.md](env-vars.md); routing yaml:
[routing.md](routing.md). **Print env lines for the operator — never write their
env file.** Never put a secret value in any file.

Things that changed under every profile since these were first written:

- **Settings moved out of the environment (v1.153.0).** Storage backend, SQL
  Memory, retention, concurrency, provider timeouts, timeout scaling and the
  metrics sampler are yaml or inferred; seven feature switches (scheduler,
  webhook receiver, channel hooks, code agents, code hooks, Bashbox, fan-out
  resume) are gone because the features are always on (Bashbox itself was
  then removed in v1.172.0). A deployment upgraded
  from before v1.153.0 must run the [upgrade checklist](settings.md#upgrading-from-before-v11530--checklist)
  first: some old lines refuse the boot, others change behaviour silently.

- **`Bash`, Bashbox and the builder sidecar are removed (v1.172.0).** Agents run
  commands in a **workspace** (`workspace.mode` + the `Workspace` tool with a
  `workspace` grant). `LOOMCYCLE_BASH_ENABLED`, `LOOMCYCLE_BASH_ALLOWED_CREDS`,
  any `LOOMCYCLE_BASHBOX_*` variable, the `sandbox` / `dev-exec` presets
  (use `dev-workspace`), and a yaml agent listing `Bash`, `Bashbox` or
  `shell_credentials` each **refuse the start**. See [workspaces.md](workspaces.md).
- **Filesystem access is a YAML `volumes:` block, not env.** The retired
  jail variables (`LOOMCYCLE_READ_ROOT` / `LOOMCYCLE_WRITE_ROOT` /
  `LOOMCYCLE_BASH_CWD`, retired in v1.1.0) **refuse the boot** when set to a
  non-empty value. An agent bound
  to no volume has no disk access. See [volumes.md](volumes.md).
- **Routing comes from the profile preset.** Your own yaml layers on top; the
  YAML skeletons below assume `presets: [personal]` or `presets: [server]` in
  the primary config file (`--preset` or `LOOMCYCLE_PRESETS` win over it). The
  agent tool-allowlist key is `tools:`. Opt-in additions:
  `knowledge-base` (v1.128.0 — the `kb/linker` links agent for statements; see
  [knowledge-base.md](knowledge-base.md)) and `loomboard` (v1.127.0 — the
  loomboard app's sign-in client; see [identity.md](identity.md)), e.g.
  `presets: [server, knowledge-base, loomboard]`.
- **Sign-in gate keys are strict (v1.130.0).** A misspelt or stale key under
  `auth.gates.<name>` or its `new_user` block now **fails the config load**.
  Run `loomcycle validate` over your config before upgrading to v1.130.0+.
- **Upgrading to v1.128.0+ with SQL Memory / Documents: take a runtime
  snapshot first** (`POST /v1/_snapshot`, which includes SQL Memory — a
  non-superuser `pg_dump` can't capture it). The upgrade rebuilds each scope's
  statements table on first use and, on Postgres, moves the document tables
  (below). Memory `sql_query` / `sql_exec` also stop reaching Document tables
  (`document_tables_reserved`) — an agent that read them that way must use
  `Document op=query_chunks`.
- **No credential = open mode, and open mode stays on loopback (v1.119.0).** A
  server with no `LOOMCYCLE_AUTH_TOKEN`, no config `principals:` and no admin
  operator token serves every route unauthenticated — and now **exits at boot**
  if `LOOMCYCLE_LISTEN_ADDR` or `LOOMCYCLE_GRPC_ADDR` binds beyond loopback
  (`0.0.0.0`, `:8787`, a LAN IP). Only `LOOMCYCLE_ALLOW_OPEN_MODE=1` overrides
  that, for a throwaway test harness. **Declaring config `principals:` turns
  authentication on** by itself (even one with an empty `token_env`).
- **Install methods:** Homebrew, the Docker images, or a release tarball (or
  build from a clone). **`go install …@version` no longer works (v1.122.0)** —
  the module uses nested modules with `replace`.

---

## 1. Brew install + in-system agent (full host trust)

**When:** a developer workstation or a single trusted box doing personal
automation, where you author and trust every prompt. The agent legitimately
needs the host's tools, files, and shell.

**Trust:** full — the loomcycle process runs as your user with your filesystem.
There is no isolation; the trust boundary is "you wrote the prompts."

```bash
brew install denn-gubsky/loomcycle/loomcycle
loomcycle init --with-token   # ~/.config/loomcycle/loomcycle.yaml with `presets: [personal]`,
                              # plus auth.env (mode 0600) holding a generated LOOMCYCLE_AUTH_TOKEN
loomcycle doctor              # config, storage, port, which provider keys are set; must end `0 failures`
loomcycle validate            # after every edit (no path = the stack a bare `loomcycle` loads)
```

Secrets go in `auth.env` beside the yaml (loomcycle reads it at start, for
variables not already set) or your own secret store; non-secret switches in
your shell profile. Print these for the operator:

```bash
# secrets (auth.env)
LOOMCYCLE_AUTH_TOKEN=<written by init --with-token>   # set even locally; open mode on loopback works but warns every 10 min
ANTHROPIC_API_KEY=<from your secret store>            # or OPENAI/DEEPSEEK/GEMINI; none needed with only Ollama
BRAVE_API_KEY=<optional, for WebSearch>

# non-secret (shell profile) — each one a deliberate opt-in no preset can set
LOOMCYCLE_DATA_DIR=$HOME/loomcycle-data               # else ./data under the start directory
LOOMCYCLE_HTTP_HOST_ALLOWLIST=api.anthropic.com,api.github.com
LOOMCYCLE_MCP_ALLOW_PRIVILEGED_TOOLS=1                # only because the MCP client is you
```

Commands run in a workspace: `workspace.mode: local` (yaml below) has the
runtime start its own worker. The listener stays on its default `127.0.0.1:8787`. Local models need only
Ollama at `OLLAMA_BASE_URL` (default `http://localhost:11434`); with a cloud key
too, local is tried first. File access on real working dirs is declared in
`loomcycle.yaml` (the paths must already exist):

```yaml
presets: [personal]

volumes:
  default: { path: /Users/you/work/scratch, mode: rw, default: true }
  work:    { path: /Users/you/work,         mode: ro }

workspace:
  mode: local                    # commands run as you, no isolation

agents:
  dev:
    tier: middle
    tools: [Read, Write, Edit, Grep, Glob, Workspace, File]
    volumes: [default, work]     # confined to exactly these
    workspace: { ops: [read, write, exec], open: true }
```

Storage: SQLite, inferred because no Postgres DSN is set; SQL Memory (and so
Documents) is on with it. An agent that declares no `volumes:` is bound to the `default`
volume if one exists. For a larger local context window set
`providers.ollama-local.options.num_ctx` (or `LOOMCYCLE_OLLAMA_LOCAL_NUM_CTX`,
which wins); for durable memory add `presets: [personal, memory]` and
`scheduled_runs: { memory-consolidation: { enabled: true } }`.

**Sharp edges:** the `local` workspace worker is *not isolated* — a command runs
as the runtime's user and can read its data directory, config and secrets;
anything your user can do, a prompt can do. Fine here because you trust the prompts. The moment
prompts come from elsewhere, move to profile 2 or 3.

**Relative paths resolve under the volume, not the process CWD.** A relative
`Read`/`Write`/`Edit`/`Grep`/`Glob` path is joined to the root of the volume the
call targets — so where you launch loomcycle from no longer matters. (The old
advice to launch from the jail root applied to the retired
`READ_ROOT`/`WRITE_ROOT`/`BASH_CWD` jail.) A workspace is a separate directory
on the worker; the `File` tool copies files between volumes and workspaces (see
[workspaces.md](workspaces.md)).

---

## 2. Containerized with in-container resource access (safer default)

**When:** you want the same capabilities (incl. running commands) but a real
blast-radius boundary. The container *is* the sandbox.

**Trust:** container-bounded. A prompt can act inside the container only;
nonroot (uid 65532), no host shell.

**Run the distroless `denngubsky/loomcycle` image; run commands on a workspace
worker.** The runtime image has no `/bin/sh` (the `loomcycle-toolbox` image is no
longer published since v1.172.0). For commands, add a
`denngubsky/loomcycle-ws-worker` container beside it on the `container` engine,
starting each workspace in `denngubsky/loomcycle-workspace` (Python, Node, git),
with `workspace.mode: remote` and a `workers:attach` token — see
[workspaces.md](workspaces.md) and loomcycle `docs/WORKERS.md` for the compose
service.

```bash
docker pull denngubsky/loomcycle:latest
mkdir -p ./config ./data/files ./data/scratch && sudo chown -R 65532:65532 ./data
docker run --rm -v $(pwd)/config:/home/nonroot/.config/loomcycle \
  denngubsky/loomcycle:latest init --no-interactive
# add the volumes: block below to ./config/loomcycle.yaml, then:
docker run -d --name loomcycle \
  -p 127.0.0.1:8787:8787 \
  -v $(pwd)/config:/home/nonroot/.config/loomcycle:ro \
  -v $(pwd)/data:/home/nonroot/.local/share/loomcycle \
  -e LOOMCYCLE_AUTH_TOKEN=$(openssl rand -hex 32) \
  -e ANTHROPIC_API_KEY=your-key \
  -e LOOMCYCLE_LISTEN_ADDR=0.0.0.0:8787 \
  -e LOOMCYCLE_HTTP_HOST_ALLOWLIST=api.anthropic.com \
  denngubsky/loomcycle:latest
```

```yaml
# ./config/loomcycle.yaml — in-container paths (they must exist; created above)
volumes:
  default: { path: /home/nonroot/.local/share/loomcycle/scratch, mode: rw, default: true }
  files:   { path: /home/nonroot/.local/share/loomcycle/files,   mode: ro }
```

`init` in the container writes `presets: [personal]` to the mounted config.
The images set `LOOMCYCLE_DATA_DIR=/home/nonroot/.local/share/loomcycle`
(v1.153.0) — the data mount above.

Key differences from profile 1: `LISTEN_ADDR=0.0.0.0:8787` *inside* the
container (port-mapped to `127.0.0.1` on the host) — which **requires**
`LOOMCYCLE_AUTH_TOKEN` since v1.119.0 (a `0.0.0.0` bind with no credential
refuses to boot); volumes point at
**in-container** mounted dirs, not host paths; config mounted read-only. SQLite
or Postgres (a `LOOMCYCLE_PG_DSN` selects it). No host filesystem is reachable.

**Sharp edges:** the distroless image has no shell — debug via `docker logs`,
not `docker exec sh`; commands belong on a workspace worker. Writable mount must be
owned by uid 65532 on Linux.

---

## 3. True sandbox (least privilege, untrusted prompts)

**When:** prompts are untrusted or model-authored (public-facing agents,
self-evolution, anything you didn't write). Minimize what a hostile prompt can
reach.

**Trust:** minimal. Container boundary **plus** default-deny tools.

Posture = *what you don't set*. Start from the empty (refusing) defaults and add
back only the narrowest needs:

```bash
LOOMCYCLE_LISTEN_ADDR=0.0.0.0:8787            # inside container, port-mapped to loopback
LOOMCYCLE_AUTH_TOKEN=<required>
ANTHROPIC_API_KEY=<key>

# No workspace (leave workspace.mode off), or only container-engine workers.
# No privileged tools for dynamic agents
# (do NOT set LOOMCYCLE_MCP_ALLOW_PRIVILEGED_TOOLS; do NOT set LOOMCYCLE_MCP_ALLOW_DYNAMIC_STDIO).
# No `volumes:` block in the yaml → every file/exec tool refuses (no disk access).
# If an agent must read files, bind ONE read-only volume and nothing else:
#   volumes: { ref: { path: /srv/reference, mode: ro, default: true } }

# HTTP: tightest possible allowlist (only the APIs agents truly need):
LOOMCYCLE_HTTP_HOST_ALLOWLIST=api.anthropic.com
# Private IPs are hard-blocked at connect regardless — leave it that way.
```

For agents that genuinely need to *execute* logic without a toolchain, prefer
**code-js** — a real sandbox in time (goja; `eval`/`Function` deleted; no ambient
fetch/fs/setTimeout; path-traversal names refused), though **not bounded in
memory**. Code agents are always available since v1.153.0 wherever the config
declares a `code-js` provider (the default providers layer does); the root is
an environment path, the budgets are yaml:

```bash
LOOMCYCLE_CODE_AGENTS_ROOT=/home/nonroot/.local/share/loomcycle/agent_code
```

```yaml
providers:
  code-js:
    options:
      run_timeout_seconds: 60      # ACTIVE time; waits are not counted (default 120)
      max_wall_seconds: 3600       # lifetime cap, waits included (default 86400)
```

To make code agents unavailable instead, run with
`LOOMCYCLE_NO_DEFAULT_PROVIDERS=1` and your own `providers:` without a
`code-js` entry. Code hooks have no switch: control who may author hook
definitions.

For untrusted code that needs a real toolchain, use **workspaces on remote
workers with the `container` engine** (`LOOMCYCLE_WORKSPACE_ENGINE=container`):
each workspace runs in its own container with no network but the egress routes
it holds, a read-only root, every capability dropped and a non-root uid;
`LOOMCYCLE_WORKSPACE_CONTAINER_RUNTIME=runsc` (gVisor) or a Kata runtime adds a
kernel boundary. Set `engine: container` in each agent's `workspace` grant so it
never lands on a `host`-engine worker, and do **not** use `workspace.mode: local`
here. (This replaces Bashbox and the builder sidecar — the `sandbox` and
`dev-exec` presets are removed since v1.172.0; `dev-workspace` replaces them.)
See [workspaces.md](workspaces.md).

Agent `tools` should be the minimal set (often just `Read` on one read-only
volume, or specific `mcp__*` tools). Run on the distroless profile-2 image, add
seccomp/read-only-rootfs/`--cap-drop=ALL` at the container layer, and keep the
listener bound to loopback behind your app.

**Some capability tools have a *second* default-deny gate — and some no longer
do.** Beyond the operator tool-enable (the HTTP env vars, `volumes:`, `workspace.mode`) and the
agent `tools`:

- **Still default-deny when the gate is unset:** `Channel` (`channels:` —
  per-side publish/subscribe ACL), `AgentDef` (`agent_def_scopes:` —
  `self`/`descendants`/`named:<n>`/`any`), `ScheduleDef`
  (`schedule_def_scopes:`), `VolumeDef` (`volume_def_scopes:`) and the A2A def
  tools. Listing the tool in `tools` is necessary but **not** sufficient.
- **No longer deny when unset (v1.82.0 / v1.83.0):** an agent holding `Memory`,
  `History` or `Evaluation` with no scope list resolves to what the caller
  already owns — `memory_scopes` → `user` (+ `tenant` for a non-isolated
  member), `history_scope` → `user`, `sql_scopes` → `["user"]`,
  `evaluation_scopes` → `["submit_self"]`. **For this profile, give an agent only the tools it
  needs**: an agent that should hold no memory gets no `Memory` in `tools:`. The
  deny-all value `["-*"]` fails static config load; it is accepted only on an
  `AgentDef` create/fork overlay.

`loomcycle validate`, `loomcycle doctor` and boot print an advisory for each
unset or inert gate (e.g. "`Channel` is in this agent's tools but
`channels.publish` and `channels.subscribe` are both empty, so every Channel
call is refused"), so a forgotten scope is visible before a run rather than
looking like the agent "chose" not to use the tool. An agent authored *inside a
run* (`AgentDef` create/fork) is additionally held to its author's own
capability fields (v1.104.0).

**Sharp edges:** a `local` (host-engine) workspace worker is *not* a sandbox; if
you need shell-like behavior for untrusted prompts, you want code-js or
container-engine workers.

---

## 4. Server (one backend serving one app's agents)

**When:** loomcycle is the sidecar/back-end for a single application. Not
customer-multi-tenant yet, but real traffic.

**Trust:** app-scoped. Usually **no workspace**; tools limited to what the app's
agents need (often just `Read` + specific MCP tools + HTTP to the app's own API).

Environment (the `examples/profiles/server/` env files have the same split):

```bash
# non-secret
LOOMCYCLE_LISTEN_ADDR=0.0.0.0:8787            # behind a reverse proxy / LB
LOOMCYCLE_PUBLIC_URL=https://agents.example.com
LOOMCYCLE_CONFIG_DIR=/config                  # holds loomcycle.yaml
LOOMCYCLE_DATA_DIR=/data
LOOMCYCLE_CONFIG_STRICT=1                     # a cross-layer config clobber is fatal, not a log line
# App callback: let agents reach the app's own API without opening egress:
LOOMCYCLE_HTTP_HOST_ALLOWLIST=app.internal,api.anthropic.com
LOOMCYCLE_HTTP_PRIVATE_HOST_ALLOWLIST=app.internal   # if it resolves to a private IP
# "Private" includes CGNAT 100.64.0.0/10 — a Tailscale peer needs an entry here;
# a CIDR entry (100.64.0.0/10) admits a whole tailnet.
OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4318   # standard OTEL_* since v1.148.0

# secrets
LOOMCYCLE_AUTH_TOKEN=<required, strong>
ANTHROPIC_API_KEY=<key>
DEEPSEEK_API_KEY=<key>                        # if using a cost cascade (routing pattern 2)
# LOOMCYCLE_PG_DSN=postgres://…?sslmode=require        # its presence selects Postgres
# LOOMCYCLE_SQLMEM_PG_DSN=postgres://…/loomcycle_sqlmem # keeps SQL Memory + Documents on with Postgres
```

Yaml (`/config/loomcycle.yaml`):

```yaml
presets: [server]            # routing, chat/document/memory agents, metrics sampler on

storage:
  backend: sqlite            # or postgres — pin it either way

concurrency:
  max_concurrent_runs: 16
  max_queue_depth: 64

volumes:
  dynamic: { path: /mnt/dynamic, mode: rw, dynamic_root: true }

auth:
  gates:
    token: { kind: token, label: "Access token" }
```

The `server` preset already sets `metrics: {enabled: true, collect_system:
true}` — host CPU/mem (Linux `/proc`) catches co-tenant pressure that the
process's own numbers miss. On Postgres, the schema is applied by
`loomcycle migrate up` (or `LOOMCYCLE_PG_AUTOMIGRATE=1`). See
[observability.md](observability.md) for traces and `/metrics`.

Routing: this is where `user_tiers:` earns its keep — gate plans by tier
(routing pattern 3/4), and set `fallback_on_error: true` on each overlay that
should cascade (the key has no default). Use `loomcycle pause`/`resume`/`snapshot` for safe
deploys, and `POST /v1/_config/reload` (`?dry_run=1` to preview) to apply a
routing/agent edit without a restart. Workspaces stay off unless the app's
agents must run code; then use remote `container`-engine workers, not `local`.

A single app can also skip minted tokens and **declare** its service identities
in yaml — the yaml carries only the env-var *name* of each bearer:

```yaml
principals:
  app-backend:
    tenant: app                      # required unless the principal is substrate:admin
    subject: backend
    scopes: [runs:create, runs:read]
    token_env: LOOMCYCLE_TOKEN_APP_BACKEND   # secret value lives in .env.local
```

Tenant names must match `[a-zA-Z0-9_-]{1,64}`; an unknown scope or a non-admin
principal with no `tenant:` fails config load; an empty `token_env` leaves the
principal inert (a warning). Declaring any principal turns authentication on
(v1.119.0) — a request without a valid bearer gets `401`.

On SIGTERM the server pauses in-flight runs for up to
`LOOMCYCLE_SHUTDOWN_PAUSE_TIMEOUT_MS` (default 7000, v1.119.0) and resumes them
on restart — raise it together with your platform's stop grace period for slow
models.

**Sharp edges:** never leave a server without a credential — since v1.119.0 a
non-loopback listener with no `LOOMCYCLE_AUTH_TOKEN` / `principals:` / admin
token refuses to boot rather than run open. Put TLS at the proxy; loomcycle
speaks plain HTTP (set an `https://` `LOOMCYCLE_PUBLIC_URL` so the Web UI's
session cookie is `Secure` behind it).

---

## 5. Multi-tenant (customers who don't trust each other)

**When:** one instance fronts multiple tenants/customers. Per-principal identity
and tenant isolation become real boundaries.

**Trust:** per-principal. The bearer token — not the request body — is the
authority for `(tenant, subject, scopes)`.

Builds on profile 4 and adds the settings below. Use Postgres for a real
multi-tenant service (SQLite stores tokens too, so a single-box trial works;
Postgres is required once you add replicas):

```bash
# secrets
LOOMCYCLE_PG_DSN=postgres://loomcycle:…@db:5432/loomcycle?sslmode=require        # selects Postgres
LOOMCYCLE_SQLMEM_PG_DSN=postgres://loomcycle:…@db:5432/loomcycle_sqlmem?sslmode=require  # SQL Memory + Documents; role needs CREATEROLE
LOOMCYCLE_SECRET_KEY=<openssl rand -base64 32>            # credential store, sessions, audit chain, derived token pepper; required with >1 principal

# non-secret
LOOMCYCLE_AUDIT_LOG_PATH=/var/log/loomcycle/audit.jsonl   # optional file mirror of the store-backed audit trail
LOOMCYCLE_AUTH_CACHE_TTL_SECONDS=30                       # 0 for immediate revocation
LOOMCYCLE_OPERATOR_TOKEN_ROTATION_GRACE_SECONDS=86400
# LOOMCYCLE_LOG_LEVEL=debug                               # while diagnosing: server-side reason on 401s (wire stays opaque)
# LOOMCYCLE_OPERATOR_KEY_RESTRICTION=1                    # tenants without providers:operator-key must use their own key
# LOOMCYCLE_USER_TOKEN_MAX_TTL_SECONDS=86400              # cap per-user token life (v1.112.0)
# LOOMCYCLE_LIMITS_ENFORCE=strict                         # hard budgets also stop runs in flight (v1.112.0)
# LOOMCYCLE_RUN_RATE_PER_MINUTE=60                        # default run-start rate for tokens with none (v1.112.0)
# LOOMCYCLE_ACL=shadow                                    # access-control rollout: compat → shadow → enforce (v1.122.0)
```

```yaml
presets: [server]
storage:
  backend: postgres
concurrency:
  max_concurrent_runs: 32
  max_queue_depth: 128
  max_concurrent_runs_per_user: 4       # per-user fairness; cluster-wide on Postgres
  max_queued_runs_per_user: 16
retention:                              # nothing is deleted with age until enabled
  enabled: true
  interval: 24h
  export_dir: /data/retention-exports
  chats: { mode: export+prune, max_age: 90d }
  defs:  { mode: prune, max_age: 30d }
```

**The audit trail is in the store.** A sign-in gate, `auth.mode: strict`, a
`LOOMCYCLE_ACL` other than `compat`, or more than one principal turns on the
store-backed, hash-chained audit stream, which needs `LOOMCYCLE_SECRET_KEY`
(`LOOMCYCLE_AUDIT_RETENTION_DAYS` prunes it; default keep forever). Subject
erasure needs a durable audit record — the store stream or the file mirror.

**Token hashes are peppered by default (v1.119.0).** With
`LOOMCYCLE_SECRET_KEY` set, the pepper is derived from the key; with no key,
hashes are unpeppered and boot warns. **Since v1.156.0 an explicit
`LOOMCYCLE_OPERATOR_TOKEN_PEPPER` beside the key is legacy**: new tokens use the
derived pepper and old ones move as they log in; remove the variable once the
boot line `auth: LOOMCYCLE_OPERATOR_TOKEN_PEPPER is legacy: …` counts no row
([settings.md](settings.md#after-v11550-the-explicit-token-pepper-is-legacy)). Consequences: upgrade every replica together (older releases cannot read
the new hash forms); rolling back means re-minting every operator token; and
removing or changing `LOOMCYCLE_SECRET_KEY` without `LOOMCYCLE_SECRET_KEY_PREVIOUS`
logs every operator token out. **Upgrading from a release before v1.119.0
straight to a later one:** pre-pepper token rows are refused at login until you
run **`loomcycle tokens rewrap`** (v1.120.0; refused while a legacy explicit
pepper is set) with the server's own config and env — it first lists the unpeppered rows (writes nothing), then
`loomcycle tokens rewrap --def-id <def_id>@<fingerprint>` (or
`--all-listed <digest>`) moves the rows you recognise. Retire any row you did
not mint instead. The legacy `LOOMCYCLE_AUTH_TOKEN` keeps working meanwhile.

Mint per-tenant tokens (admin bearer required); the token's `subject` becomes
the run's `user_id` (fairness key) and its `tenant_id` is the memory-isolation
boundary:

```bash
loomcycle operator-token create --name alice --tenant acme --subject alice \
  --scopes runs:create,runs:read
loomcycle operator-token create --name acme-ops --tenant acme --scopes substrate:tenant
loomcycle operator-token rotate --name alice    # zero-downtime, grace window (default 24h)
loomcycle operator-token retire --name alice    # immediate revoke
# Migrate an existing shared secret in place (keeps working as an admin token):
loomcycle operator-token create --name ops --tenant default --subject ops --copy-from-env
```

`--name` and `--tenant` are required. **`--scopes` is required too (v1.87.0)**:
an omitted scope list is refused — it used to default to `substrate:admin`, so a
mistyped key minted a full-power token. `--copy-from-env` is the one exemption.
Over HTTP / MCP the request key is `scopes` (`allowed_scopes` is only what the
response echoes; an unknown key is refused).

The closed scope catalog (an unknown scope is refused):

| Scope | Grants |
|---|---|
| `runs:create` / `runs:read` | Create/continue runs · read runs, agents, sessions. |
| `channel:publish` / `channel:read` | Publish/ack · subscribe/peek on the channel surface. |
| `substrate:user` | **Isolated member.** Its own runs only (implies `runs:create` + `runs:read`), confined to its own user scope: no tenant-shared or global data, no other user's runs, no channel scopes, no def authoring. Over `/v1/_mcp` it may call only `credentialdef` (its own `scope=user` credentials) and, since v1.122.0, `authz` (its own access questions). |
| `substrate:tenant` | **Tenant operator.** Full power *within its own tenant*: runs, channels, authoring every substrate def (agents, skills, teams, hooks, MCP servers, schedules, webhooks…), and a tenant-confined `/v1/_mcp` session. Implies the four `runs:*` / `channel:*` scopes and `providers:operator-key`. No minting, no runtime admin, no cross-tenant access. |
| `substrate:admin` | **Superuser** — every scope, token minting, runtime admin (pause/resume/snapshot/reload), cross-tenant focus. Never implicit; ask for it by name. |
| `providers:operator-key` | Lets a run fall back to the operator's host provider key. Inert unless `LOOMCYCLE_OPERATOR_KEY_RESTRICTION=1`. To make a tenant pay its own way: set the gate, mint its tokens with granular scopes that omit this one (e.g. `runs:create,runs:read`), and give the tenant its own key as a CredentialDef ([credentials.md](credentials.md)); a restricted run with no usable key gets `403 operator_key_restricted`. |
| `runs:delete` | **(v1.112.0)** Delete a run tree (`delete_run_tree`, `DELETE /v1/runs/{id}/tree`). Tenant-implied; a member or isolated user has it only when granted by name. |
| `llm:gateway` | **(v1.112.0)** The raw model endpoints (`/v1/_llm/chat`, `/v1/chat/completions`, `/v1/embeddings`) — metered and budget-checked. Tenant-implied and admitted for a non-isolated member; an **isolated** user's token needs it by name. |
| `auth:manage` | **(v1.123.0)** A website's user-management token (password gate + `/v1/_users`), across tenants and nothing else. Must be the token's only scope; refused over gRPC. See [identity.md](identity.md). |
| `scim:provision` | **(v1.127.0)** An identity provider's SCIM 2.0 credential for a `kind: scim` gate: `/scim/v2/*` in its own tenant and nothing else. Must be the token's only scope; refused over gRPC. See [identity.md](identity.md). |

**Restricted tokens (v1.112.0)** — for a token handed to a machine you do not
control. Each restriction is set at mint (`operator-token create`, the
`operatortokendef` tool, `POST /v1/_users/{subject}/tokens`, a declared
principal) and survives rotation:

- **`ttl_seconds`** — a fixed life; rotation does not extend it, and a token
  cannot mint one that outlives it. Not allowed on `substrate:admin`. The
  per-user mint also takes `name` and `max_active`.
- **`agents: [...]`** — may start only those agents as top-level runs, and is
  held to the run endpoints on every transport (definitions, team walks,
  schedules, gateways, channels, memory, documents, credentials, A2A →
  `restricted_token`). Since v1.115.0 it also cannot steer, retune, cancel or
  review other agents' runs, and (v1.119.0) reads only runs whose spawn-tree
  root is on its list.
- **`overrides: "none"`** (or a list of what it may still set) — locks model,
  provider, tier, effort, limits, sampling, hooks… for runs it starts
  (`override_not_allowed`). The agent-side twin is `allow_overrides: false` on
  the definition.
- **`rate: {per_minute, burst}`** — run starts (and steers) per user, per
  replica (`429 rate_limited`, `Retry-After`).
- **No-trace** — `retention: "none"` on the token makes every run it starts
  deliver its output and store none of it (also settable per run or per agent;
  strictest wins). Interactive, review, session-continuing and team-walk runs
  are refused in this mode. `retention_override` (v1.112.0) temporarily stores
  one no-trace agent's runs for debugging — never one a token requires.

**People sign in through gates (v1.123.0 / v1.126.0).** The Web UI holds a
server-side session (`auth.mode: token` or `strict`); OIDC, OAuth, password,
header (Cloudflare Access / ALB / forward-auth), AWS IAM, device-code and
external (signed-assertion, for bridges and apps) gates issue per-user tokens,
and `loomcycle login` stores a terminal's token in the OS keychain (which
`loomcycle mcp --upstream` uses when `LOOMCYCLE_MCP_UPSTREAM_TOKEN` is unset).
External and device gates need `LOOMCYCLE_PUBLIC_URL`. Since v1.127.0:
passkeys (a second factor at a password gate, or a password-less
`kind: passkey` gate — relying party `LOOMCYCLE_PUBLIC_URL`), SCIM provisioning
(`kind: scim`), and `auth.strict.user_tokens: gate_only`, which refuses
hand-minted per-user tokens everywhere (a pasted per-user token in this
plugin's `auth_token` then stops working — use `loomcycle login`). In strict
mode a hand-minted per-user token is never a Web UI sign-in, with or without
`gate_only`. See [identity.md](identity.md).

**Access control (v1.122.0).** Per-user and per-group ACL rule lists, nested
groups and bindings, explicit deny over allow, intersected with each agent's
grants inside a run. Roll out with `LOOMCYCLE_ACL`: `compat` (default —
nothing changes until you write a deny) → `shadow` (log every divergence) →
`enforce`. See [access-control.md](access-control.md).

**Runs queue instead of being refused (v1.113.0 / v1.114.0).** A run over
`concurrency.max_concurrent_runs_per_user` or the global cap gets its row with
status `queued` (cancellable, survives a restart), served round-robin across
(tenant, user). Bounds: `concurrency.max_queue_depth` (32) and
`concurrency.max_queued_runs_per_user` (16); past them `429 backpressure`.
`admission: "reject"` on a request restores the old refuse-at-once answer.
Session continuations and the LLM gateway queue too (v1.114.0). A token
budget is checked before a run may queue and again when it starts. Details:
[routing.md](routing.md).

**MCP sessions are held to token scopes (v1.107.0).** A member token driving
`/v1/_mcp` (the plugin's HTTP MCP transport or `loomcycle mcp --upstream`) needs
`runs:create` for the run tools (`spawn_run`, `spawn_runs`, `cancel_run`,
`compact_run`, `retune_run`, `review_run`, `configured_run`,
`interruption_resolve`, `decision`, and `teamdef` `run`/`cancel`), `runs:read`
for the read tools (`get_run`, `list_runs`, `stream_user_run_states`),
`channel:publish` for `publish_channel` / `ack_channel` and `channel:read` for
`subscribe_channel` / `peek_channel`. A token minted with only `runs:read` can
no longer start runs over MCP. Tools added since (v1.108.0–v1.126.0): `file`
and `evaluation` need `runs:read`; `delete_run_tree` needs `runs:delete`;
`list_team_channels` / `peek_team_channel` need `channel:read` and
`release_team_channel` needs `channel:publish`; `groupdef`, `acldef`,
`aclbinding`, `clientdef`, `crypto`, `retention_override` and `ontology`
(subject merge / bind, v1.131.0) need `substrate:tenant`; `identity` needs
nothing beyond a non-isolated token; `review` (v1.133.0) needs no scope by name
— each statement asks whether the caller may rule (an operator, or a member
holding the access-control `review` verb). Stdio, admin, legacy and `substrate:tenant`
sessions are unchanged.

Routing: use `user_tiers:` privacy boundaries (routing pattern 4) so a tenant's
high tier never escapes the anthropic/openai boundary. **No anthropic-oauth-dev**
(single-operator only). No `local` workspace worker for untrusted tenants — use
per-tenant or shared `container`-engine workers and pair with profile 3 tool
posture. **Always-on features reach every tenant (v1.153.0):** anyone who may
author agent or hook definitions in a tenant can run code-js in the shared
process (bounded in time, not in memory), schedules and webhooks fire without a
switch, and channel `hooks:` always apply. Grant definition authoring
deliberately ([access-control.md](access-control.md)); run tenants that need
memory isolation in separate processes.

**Postgres document plane (v1.128.0).** Each SQL Memory scope that holds
documents gets a second schema and login role for the Document tool's tables —
`sqlmem_d_<h>` / `sqlmem_dr_<h>`, beside the agent's `sqlmem_s_<h>` /
`sqlmem_r_<h>` — and neither role can reach the other's schema, so the engine
enforces that an agent's Memory SQL cannot touch documents. The admin role
still needs `CREATEROLE`. **`pg_hba` must admit the new `sqlmem_dr_…` login
roles wherever it lists the scope roles (`sqlmem_r_…`) individually**; a rule
by pattern or `all` needs nothing. The first Document op on an older scope
waits while its rows are copied (bounded at 10 minutes per scope; a failed copy
is retried on the next op, nothing half-moved). `Document op=query_chunks` raw
`sql` now runs as the Document role, so it can no longer read an agent's own
tables. On sqlite a scope stays one file and a statement check is the boundary.

**Sharp edges:** creating the *first* admin-scoped `OperatorTokenDef` disables
the legacy `LOOMCYCLE_AUTH_TOKEN` for inbound HTTP (the no-lockout gate) — which
is why `substrate:admin` is never minted implicitly. Before you mint one, be
ready to update every HTTP client (incl. this plugin's auth_token + the
auto-snapshot hook) to the new `lct_…` admin bearer. Minting only
`substrate:tenant` / granular tokens leaves the legacy token working. Audit
tokens minted before v1.87.0 without scopes: they are admin. Routes enforce a
scope from a closed catalog; an under-scoped token gets
`403 + WWW-Authenticate: Bearer scope="…"`. A webhook or schedule stored by a
non-admin may only run in its own tenant, and only an admin may put a `${NAME}`
env reference in a runtime MCP server def (tenants use `$cred:<name>`). This is
also the profile to pair with the plugin's **HTTP MCP transport**
(`examples/mcp-http-tenant.json`) when driving a confined tenant from the IDE.

---

## 6. Cloud / multi-replica (horizontal HA)

**When:** N replicas behind a load balancer for availability + throughput.

**Trust:** inherits profile 4/5; adds horizontal scale.

Builds on profile 5, **requires shared Postgres**, and adds per-replica identity:

```bash
# Every replica: SAME yaml (presets: [server], storage.backend: postgres),
# SAME binary version, SAME secrets.
LOOMCYCLE_PG_DSN=postgres://…@db.example.com:5432/loomcycle?sslmode=require
LOOMCYCLE_SQLMEM_PG_DSN=postgres://…@db.example.com:5432/loomcycle_sqlmem?sslmode=require
LOOMCYCLE_AUTH_TOKEN=<shared bearer — identical on all replicas>
LOOMCYCLE_SECRET_KEY=<identical on all replicas>
LOOMCYCLE_PG_MAX_OPEN_CONNS=<max_concurrent_runs × 1.5>   # or storage.pg_max_open_conns; the variable wins

# Per replica (UNIQUE):
LOOMCYCLE_REPLICA_ID=replica-a    # replica-b, replica-c, …  (SQLite refuses to boot with this set)

# Recommended:
OTEL_EXPORTER_OTLP_ENDPOINT=<collector URL with scheme>
```

The stale-run heartbeat sweeper always runs (its switch was retired in
v1.153.0); the `server` preset turns the metrics sampler on.

Load balancer: any HTTP LB, round-robin/least-conn, **no sticky sessions**.
Cancel, pause/resume, fairness, run status, steering/retune and session locks
all work cluster-wide via Postgres LISTEN/NOTIFY (a cancel, steer or retune is
routed to the replica that owns the run). Verify with
`GET /healthz` (shows the `replicas[]` membership).

The scheduler runs on every replica (always on since v1.153.0; cluster-safe
since v1.105.0): each due slot is fired by the one replica that claims it, and `concurrency_policy` /
`catch_up_max` hold cluster-wide. Team webhooks are answered by any replica.

Rolling upgrade: `POST /v1/_pause` → drain → snapshot → upgrade replicas one at
a time → `POST /v1/_resume`. Crashed replicas auto-recover within ~90s (runs
marked failed, quota slots reclaimed) — no manual DB cleanup. A cancel aimed at
a dead replica's run ends it `cancelled` straight away (`owner_dead_cancelled`).
A **team walk does not move**: one left running by a stopped instance is ended
`failed`.

**Sharp edges:**
- Global concurrency cap (yaml `concurrency.max_concurrent_runs`) is
  **per-replica** — e.g. a cap of 10 × 2 replicas = 20 cluster-wide; per-user
  fairness (`concurrency.max_concurrent_runs_per_user`) IS cluster-wide, while
  `max_queued_runs_per_user` counts per replica.
- MCP stdio children are per-replica — size memory for `N replicas × M servers`.
- Token budgets, the auth-token cache, per-provider `max_concurrent` gates,
  token run rates (`rate`, `LOOMCYCLE_RUN_RATE_PER_MINUTE`) and the
  `timeout_scaling` speed estimate are per-replica / advisory.
- Queued runs belong to a replica: at boot each replica restarts its own
  queued runs. A queued run carrying per-run secrets needs
  `LOOMCYCLE_SECRET_KEY` (same on every replica) to come back.
- Upgrade every replica together when moving to v1.119.0+ with
  `LOOMCYCLE_SECRET_KEY` set — an older replica cannot read peppered token
  hashes.
- **Upgrade every replica together when moving to v1.153.0+** and run the
  [upgrade checklist](settings.md#upgrading-from-before-v11530--checklist) with
  each replica's own environment; likewise v1.156.0+ with an explicit token
  pepper (an older replica refuses tokens that moved to the derived pepper).
- **Upgrade every replica together when moving to v1.128.0+** (snapshot
  first): an older replica knows neither the statement columns nor the Postgres
  document plane — it writes documents into the agent schema, and once a newer
  replica has moved that scope those writes are dropped (with a warning).
  Likewise v1.127.0+ before configuring passkeys, SCIM or `gate_only` (older
  replicas have no handling for them).
- Access-control sets are cached per replica for
  `LOOMCYCLE_ACL_CACHE_TTL_SECONDS` (default 5) at worst; writes invalidate
  over the cluster bus.
- `anthropic-oauth-dev` and snapshot `--file` restore are per-host — use API
  keys and inline `raw_json` restore in a cluster.
- Postgres is the single source of truth; no split-brain (an isolated replica is
  reaped in ~90s).

---

## Quick decision aid

- Trust every prompt + want host tools → **1** (or **2** to contain it).
- Need to run commands but prompts aren't fully trusted → **2** (container-engine workspace workers).
- Prompts untrusted/model-authored → **3** (no `local` workspace, default-deny, code-js).
- One app, real traffic, single instance → **4** (`presets: [server]`).
- Profiles 1–3 start from `presets: [personal]`, 4–6 from `presets: [server]`.
- Multiple customers, one instance → **5** (Postgres + per-principal tokens).
- Need availability/scale → **6** (Postgres + replicas).
