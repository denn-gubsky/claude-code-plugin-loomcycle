# Inbound webhooks & third-party MCP servers

Two `loomcycle.yaml` blocks that let an instance talk to the outside world:
`webhooks:` (an external POST starts/wakes an agent) and `mcp_servers:` (agents
call out to third-party tools). They share one seam — **operator-owned secrets,
referenced by env-var name, never written into the yaml** — but they gate those
secrets through **two different mechanisms** (webhook secret-resolution rules
vs. the `${}` interpolation allowlist), which is the #1 thing operators conflate.
Authoritative source: loomcycle `Context.help input-webhooks` +
`docs/CONFIGURATION.md` + `internal/api/webhook/allowlist.go` +
`internal/config/config.go` (verified against loomcycle **v0.23.3** — the
F23/F24/F28 trigger fixes + the F29/F30 dynamic-substrate fixes; **none are in the
v0.23.0 brew binary** — see the version notes below). Field names below match the
config loader.

---

## Inbound webhooks (`webhooks:` block)

An external system (GitHub, GitLab, Stripe, Linear, Gitea, a CI server, n8n)
signs and POSTs an event; loomcycle either **spawns an agent run**
(`delivery: spawn`) or **publishes to a channel** to wake a parked agent
(`delivery: channel`). Verify-before-parse, fail-loud, retry-safe.

### Enable

```bash
LOOMCYCLE_WEBHOOKS_ENABLED=1      # off by default
```

The receiver mounts at **`POST /v1/_webhooks/{name}`**. Boot log confirms it:
`webhooks: enabled (receiver mounted at POST /v1/_webhooks/{name}, env_allowlist=N names)`
— **watch that `N`**; `env_allowlist=0` means no secret can resolve (see below).
The receiver POST is **not** bearer-gated — the per-def signature *is* the auth.
Every other `/v1/*` route stays bearer-gated.

### A static def needs `enabled` **and** `delivery`

```yaml
webhooks:
  pr-opened:                       # → POST /v1/_webhooks/pr-opened
    enabled: true                  # REQUIRED — absent/false ⇒ def is inactive ⇒ opaque 404
    delivery: spawn                # REQUIRED — spawn | channel
    agent: code-reviewer           # spawn target
    auth:
      kind: hmac                   # hmac (default) | bearer
      header: "X-Hub-Signature-256"    # GitHub/Gitea shape; default is X-Loomcycle-Signature (Stripe)
      signing_secret_env: "LOOMCYCLE_GITEA_WEBHOOK_SECRET"   # env-var NAME, not the value
      delivery_id_header: "X-Gitea-Delivery"                 # for replay/idempotency dedup
    payload_mapping:
      goal: "$"                    # see "payload delivery" below
    rate_limit: { requests_per_minute: 60, burst: 10 }
```

A def that is missing `enabled: true` is **silently inactive** → the URL returns
an opaque `404 unknown_webhook` (no enumeration oracle). Static yaml defs are read
directly; they do **not** bootstrap rows into the `webhook_defs` DB table, so
don't go looking for them there.

> **Boot-time validation (v0.23.3, F24).** A static `webhooks:` entry whose
> delivery target can *never* fire is now a **hard `loomcycle validate` / startup
> error** (not a silent request-time failure): `delivery: spawn` requires `agent`
> and forbids `channel`; `delivery: channel` requires `channel` and forbids
> `agent`; an unknown `delivery` or `auth.kind` is rejected. Secret
> *resolvability* stays a **non-fatal boot `WARNING:`** (one line per static
> webhook whose secret won't resolve). On the **v0.23.0 brew binary** these
> mistakes surface only at request time (404/500). *(A missing `enabled: true` is
> still just inactive, not an error.)*

> **The `agent:` target may be a runtime-authored (AgentDef-substrate) agent
> (v0.23.3, F30/#403).** A `delivery: spawn` webhook can now resolve an agent
> created at runtime via `POST /v1/_agentdef` / the `agentdef` tool, not just a
> static `agents:` yaml entry. On v0.23.0–v0.23.2-era `main` a delivery to a
> dynamic agent failed `rejected_spawn_setup: unknown agent` because the spawn
> resolver consulted yaml only; v0.23.3 stamps the def's `tenant_id` from the run
> identity so the spawn resolves it under the right tenant. So a fully-dynamic
> "webhook → spawn a substrate agent" loop now works end-to-end. *(This pairs
> with F33 below if that agent's only capability is a dynamic MCP tool.)*

### The signing secret — how a name is authorized (the #1 setup snag)

`signing_secret_env` (hmac) / `bearer_token_env` (bearer) name an env var the
receiver resolves **at verify time** — but only if that name is *authorized*.
On loomcycle **v0.23.3** (F23/#385; **NOT in the v0.23.0 brew binary**) the
receiver authorizes a name when **any one** of three rules holds (verified
against `internal/api/webhook/allowlist.go` + `config.go`):

1. **`LOOMCYCLE_*`-prefixed** (or a known third-party name — `GITHUB_TOKEN` etc.)
   — auto-allowed **for the verification secret only** (`signing_secret_env` /
   `bearer_token_env`, consumed by the receiver, never reaches the agent). This
   is why `signing_secret_env: "LOOMCYCLE_GITEA_WEBHOOK_SECRET"` **Just Works
   with zero allowlist config.**
2. **Declared by a static (yaml) webhook** — a static def's own secret +
   `user_credentials_from_env` names are auto-trusted (the operator wrote the
   yaml). So a static webhook resolves *all* its env names with no allowlist.
3. **Explicitly listed** in **`LOOMCYCLE_WEBHOOKS_ENV_ALLOWLIST`** (the
   correctly-named knob) or the scheduler's shared
   **`LOOMCYCLE_SCHEDULER_ENV_ALLOWLIST`** — comma-separated, merged as a union.

```bash
# Only needed for a NON-LOOMCYCLE_-named secret, or an agent-reachable credential
# on a RUNTIME-authored (webhookdef-tool) def — both fall outside rules 1 & 2:
LOOMCYCLE_WEBHOOKS_ENV_ALLOWLIST=GITEA_WEBHOOK_SECRET,STRIPE_WH_SECRET
```

Sharp edges that remain:

- **Agent-reachable creds on a *runtime*-authored def are still strictly gated.**
  Rule 1's namespace auto-allow covers only the verification secret. A
  `user_credentials_from_env` value on a def created via the `webhookdef` tool
  (not yaml) must be named in `LOOMCYCLE_WEBHOOKS_ENV_ALLOWLIST` explicitly — so
  a less-trusted authoring path can't inject an arbitrary env var into a run.
- A name authorized by none of the three rules → `503 secret_unresolvable`
  (names the env var, never its value). The **boot log now names both allowlist
  vars, the live seeded count, and prints a `WARNING:` line per static webhook
  whose secret won't resolve** — read it; it tells you exactly which knob to set.
- This secret-resolution allowlist is conceptually distinct from the `${}`
  yaml-interpolation allowlist (below), but both honor the `LOOMCYCLE_*`
  namespace, so a `LOOMCYCLE_`-named secret sails through both.

> **Version note.** The three-rule model + the boot warnings shipped in the
> **v0.23.3** tag (F23, PR #385) — loomcycle went **v0.23.0 → v0.23.3 directly
> (no `v0.23.1`/`v0.23.2` tag)**. The **v0.23.0 brew binary does NOT have them**:
> it reads *only* `LOOMCYCLE_SCHEDULER_ENV_ALLOWLIST`, does **not** auto-trust
> static secrets, and a bare `env_allowlist=0 names` is the only clue — the
> original F23 trap. On a v0.23.0 binary, fall back to listing the secret in
> `LOOMCYCLE_SCHEDULER_ENV_ALLOWLIST`.

### Trusted-network ingress — `auth.kind: none` (v0.23.3)

When the receiver is reachable **only** over an already-authenticated transport
(a WireGuard/tailnet hop, an mTLS mesh) HMAC is redundant. Set `auth.kind: none`
to skip signature verification:

```yaml
  internal-pr:
    enabled: true
    delivery: spawn
    agent: code-reviewer
    auth: { kind: none }           # no signing secret
    payload_mapping: { goal: "$" }
```

It is **refused by default** (`503 unauthenticated_mode_disabled`) — the
receiver never silently accepts unsigned external POSTs. Opt in explicitly:

```bash
LOOMCYCLE_WEBHOOKS_ALLOW_UNAUTHENTICATED=1
```

Only do this when the listen surface is genuinely private (e.g. bound to a
tailnet IP behind WireGuard). For a publicly-reachable receiver, keep HMAC.

### Payload delivery — the spawned agent's prompt is the `goal`

The receiver projects the verified body through `payload_mapping` (a strict
JSONPath subset: `$.a.b`, `$.a[0]` — no wildcards/filters/recursion) and the
spawned run's **prompt is the `goal`**, fenced in `<untrusted>` tags (a webhook
body is attacker-influenceable, external input).

**The `goal` default changed in v0.23.3 (F28).** What the agent receives:

- **No `goal` key in `payload_mapping`** (or no `payload_mapping` at all) ⇒ the
  agent receives the **entire raw signed body** as its task. On the **v0.23.0
  brew binary** this case delivered an *empty* prompt and the run silently
  no-op'd — the classic "webhook fired but the agent did nothing" trap.
  Post-v0.23.0 the whole event is handed over, matching the GitHub-pattern
  expectation that "the agent receives the event."
- **A `goal` key IS mapped** ⇒ that projected value is used **verbatim**, even if
  it resolves empty (the operator's explicit choice of which field is the task is
  respected).

So mapping the root is now optional, but still the clearest way to be explicit
(and the only portable choice if you must also support a v0.23.0 binary):

```yaml
    payload_mapping:
      goal: "$"                    # "$" root ⇒ the entire signed body as JSON (explicit)
```

Other mappable targets: `user_id`, `user_tier`, `run_metadata.*`, and
`user_credentials.<name>` (per-event MCP bearer; spawn only). An absent path
resolves to empty + a trace note — never a hard failure.

> **Security:** `user_id`/`user_tier` MAY come from the signed body (only as
> trustworthy as the per-def secret), but `tenant_id` comes from the **static
> def only** — there is deliberately no `payload_mapping` path for it, so an
> attacker-influenceable body can't steer the run into another tenant's
> agents/skills/memory.

### Per-tenant route (v0.24.0, RFC N wire change)

v0.24.0 extended the RFC N tenant axis to webhooks (and all 8 def families).
A webhook authored under a **non-empty tenant** is reached at
**`POST /v1/_webhooks/{tenant}/{name}`** — the tenant is path-authoritative,
resolved from the route, never the body. The bare-root
**`POST /v1/_webhooks/{name}`** still resolves under the shared `""` tenant, so
existing single-tenant webhooks are unchanged. The admin `/test` dry-run
resolves under the caller's principal tenant.

> **Action for multi-tenant operators:** if you author a webhook under a tenant,
> register its delivery URL with the `/{tenant}/` prefix at the sender (GitHub,
> Stripe, …) — the bare `/{name}` URL will 404 (or resolve the wrong, shared-`""`
> def). Single-tenant / open-mode deployments need no change.

### Per-run MCP credentials for the spawned run

A spawn run wires MCP-tool bearers exactly like a scheduled run:

```yaml
    user_credentials_from_env:     # operator-owned, env-allowlist-gated (gate #1)
      gitea: "LOOMCYCLE_GITEA_TOKEN"          # → ${run.credentials.gitea}
    payload_mapping:
      user_credentials.gitea: "$.installation.token"   # per-event token; payload overlays + wins
```

These land on the run's `UserCredentials` and substitute into
`${run.credentials.<name>}` inside `mcp_servers.*.headers`. **Channel-delivery
webhooks carry no credentials** (no run identity to attach them to) — any
`user_credentials*` on a `delivery: channel` def is refused at create time.

### Responses & triage

All outcomes are loud and distinct: `202` (async accept, default; returns
`{run_id, webhook_name, delivery_id}`) · `200` (sync, if `sync_response.enabled`,
or an idempotent replay `{deduped:true}`) · `401` sig/auth (no body detail — no
oracle) · `404` unknown/disabled · `429` rate-limited (`Retry-After`) · `503
secret_unresolvable` / runtime-unavailable · `400` malformed body/mapping.

Two bearer-authed debug endpoints (the receiver POST itself is unauthed):

```bash
GET  /v1/_webhooks/{name}/recent-deliveries?limit=50   # delivery_id, verdict, received_at, run_id
POST /v1/_webhooks/{name}/test                          # dry-run: {would_accept, verdict, run_input_preview} — no run
```

Use `/test` to confirm HMAC + payload→goal + agent spawn **before** wiring the
real sender.

### Ingress for an external sender (no relay needed)

The hard part of GitHub-style webhooks is public ingress. If the sender is on a
**tailnet**, skip smee.io/Funnel entirely: bind `LOOMCYCLE_LISTEN_ADDR` to the
node's tailscale IP (e.g. `100.x.y.z:8788`) so the sender on another tailnet
host POSTs directly — WireGuard encrypts the hop, the per-def HMAC authenticates
it, and the other `/v1/*` routes stay bearer-gated. (Verified end-to-end with a
self-hosted Gitea driving the receiver across the tailnet.)

---

## Third-party MCP servers (`mcp_servers:` block)

Agents call out to external tools (a Gitea/GitHub MCP, a Slack bot, an n8n
workflow, a Telegram sender). Each declared server's tools register as
**`mcp__<server>__<tool>`** after `tools/list` discovery; an agent opts in by
globbing `mcp__<server>__*` (or naming individual tools) in its `allowed_tools`.

```yaml
mcp_servers:
  gitea:                           # stdio: loomcycle spawns the subprocess
    transport: stdio
    command: /abs/path/work/bin/gitea-mcp
    args: ["-t", "stdio"]
    env:
      GITEA_HOST: "https://gitea.example.ts.net:30008"
      GITEA_ACCESS_TOKEN: "${LOOMCYCLE_GITEA_TOKEN}"   # see allowlist note below
    pool_size: 2
    allowed_tools: [create_pull_request, pull_request_read]   # operator-level filter (optional)

  jobs:                            # http: dialed per tool-call (own process/host)
    transport: http
    url: http://localhost:3000/api/mcp
    headers:
      Authorization: "Bearer ${LOOMCYCLE_JOBS_API_TOKEN}"
```

- **Operator-level `allowed_tools`** on a server narrows which of its tools are
  registered **at all**, before any agent's own `allowed_tools` is consulted —
  two filters in series.
- **http**/**streamable-http** servers are dialed per-call and may *also* be
  registered at runtime via the MCPServerDef substrate
  (`POST /v1/_mcpserverdef` / the `mcpserverdef` tool, no restart) — mediated by
  the outbound host allowlist. **stdio** servers are spawned at startup; in yaml
  they're operator-trusted and need no flag. Runtime-registering a **stdio**
  server is **gated off by default** (`LOOMCYCLE_MCP_ALLOW_DYNAMIC_STDIO=1`, F31)
  because it runs an arbitrary local command — **v0.23.3** lifted the old
  "stdio can't be dynamic" hard rule, but kept it behind that flag.
- The **server process holds the token** (in its own env); the agent's Bash
  never sees it.

> **A dynamic-MCP-only agent now actually calls its tools (v0.23.5, F33/#409).**
> An agent whose `allowed_tools` is **only** a runtime-MCP wildcard (e.g.
> `["mcp__telegram-dyn__*"]`, no native tool) — the natural "single-purpose
> notifier" shape — used to **silently no-op**: dynamic MCP tools were a
> first-call *fallback* and were never **advertised** to the model, so with zero
> advertised tools the model emitted the call as inert `<function_calls>` **text**
> and the run reported a plausible "✅ done" having sent nothing. **v0.23.5 loads
> + advertises dynamic MCP tools at run START**, so the model emits a real
> `tool_call` the first time with no native-tool crutch. *On v0.23.3/v0.23.4*, the
> workaround is to also give such an agent **one native tool** (e.g. `Context`),
> which puts it in tool-calling mode so the lazy MCP call then dispatches.

### Secret injection — gate #2: the `${}` interpolation allowlist

`${VAR}` in a yaml string expands **only** for an allowlisted name. Everything
else passes through **verbatim** — the MCP server then receives the literal
string `${GITEA_ACCESS_TOKEN}` and `401`s on every call. The allowlist (from
`config.go::expandEnvAllowed`) is:

- **any `LOOMCYCLE_`-prefixed name** (the project's own namespace), plus
- the hardcoded third-party set: **`BRAVE_API_KEY`, `GITHUB_TOKEN`,
  `SLACK_BOT_TOKEN`, `PG_DSN`, `REDIS_URL`** — and nothing else.

So `${GITEA_ACCESS_TOKEN}`, `${TELEGRAM_BOT_TOKEN}`, `${OPENAI_API_KEY}` do
**not** expand. The fix is to name your secret `LOOMCYCLE_*` in `.env.local` and
map it on the right-hand side, where the server expects the un-prefixed name on
the left:

```yaml
    env:
      GITEA_ACCESS_TOKEN: "${LOOMCYCLE_GITEA_TOKEN}"     # LHS = what the server reads; RHS = what loomcycle expands
      TELEGRAM_BOT_TOKEN: "${LOOMCYCLE_TELEGRAM_BOT_TOKEN}"
```

> **Provider API keys are intentionally NOT interpolated.** `ANTHROPIC_API_KEY`
> / `OPENAI_API_KEY` reach providers through the `Env` struct, not the yaml
> `${}` path — so you cannot `${ANTHROPIC_API_KEY}` a provider key into an MCP
> header (a deliberate exfiltration guard against a malicious shared yaml).

### Per-run bearers in MCP headers

`${run.user_bearer}` and `${run.credentials.<name>}` are **not** expanded at
yaml-load (the `.` can't match the `${}` name regex, so they survive verbatim)
— they're substituted at MCP **outbound-request** time from the run's fields
(set by `POST /v1/runs` or, for a webhook spawn, by `user_credentials_from_env`
/ `payload_mapping`). Use the `:-` fallback for runs without one:

```yaml
    headers:
      Authorization: "Bearer ${run.credentials.gitea:-${LOOMCYCLE_GITEA_TOKEN}}"
```

---

## Quick gotcha table

| Symptom | Cause | Fix |
|---|---|---|
| webhook URL → `404 unknown_webhook` | def missing `enabled: true` (inactive) | add `enabled: true` to the `webhooks:` entry |
| `loomcycle validate` / startup **fails** on a `webhooks:` entry | v0.23.3 (F24) delivery-target mismatch: `spawn` w/o `agent`, `channel` w/o `channel`, or unknown `delivery`/`auth.kind` | fix the entry per the boot error |
| webhook → `503 secret_unresolvable` (v0.23.3: see the boot `WARNING:` line) | secret name authorized by none of the 3 rules | name it `LOOMCYCLE_*`, declare it in a static yaml def, or add it to `LOOMCYCLE_WEBHOOKS_ENV_ALLOWLIST` |
| webhook → `503 unauthenticated_mode_disabled` | `auth.kind: none` without the opt-in | set `LOOMCYCLE_WEBHOOKS_ALLOW_UNAUTHENTICATED=1` (only on a private listen surface) |
| spawned agent gets an **empty** task | **v0.23.0 binary** with no `payload_mapping.goal` (v0.23.3 F28 defaults to the raw body) | upgrade, or add `payload_mapping: { goal: "$" }` |
| MCP server `401`s; header shows literal `${FOO}` | non-allowlisted `${}` name | rename secret to `LOOMCYCLE_*` and map it: `FOO: "${LOOMCYCLE_FOO}"` |
| webhook → `rejected_spawn_setup: unknown agent` (target is an AgentDef/runtime agent) | pre-v0.23.3 webhook-spawn resolver read yaml agents only (F30) | upgrade to **v0.23.3+**, or declare the target as a static `agents:` yaml entry |
| "notifier" agent reports success but **nothing is sent**; its `allowed_tools` is only `mcp__server__*` | pre-v0.23.5 didn't advertise dynamic-MCP tools, so the call was emitted as text, never dispatched (F33) | upgrade to **v0.23.5+**, or give the agent one native tool (e.g. `Context`) to enter tool-calling mode |
| external sender can't reach the receiver | `LISTEN_ADDR=127.0.0.1` | bind a reachable IP (tailnet IP for a tailnet sender; no relay needed) |
