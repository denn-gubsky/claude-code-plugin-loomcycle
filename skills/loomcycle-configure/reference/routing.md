# Routing reference — providers, tiers, user_tiers, fallbacks

This is the **`loomcycle.yaml` model-routing axis**. Authoritative source:
loomcycle `docs/CONFIGURATION.md` + `docs/PROVIDERS.md`. Field names below match
loomcycle's config loader — do not invent fields.

## Providers + their auth env vars

| Provider id | Auth env var | Endpoint / override | Notes |
|---|---|---|---|
| `anthropic` | `ANTHROPIC_API_KEY` | api.anthropic.com | Production default. |
| `openai` | `OPENAI_API_KEY` | api.openai.com | Production. |
| `deepseek` | `DEEPSEEK_API_KEY` | api.deepseek.com | Production; cost floor. |
| `gemini` | `GEMINI_API_KEY` | generativelanguage.googleapis.com | Production. |
| `ollama` | `OLLAMA_API_KEY` (Bearer) | `OLLAMA_CLOUD_BASE_URL` (default ollama.com) | Hosted Ollama (subscription billing). |
| `ollama-local` | none (local trust) | `OLLAMA_BASE_URL` (default `http://localhost:11434`; `disabled` to opt out) | Local-network Ollama. |
| `anthropic-oauth-dev` | OAuth (`loomcycle anthropic login`) | api.anthropic.com | **Research/dev ONLY**, opt-in via `LOOMCYCLE_ANTHROPIC_OAUTH_DEV_ENABLED=1`. Single-machine. **Never** for production, multi-tenant, multi-replica, or customer-facing. Reverse-engineered subscription billing; no SLA. Verify a live token server-side with `loomcycle anthropic status --probe` (post-v0.23.0, F6 — plain `status` reports only local file metadata); concurrent loomcycle processes share the token file safely via a cross-process refresh lock (F7). |

A provider with no API key set is marked **excluded** (treated like unreachable)
and skipped by the resolver. Only set keys for providers you'll use.

> **Provider keys are referenced by env-var name, never `${}`-interpolated.**
> A provider key reaches its driver through loomcycle's `Env` struct — there is
> no `api_key: ${ANTHROPIC_API_KEY}` field, and the yaml `${}` expander
> deliberately **excludes** provider keys (so a malicious shared yaml can't
> `${ANTHROPIC_API_KEY}` a secret into an outbound MCP header). `${}`
> interpolation is for `mcp_servers:` (and other outbound string fields) only,
> and is itself allowlisted — any `LOOMCYCLE_`-prefixed name plus the hardcoded
> set `BRAVE_API_KEY` / `GITHUB_TOKEN` / `SLACK_BOT_TOKEN` / `PG_DSN` /
> `REDIS_URL`; every other name passes through verbatim. See
> [webhooks.md](webhooks.md) for the MCP-server secret-injection pattern.

## The 4-layer resolver precedence (highest → lowest)

The resolver picks `(provider, model)` per run. First layer with something to
say wins:

1. **Explicit pin** — agent `provider:` + `model:` (both, or via a `models:`
   alias). Hard-pin to exactly one pair.
2. **Per-agent override** — agent `providers:` (replaces walk order) and/or
   `models[tier]:` (replaces candidate list) for that agent only.
3. **user_tier overlay** — `user_tiers.<tier>.provider_priority` +
   `.tiers[agent.tier]`. Per-user-class policy (plan gating, privacy).
4. **Library defaults** — top-level `provider_priority:` + `tiers:`. The
   backstop every config sets.

`pin` and `tier` are **mutually exclusive** on one agent — setting both fails at
config-load (`cannot set both explicit provider/model pin and tier`).

When an agent's `providers:` AND a user_tier's `provider_priority` are both set,
the resolver uses their **intersection in agent order**. Empty intersection →
`ErrTierAgentNotAvailable` (a *policy* refusal: "this user's plan doesn't cover
this agent"). This is the load-bearing gate: "agent may use X" AND "user may use
X" are enforced together.

## Pattern 1 — single provider, tiers + aliases

```yaml
provider_priority: [anthropic]

tiers:
  low:    [{ provider: anthropic, model: claude-haiku-4-5 }]
  middle: [{ provider: anthropic, model: claude-sonnet-4-6 }]
  high:   [{ provider: anthropic, model: claude-opus-4-7 }]

models:                       # short aliases agents can write as `model: sonnet`
  haiku:  { provider: anthropic, model: claude-haiku-4-5 }
  sonnet: { provider: anthropic, model: claude-sonnet-4-6 }
  opus:   { provider: anthropic, model: claude-opus-4-7 }

defaults:                     # only for agents with neither tier nor pin (rare)
  provider: anthropic
  model:    claude-sonnet-4-6
```

Benefit: when a new model family ships, change the `tiers:` block once and every
tier-driven agent picks it up.

## Pattern 2 — multiple providers, cost-floor cascade

```yaml
provider_priority: [deepseek, gemini, anthropic]   # cheapest first

tiers:
  low:
    - { provider: deepseek,  model: deepseek-v4-flash }
    - { provider: gemini,    model: gemini-2.5-flash-lite }
    - { provider: anthropic, model: claude-haiku-4-5 }   # baseline fallback
  middle:
    - { provider: deepseek,  model: deepseek-v4-pro }
    - { provider: gemini,    model: gemini-2.5-pro }
    - { provider: anthropic, model: claude-sonnet-4-6 }
  high:
    - { provider: anthropic, model: claude-sonnet-4-6 }  # premium-privacy: anthropic only
    - { provider: anthropic, model: claude-opus-4-7 }
```

A `tier: low` run tries `deepseek-v4-flash`; on a retryable error (429/5xx) with
`fallback_on_error` true the resolver re-picks the next candidate (gemini, then
anthropic) until one succeeds or the cascade exhausts (`ErrTierUnavailable`).

Per-agent privacy override (skip cheap third parties for one sensitive agent):

```yaml
# in the agent .md frontmatter
providers: [anthropic]   # full replacement of provider_priority for this agent
```

## Pattern 3 — single provider, per-plan user_tiers

```yaml
provider_priority: [anthropic]
tiers:
  low:    [{ provider: anthropic, model: claude-haiku-4-5 }]
  middle: [{ provider: anthropic, model: claude-sonnet-4-6 }]
  high:   [{ provider: anthropic, model: claude-opus-4-7 }]

user_tiers:
  default:                       # REQUIRED if you set user_tiers at all
    provider_priority: [anthropic]
    fallback_on_error: true
  free:                          # free plan locked to haiku regardless of agent.tier
    provider_priority: [anthropic]
    fallback_on_error: true
    tiers:
      low:    [{ provider: anthropic, model: claude-haiku-4-5 }]
      middle: [{ provider: anthropic, model: claude-haiku-4-5 }]
      high:   [{ provider: anthropic, model: claude-haiku-4-5 }]
  high:                          # full menu
    provider_priority: [anthropic]
    fallback_on_error: true
    tiers:
      low:    [{ provider: anthropic, model: claude-haiku-4-5 }]
      middle: [{ provider: anthropic, model: claude-sonnet-4-6 }]
      high:   [{ provider: anthropic, model: claude-opus-4-7 }]
```

The caller passes `user_tier` on the run request; the agent `.md` never changes.
**You must include a `default:` entry** — it's the fallback when the caller omits
`user_tier` or sends an unknown one. Without it, unknown user_tiers error out.

## Pattern 4 — multi-provider + multi-user-tier (production)

The library is the backstop; user_tiers carve cost/privacy boundaries. The
**privacy boundary** trick: a `high` user_tier sets
`provider_priority: [anthropic, openai]` and omits `tiers:` — library tiers are
inherited but **filtered** to those two providers, so a high-tier user's run
never touches a third-party cloud even if library tiers list ollama/gemini
first. If both are down it's a hard 503, never a silent fallback. See
`docs/CONFIGURATION.md §6` for the full six-tier example and routing table.

## fallback_on_error

Per user_tier overlay. `true` (default) = retryable provider error cascades to
the next candidate. `false` = the error surfaces directly (use on a free tier to
prevent accidental fallback into an expensive provider during an outage).

Related env knob: `LOOMCYCLE_FALLBACK_PIN_AFTER_SUCCESS=1` suppresses
cross-provider fallback *after* the run has completed ≥1 successful turn (avoids
mid-conversation transcript-translation bugs across providers). Recommended for
deployments using thinking-mode providers. Initial-turn fallback still works.

## Agent `.md` frontmatter (routing-relevant fields)

| Field | Meaning |
|---|---|
| `tier` | `low`/`middle`/`high` — tier-driven resolution (XOR with pin). |
| `provider` + `model` | Explicit pin (XOR with tier). `model:` may be an alias from `models:`. |
| `providers` | `[]string` — per-agent provider walk order (full replacement). |
| `models` | `map<tier,[{provider,model}]>` — per-agent candidate lists (full replacement). |
| `effort` | `low`/`medium`/`high` reasoning hint (anthropic+openai honour; ollama ignores). |
| `max_tokens` | Per-iteration output cap; 0 = provider default. |

The operator-yaml `agents:` map overrides any frontmatter field per-deployment:
scalars — non-zero yaml wins; slices/maps — yaml `nil` keeps the discovered
value, yaml non-nil (even `[]`) is an explicit override; set `model: ""` to
*clear* a discovered pin and fall back to `tier:`.

## Config-load errors (what they mean)

| Error | Fix |
|---|---|
| `cannot set both explicit provider/model pin and tier` | Pick one on that agent. |
| `no model, no tier, and no defaults.model` | Give the agent a `tier:`/pin, or set `defaults.model`. |
| `user_tiers: missing "default" entry` | Add a `default:` overlay. |
| `unknown provider: X` | `X` isn't a registered driver — check spelling against the provider table. |
| `model alias cycle: X → Y → X` | Break the cycle in `models:`. |
