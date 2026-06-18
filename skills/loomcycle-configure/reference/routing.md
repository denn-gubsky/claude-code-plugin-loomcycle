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
| `anthropic-oauth-dev` | OAuth (`loomcycle anthropic login`) | api.anthropic.com | **Research/dev ONLY**, opt-in via `LOOMCYCLE_ANTHROPIC_OAUTH_DEV_ENABLED=1`. Single-machine. **Never** for production, multi-tenant, multi-replica, or customer-facing. Reverse-engineered subscription billing; no SLA, ToS risk. Verify a live token server-side with `loomcycle anthropic status --probe` (**v0.23.3**, F6/#392 — plain `status` reports only local file metadata); concurrent loomcycle processes now share the token file safely via a cross-process refresh lock (**v0.23.3**, F7/#391). Setup + robustness walkthrough below. |

A provider with no API key set is marked **excluded** (treated like unreachable)
and skipped by the resolver. Only set keys for providers you'll use.

> **Provider keys are referenced by env-var name, never `${}`-interpolated.**
> A provider key reaches its driver through loomcycle's `Env` struct — there is
> no `api_key: ${ANTHROPIC_API_KEY}` field, and the yaml `${}` expander
> deliberately **excludes** provider keys (so a malicious shared yaml can't
> `${ANTHROPIC_API_KEY}` a secret into an outbound MCP header). `${}`
> interpolation is for `mcp_servers:` (and other outbound string fields) only,
> and is itself allowlisted — any `LOOMCYCLE_`-prefixed name plus the hardcoded
> set `BRAVE_API_KEY` / `GITHUB_TOKEN` / `SLACK_BOT_TOKEN` / `REDIS_URL`; every
> other name passes through verbatim.
>
> **Deny-list (v0.32.0, #462 / exp7-C2):** `PG_DSN`, `LOOMCYCLE_PG_DSN`, and
> `LOOMCYCLE_AUTH_TOKEN` are **never** interpolated — even though the
> `LOOMCYCLE_` prefix would otherwise allow them — because they are loomcycle's
> own infra/admin credentials; interpolating them into an outbound MCP URL/header
> would exfiltrate loomcycle's own creds to a third party. (They reach the runtime
> via the `Env` struct, never via yaml, so denying them breaks nothing.) An
> expanded value containing `\r`/`\n` is also rejected (yaml-injection guard).
> See [webhooks.md](webhooks.md) for the MCP-server secret-injection pattern.

## Robust `anthropic-oauth-dev` setup (research/dev only)

Routes loomcycle through an operator's **Claude subscription** instead of a
metered `ANTHROPIC_API_KEY`. It is a reverse-engineered, unofficial path — no
SLA, ToS risk, single-machine, **never** production/multi-tenant/customer-facing.
With the v0.23.3 fixes (F6 + F7) it is now *reliable enough for a local dev loop*;
before, it died silently under parallel runs. Five steps, all server-side (this
is loomcycle's own auth — **not** the plugin's `auth_token` / `/loomcycle:connect`
bearer, which is unrelated):

1. **Enable the provider** (non-secret, `.env.insecure`): `LOOMCYCLE_ANTHROPIC_OAUTH_DEV_ENABLED=1`.
   Without it the driver isn't registered and the resolver never sees the provider.
2. **Authorize once:** `loomcycle anthropic login` (browser OAuth). The token lands
   at `~/.config/loomcycle/anthropic-oauth.json`, mode `0600` — **outside the repo
   and the loomcycle DB**, so it is never committed and never hits the F32 at-rest
   transcript path. Nothing to put in any env file.
3. **Route it.** Append `anthropic-oauth-dev` **last** in `provider_priority` so
   unpinned runs still prefer your cheaper primary; **pin it per-agent** to force
   Claude:
   ```yaml
   provider_priority: [deepseek, anthropic-oauth-dev]   # oauth-dev only as last resort
   # …and on the one agent that should use the subscription:
   #   provider: anthropic-oauth-dev
   #   model:    claude-sonnet-4-6
   ```
   Subscription models are exposed under the `anthropic-oauth-dev` provider id —
   reference them there, not under `anthropic`.
4. **Verify health server-side:** `loomcycle anthropic status --probe` (alias
   `--verify`). Plain `status` prints **only local token-file metadata** and can
   read "valid" while Anthropic has already revoked the token (the original F6
   trap). `--probe` does a *free* token refresh against Anthropic — `✓ valid`
   (exit 0, and it **rotates + persists a fresh token**, healing the session) or
   `✗ INVALID` (exit 1, "run `loomcycle anthropic login`"). Also confirm the
   resolver sees it: `GET /v1/_resolver` should list the provider as reachable.
5. **(automatic) Concurrent-process safety.** Multiple loomcycle processes sharing
   one token file (a server + a thin-client run, say) used to race the refresh:
   the first rotated the refresh token, the rest were stranded with
   `invalid_grant` until a full re-login (F7). v0.23.3 serializes refresh with a
   cross-process **`flock`** and a **reload-before-refresh** (a process that
   blocked on the lock adopts the peer's freshly-rotated token instead of POSTing
   a now-dead one). The lock auto-releases on close/crash, and a lock-infra
   failure degrades to best-effort (logs, proceeds) rather than stranding refresh.
   Nothing to configure — just don't expect it on a pre-v0.23.3 binary.

> **Pre-v0.23.3 fallback.** On the v0.23.0 brew binary, `--probe` doesn't exist
> (`status` is local-metadata-only, F6) and there is no cross-process lock (F7) —
> run a single loomcycle process against the OAuth token, and re-`login` whenever
> inference starts returning `401 invalid_grant`.

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

## Per-agent `sampling:` block (v0.28.0)

Tune the LLM decoding params per agent (or per-run, or via the `agents:`
overlay). All optional; omit the block for provider defaults.

```yaml
sampling:
  temperature: 0.2          # float
  top_p: 0.9                # float
  top_k: 40                 # int
  frequency_penalty: 0.0    # float
  presence_penalty: 0.0     # float
  seed: 42                  # int — reproducibility where the provider supports it
  stop: ["\n\n###"]         # []string stop sequences
```

- Mapped to each provider's request params; a param a provider doesn't support
  is dropped.
- **Anthropic mutual-exclusion:** when an `effort` (extended-thinking) hint is
  attached, the Anthropic driver **drops `temperature`/`top_p`** (the API forbids
  both) — pick reasoning-effort *or* temperature shaping, not both.
- Surfaced on the agent-def overlay, per-run params, and `Context op=self`
  (which reports the *resolved* sampling). Flows down the spawn tree.

## Per-agent `compaction:` block (v0.32.0)

Context-compaction: summarise old conversation turns to keep a long run inside
the window. Optional; off unless `enabled: true`.

```yaml
compaction:
  enabled: true             # turn AUTO-compaction on
  target_percentage: 10     # 10–50; summary aims for ~N% of the compacted span (default 10)
  keep_last_n: 4            # keep the last N messages verbatim (default 4; 0 = summarize all)
  keep_first: true          # pin the first user message (the task) verbatim (default true)
  autocompact_at_pct: 80    # 50–95; auto-compact when used/window ≥ N% (default 80, needs a provider window)
  model: claude-haiku-4-5   # optional cheaper/faster summary model (same provider)
```

- **Flows down the spawn tree** with per-field precedence: child def is the
  fallback, a parent-set value wins, a per-spawn override wins all.
- **Per-run override:** the `spawn_run` MCP tool takes an optional `compaction`
  object (merged per-field over this block) — `/loomcycle:run --compact` sets
  `enabled: true` for one run.
- **Trigger manually:** the `compact_run` MCP tool compacts a *parked* run on
  demand (`/loomcycle:compact <agent_id>`); `Context op=compact` is the in-agent
  equivalent.
- Durable park+resume of a fan-out parent blocked in `parallel_spawn` is a
  separate, runtime-level opt-in — see `LOOMCYCLE_RESUME_FANOUT` in
  [env-vars.md](env-vars.md).

## Config-load errors (what they mean)

| Error | Fix |
|---|---|
| `cannot set both explicit provider/model pin and tier` | Pick one on that agent. |
| `no model, no tier, and no defaults.model` | Give the agent a `tier:`/pin, or set `defaults.model`. |
| `agent "X": no provider resolved` | Add a `defaults: {provider: …, model: …}` block (required for `loomcycle validate`'s dry-run resolver; inert at runtime). |
| `user_tiers: missing "default" entry` | Add a `default:` overlay. |
| `unknown provider: X` | `X` isn't a registered driver — check spelling against the provider table. |
| `model alias cycle: X → Y → X` | Break the cycle in `models:`. |
| `LOOMCYCLE_READ_ROOT (or WRITE_ROOT / BASH_CWD) is set but retired` | **Phase 3 breaking change (v1.0.3).** Remove the var from env; use `volumes:` block. See [volumes.md](volumes.md). |
| `volumes: referenced volume "X" not defined` | Declare `X` under `volumes:` or remove it from the agent's `volumes:` list. |
| `volumes: dynamic-root required for VolumeDef` | Add `dynamic_root: true` to a `volumes:` entry and list it in the agent's `volumes:`. |
| `volumes: more than one volume has default: true` | Set `default: true` on exactly one volume. |
