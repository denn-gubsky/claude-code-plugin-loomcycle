# Inbound webhooks & third-party MCP servers

Two `loomcycle.yaml` blocks that let an instance talk to the outside world:
`webhooks:` (an external POST starts/wakes an agent) and `mcp_servers:` (agents
call out to third-party tools). They share one seam — **operator-owned secrets,
referenced by env-var name, never written into the yaml** — but they gate those
secrets through **two different allowlists**, which is the #1 thing operators
trip on. Authoritative source: loomcycle `Context.help input-webhooks` +
`docs/CONFIGURATION.md` + `internal/config/config.go`. Field names below match
the config loader.

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

A def that is missing `enabled: true` or a valid `delivery:` is **silently
inactive** → the URL returns an opaque `404 unknown_webhook` (no enumeration
oracle). Static yaml defs are read directly; they do **not** bootstrap rows into
the `webhook_defs` DB table, so don't go looking for them there.

### The signing secret — gate #1: `LOOMCYCLE_SCHEDULER_ENV_ALLOWLIST`

`signing_secret_env` (hmac) / `bearer_token_env` (bearer) name an env var the
receiver resolves **at verify time** — but only if that name is on the
**scheduler env allowlist**:

```bash
LOOMCYCLE_SCHEDULER_ENV_ALLOWLIST=LOOMCYCLE_GITEA_WEBHOOK_SECRET,LOOMCYCLE_STRIPE_WEBHOOK_SECRET
```

This one env var is the **shared trigger-credential gate** for the scheduler,
the webhook receiver, *and* the mem9 memory backend (`config.go` populates a
single `SchedulerEnvAllowlist`; `main.go` hands the same set to the webhook
receiver). Sharp edges, all verified against source:

- It is the **only** knob. There is **no** yaml `env_allowlist:` key, and **no**
  hardcoded "recognized webhook-secret names" bypass — a name like
  `LOOMCYCLE_GITHUB_WEBHOOK_SECRET` still must appear in this list. A secret not
  on the list is **never read** → `503 secret_unresolvable` (the response names
  the env var, never its value) and the boot log shows `env_allowlist=0 names`.
- The intuitively-named `LOOMCYCLE_ENV_ALLOWLIST` / `LOOMCYCLE_WEBHOOKS_ENV_ALLOWLIST`
  are read **nowhere** — the scheduler-named var is the real one. (A CLI hint
  pointing at the former is stale.) **Don't reach for the obvious name.**
- This gate (secret-name → value resolution) is **separate** from the `${}`
  interpolation allowlist below. A `LOOMCYCLE_`-prefixed name passes `${}`
  expansion automatically, but that does **not** make it resolvable as a webhook
  secret — it must *also* be in `LOOMCYCLE_SCHEDULER_ENV_ALLOWLIST`. Two
  allowlists, two purposes; do not conflate them.

### Payload delivery — the spawned agent's prompt is the mapped `goal`

The receiver projects the verified body through `payload_mapping` (a strict
JSONPath subset: `$.a.b`, `$.a[0]` — no wildcards/filters/recursion) and the
spawned run's **prompt is the mapped `goal`**, fenced in `<untrusted>` tags
(a webhook body is attacker-influenceable, external input).

**With no `payload_mapping`, `goal` is empty and the agent receives nothing.**
This is silent — the run spawns but has no task. To hand the agent the whole
signed event to parse, map the root:

```yaml
    payload_mapping:
      goal: "$"                    # "$" root ⇒ the entire signed body as JSON
```

Other mappable targets: `user_id`, `user_tier`, `run_metadata.*`, and
`user_credentials.<name>` (per-event MCP bearer; spawn only). An absent path
resolves to empty + a trace note — never a hard failure.

> **Security:** `user_id`/`user_tier` MAY come from the signed body (only as
> trustworthy as the per-def secret), but `tenant_id` comes from the **static
> def only** — there is deliberately no `payload_mapping` path for it, so an
> attacker-influenceable body can't steer the run into another tenant's
> agents/skills/memory.

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
- **stdio** servers are spawned at startup and yaml-only. **http** servers are
  dialed per-call and may *also* be registered at runtime via the MCPServerDef
  substrate (`POST /v1/_mcpserverdef`, no restart) — stdio cannot.
- The **server process holds the token** (in its own env); the agent's Bash
  never sees it.

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
| webhook URL → `404 unknown_webhook` | def missing `enabled: true` or `delivery:` | add both to the `webhooks:` entry |
| webhook → `503 secret_unresolvable`, boot log `env_allowlist=0` | secret env not allowlisted | add the name to `LOOMCYCLE_SCHEDULER_ENV_ALLOWLIST` (NOT `LOOMCYCLE_ENV_ALLOWLIST`) |
| spawned agent gets an **empty** task | no `payload_mapping.goal` | add `payload_mapping: { goal: "$" }` (or a specific path) |
| MCP server `401`s; header shows literal `${FOO}` | non-allowlisted `${}` name | rename secret to `LOOMCYCLE_*` and map it: `FOO: "${LOOMCYCLE_FOO}"` |
| external sender can't reach the receiver | `LISTEN_ADDR=127.0.0.1` | bind a reachable IP (tailnet IP for a tailnet sender; no relay needed) |
