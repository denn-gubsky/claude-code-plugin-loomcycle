# Deployment profiles

Six postures on a **trust × scale** grid. Each is a preset of env vars (the
posture axis) over the same `loomcycle.yaml` routing. Profiles are cumulative —
5 layers on 4, 6 layers on 5. Pick the *lowest-trust* one that does the job.

Cross-check every var against [env-vars.md](env-vars.md); routing yaml lives in
[routing.md](routing.md). **Print env lines for the operator — never write their
env file.** Never put a secret value in any file.

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
loomcycle doctor    # verify
```

Env (operator adds to `.env.local`, sourced by `loomcycle.sh`):

```bash
LOOMCYCLE_LISTEN_ADDR=127.0.0.1:8787          # local only
LOOMCYCLE_AUTH_TOKEN=<openssl rand -hex 32>   # set even locally; avoids the dev-mode warning
ANTHROPIC_API_KEY=<from your secret store>    # at least one provider key

# Full tool access on real working dirs:
LOOMCYCLE_READ_ROOT=/Users/you/work
LOOMCYCLE_WRITE_ROOT=/Users/you/work/scratch
LOOMCYCLE_BASH_ENABLED=1
LOOMCYCLE_BASH_CWD=/Users/you/work/scratch
LOOMCYCLE_HTTP_HOST_ALLOWLIST=api.anthropic.com,api.github.com
BRAVE_API_KEY=<optional, for WebSearch>
LOOMCYCLE_MCP_ALLOW_PRIVILEGED_TOOLS=1        # only because the stdio MCP client is you
```

Storage: SQLite (`LOOMCYCLE_DATA_DIR=./data`, the default). Agents may list
`allowed_tools` including `Bash`/`Write`/`Edit`/`Read`/`Grep`/`Glob`.

**Sharp edges:** Bash is cwd-restricted but *not isolated* — anything your user
can do, a prompt can do. Fine here because you trust the prompts. The moment
prompts come from elsewhere, move to profile 2 or 3.

---

## 2. Containerized with in-container resource access (safer default)

**When:** you want the same capabilities (incl. Bash) but a real blast-radius
boundary. **This is the recommended way to expose Bash.** The container *is* the
sandbox.

**Trust:** container-bounded. A prompt can act inside the container only;
distroless nonroot (uid 65532), no host shell.

```bash
docker pull denngubsky/loomcycle:latest        # NOTE: Hub strips the hyphen
mkdir -p ./config ./data && sudo chown -R 65532:65532 ./data
docker run --rm -v $(pwd)/config:/home/nonroot/.config/loomcycle \
  denngubsky/loomcycle:latest init --no-interactive
docker run -d --name loomcycle \
  -p 127.0.0.1:8787:8787 \
  -v $(pwd)/config:/home/nonroot/.config/loomcycle:ro \
  -v $(pwd)/data:/home/nonroot/.local/share/loomcycle \
  -e LOOMCYCLE_AUTH_TOKEN=$(openssl rand -hex 32) \
  -e ANTHROPIC_API_KEY=your-key \
  -e LOOMCYCLE_LISTEN_ADDR=0.0.0.0:8787 \
  -e LOOMCYCLE_READ_ROOT=/home/nonroot/.local/share/loomcycle/files \
  -e LOOMCYCLE_WRITE_ROOT=/home/nonroot/.local/share/loomcycle/scratch \
  -e LOOMCYCLE_BASH_ENABLED=1 \
  -e LOOMCYCLE_BASH_CWD=/home/nonroot/.local/share/loomcycle/scratch \
  -e LOOMCYCLE_HTTP_HOST_ALLOWLIST=api.anthropic.com \
  denngubsky/loomcycle:latest
```

Key differences from profile 1: `LISTEN_ADDR=0.0.0.0:8787` *inside* the
container (port-mapped to `127.0.0.1` on the host); tool roots point at
**in-container** mounted dirs, not host paths; config mounted read-only. SQLite
or Postgres. No host filesystem is reachable.

**Sharp edges:** distroless has no shell — debug via `docker logs`, not
`docker exec sh`. Writable mount must be owned by uid 65532 on Linux.

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
# (do NOT set LOOMCYCLE_MCP_ALLOW_PRIVILEGED_TOOLS).
# READ/WRITE roots unset → Read/Write/Edit refuse every call.

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
LOOMCYCLE_CODE_AGENTS_RUN_TIMEOUT_SECONDS=60
```

Agent `allowed_tools` should be the minimal set (often just `Read` on a fixed
root, or specific `mcp__*` tools). Run inside the profile-2 container, add
seccomp/read-only-rootfs/`--cap-drop=ALL` at the container layer, and keep the
listener bound to loopback behind your app.

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

# Ops:
LOOMCYCLE_METRICS_ENABLED=1
LOOMCYCLE_OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4318
```

Routing: this is where `user_tiers:` earns its keep — gate plans by tier
(routing pattern 3/4). Use `loomcycle pause`/`resume`/`snapshot` for safe
deploys. Bash stays off unless the box is dedicated and the prompts are trusted
(then it's really profile 2).

**Sharp edges:** never leave `LOOMCYCLE_AUTH_TOKEN` empty on a server (dev-mode =
open). Put TLS at the proxy; loomcycle speaks plain HTTP.

---

## 5. Multi-tenant (customers who don't trust each other)

**When:** one instance fronts multiple tenants/customers. Per-principal identity
and tenant isolation become real boundaries (RFC L).

**Trust:** per-principal. The bearer token — not the request body — is the
authority for `(tenant, subject, scopes)`.

Builds on profile 4, **requires Postgres**, and adds:

```bash
LOOMCYCLE_STORAGE_BACKEND=postgres
LOOMCYCLE_PG_DSN=postgres://loomcycle:…@db:5432/loomcycle?sslmode=require

LOOMCYCLE_OPERATOR_TOKEN_PEPPER=<openssl rand -hex 32>   # set this — DB-dump defense
LOOMCYCLE_AUDIT_LOG_PATH=/var/log/loomcycle/audit.jsonl
LOOMCYCLE_AUTH_CACHE_TTL_SECONDS=30                       # 0 for immediate revocation
LOOMCYCLE_OPERATOR_TOKEN_ROTATION_GRACE_SECONDS=86400
LOOMCYCLE_AUTH_VERBOSE=1                                  # server-side reason on 401s (wire stays opaque)
```

Mint per-tenant tokens (admin bearer required); the token's `subject` becomes
the run's `user_id` (fairness key) and its `tenant_id` is the memory-isolation
boundary:

```bash
loomcycle operator-token create --tenant acme --subject alice --scopes runs:create,runs:read
loomcycle operator-token rotate --name alice    # zero-downtime, grace window
loomcycle operator-token retire --name alice    # immediate revoke
# Migrate an existing shared secret in place (keeps working as an admin token):
loomcycle operator-token create --tenant default --subject ops --copy-from-env
```

Routing: use `user_tiers:` privacy boundaries (routing pattern 4) so a tenant's
high tier never escapes the anthropic/openai boundary. **No anthropic-oauth-dev**
(single-operator only). No Bash to untrusted tenants — pair with profile 3 tool
posture.

**Sharp edges:** creating the *first* admin `OperatorTokenDef` disables the
legacy `LOOMCYCLE_AUTH_TOKEN` for inbound HTTP (the no-lockout gate). Update any
HTTP client (incl. this plugin's auth_token + the auto-snapshot hook) to an
`lct_…` admin bearer and restart. Routes enforce a scope from a closed catalog;
an under-scoped token gets `403 + WWW-Authenticate: Bearer scope="…"`. This is
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

# Recommended:
LOOMCYCLE_HEARTBEAT_SWEEPER=1
LOOMCYCLE_METRICS_ENABLED=1
LOOMCYCLE_OTEL_EXPORTER_OTLP_ENDPOINT=<collector>
```

Load balancer: any HTTP LB, round-robin/least-conn, **no sticky sessions**.
Cancel, pause/resume, fairness, run status, hooks, session locks all work
cluster-wide via Postgres LISTEN/NOTIFY. Verify with
`GET /healthz` (shows the `replicas[]` membership).

Rolling upgrade: `POST /v1/_pause` → drain → snapshot → upgrade replicas one at
a time → `POST /v1/_resume`. Crashed replicas auto-recover within ~90s (runs
marked failed, quota slots reclaimed) — no manual DB cleanup.

**Sharp edges:**
- Global concurrency cap (yaml `concurrency.max_concurrent_runs`) is
  **per-replica** — e.g. a cap of 10 × 2 replicas = 20 cluster-wide; per-user
  fairness (`LOOMCYCLE_MAX_CONCURRENT_RUNS_PER_USER`) IS cluster-wide.
- MCP stdio children are per-replica — size memory for `N replicas × M servers`.
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
