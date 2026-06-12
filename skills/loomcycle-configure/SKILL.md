---
name: loomcycle-configure
description: Configure a loomcycle runtime — providers, model tiers, user tiers, fallbacks, per-agent sampling and context-compaction, environment variables, deployment profiles (brew/in-system, containerized, true sandbox, server, multi-tenant, cloud), inbound webhooks, and third-party MCP servers. Use when the user wants to set up or tune loomcycle.yaml or its env, pick a deployment posture, wire provider routing/cost-cascades, gate plans, tune decoding (temperature/top_p) or compaction, lock down tool/sandbox/auth, receive webhooks, or connect external MCP tools.
allowed-tools: Read Write Edit Bash(loomcycle validate*) Bash(loomcycle doctor*) Bash(loomcycle init*)
---

# Configure loomcycle

Help an operator write or tune their **`loomcycle.yaml`** (model routing) and
**environment** (posture: sandbox, auth, storage, scale). loomcycle splits its
configuration along one seam — keep it in mind throughout:

- **`loomcycle.yaml` owns routing** — `provider_priority`, `tiers`, `models:`
  aliases, `user_tiers:` overlays, `agents:` overrides. Declarative model policy.
- **Environment owns posture** — tool sandbox roots, the auth token, storage
  backend, multi-tenant pepper, replica id, observability. *How* and *where* it
  runs.

The six deployment profiles the operator may ask about are points on a
**trust × scale** grid; each is a preset of env vars over the *same* yaml.

## Hard safety rules (non-negotiable)

1. **Never read or write the secret env file `.env.local`** (`*_API_KEY`,
   `LOOMCYCLE_AUTH_TOKEN`, the operator-token pepper, trigger-secret *values*).
   It is git-ignored. To set a secret, **print the exact line for the operator to
   add themselves**. Its non-secret companion **`.env.insecure`** (v0.23.3 split,
   #399 — listen addr, sandbox roots, feature flags, allowlist *names*) carries
   no credentials and *is* safe to read and edit; only `.env.local` is off-limits.
   You may also read/write `loomcycle.yaml`. *(On a v0.23.0 binary there is only
   `.env.local` — treat it as secret-bearing.)*
2. **Never put a secret value in `loomcycle.yaml` or any file.** API keys and
   `LOOMCYCLE_AUTH_TOKEN` are referenced by **env-var name** only. The yaml
   never holds a key.
3. **Tools are default-deny — in *two* layers.** (a) The built-ins
   `Read`/`Write`/`Edit`/`Bash`/`HTTP`/`WebFetch` refuse every call until their
   *operator* root/allowlist env var is set. (b) The capability tools
   `Memory`/`Channel`/`AgentDef`/`ScheduleDef`/… additionally refuse until the
   *agent* carries an explicit scope list (`memory_scopes`, `channels:`,
   `agent_def_scopes`, …) — having the tool in `allowed_tools` is necessary but
   **not sufficient**. An agent sees `operator-enabled ∩ allowed_tools ∩
   per-tool-scope`. Recommend the *narrowest* setting that works at every layer;
   never widen "to make it work." *(v0.23.3 (F21/#389), loomcycle emits a boot
   `WARNING:` when a tool is in `allowed_tools` but its gate is unset — `Memory`
   w/o `memory_scopes`, `Channel` w/o `channels`, `Evaluation` w/o
   `evaluation_scopes`, `Interruption` w/o `interruption.enabled` — so this
   silent default-deny is now visible at startup, surfaced in `cfg.Warnings` /
   `loomcycle validate`.)*
4. **Bash is not a sandbox.** It is cwd-restricted + env-scrubbed only. If Bash
   is exposed to untrusted prompts, the runtime **must** be containerized — say
   so explicitly.
5. **Secrets at rest in the DB are redacted (v0.23.4, F32) — but keep them
   off the cmdline anyway.** loomcycle persists agent tool I/O (the full `Bash`
   input + result, etc.) in its store; before v0.23.4 a token an agent inlined
   on a command line (`curl -H "Authorization: token <TOKEN>"`) was written to
   the DB in **cleartext** — and a tracked DB checkpoint could carry it into git.
   **v0.23.4 masks secret-shaped values to `[redacted:<ENV_NAME>]` before
   persisting** (value-based match — it catches the secret even renamed or inlined
   in a URL; the env-var *name* is kept for debuggability). Still advise agents to
   pass secrets **out-of-band** (env / stdin / a credential-helper script), never
   inline — so the secret never even transits a transcript. Redaction is an
   **at-rest** guard only: a `Bash` child still inherits the live `LOOMCYCLE_*`
   process env, so an agent *can* read a secret at runtime (ties back to rule #4).
6. **Validate before declaring done.** Run `loomcycle validate <yaml>` (and
   `loomcycle doctor` if an instance is reachable). Report the real outcome.

## Workflow

1. **Discover.** Ask for (or read) the current `loomcycle.yaml` and which
   providers the operator has keys for. Ask what they're building (personal
   automation? an app backend? a multi-customer SaaS?) — that picks the profile.
2. **Pick the profile.** Use the selector below. When unsure between two,
   pick the *safer* (lower-trust) one and say why.
3. **Author routing.** Write/adjust `loomcycle.yaml` per
   [reference/routing.md](reference/routing.md) — start at library defaults,
   push exceptions up the precedence stack only as needed.
4. **Author posture.** Emit the env lines for the chosen profile from
   [reference/profiles.md](reference/profiles.md); cross-check each var against
   [reference/env-vars.md](reference/env-vars.md). Print env lines for the
   operator to add — never write the env file.
5. **Validate.** `loomcycle validate <yaml>`; if reachable, `loomcycle doctor`
   and `GET /v1/_resolver` to confirm providers probe green.

## Profile selector

| Profile | Use when | Trust | Storage | Detail |
|---|---|---|---|---|
| **1. Brew + in-system agent** | Personal workstation / local automation; you trust every prompt | **Full host** — all tools incl. Bash/Write/Edit on real dirs | SQLite | [profiles.md §1](reference/profiles.md) |
| **2. Containerized (in-container access)** | Same power, contained blast radius; the recommended default for exposing Bash | Container-bounded | SQLite or PG | [profiles.md §2](reference/profiles.md) |
| **3. True sandbox** | Untrusted/model-authored prompts; least privilege | Minimal — Bash off, default-deny roots, tight HTTP allowlist, code-js for any exec | SQLite or PG | [profiles.md §3](reference/profiles.md) |
| **4. Server** | A single backend serving one app's agents | App-scoped tools, no Bash, callback allowlist | SQLite or PG | [profiles.md §4](reference/profiles.md) |
| **5. Multi-tenant** | One instance fronting customers who don't trust each other | Per-principal tokens (RFC L), tenant isolation | **Postgres** | [profiles.md §5](reference/profiles.md) |
| **6. Cloud / multi-replica** | Horizontal HA behind a load balancer | Server/multi-tenant + N replicas | **Postgres** | [profiles.md §6](reference/profiles.md) |

Profiles are cumulative: 5 builds on 4, 6 builds on 5. Read the matching section
of [reference/profiles.md](reference/profiles.md) before emitting config — each
lists the exact env set, the yaml shape, and the sharp edges.

## Reference files (read on demand)

- **[reference/routing.md](reference/routing.md)** — providers + API-key env
  vars, the 4-layer resolver precedence, `tiers` / `user_tiers` / `models:`
  aliases / per-agent overrides, `fallback_on_error`, the four cookbook
  patterns (single/multi provider × single/multi user-tier), and the per-agent
  `sampling:` (temperature/top_p/…) and `compaction:` blocks. Read this for any
  routing, decoding, or compaction question.
- **[reference/profiles.md](reference/profiles.md)** — the six deployment
  profiles in full: trust posture, exact env set, yaml skeleton, and sharp
  edges per profile.
- **[reference/env-vars.md](reference/env-vars.md)** — the grouped environment
  variable catalogue (identity/listen, storage, tool sandboxes, providers,
  memory, scheduler/webhooks/A2A, code-js, multi-tenant, observability,
  cluster). Look up any `LOOMCYCLE_*` here before recommending it.
- **[reference/webhooks.md](reference/webhooks.md)** — inbound webhooks
  (`webhooks:` block — enable, the `enabled`+`delivery` requirement + v0.23.3
  boot-validation, the webhook secret-resolution rules (`LOOMCYCLE_*` auto-allow /
  static-yaml auto-trust / `LOOMCYCLE_WEBHOOKS_ENV_ALLOWLIST`), `auth.kind: none`
  trusted-network ingress, `payload_mapping.goal` (raw-body default), triage
  endpoints, tailnet ingress) **and** third-party MCP servers (`mcp_servers:` —
  stdio/http, `mcp__server__tool`, the `${}` interpolation allowlist). Read this
  for any external-integration wiring.

## Validation cheatsheet

```bash
loomcycle validate loomcycle.yaml   # config-load checks (pin XOR tier, user_tiers default, alias cycles, unknown provider)
loomcycle doctor                    # config + env + providers + storage + listen; exit 0 = green
loomcycle init                      # bootstrap a starter loomcycle.yaml + README in the config dir
```

```bash
# Live resolver matrix — which providers probe green, which models each lists:
curl -s -H "Authorization: Bearer $LOOMCYCLE_AUTH_TOKEN" http://localhost:8787/v1/_resolver | jq .
# Force an immediate re-probe (unstick a transient outage without a restart):
curl -s -X POST -H "Authorization: Bearer $LOOMCYCLE_AUTH_TOKEN" http://localhost:8787/v1/_resolve/probe | jq .
```

Two resolver error classes to teach the operator: `ErrTierUnavailable` (every
candidate stalled/unreachable → retry, 503) vs `ErrTierAgentNotAvailable`
(agent `providers:` ∩ user_tier `provider_priority` is empty → **policy**
refusal, "upgrade your plan", do NOT retry).

This skill configures a **self-hosted** loomcycle the operator runs. It does not
manage loomcycle's lifecycle (start/stop) — that stays the operator's job, and
this plugin never auto-starts the binary.
