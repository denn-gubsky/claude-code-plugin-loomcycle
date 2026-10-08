# Routing reference — providers, tiers, user_tiers, fallbacks

This is the **`loomcycle.yaml` model-routing axis**. Authoritative source:
loomcycle `docs/CONFIGURATION.md` + `docs/PROVIDERS.md` (+ `docs/DECISION-MODELS.md`
for decision models). Field names below match loomcycle's config loader at
**v1.107.0** — do not invent fields. Check any config you write with
`loomcycle validate <file>` (it prints agent-gate and model-kind advisories too).

The agent tool-allowlist key is **`tools:`**. The old `allowed_tools:` key is
not read at all — it is dropped without an error and the agent ends up with no
tools — so use `tools:` in every agent, yaml or `.md`.

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

**The built-ins need no declaration.** The first six rows above (plus `mock`
and `code-js`) ship as an embedded default layer under every config. Add a top-level
`providers:` map only to introduce a 3rd-party / self-hosted provider or to
override a built-in field (entries deep-merge over the defaults):

```yaml
providers:
  my-vllm:                      # the id you then use in provider:
    driver: vllm                # openai | anthropic | gemini | deepseek | ollama | vllm | llamacpp
    base_url: http://vllm.local:8000/v1
    api_key_env: VLLM_API_KEY   # env-var NAME; omit for a keyless endpoint
    max_concurrent: 2           # optional cap on in-flight runs (queue, then 429)
    options: { header_timeout_ms: 600000, idle_timeout_ms: 600000 }
    capabilities: { max_context_tokens: 32768 }   # vLLM / llama.cpp fix the window at launch
  ollama-local:                 # override one field of a built-in
    driver: ollama
    max_concurrent: 2
```

- `vllm` and `llamacpp` are dedicated local drivers (OpenAI-compatible; default
  endpoints `http://localhost:8000/v1` and `http://localhost:8080/v1`).
- `LOOMCYCLE_NO_DEFAULT_PROVIDERS=1` drops the built-in layer so only your
  `providers:` entries exist.
- **An empty key replaces.** A bare `providers:` with every entry commented out
  is a YAML null and *removes* every provider an earlier layer declared. Comment
  the key out too.

> **Provider keys are referenced by env-var name, never `${}`-interpolated.**
> A provider key reaches its driver through loomcycle's `Env` struct — there is
> no `api_key: ${ANTHROPIC_API_KEY}` field, and the yaml `${}` expander
> deliberately **excludes** provider keys (so a malicious shared yaml can't
> `${ANTHROPIC_API_KEY}` a secret into an outbound MCP header). `${}`
> interpolation is for `mcp_servers:` (and other outbound string fields) only,
> and is itself allowlisted — any `LOOMCYCLE_`-prefixed name plus the hardcoded
> set `BRAVE_API_KEY` / `SERPER_API_KEY` / `EXA_API_KEY` / `TAVILY_API_KEY` /
> `GITHUB_TOKEN` / `SLACK_BOT_TOKEN` / `REDIS_URL` / `SANDBOX_AUTH_TOKEN`; every
> other name passes through verbatim.
>
> **Deny-list:** loomcycle's own infra/admin credentials are **never**
> interpolated — even though the `LOOMCYCLE_` prefix would otherwise allow them:
> `PG_DSN`, `LOOMCYCLE_PG_DSN`, `LOOMCYCLE_SQLMEM_PG_DSN`, `LOOMCYCLE_AUTH_TOKEN`,
> `LOOMCYCLE_OPERATOR_TOKEN_PEPPER`, `LOOMCYCLE_MCP_UPSTREAM_TOKEN`,
> `LOOMCYCLE_OTEL_EXPORTER_OTLP_HEADERS`, `LOOMCYCLE_SECRET_KEY`,
> `LOOMCYCLE_SECRET_KEY_PREVIOUS`. Interpolating them into an outbound MCP
> URL/header would exfiltrate loomcycle's own creds to a third party. (They reach
> the runtime via the `Env` struct, never via yaml, so denying them breaks
> nothing.) An expanded value containing `\r`/`\n` is also left unexpanded
> (yaml-injection guard). See [webhooks.md](webhooks.md) for the MCP-server
> secret-injection pattern.
>
> **Runtime-authored MCP server defs (v1.101.1):** only an admin (or the
> open-mode / stdio operator) may store a `${NAME}` env reference in one. A
> `substrate:tenant` author or an agent uses `${run.credentials.<name>}`,
> `${run.user_bearer}` or `$cred:<name>` instead. Static `mcp_servers:` yaml is
> unaffected.

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
config-load (`cannot set both explicit provider/model pin and tier (pick one)`).
A `model:` alone counts as a pin, alias or not: `model: sonnet` + `tier: middle`
is refused. Since v1.102.0 the same refusal applies to runtime authoring
(`AgentDef` create/fork, `register_agent`), which used to store both.

When an agent's `providers:` AND a user_tier's `provider_priority` are both set,
the resolver uses their **intersection in agent order**. Empty intersection →
`ErrTierAgentNotAvailable` (a *policy* refusal: "this user's plan doesn't cover
this agent"). This is the load-bearing gate: "agent may use X" AND "user may use
X" are enforced together.

## Pattern 1 — single provider, tiers + aliases

```yaml
models:                       # name each model once; reference it by name everywhere
  haiku:  { provider: anthropic, model: claude-haiku-4-5 }
  sonnet: { provider: anthropic, model: claude-sonnet-4-6 }
  opus:   { provider: anthropic, model: claude-opus-4-7 }

provider_priority: [anthropic]

tiers:                        # a bare alias == its { provider, model } pair
  low:    [haiku]
  middle: [sonnet]
  high:   [opus]

defaults:                     # only for agents with neither tier nor pin (rare)
  provider: anthropic         # NOT alias-expanded — write a concrete provider + model
  model:    claude-sonnet-4-6
```

Benefit: when a new model family ships, change one `models:` right-hand side and
every tier and every `model: sonnet` pin that names the alias picks it up. A raw
`{ provider, model }` pair still works anywhere an alias does.

An alias may use `model_pattern: "qwen3.6*"` instead of `model:` to match
whatever the provider's live catalog serves (the embedded presets do this for
local models). A `model_pattern` alias is refused in `decision:`,
`memory.embedder` and `memory.reranker`.

### Model kinds — the `kind:` tag on an alias (v1.107.0)

```yaml
models:
  local-medium:    { provider: ollama-local, model: qwen3.6 }                  # kind: chat (the default)
  local-embedding: { provider: ollama-local, model: bge-m3, kind: embedder }
  decide:          { provider: ollama-local, model: nimble, kind: decision }
```

| Where the alias is written | Kind it must have |
|---|---|
| an agent's `model:`, a tier candidate, the listwise memory reranker, `memory.unit_generator` | `chat` |
| the `decision:` block, a memory reranker with `kind: decision` | `decision` |
| `memory.embedder.model` | `embedder` |

- **Wrong tag → config load fails.** The error names the alias, its kind and the
  place (`memory.embedder.model: models.decide is kind: decision, and a model of
  kind: embedder is needed here`).
- **Missing tag** on an alias used as an embedder or a decision model → still
  loads, with an advisory at boot and in `loomcycle validate` naming the alias
  and the tag to add. A later release makes this a failure, so tag them now.
- An untagged alias used as a chat model is the normal case and says nothing. A
  plain model name (not an alias) is never checked.
- The kind is a placement check only — never a routing input. `GET /v1/_models`
  reports it.

## Pattern 2 — multiple providers, cost-floor cascade

```yaml
provider_priority: [deepseek, gemini, anthropic]   # cheapest first

tiers:
  low:
    - { provider: deepseek,  model: deepseek-flash }
    - { provider: gemini,    model: gemini-2.5-flash-lite }
    - { provider: anthropic, model: claude-haiku-4-5 }   # baseline fallback
  middle:
    - { provider: deepseek,  model: deepseek-v4-pro }
    - { provider: gemini,    model: gemini-2.5-pro }
    - { provider: anthropic, model: claude-sonnet-4-6 }
  high:
    - { provider: anthropic, model: claude-sonnet-4-6 }  # premium-privacy: anthropic only
    - { provider: anthropic, model: claude-opus-4-7 }

user_tiers:
  default:                       # mid-run fallback is a user_tier setting — see below
    provider_priority: [deepseek, gemini, anthropic]
    fallback_on_error: true
```

A `tier: low` run starts on the first candidate that is available right now
(`deepseek-flash`; an excluded, unreachable or stalled candidate is skipped at
pick time). On a retryable error (429/5xx) **with `fallback_on_error: true` on
the run's user_tier** the resolver re-picks the next candidate (gemini, then
anthropic) until one succeeds or the cascade exhausts (`ErrTierUnavailable`).

> **`deepseek-v4-flash` → `deepseek-flash` (v1.102.0).** DeepSeek's catalog
> replaced the old id. Change it in your own config: a model the provider no
> longer lists is skipped as a tier candidate. `deepseek-flash` is a thinking
> model at any effort.

Per-agent privacy override (skip cheap third parties for one sensitive agent):

```yaml
# in the agent .md frontmatter (or its `agents:` yaml entry)
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
**You must include a `default:` entry** — it is what a request that omits
`user_tier` gets, and config load fails without it. A request that names a
user_tier you did not define is refused `400 unknown user_tier`, not mapped to
`default`.

## Pattern 4 — multi-provider + multi-user-tier (production)

The library is the backstop; user_tiers carve cost/privacy boundaries. The
**privacy boundary** trick: a `high` user_tier sets
`provider_priority: [anthropic, openai]` and omits `tiers:` — library tiers are
inherited but **filtered** to those two providers, so a high-tier user's run
never touches a third-party cloud even if library tiers list ollama/gemini
first. If both are down it's a hard 503, never a silent fallback. See
`docs/CONFIGURATION.md §6` for the full six-tier example and routing table.

## fallback_on_error

Per user_tier overlay. `true` = a retryable provider error mid-run cascades to
the next candidate. `false` = the error surfaces directly (use on a free tier to
prevent accidental fallback into an expensive provider during an outage).

**Write it explicitly on every overlay.** The loader applies no default: an
overlay that omits the key has it `false`, and a config with **no `user_tiers:`
block at all has no mid-run fallback** (candidates that are unavailable when the
run starts are still skipped). `max_fallback_attempts` (default 3) caps provider
switches per run; `retry_attempts` (default 0, 1–3 recommended, capped at 5)
retries the same provider with backoff before falling back.

Related env knob: `LOOMCYCLE_FALLBACK_PIN_AFTER_SUCCESS=1` suppresses
cross-provider fallback *after* the run has completed ≥1 successful turn (avoids
mid-conversation transcript-translation bugs across providers). Recommended for
deployments using thinking-mode providers. Initial-turn fallback still works.

## Agent `.md` frontmatter (routing-relevant fields)

| Field | Meaning |
|---|---|
| `tools` | Tool allowlist — list, or a Claude-Code comma-string. Empty/absent = zero tools. (`allowed_tools` is not read.) |
| `tier` | `low`/`middle`/`high` — tier-driven resolution (XOR with pin). |
| `provider` + `model` | Explicit pin (XOR with tier). `model:` may be an alias from `models:` (it must be a `chat` alias). |
| `providers` | `[]string` — per-agent provider walk order (full replacement). |
| `models` | `map<tier,[{provider,model}]>` — per-agent candidate lists (full replacement). |
| `effort` | `low`/`medium`/`high` reasoning hint. On Ollama it drives the `think` flag: `medium`/`high` → on, `low` → off, unset → model default (so `effort` on a non-thinking Ollama model errors). |
| `max_tokens` | Per-iteration **output** cap; 0 = provider default. |
| `max_context_tokens` | Per-agent context **window** (v1.61.0); see below. |
| `decision` | Narrows which decision models the agent may ask; see below. |

The block-shaped keys `sampling`, `compaction`, `context`, `tool_choice` and
`output_format` go in the operator-yaml `agents:` entry (or an `AgentDef`
create/fork overlay). The `.md` frontmatter parser has no field for them, so in
a `.md` file they are dropped silently.

The operator-yaml `agents:` map overrides any frontmatter field per-deployment:
scalars — non-zero yaml wins; slices/maps — yaml `nil` keeps the discovered
value, yaml non-nil (even `[]`) is an explicit override; set `model: ""` to
*clear* a discovered pin and fall back to `tier:`.

## Per-agent `max_context_tokens` (v1.61.0)

```yaml
agents:
  researcher: { model: local-medium, tools: [Read, WebFetch], max_context_tokens: 131072 }
```

- **Ollama:** sent as `options.num_ctx` for that agent's runs — wins over
  `LOOMCYCLE_OLLAMA_LOCAL_NUM_CTX` and `providers.<id>.options.num_ctx`. Ollama
  keeps one resident copy per `(model, num_ctx)`, so mixed windows for one model
  cost VRAM.
- **Cloud:** cannot enlarge the model's window; it only *lowers* the effective
  window that the context gauge and `autocompact_at_pct` use.
- Distinct from `max_tokens` (output). Also a per-run override
  (`max_context_tokens` on the run request / `spawn_run`); a per-run value is not
  inherited by sub-agents.

## Per-agent `sampling:` block (v0.28.0)

Tune the LLM decoding params per agent (in its `agents:` yaml entry or AgentDef
overlay) or per-run. All optional; omit the block for provider defaults.

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
  both) — pick reasoning-effort *or* temperature shaping, not both. Newer
  Anthropic models that reject non-default sampling have
  `temperature`/`top_p`/`top_k` dropped with a log line (v1.92.0).
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
  memory_flush: true        # queue the dropped turns for the memory consolidator (needs `user` in memory_scopes)
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
- `compaction.keep_last_n` (default 4, messages) is a different key from
  `context.keep_last_n` (default 6, tool-call pairs) below.
- Compacting a `mode: stateful` run is refused (`409 stateful_run`).

## Per-agent `context:` block (v1.70.0+)

A different retention strategy from compaction, for long runs — especially on
weak or local models. `append` (the default) keeps today's behaviour.

```yaml
agents:
  long-runner:
    model: local-medium
    tools: [Read, Grep]
    context:
      mode: recap             # append (default) | recap | stateful | auto
      keep_last_n: 6          # recent tool_use/tool_result pairs kept verbatim (default 6)
      reasoning: recap        # recap (default) | drop | keep
      recap_max_chars: 512    # bound on the running recap note (default 512)
      autorecap_at_pct: 80    # 50–95, default 80
      model: local-small      # optional: a cheap NON-thinking summarizer for the recap (alias or model id)
      recall: true            # index evicted spans + auto-grant the Recall tool (needs memory.embedder)
      harvest_to_memory: true # bank evicted spans for the consolidator (needs `user` in memory_scopes)
```

| `mode` | What the model is fed |
|---|---|
| `append` | Full history; the `compaction:` block may summarise it. |
| `recap` | The pinned task + a bounded running recap + the last `keep_last_n` tool pairs verbatim. Takes precedence over the compaction auto-trigger. |
| `stateful` | The preamble + a structured state object + the latest observation. The model answers with one `emit_state` call (a patch + the next action); the runtime dispatches the action. For procedural work, not open conversation. |
| `auto` | Resolved at run start from the provider the run landed on: a local backend (`ollama-local`, `vllm`, `llamacpp`) → `recap`; a frontier API → `stateful`. An interactive run always resolves to `recap`. |

- `stateful` extra keys: `state_schema` (optional JSON-schema subset the state
  and every patch must hold), `on_invalid_patch` (`retry` default | `fail`),
  `max_patch_retries` (default 2).
- `recall` and `harvest_to_memory` work in every mode, including `append` +
  compaction. `recall: true` adds `Recall` to the run's tools without listing it.
- Compaction stays reachable from every mode as a second tier:
  `compaction.autocompact_at_pct` is the backstop when the window still fills.
- Content-identifying; a per-run `context` override exists on the run request and
  MCP `spawn_run`/`spawn_runs`; it flows down the spawn tree. The full transcript
  is always retained — only the fed window is distilled.

## Per-agent `tool_choice` and `output_format` (v1.92.0 / v1.93.0)

```yaml
agents:
  extractor:
    tier: middle
    tools: [Read]
    tool_choice: { mode: required, until: first_call }
    output_format:
      type: json_schema        # the only type; may be omitted
      name: verdict            # optional label, default "output"
      schema:                  # root MUST be type: object
        type: object
        properties: { ok: { type: boolean } }
        required: [ok]
```

- **`tool_choice.mode`**: `auto` | `none` | `required` (some tool) | `tool` (the
  one in `name`; `name` is refused with any other mode).
  **`until`**: `first_call` (default) | `until_called` (needs `required`/`tool`)
  | `always` (refused with `required`/`tool` — the run could never finish).
- Provider support: sent on the Anthropic, OpenAI and Gemini dialects (deepseek /
  vllm / llamacpp inherit). Ollama does not enforce it. A forced choice is
  dropped under Anthropic extended thinking and is not sent to `deepseek-flash`.
- **`output_format`**: the parsed answer lands in the run result as `structured`.
  Enforced natively by Anthropic, OpenAI and Gemini; by a grammar on a tool-free
  request for vLLM, llama.cpp and `ollama-local`; DeepSeek and hosted Ollama
  cannot enforce it.
- Both are also per-run overrides. When a provider cannot honour one, the run
  emits a `capability_inert` event at start instead of failing.

## Decision models — the top-level `decision:` block (v1.107.0)

A decision model answers typed questions (pick an option, yes/no, a score) with
probabilities instead of text. The block lists the ones this deployment may ask.

```yaml
models:
  decide: { provider: ollama-local, model: nimble, kind: decision }

decision:
  default: decide            # required when the block is set
  models: [decide]           # optional; omitted = every alias tagged kind: decision, plus the default
  provider: ollama-local     # only for plain model names in the list (an alias carries its own)
  timeout_ms: 30000          # default 30000 — must cover a model reload on a shared GPU
  max_concurrent: 4          # default 4, per provider

agents:
  triage:
    tier: low
    tools: [Decision]        # grant the tool
    decision:                # optional per-agent narrowing
      default: decide
      models: [decide]
```

- **No block = capability off.** The tool is not offered and the endpoints answer
  `decision_not_configured`. Changing the block needs a restart.
- Only Ollama (0.35 or later: `nimble`, `clef`, `clef-flash`, `tev1`) serves
  decision models today.
- Config load fails on: a missing `default`, a provider whose driver serves no
  decision models, a `model_pattern` alias, a plain model name with no
  `decision.provider`, an alias tagged another kind, or an unknown key in the
  block.
- The per-agent `decision:` **only narrows**: every name must be in the
  operator's list (else config load fails, or the runtime create/fork is
  refused). Unset = the operator's whole list and default.
- The embedded `local` preset ships a `local-decide` alias (`ollama-local` /
  `nimble`) and no block — add `decision: { default: local-decide }` to turn it on.
- Surfaces: the `Decision` tool in a run, `POST /v1/_decide`, gRPC `Decide`, MCP
  `decision`. The run-less surfaces need the `runs:create` scope.

## Memory reranker — `memory.reranker` (v1.99.0+)

An opt-in model call that reorders search results. The operator declares what
serves it; an agent turns it on with `memory_rerank`.

```yaml
memory:
  reranker:
    kind: listwise               # listwise (default) | decision
    provider: ollama-local       # a declared provider…
    model: qwen3.6:latest        # …and model, or just a models: alias
    effort: low                  # listwise only — thinking off on a hybrid local model
    timeout_ms: 30000            # default 30000; a slower rerank keeps search's own order
    max_concurrent: 2            # default 4
    sources: [documents, facts, notes]   # default [documents]

agents:
  researcher:
    tier: middle
    tools: [Memory, Document]
    memory_rerank: { enabled: true }     # optional: candidates, max_chars
```

- **`kind: listwise`** asks a chat model for an ordering. **`kind: decision`**
  asks a decision model (Ollama) one typed choice and orders by its
  probabilities; `effort` and `context_tokens` with it fail config load. An
  unknown `kind` fails load.
- **`sources`** is what the rerank may reorder: `documents`, `facts`, `notes`,
  `traces`. Unset = `[documents]`. Adding `facts` and `notes` is what reranks an
  agent's `recall`. An unknown source fails load.
- No default model: with no block, an agent that enables `memory_rerank` gets
  `reranked: false` with `rerank_reason: not_configured` — never an error.
- `memory_rerank` is per agent only (no per-run override, no tool parameter).
  `candidates` defaults to 40 for listwise, 20 for decision; `max_chars` to 1200.
- `base_url` / `api_key_env` override the provider's, as for `memory.embedder`.
  A change to the block needs a restart.

## `timeout_scaling:` — measured model speed (v1.101.2)

loomcycle times every model call and keeps, per (provider, model), a slowdown
against a reference machine. **This version only measures — no timeout changes.**

```yaml
timeout_scaling:
  mode: measure            # measure (default) | off. `on` is refused at load.
  reference: { decode_tps: 100, prefill_tps: 2000, ttft_ms: 1000 }
  max_multiplier: 8        # ceiling, 1–100
  min_samples: 5
  local_prior: 4           # assumed multiplier for a local provider before min_samples
  models:                  # keyed provider/model, or by a models: alias
    ollama-local/qwen3.6:latest: { decode_tps: 20 }
    local-medium: { max_multiplier: 24 }   # this model's own cap, 1–100
```

- Reported on `GET /v1/_routing` (a `throughput` block per candidate), `/metrics`
  (`loomcycle_model_slowdown`, `loomcycle_model_timeout_multiplier`, …) and
  `Context op=self` (`timeouts`).
- Env overrides win over the yaml: `LOOMCYCLE_TIMEOUT_SCALING`,
  `LOOMCYCLE_TIMEOUT_SCALING_REFERENCE_TPS`,
  `LOOMCYCLE_TIMEOUT_SCALING_MAX_MULTIPLIER`. A change needs a restart.

## Embedded presets and config layering

The binary ships provider/tier presets and agent bundles, so an install can
resolve a sane routing base without a source checkout. Opt-in:

```bash
LOOMCYCLE_PRESETS=base,local loomcycle --config ~/.config/loomcycle/loomcycle.yaml
```

- **Presets** (routing only): `base` (the full provider matrix, aliases, tiers,
  user_tiers), `oauth` (puts `anthropic-oauth-dev` on top), `local` (puts
  `ollama-local` on top). `oauth` / `local` `!prepend` onto `base`, so `base,local`
  keeps base's cloud providers as fallback — unset the cloud keys or set
  `LOOMCYCLE_NO_DEFAULT_PROVIDERS=1` to stay local-only.
- **Bundles** (agents + inline skills): `chat`, `document-agent`, `memory`,
  `system-channels`, `sandbox`, `dev-exec`, `agent-teams`, `team-examples`,
  `doc-colorizer`. List them with `loomcycle presets`; print one with
  `loomcycle presets show <name>`.
- **Precedence** (base → top, last wins): `LOOMCYCLE_PRESETS` (in order) →
  `LOOMCYCLE_CONFIG_DIR/*.yaml` (lexical) → `LOOMCYCLE_CONFIG_FILES`
  (`:`-separated) → `--config` flags (repeatable). An unknown preset name is fatal.
- **Section files:** a `loomcycle.yaml` base auto-layers every sibling
  `loomcycle.*.yaml` (lexical order; `*.example.yaml` ignored), e.g.
  `loomcycle.providers.yaml`, `loomcycle.memory.yaml`.
- **Merge rule:** mapping ⊕ mapping merges by key; a scalar or a sequence is
  replaced by the later layer. `agents`, `models`, `user_tiers`, `providers`
  merge by key; each `tiers.<tier>` list and `provider_priority` replace
  wholesale unless the overlay tags the sequence `!prepend` / `!append`:

  ```yaml
  provider_priority: !prepend [ollama-local]
  tiers:
    middle: !prepend [local-medium]
  ```

- `LOOMCYCLE_CONFIG_STRICT=1` makes any cross-layer conflict a fatal load error
  (recommended in production). Without it each override is logged at startup.
- `loomcycle validate`, `agents list` and `doctor` assemble the same layered
  stack the server does. `POST /v1/_config/reload` (`?dry_run=1` to preview)
  applies `providers`, `models`, `tiers`, `provider_priority`, `user_tiers`,
  `agents` and `defaults` live; `memory`, `decision` and `timeout_scaling`
  changes are reported `restart_required`.

## Config-load errors (what they mean)

| Error | Fix |
|---|---|
| `cannot set both explicit provider/model pin and tier (pick one)` | Pick one on that agent. |
| `no model, no tier, and no defaults.model` | Give the agent a `tier:`/pin, or set `defaults.model`. If the entry only carries capability grants for a bundled agent, the bundle that defines it is missing from the layer stack — check `LOOMCYCLE_PRESETS`. |
| `agent "X": no provider resolved` | The agent's model names no provider and there is no `defaults.provider` — use a `models:` alias, a `provider:`, or a `defaults:` block. |
| `user_tiers: a "default" entry is required when the user_tiers block is populated` | Add a `default:` overlay. |
| `unknown provider "X"` | `X` isn't a declared provider — check spelling against the provider table / your `providers:` map. |
| `models.X is kind: K, and a model of kind: K2 is needed here` | The alias is tagged for another use — point the field at an alias of the right kind. |
| `decision.default: "X" is served by provider "P", whose "D" driver serves no decision models` | Decision models need an Ollama provider. |
| `decision: unknown key "X"` | The block takes only `default`, `models`, `provider`, `timeout_ms`, `max_concurrent`. |
| `memory.reranker.kind: "X" is not one of listwise, decision` / `memory.reranker.sources: "X" is not one of documents, facts, notes, traces` | Fix the value. |
| `context.mode "X" invalid (want append\|recap\|stateful\|auto)` | Fix the mode. |
| `LOOMCYCLE_READ_ROOT, … retired in RFC AH Phase 3 — declare a volumes: block instead` | Remove the var(s) from env; use a `volumes:` block. See [volumes.md](volumes.md). |
| `agent "A": volumes[0]: unknown volume "X" (declare it in the top-level volumes: map)` | Declare `X` under `volumes:` or remove it from the agent's `volumes:` list. |
| `no dynamic volume root configured — mark a static volume dynamic_root: true` (a `VolumeDef` tool error, not a load error) | Add `dynamic_root: true` to one `volumes:` entry. |
| `volumes: at most one volume may be default:true` | Set `default: true` on exactly one volume. |
