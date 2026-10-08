# Deployment profiles

Six postures on a **trust × scale** grid. Each is a preset of env vars (the
posture axis) over the same `loomcycle.yaml` routing. Profiles are cumulative —
5 layers on 4, 6 layers on 5. Pick the *lowest-trust* one that does the job.

Cross-check every var against [env-vars.md](env-vars.md); routing yaml lives in
[routing.md](routing.md). **Print env lines for the operator — never write their
env file.** Never put a secret value in any file.

Two things changed under every profile since these were first written (current
as of **v1.107.0**):

- **Filesystem access is a YAML `volumes:` block, not env.** The
  `LOOMCYCLE_READ_ROOT` / `LOOMCYCLE_WRITE_ROOT` / `LOOMCYCLE_BASH_CWD` jail was
  retired in v1.1.0 — setting any of them now **fails startup**. An agent bound
  to no volume has no disk access. See [volumes.md](volumes.md).
- **Routing can come from an embedded preset.** `LOOMCYCLE_PRESETS=base` supplies
  the provider matrix, aliases and tiers; your own `--config` layers on top. The
  YAML skeletons below assume that (or your own `tiers:` — see routing.md).
  The agent tool-allowlist key is `tools:`.

---

## 1. Brew install + in-system agent (full host trust)

**When:** a developer workstation or a single trusted box doing personal
automation, where you author and trust every prompt. The agent legitimately
needs the host's tools, files, and shell.

**Trust:** full — the loomcycle process runs as your user with your filesystem.
There is no isolation; the trust boundary is "you wrote the prompts."

```bash
brew install denn-gubsky/loomcycle/loomcycle
loomcycle init      # writes a starter loomcycle.yaml + README in the config dir
                    # (--with-token also mints LOOMCYCLE_AUTH_TOKEN into <configdir>/auth.env, mode 0600)
loomcycle doctor    # verify
loomcycle validate ~/.config/loomcycle/loomcycle.yaml   # after every edit
```

Env (secrets → `.env.local`; non-secret config → `.env.insecure`; both sourced by
`loomcycle.sh`. Post-v0.23.0 split — see [env-vars.md](env-vars.md); a v0.23.0
binary uses one `.env.local`):

```bash
LOOMCYCLE_LISTEN_ADDR=127.0.0.1:8787          # local only
LOOMCYCLE_AUTH_TOKEN=<openssl rand -hex 32>   # set even locally; avoids the dev-mode warning
ANTHROPIC_API_KEY=<from your secret store>    # at least one provider key

LOOMCYCLE_PRESETS=base                        # embedded provider/tier matrix (or write your own tiers:)
LOOMCYCLE_BASH_ENABLED=1
LOOMCYCLE_HTTP_HOST_ALLOWLIST=api.anthropic.com,api.github.com
BRAVE_API_KEY=<optional, for WebSearch>
LOOMCYCLE_MCP_ALLOW_PRIVILEGED_TOOLS=1        # only because the stdio MCP client is you
```

File access on real working dirs is declared in `loomcycle.yaml` (the paths must
already exist):

```yaml
volumes:
  default: { path: /Users/you/work/scratch, mode: rw, default: true }
  work:    { path: /Users/you/work,         mode: ro }

agents:
  dev:
    tier: middle
    tools: [Read, Write, Edit, Grep, Glob, Bash]
    volumes: [default, work]     # confined to exactly these
```

Storage: SQLite (`LOOMCYCLE_DATA_DIR=./data`, the default). Agents may list
`tools` including `Bash`/`Write`/`Edit`/`Read`/`Grep`/`Glob`. An agent that
declares no `volumes:` is bound to the `default` volume if one exists.

**Sharp edges:** Bash is cwd-restricted but *not isolated* — anything your user
can do, a prompt can do. Fine here because you trust the prompts. The moment
prompts come from elsewhere, move to profile 2 or 3.

**Relative paths resolve under the volume, not the process CWD.** A relative
`Read`/`Write`/`Edit`/`Grep`/`Glob` path is joined to the root of the volume the
call targets, and `Bash` runs in the root of its bound `rw` volume — so where
you launch loomcycle from no longer matters. (The old advice to launch from the
jail root applied to the retired `READ_ROOT`/`WRITE_ROOT`/`BASH_CWD` jail.)
`Bash` is refused on a `ro` volume; `Bashbox` honours `ro` (see
[bashbox.md](bashbox.md)).

---

## 2. Containerized with in-container resource access (safer default)

**When:** you want the same capabilities (incl. Bash) but a real blast-radius
boundary. **This is the recommended way to expose Bash.** The container *is* the
sandbox.

**Trust:** container-bounded. A prompt can act inside the container only;
nonroot (uid 65532), no host shell.

**Pick the image by whether you need `Bash`.** The default
`denngubsky/loomcycle` image is distroless — it has no `/bin/sh`, so the `Bash`
tool cannot run there (file tools, `Bashbox`, HTTP and MCP all work).
`denngubsky/loomcycle-toolbox` is the same binary on a Debian base with a dev
toolchain (Python / Go / Rust / C++ / Node, `git`, `gh`, `curl`) — a drop-in
swap with the same uid and mount paths. Use it for `Bash`, single-tenant /
trusted prompts only: commands run inside loomcycle's own container.

```bash
docker pull denngubsky/loomcycle-toolbox:latest   # or denngubsky/loomcycle:latest (no Bash)
mkdir -p ./config ./data/files ./data/scratch && sudo chown -R 65532:65532 ./data
docker run --rm -v $(pwd)/config:/home/nonroot/.config/loomcycle \
  denngubsky/loomcycle-toolbox:latest init --no-interactive
# add the volumes: block below to ./config/loomcycle.yaml, then:
docker run -d --name loomcycle \
  -p 127.0.0.1:8787:8787 \
  -v $(pwd)/config:/home/nonroot/.config/loomcycle:ro \
  -v $(pwd)/data:/home/nonroot/.local/share/loomcycle \
  -e LOOMCYCLE_AUTH_TOKEN=$(openssl rand -hex 32) \
  -e ANTHROPIC_API_KEY=your-key \
  -e LOOMCYCLE_LISTEN_ADDR=0.0.0.0:8787 \
  -e LOOMCYCLE_BASH_ENABLED=1 \
  -e LOOMCYCLE_HTTP_HOST_ALLOWLIST=api.anthropic.com \
  denngubsky/loomcycle-toolbox:latest
```

```yaml
# ./config/loomcycle.yaml — in-container paths (they must exist; created above)
volumes:
  default: { path: /home/nonroot/.local/share/loomcycle/scratch, mode: rw, default: true }
  files:   { path: /home/nonroot/.local/share/loomcycle/files,   mode: ro }
```

Key differences from profile 1: `LISTEN_ADDR=0.0.0.0:8787` *inside* the
container (port-mapped to `127.0.0.1` on the host); volumes point at
**in-container** mounted dirs, not host paths; config mounted read-only. SQLite
or Postgres. No host filesystem is reachable.

**Sharp edges:** the distroless image has no shell — debug via `docker logs`,
not `docker exec sh`, and `Bash` needs the toolbox image. Writable mount must be
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

# Bash OFF (unset LOOMCYCLE_BASH_ENABLED). No privileged tools for dynamic agents
# (do NOT set LOOMCYCLE_MCP_ALLOW_PRIVILEGED_TOOLS; do NOT set LOOMCYCLE_MCP_ALLOW_DYNAMIC_STDIO).
# No `volumes:` block in the yaml → every file/exec tool refuses (no disk access).
# If an agent must read files, bind ONE read-only volume and nothing else:
#   volumes: { ref: { path: /srv/reference, mode: ro, default: true } }

# HTTP: tightest possible allowlist (only the APIs agents truly need):
LOOMCYCLE_HTTP_HOST_ALLOWLIST=api.anthropic.com
# Private IPs are hard-blocked at connect regardless — leave it that way.
```

For agents that genuinely need to *execute* logic, prefer **code-js** over Bash
— it's a real sandbox (goja; `eval`/`Function` deleted; no ambient
fetch/fs/setTimeout; path-traversal names refused; whole-run timeout):

```bash
LOOMCYCLE_CODE_AGENTS_ENABLED=1
LOOMCYCLE_CODE_AGENTS_ROOT=/home/nonroot/.local/share/loomcycle/agent_code
LOOMCYCLE_CODE_AGENTS_RUN_TIMEOUT_SECONDS=60     # ACTIVE time; waits are not counted
LOOMCYCLE_CODE_AGENTS_MAX_WALL_SECONDS=3600      # lifetime cap, waits included (default 24h)
```

Two more sandboxed execution paths, both stronger than `Bash`:

- **`Bashbox`** (`LOOMCYCLE_BASHBOX_ENABLED=1`) — an in-process shell with no OS
  process and no network that honours `ro` volumes. Leave
  `LOOMCYCLE_BASHBOX_FALLBACK_COMMANDS` unset here. See [bashbox.md](bashbox.md).
- **The builder sidecar** — for untrusted code that needs a real toolchain, each
  session runs in a separate ephemeral container (network off, read-only
  rootfs, `--cap-drop=ALL`); loomcycle stays distroless and drives it over
  HTTP-MCP. Enable with `LOOMCYCLE_PRESETS=base,sandbox,dev-exec` and a shared
  `SANDBOX_AUTH_TOKEN` (secret). Its shipped auth is one shared bearer, i.e.
  single-tenant. See loomcycle `docs/SANDBOX.md`.

Agent `tools` should be the minimal set (often just `Read` on one read-only
volume, or specific `mcp__*` tools). Run on the distroless profile-2 image, add
seccomp/read-only-rootfs/`--cap-drop=ALL` at the container layer, and keep the
listener bound to loopback behind your app.

**Some capability tools have a *second* default-deny gate — and some no longer
do.** Beyond the operator tool-enable (the Bash/HTTP env vars, `volumes:`) and the
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
  `evaluation_scopes` → `["submit_self"]`. **For this profile, write the gates
  explicitly**: `memory_scopes: ["-*"]` (and `history_scope` / `sql_scopes`
  `["-*"]`) grants nothing; an empty list cannot express that.

`loomcycle validate`, `loomcycle doctor` and boot print an advisory for each
unset or inert gate (e.g. "`Channel` is in this agent's tools but
`channels.publish` and `channels.subscribe` are both empty, so every Channel
call is refused"), so a forgotten scope is visible before a run rather than
looking like the agent "chose" not to use the tool. An agent authored *inside a
run* (`AgentDef` create/fork) is additionally held to its author's own
capability fields (v1.104.0).

**Sharp edges:** loomcycle's docs are explicit — Bash is *not* a sandbox; if you
need shell-like behavior for untrusted prompts, you want code-js or a separate
hardened container, not `LOOMCYCLE_BASH_ENABLED=1`.

---

## 4. Server (one backend serving one app's agents)

**When:** loomcycle is the sidecar/back-end for a single application. Not
customer-multi-tenant yet, but real traffic.

**Trust:** app-scoped. Usually **no Bash**; tools limited to what the app's
agents need (often just `Read` + specific MCP tools + HTTP to the app's own API).

```bash
LOOMCYCLE_LISTEN_ADDR=0.0.0.0:8787            # behind a reverse proxy / LB
LOOMCYCLE_AUTH_TOKEN=<required, strong>
ANTHROPIC_API_KEY=<key>
DEEPSEEK_API_KEY=<key>                         # if using a cost cascade (routing pattern 2)

LOOMCYCLE_STORAGE_BACKEND=sqlite               # or postgres for durability/HA-readiness
# LOOMCYCLE_PG_DSN=postgres://…?sslmode=require

# App callback: let agents reach the app's own API on localhost without opening egress:
LOOMCYCLE_HTTP_HOST_ALLOWLIST=app.internal,api.anthropic.com
LOOMCYCLE_HTTP_PRIVATE_HOST_ALLOWLIST=app.internal   # if it resolves to a private IP
# "Private" includes CGNAT 100.64.0.0/10 — a Tailscale peer needs an entry here;
# a CIDR entry (100.64.0.0/10) admits a whole tailnet.

LOOMCYCLE_CONFIG_STRICT=1                      # a cross-layer config clobber is fatal, not a log line

# Ops:
LOOMCYCLE_METRICS_ENABLED=1
LOOMCYCLE_METRICS_COLLECT_SYSTEM=1             # also sample host CPU/mem (Linux /proc) — catches co-tenant pressure (F19)
LOOMCYCLE_OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4318
```

Routing: this is where `user_tiers:` earns its keep — gate plans by tier
(routing pattern 3/4), and set `fallback_on_error: true` on each overlay that
should cascade (the key has no default). Use `loomcycle pause`/`resume`/`snapshot` for safe
deploys, and `POST /v1/_config/reload` (`?dry_run=1` to preview) to apply a
routing/agent edit without a restart. Bash stays off unless the box is dedicated
and the prompts are trusted (then it's really profile 2).

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
principal inert (a warning).

**Sharp edges:** never leave `LOOMCYCLE_AUTH_TOKEN` empty on a server (dev-mode =
open). Put TLS at the proxy; loomcycle speaks plain HTTP.

---

## 5. Multi-tenant (customers who don't trust each other)

**When:** one instance fronts multiple tenants/customers. Per-principal identity
and tenant isolation become real boundaries (RFC L).

**Trust:** per-principal. The bearer token — not the request body — is the
authority for `(tenant, subject, scopes)`.

Builds on profile 4 and adds the settings below. Use Postgres for a real
multi-tenant service (SQLite stores tokens too, so a single-box trial works;
Postgres is required once you add replicas):

```bash
LOOMCYCLE_STORAGE_BACKEND=postgres
LOOMCYCLE_PG_DSN=postgres://loomcycle:…@db:5432/loomcycle?sslmode=require

LOOMCYCLE_OPERATOR_TOKEN_PEPPER=<openssl rand -hex 32>   # set this — DB-dump defense
LOOMCYCLE_AUDIT_LOG_PATH=/var/log/loomcycle/audit.jsonl   # also REQUIRED for subject erasure (disabled without it)
LOOMCYCLE_AUTH_CACHE_TTL_SECONDS=30                       # 0 for immediate revocation
LOOMCYCLE_OPERATOR_TOKEN_ROTATION_GRACE_SECONDS=86400
LOOMCYCLE_AUTH_VERBOSE=1                                  # server-side reason on 401s (wire stays opaque)
LOOMCYCLE_SECRET_KEY=<openssl rand -base64 32>            # tenant credential store (bring-your-own keys); secret
# LOOMCYCLE_OPERATOR_KEY_RESTRICTION=1                    # tenants without providers:operator-key must use their own key
```

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
| `substrate:user` | **Isolated member.** Its own runs only (implies `runs:create` + `runs:read`), confined to its own user scope: no tenant-shared or global data, no other user's runs, no channel scopes, no def authoring. Over `/v1/_mcp` it may call only `credentialdef` (its own `scope=user` credentials). |
| `substrate:tenant` | **Tenant operator.** Full power *within its own tenant*: runs, channels, authoring every substrate def (agents, skills, teams, hooks, MCP servers, schedules, webhooks…), and a tenant-confined `/v1/_mcp` session. Implies the four `runs:*` / `channel:*` scopes and `providers:operator-key`. No minting, no runtime admin, no cross-tenant access. |
| `substrate:admin` | **Superuser** — every scope, token minting, runtime admin (pause/resume/snapshot/reload), cross-tenant focus. Never implicit; ask for it by name. |
| `providers:operator-key` | Lets a run fall back to the operator's host provider key. Inert unless `LOOMCYCLE_OPERATOR_KEY_RESTRICTION=1`. To make a tenant pay its own way: set the gate, mint its tokens with granular scopes that omit this one (e.g. `runs:create,runs:read`), and give the tenant its own key as a CredentialDef ([credentials.md](credentials.md)); a restricted run with no usable key gets `403 operator_key_restricted`. |

**MCP sessions are held to token scopes (v1.107.0).** A member token driving
`/v1/_mcp` (the plugin's HTTP MCP transport or `loomcycle mcp --upstream`) needs
`runs:create` for the run tools (`spawn_run`, `spawn_runs`, `cancel_run`,
`compact_run`, `retune_run`, `review_run`, `configured_run`,
`interruption_resolve`, `decision`, and `teamdef` `run`/`cancel`), `runs:read`
for the read tools (`get_run`, `list_runs`, `stream_user_run_states`),
`channel:publish` for `publish_channel` / `ack_channel` and `channel:read` for
`subscribe_channel` / `peek_channel`. A token minted with only `runs:read` can
no longer start runs over MCP. Stdio, admin, legacy and `substrate:tenant`
sessions are unchanged.

Routing: use `user_tiers:` privacy boundaries (routing pattern 4) so a tenant's
high tier never escapes the anthropic/openai boundary. **No anthropic-oauth-dev**
(single-operator only). No Bash to untrusted tenants — pair with profile 3 tool
posture.

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
# Every replica: SAME yaml, SAME binary version, SAME auth token.
LOOMCYCLE_STORAGE_BACKEND=postgres
LOOMCYCLE_PG_DSN=postgres://…@db.example.com:5432/loomcycle?sslmode=require
LOOMCYCLE_AUTH_TOKEN=<shared bearer — identical on all replicas>
LOOMCYCLE_PG_MAX_OPEN_CONNS=<MaxConcurrentRuns × 1.5>

# Per replica (UNIQUE):
LOOMCYCLE_REPLICA_ID=replica-a    # replica-b, replica-c, …  (SQLite refuses to boot with this set)

# Recommended (the stale-run sweeper LOOMCYCLE_HEARTBEAT_SWEEPER is ON by default — don't set it to 0):
LOOMCYCLE_METRICS_ENABLED=1
LOOMCYCLE_OTEL_EXPORTER_OTLP_ENDPOINT=<collector>
```

Load balancer: any HTTP LB, round-robin/least-conn, **no sticky sessions**.
Cancel, pause/resume, fairness, run status, steering/retune and session locks
all work cluster-wide via Postgres LISTEN/NOTIFY (a cancel, steer or retune is
routed to the replica that owns the run). Verify with
`GET /healthz` (shows the `replicas[]` membership).

The scheduler may be enabled on every replica (v1.105.0): each due slot is
fired by the one replica that claims it, and `concurrency_policy` /
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
  fairness (`LOOMCYCLE_MAX_CONCURRENT_RUNS_PER_USER`) IS cluster-wide.
- MCP stdio children are per-replica — size memory for `N replicas × M servers`.
- Token budgets, the auth-token cache, per-provider `max_concurrent` gates and
  the `timeout_scaling` speed estimate are per-replica / advisory.
- `anthropic-oauth-dev` and snapshot `--file` restore are per-host — use API
  keys and inline `raw_json` restore in a cluster.
- Postgres is the single source of truth; no split-brain (an isolated replica is
  reaped in ~90s).

---

## Quick decision aid

- Trust every prompt + want host tools → **1** (or **2** to contain it).
- Need Bash but prompts aren't fully trusted → **2** (container is the boundary).
- Prompts untrusted/model-authored → **3** (Bash off, default-deny, code-js).
- One app, real traffic, single instance → **4**.
- Multiple customers, one instance → **5** (Postgres + per-principal tokens).
- Need availability/scale → **6** (Postgres + replicas).
