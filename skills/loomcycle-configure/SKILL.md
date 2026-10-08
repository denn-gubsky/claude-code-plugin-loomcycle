---
name: loomcycle-configure
description: Configure a loomcycle runtime — providers, model tiers and aliases, model kinds (chat / decision / embedder) and decision models, user tiers, fallbacks, per-agent sampling, context retention and compaction, agent hooks and hook definitions, interactive runs and review holds, environment variables, deployment profiles (brew/in-system, containerized, true sandbox, server, multi-tenant, cloud), filesystem Volumes, the Bashbox in-process sandbox, the Path VFS, chunked-graph Documents, encrypted per-tenant credentials (CredentialDef / $cred: / provider-key override), per-scope token budgets and usage/cost attribution, inbound webhooks, and third-party MCP servers. Use when the user wants to set up or tune loomcycle.yaml or its env, pick a deployment posture, wire provider routing/cost-cascades, gate plans, tune decoding (temperature/top_p), context retention or compaction, add a decision model, gate an agent's tool calls with hooks, make runs interactive or hold their answers for review, lock down tool/sandbox/auth, enable or choose between Bash and the Bashbox sandbox (incl. its host-command fallback), name resources with Path, author chunked-graph Documents (and the SQL Memory they require), store tenant/user API keys or bring-your-own provider keys, set token budgets, receive webhooks, or connect external MCP tools.
allowed-tools: Read Write Edit Bash(loomcycle validate*) Bash(loomcycle doctor*) Bash(loomcycle init*)
---

# Configure loomcycle

Help an operator write or tune their **`loomcycle.yaml`** (model routing) and
**environment** (posture: sandbox, auth, storage, scale). loomcycle splits its
configuration along one seam — keep it in mind throughout:

- **`loomcycle.yaml` owns routing** — `provider_priority`, `tiers`, `models:`
  aliases, `user_tiers:` overlays, `agents:` overrides. Declarative model policy.
  It can be split and stacked: embedded presets (`LOOMCYCLE_PRESETS`), a config
  directory, and repeatable `--config` files merge left to right, last wins.
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
3. **Tools are gated in *two* layers.** (a) The built-ins
   `Read`/`Write`/`Edit`/`Bash`/`HTTP`/`WebFetch` refuse every call until their
   *operator* volume/allowlist is set. (b) The capability tools additionally need
   a per-agent grant, and having the tool in `tools` is necessary but **not
   sufficient**: `Channel` needs `channels:`, `Interruption` needs
   `interruption.enabled`, and the definition-authoring tools (`AgentDef`,
   `ScheduleDef`, …) need their `*_def_scopes` list. An agent sees
   `operator-enabled ∩ tools ∩ per-tool grant`. Since v1.82–v1.83 four grants are
   no longer deny-when-unset: an unset `memory_scopes` resolves to the caller's
   **own** data (`user`, plus `tenant` for a non-isolated member), `history_scope`
   to `user`, `sql_scopes` to `[user]`, and `evaluation_scopes` to
   `[submit_self]`. Write `["-*"]` to grant none. Recommend the *narrowest*
   setting that works at every layer; never widen "to make it work."
   `loomcycle validate` and `doctor` print an advisory for each gate an agent's
   tools would hit.
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

## Things that fail silently — check these first

Four mistakes load clean and then do the wrong thing. Look for them before
anything else when "it validates but does not work":

- **`allowed_tools:` instead of `tools:`.** The old key is ignored, `validate`
  prints `OK`, and the agent gets an empty allowlist: no tools at all.
- **A capability tool with no grant.** `Channel` without `channels:`,
  `Interruption` without `interruption.enabled`, a `Memory` scope the agent was
  not given. `loomcycle validate` and `doctor` print an advisory for each gate;
  read them.
- **An untagged decision model or embedder.** A `models:` alias used by the
  `decision:` block or `memory.embedder` should carry `kind: decision` /
  `kind: embedder`. Untagged still loads, with a warning; a wrong tag fails the
  load.
- **A change that needs a restart.** `POST /v1/_config/reload` applies most
  routing live and lists what it could not under `restart_required` (the memory
  embedder, skills, the `decision:` block, among others).

## Model kinds and decision models — v1.107.0+

A `models:` alias can say what the model is for: `kind: chat` (the default),
`kind: decision` or `kind: embedder`. The kind is a check on **where an alias may
be written**, never a routing input.

A **decision model** answers typed questions (a choice, a yes/no, a score) about
text, with probabilities, for a few tokens. It is declared as an alias and listed
in a `decision:` block:

```yaml
models:
  decide: { provider: ollama-local, model: nimble, kind: decision }

decision:
  default: decide        # the model a call gets when it names none
  timeout_ms: 30000      # must cover a model reload on a shared GPU
  max_concurrent: 4      # per provider
```

Without a `decision:` block the capability does not exist: the tool is not
offered and every call answers `decision_not_configured`. Today only Ollama
(0.35 or later) serves decision models. An agent uses one by listing `Decision`
in its `tools:`; from the IDE it is `/loomcycle:decide`. **The probabilities are
not calibrated** — say so before an operator gates on a threshold.
**Full reference:** [reference/routing.md](reference/routing.md).

## Agent hooks — v1.94.0+ (the registry removed in v1.97.0)

A hook is a webhook or a JavaScript body an agent's definition carries, called
around a tool call (`pre`, `post`, `post_failure`) or at a point in the run
(`agent_start`, `agent_stop`, `run_end`, …). It can check, rewrite, deny, or
hold an answer for a person. Hooks are attached **on the agent** (per tool, or
agent-wide), by naming a reusable hook definition (`hookdef`) or inline as a
webhook. **A security check must be `fail_mode: closed`.** The old global
`register_hook` / `/v1/hooks` registry no longer exists.
**Full reference:** [reference/hooks.md](reference/hooks.md).

## Runs that wait for a person — interactive, review, retune

Three run controls an operator sets per agent or per run. An **interactive** run
parks at each turn boundary to be steered; a run under **review** holds its
finished answer for a verdict; a **retune** changes a running agent's model or
bounds without sending it a message, and can turn either mode on for a run that
is already going. From the IDE these are `/loomcycle:run --interactive`,
`/loomcycle:steer`, `/loomcycle:review` and `/loomcycle:retune`.
**Full reference:** [reference/interactive.md](reference/interactive.md).

## Volume primitive — v1.1.0+

**The Volume primitive replaces the env-var file jail with a `volumes:` block in `loomcycle.yaml`.** The old
vars `LOOMCYCLE_READ_ROOT`, `LOOMCYCLE_WRITE_ROOT`, and `LOOMCYCLE_BASH_CWD` are **retired
(a fatal config-load error since v1.1.0)**. Remove them from env files before upgrading.

### Quick migration (most configs)

In most configs all three vars pointed at the same directory. One block replaces all three:

```yaml
volumes:
  default:
    path: ./work    # relative to the dir run.sh cd's into
    mode: rw        # rw = Read+Write+Edit+Bash; ro = Read/Grep/Glob only
    default: true   # agents without an explicit `volumes:` list bind here

# Required only if any agent uses VolumeDef (mkdir -p ./work/dynamic first):
  dynamic-root:
    path: ./work/dynamic
    mode: rw
    dynamic_root: true
```

### VolumeDef tool (Phase 2a/2b — agent-provisioned volumes)

Agents can provision volumes at runtime with `VolumeDef op=create`. Two gates required:

1. `volume_def_scopes` on the agent: `[any]`, or `[named:<volume>]` (per-agent capability gate)
2. A `dynamic_root: true` volume declared in `volumes:` (backing store for provisioned volumes)

`ephemeral: true` makes the volume auto-purge when the creating run ends — no `rm -rf` needed.
A sub-agent that declares no volumes inherits its parent's; one that declares its own gets the intersection, with `ro` winning. Address files with `volume="name"`.

**Full reference:** [reference/volumes.md](reference/volumes.md) — migration table, field reference,
VolumeDef op catalogue, spawn narrowing, validation errors.

## Bashbox — a TRUE in-process sandbox (RFC AJ) — v1.3.0+

`Bashbox` is the **isolated** alternative to `Bash`: it runs commands in-process via gbash
(pure-Go) — **no OS process, no network**, every path rooted at the bound volume. Because the
isolation is real it **honors read-only volumes** (a `ro` binding mounts under an in-RAM overlay —
writes succeed in-run but never touch the host; `Bash` refuses `ro`). Opt-in like Bash:
`LOOMCYCLE_BASHBOX_ENABLED=1` + `tools:[Bashbox]`. **Prefer Bashbox over Bash for untrusted
prompts or read-only work;** use `Bash` only when an agent needs a real host binary (in a contained
deployment). An operator can allowlist specific host commands gbash lacks (`git`, `gh`) to fall
through to the host shell via `LOOMCYCLE_BASHBOX_FALLBACK_COMMANDS` (off by default; only those names
escape; rw-only; creds via `LOOMCYCLE_BASHBOX_FALLBACK_ALLOWED_ENV` injected into the host child
only). Bashbox is **in-band only** — there is no `bashbox` meta-tool.
**Full reference:** [reference/bashbox.md](reference/bashbox.md).

## Path — a Unix-like VFS (RFC AL) — v1.4.0+

`Path` names Memory entries / Volume mounts / Documents by human-readable paths (`/docs/launch`)
over a `dirents` inode/dirent table. Six ops (`resolve`/`ls`/`stat`/`mkdir`(no-op)/`mv`/`rm`),
scope-aware (`agent`/`user`/`tenant`), `..` rejected, tenant-isolated. **Gate: `tools:
[Path]`** — no env flag, no separate scope policy (a dirent is a name, not an authority grant).
Resources opt into a name via `Memory.set path:` / `VolumeDef.create mount_at:` /
`Document.create_document path:`. **Also a direct MCP meta-tool** — call `path`
from the plugin without spawning a run (scope + tenant resolved server-side from the principal).
**Full reference:** [reference/path.md](reference/path.md).

## Document — chunked-graph documents (RFC AK) — v1.4.0+

`Document` is a tree of **chunks** (UUID, hierarchy, type, fields, edges, Markdown body) that agents
and humans co-author. Bodies live in Memory; structure lives in **SQL Memory** (queryable). Its ops cover
the document and chunk lifecycle, links and backlinks, tags, version history, type defs, image assets,
search, Markdown and canvas round-trips, federation with a peer loomcycle, and the entity tier below;
optimistic `revision` concurrency, atomic + orphan-free deletes. **Two
gates: `tools:[Document]` AND `LOOMCYCLE_SQLMEM_ENABLED=1`** (the structure tables live in SQL
Memory — the #1 "Document refused" cause). Scope `agent`/`user`/**`tenant`** (v1.41.0+ — tenant is
shared across the tenant and needs `tenant` in **both** `memory_scopes` and `sql_scopes`, since a
document spans both planes). **Also a direct MCP meta-tool** — `document`.
**Full reference:** [reference/document.md](reference/document.md).

## Entity memory — bi-temporal facts + the tenant ontology — v1.42.0+

Three Document ops make a document a **fact store that can be corrected without losing what it
corrected**. `upsert_chunk` writes by **`natural_key`** (unique per scope) so the same fact
extracted twice converges on one chunk instead of accumulating near-duplicates — the idempotency a
background consolidator needs; it takes no `revision`, and preserves any field you don't restate.
`supersede_chunk` retires a fact by stamping both end-timestamps and linking the replacement —
**the retired fact stays readable**, which is the point. `graph_recall` walks the relations
bidirectionally (one hop by default, up to 6) and is time-aware: `as_of` drops facts the store didn't believe at that
instant.

Two time axes, answering different questions: `valid_at`/`invalid_at` is **world** time (when the
fact was true), `created_at`/`expired_at` is **system** time (when the store believed it). Only the
world pair is caller-settable, so a retired fact **cannot be un-retired** — to retract a correction
you record another one, superseding the superseder. `class`
is `derived` or **`evidential`** — evidential material is exempt from retention pruning at any age,
because it's what everything else was distilled from.

The entity **types** are `base seed ⊕ tenant layer` (seed = POLE+O + `preference`/`fact`). The
tenant layer lives at `/memory/ontology` (tenant scope) and is **inert until an operator confirms
it** — the root chunk's `status` must be exactly `confirmed`, so flip it in the **Web UI → Settings
→ Ontology** tab rather than typing into the status field, where a typo leaves the layer silently
inactive.

Nesting in that document is a **type hierarchy** (v1.52.0): a child chunk is a **subclass** of its
parent, inheriting its fields, and a type filter on `list_facts`/`query_chunks` matches subtypes too
— so `type=event` returns `incident` rows. And since v1.53.0 **your agent cannot edit that document**:
on the ontology alone a run may only file a `proposed` entity, through `propose_entity`, which an
operator then accepts or rejects. Everything else there is refused.

**Verified writes (v1.54.0).** A fact can carry `source_quote` — the span of source text it was
drawn from — and a judge can be asked whether that span actually carries the claim. A fact that
fails is **withheld from `list_facts`/`graph_recall`, never deleted** (`include_refuted: true` reads
it back with the reason). Three things follow for an agent: pass the span when you write a fact;
never call `judge_fact` on your own writes, which is self-certification; and for a lookup question
try **`verbatim_answer`** before composing one, which returns the stored claim verbatim with its
citation, or a reason it will not. It refuses often, and a refusal means "answer normally", not
"there is nothing". **Full reference:**
[reference/document.md](reference/document.md).

> ⚠️ **After upgrading the runtime, reload the plugin.** The plugin ships no tool schemas — the thin
> client proxies the runtime's own `tools/list`, and Claude Code caches it **once, at connection**.
> A session opened against an older deployment keeps the old schema, and arguments it doesn't
> declare get sent as strings (`cannot unmarshal string into Go struct field …`). Reload, don't debug.

## Credentials — encrypted per-tenant secrets (RFC AR) — v1.10.0+

`CredentialDef` is an **encrypted-at-rest store for named API secrets** — a tenant (or a user)
stores its own provider/search/MCP keys and other Defs reference them **by name**, bound
server-side so the model never sees a value (`get`/`list` are metadata-only). **One env gate:
`LOOMCYCLE_SECRET_KEY`** (a base64 32-byte KEK) — **fail-closed**: unset ⇒ the store is disabled and
nothing is written (the #1 "credential refused" cause). AES-256-GCM + per-tenant HKDF key, AAD
row-binding, excluded from snapshots. **Direct MCP meta-tool `credentialdef`** (ops
`create`/`get`/`list`/`delete`; scope `tenant`/`user`/`agent`, `scope_id` derived from your identity,
never the wire; tenant-confined). Two consumption paths: **`$cred:<name>`** in an MCPServerDef
`env:`/`headers:` (per-user outbound channels — each user's own Telegram/Slack token), and a
**provider/tool key override by env-var name** (store `ANTHROPIC_API_KEY` / `BRAVE_API_KEY` → a
tenant's own key overrides the operator's host key, usage attributed to that scope).
**Full reference:** [reference/credentials.md](reference/credentials.md).

## Token budgets + usage (RFC AW / RFC AV) — v1.10.0+ / v1.11.0+

Per-scope **monthly token budgets** — a `soft` warning and a `hard` cap (refuse *new* runs at
admission; an in-flight run that crosses hard warns-but-finishes) on `operator`/`tenant`/`user`
calendar-month token totals (UTC; no row = unlimited; most-restrictive-wins; advisory, per-replica,
fail-open). Budgets are **set in the Web UI Limits console or over HTTP `GET/PUT/DELETE /v1/_limits`**
(gRPC `TokenLimit` + TS/Python `setLimit()` too) — **deliberately no MCP CRUD tool** (like steering).
But you **feel** them on the run tools: `spawn_run`/`spawn_runs` return a **`limits`** array on a soft
crossing, and a hard-over run is **refused at admission with `token_limit_exceeded`** (429 /
`ResourceExhausted`). Budgets count what the **RFC AV usage/cost ledger** reports (`GET /v1/_usage` /
the Web UI **Usage** page — tokens + money by tenant/user/provider/model/source; reporting only, also
not an MCP tool). **Full reference:** [reference/token-limits.md](reference/token-limits.md).

## Reference files (read on demand)

- **[reference/routing.md](reference/routing.md)** — providers + API-key env
  vars, the 4-layer resolver precedence, `tiers` / `user_tiers` / `models:`
  aliases / per-agent overrides, `fallback_on_error`, the four cookbook
  patterns (single/multi provider × single/multi user-tier), model kinds and the `decision:` block, and the
  per-agent `sampling:` (temperature/top_p/…), `context:` and `compaction:`
  blocks. Read this for any routing, decoding, decision-model,
  context-retention or compaction question.
- **[reference/hooks.md](reference/hooks.md)** — agent hooks: where a hook is
  attached, the events and what each may decide, hook definitions (`hookdef`),
  code hooks, fail-open vs fail-closed, secrets and host-widening. Read this for
  any "gate / check / audit an agent's tool calls" or "hold an answer" question,
  and when a config still uses the removed `register_hook` registry.
- **[reference/interactive.md](reference/interactive.md)** — interactive runs
  and steering, review holds, retune, and what each looks like over MCP and
  over HTTP.
- **[reference/volumes.md](reference/volumes.md)** — Volume primitive (v1.1.0+): `volumes:` block fields, per-agent binding, VolumeDef tool + gates,
  ephemeral volumes, spawn narrowing, migration from legacy jail vars, validation
  errors. Read this for any file-tool sandboxing, `VolumeDef`, or Phase 3
  migration question.
- **[reference/bashbox.md](reference/bashbox.md)** — Bashbox (RFC AJ, v1.3.0+):
  the true in-process gbash sandbox vs `Bash`, enablement
  (`LOOMCYCLE_BASHBOX_ENABLED` + `tools`), how it honors `ro` volumes, the
  operator host-command fallback (`LOOMCYCLE_BASHBOX_FALLBACK_*`), and gbash
  coverage caveats. Read this for any sandboxed-shell or `Bash`-vs-`Bashbox` question.
- **[reference/path.md](reference/path.md)** — Path primitive (RFC AL, v1.4.0+):
  the dirent model, the six ops, scopes + grammar, how resources opt into a name,
  the direct `path` meta-tool, and v1 caveats. Read this for any
  resource-naming / VFS question.
- **[reference/document.md](reference/document.md)** — Document primitive (RFC AK,
  v1.4.0+): chunked-graph documents, the content/structure split, the op catalogue, the
  **`LOOMCYCLE_SQLMEM_ENABLED` prerequisite**, optimistic concurrency, atomic
  deletes, and the direct `document` MCP tool. Read this for any
  chunked-document / co-authoring question.
- **[reference/credentials.md](reference/credentials.md)** — CredentialDef (RFC AR,
  v1.10.0+): the encrypted per-tenant/user secret store, the **`LOOMCYCLE_SECRET_KEY`
  fail-closed gate**, the `create`/`get`/`list`/`delete` ops + scopes, the direct
  `credentialdef` meta-tool, and the two consumption paths
  (`$cred:<name>` in MCP env/headers, and the provider-key override by env-var
  name). Read this for any bring-your-own-key / per-user-token / secret-store question.
- **[reference/token-limits.md](reference/token-limits.md)** — Token budgets (RFC AW,
  v1.11.0+) + usage/cost (RFC AV, v1.10.0+): per-scope monthly soft/hard ceilings,
  **why there's no MCP CRUD tool** (Web UI / HTTP `/v1/_limits` only), how a
  crossing surfaces on `spawn_run`/`spawn_runs` (`limits` array + `token_limit_exceeded`
  refusal), and the `/v1/_usage` reporting split. Read this for any budget /
  spend-cap / usage-report question.
- **[reference/profiles.md](reference/profiles.md)** — the six deployment
  profiles in full: trust posture, exact env set, yaml skeleton, and sharp
  edges per profile.
- **[reference/env-vars.md](reference/env-vars.md)** — the grouped environment
  variable catalogue (identity/listen, storage, tool sandboxes, providers,
  memory, scheduler/webhooks/A2A, code-js, multi-tenant, observability,
  cluster). Look up any `LOOMCYCLE_*` here before recommending it. Note: three
  vars are **retired (v1.1.0)** — see the tool-sandboxes section.
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
