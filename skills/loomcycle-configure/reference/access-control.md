# Access control reference (v1.122.0+; checked against v1.156.0)

A token's scopes name **kinds** of thing (`runs:create`, `substrate:tenant`), never
instances, and never deny. Access control adds authority **per user and per group**:
named **rule lists** (ACLs) of allow and deny rules, **groups** that nest, and
**bindings** that attach a list to a user, a group, a token or a whole tenant. That
is how an operator says "the support group may run `chat/*` but not `admin/*`, may
read the `shared-ro` volume but not write it, and never gets `Workspace`".

The rules are asked at every HTTP, gRPC and MCP gate, and **intersected with an
agent's own grants inside a run**. Nothing changes until an operator writes or
declares a list, or switches the rollout mode: `LOOMCYCLE_ACL` defaults to
`compat`, where the scope gates decide exactly as before.

**Since v1.140.0 every stored rule is either enforced or refused.** A rule that
names something no surface evaluates is refused when it is written
(`400 rule_not_enforceable`) instead of being stored and deciding nothing; the
table of what is asked where lives in the runtime (`internal/authz/enforced.go`),
held to the code by tests. Ask `acldef op=catalog` for what may be written.

---

## Who decides for the tenant — the four caller tiers (v1.140.0)

Scopes say which routes a token may call; *what a call may decide for the
tenant* depends on who calls. Every transport (HTTP, gRPC, MCP) stamps one of
four tiers on the call (an unstamped call is the lowest, `run`, so a forgotten
stamp fails closed):

| Tier | Who | What only it may do |
|---|---|---|
| **operator plane** | `substrate:admin`, the legacy `LOOMCYCLE_AUTH_TOKEN`, open mode, and `substrate:tenant` in its own tenant — each calling **from outside a run** | Confirm or adopt the tenant ontology, write the review policy, define a tenant-wide type, rule on proposals in any scope of its tenant, own the reserved names (`/memory/ontology`, `/memory/entities`, `/memory/tenant_root`), name any subject with `?scope_id=`, hold the tenant's lease, grant operator-grade capabilities to an agent it authors |
| **member** | a non-isolated tenant member (`runs:*` / `channel:*` user token) | Works in its own user scope as the operator does there. Reads and acts on **only its own** runs, sessions and user-scoped channels (v1.145.0). Proposes ontology entries instead of deciding them |
| **isolated** | `access_mode: isolated` (`substrate:user`) | Its own user scope only; never browses another subject |
| **run** | anything a model does inside a run, whatever token started it | Only what its agent's grants and its caller's rules allow — operator authority is never exercised from inside a run |

**What `?scope_id=` a member may pass** (off-run memory, Document, Path, feed and
asset routes): itself; a subject its rules let it **`browse`** — `browse
memory:user` or `browse document:user` with `owner_is_self: false` — and then
**read-only**; an agent it may run, read-only. Anything else is the same opaque
`404` for every subject. A member's write to any scope but its own user scope is
refused, and a memory browse grant does not read documents. A member's Path call
with no `scope` gets `400 scope_required`. To let a reviewer read a colleague's
scope:

```json
{"effect": "allow", "actions": ["browse"], "resources": ["memory:user", "document:user"]}
```

**A member's agents are held to a ceiling**, field by field: what its own rules
decide (tools, volumes — asked as `mount volume:<name>` — memory, SQL and history
scopes, user and agent crypto, decision models) up to what those rules allow;
**operator-grade fields** (`statement_methods`, `git_remote`, every
`*_def_scopes`, tenant and run crypto) must be unset, and so must the
`workspace` grant. A member also may not activate, retire or
delete a version of an agent or team an operator holds, nor `register_agent`
under such a name. MCP `erasure` needs `substrate:tenant`.

---

## The rule shape

A list is `{name, description, rules}`. Each rule:

```json
{"effect": "allow|deny", "actions": ["<verb>", ...], "resources": ["<type>:<selector>", ...], "when": {...}}
```

- **An explicit deny beats any allow.** Rule order never matters.
- **Parsing is strict.** An unknown field, resource type or verb is refused, at write
  and at read. A `when: {}` with no field is refused — omit `when` for "always".
- A rule may carry its own `description`.

### Resource selectors

A selector is `<type>:<name>`, and the name takes one of three shapes:

| Shape | Examples | Notes |
|---|---|---|
| `/`-glob | `agent:chat/*`, `agent:chat/**`, `tool:Workspace`, `mcp:jobs/patch*` | `*` is one segment, `**` any depth |
| scoped name | `memory:tenant`, `document:tenant:/kb/**`, `def:agent/chat/*`, `principal:user:support-*`, `credential:user:*` | `<scope><sep><glob>`; scope may be `*`; omitting the glob means every instance of the scope |
| enum | `gateway:chat`, `history:self`, `runtime:metrics` | exactly one of the type's values, or `*` |

### The catalog (types and verbs)

The catalog is closed: adding a type or verb is a code change. **`acldef op=catalog`
is the authoritative list** for the running build — it lists only the verbs some
surface asks, and a type's `type_level_only` verbs. Ask it before writing a rule.
At v1.156.0 the verbs that may be written are:

| Type | Writable verbs | Selector |
|---|---|---|
| `agent` | run, spawn; **read** (type-level only) | glob |
| `volume` | read, write, mount | glob |
| `tool` | invoke | glob (built-in tools: `tool:Workspace`, `tool:Git`) |
| `skill` | invoke; **read** (type-level only) | glob |
| `mcp` / `mcp-tool` | invoke / invoke | glob (`mcp:<server>/<tool>`; `mcp-tool:<name>` = a loomcycle MCP meta-tool) |
| `a2a` | invoke | glob |
| `memory` | read, write, browse | `user`, `agent`, `tenant`, `global` |
| `sqlmem` | read, write | `user`, `agent`, `tenant` |
| `document` | read, write, delete, link, browse, propose, review | `agent`, `user`, `tenant` (then `:<path glob>`) |
| `history` | read | enum `self`, `user`, `tenant`, `global` |
| `channel` | publish, subscribe, ack, await, broadcast, manage | glob |
| `def` | author, retire, read, manage | `def:<family>/<glob>`; families: agent, skill, team, mcpserver, schedule, webhook, volume, a2a, a2aserver, hook, credential, memorybackend, documentsource, acl, group, client |
| `team` | run, read, cancel | glob |
| `credential` | use, manage | `tenant`, `user`, `agent` |
| `crypto` | use | enum `tenant`, `user`, `agent` |
| `model`, `tier` | use | glob — asked wherever a model is resolved (v1.140.0, below) |
| `transport` | use | glob |
| `gateway` | use | enum `chat`, `embeddings`, `decide`, `speech`, `transcription` |
| `evaluation` | **read** (type-level only) | enum `self`, `siblings`, `descendants`, `any` |
| `run` | **read, delete, steer, cancel, compact, retune, review** (all type-level only) | enum `own`, `tenant` — but a rule must name `run:*` |
| `principal` | read, manage, mint | `user`, `group`, `token`, `scim` (`principal:token:metrics` = a tenant's scrape tokens, v1.149.0) |
| `runtime` | read, manage | enum: pause, snapshot, limits, retention, erasure, usage, routing, events, audit, config, tenants, metrics, telemetry |
| `git` | fetch, push | `git:<host>/<path>` (lowercase, no `.git`, no trailing `/`) |

**Refused at write as asked nowhere** (each with the reason): `steer` / `cancel` /
`review agent:` (a run is asked as `run:`), `provision volume:`, `author skill:` /
`team:` / `a2a:` (asked as `def:`), `read mcp:`, `expose a2a:`, `invoke client:` /
`localapi:` (asked as `tool:`), `recall memory:` (asked as `read`), `manage
crypto:`. **Removed from the catalog** (v1.140.0): `use search:`, `submit
evaluation:`, `raise` / `resolve interruption:` — a stored list still loads; every
write refuses them.

**Type-level-only verbs (v1.146.0).** The run verbs, `read agent:`, `read skill:`
and `read evaluation:` are asked only of **every** instance, never of a named one —
which runs a member reaches is decided by who started them, not by a rule. A rule
on one of them must name `<type>:*`; a selector naming some instances
(`deny read run:tenant`, `allow cancel run:own`, `read agent:secret/*`) is refused
with `400 rule_not_enforceable`. One stored earlier keeps its old effect — a deny
refuses nothing, an allow admits every instance — is reported at boot as
`type_level_only` and flagged with a `note` in `explain`. To keep an agent from a
caller, deny `run agent:<name>`; to keep a skill, deny `invoke skill:<name>`.

Because `acl` and `group` are `def:` families, authoring a list is itself an
access-control decision (`author def:acl/<name>`).

**The two statement verbs on `document`** (see
[knowledge-base.md](knowledge-base.md) and [document.md](document.md)):

- **`propose`** (v1.128.0) — file a relation for review without changing
  anything live: `propose_statement`, every `maintain_statement` action,
  `lease` / `release`. Narrower than `link` (which makes relations live and
  covers `accept_statement` / `reject_statement`); every built-in list grants
  it wherever it grants `read`. A principal with only `read` + `propose` cannot
  add evidence to an asserted relation.
- **`review`** (v1.133.0) — a **member's** ruling on proposed statements, asked
  on the statement's from-document: bulk rulings and their revert (the MCP
  `review` tool, `/v1/_statements/rule`), and since v1.134.0 a single
  `accept_statement` / `reject_statement` in the tenant scope too. Held only by
  a rule that names it — **no member baseline grants it**, and it implies
  nothing else (the member still needs `read` to see the queue rows):
  `{"effect":"allow","actions":["review"],"resources":["document:tenant:/board/**"]}`.
  Admins and tenant operators rule without it (with `write` on the
  from-document and `link` on both ends); isolated users, agent-limited tokens
  and runs are refused regardless. Applying a review policy stays operator-only.

### `when` — the closed condition set

Every field narrows; an absent field is always true. **A condition the request
cannot answer never holds.**

| Field | Shape |
|---|---|
| `transport` | list of `http`, `webui` (a Web UI session cookie), `mcp` (`/v1/_mcp` and the stdio server), `grpc`, `a2a`, `webhook`, `schedule` |
| `time` | `{days: [mon..sun], between: ["HH:MM","HH:MM"], tz: "Europe/Berlin"}` |
| `interactive` | bool — the run asked about (a resident child is interactive; outside a run, false) |
| `source_cidr` | list of CIDRs — the client address (below) |
| `owner_is_self` | bool |
| `agent` | glob on the run's agent (outside a run: no agent) |
| `depth` | `{max: N}` — spawn depth (outside a run: 0) |

**What changed in v1.140.0** (the boot log names every stored rule whose meaning
changed):

- **`transport: [http]` no longer covers MCP or the Web UI** — `/v1/_mcp` is now
  `mcp` and a Web UI request `webui`. A stored rule written for `http` alone must
  list them too. A transport no surface stamps (`bridge`, `bridge:<name>`) is
  refused at write.
- **`source_cidr` applies.** It reads the HTTP peer, or the client a peer in
  `auth.trusted_proxies` names; on gRPC the peer, or the client a peer in
  `auth.grpc_trusted_proxies` names (`auth.trusted_proxies` is never consulted for
  gRPC). The address that started a run is kept with it across a resume or
  restart; a webhook delivery and an A2A call carry their sender's. A schedule fire
  has no address, so a `source_cidr` condition holds for neither a deny nor an
  allow. A stored `source_cidr` deny that used to do nothing now refuses. A
  proxy list covering all of IPv4 or IPv6 no longer loads (v1.146.0–v1.147.0).
- **`tier` / `user_tier` are refused at write** — a run request names its own tier
  and nothing binds it to the caller. A stored one is inert (skipped whole).
- **`agent`, `depth` and `interactive` are filled** at run intake and in the run.

In a per-instance question (a Document, Path, credential or definition check)
only transport and clock are supplied, so a rule conditioned on `agent` or
`depth` never holds there.

---

## Groups

- A group lives in one tenant and holds **users** and **other groups**.
- Nesting is at most **8** deep; a cycle or a self-membership is refused.
- A group with an **`external_id`** belongs to an identity provider: adding or
  removing members and upserting it are refused with **`409 group_external`** —
  manage membership at the provider. Deleting it is allowed.
- `groupdef op=effective` returns every user the group holds through nested groups,
  config-declared members included.

## Bindings

A binding attaches one list to a subject:

| Field | Values |
|---|---|
| `acl` | the list's name |
| `subject_kind` | `user`, `group`, `token`, `tenant` |
| `subject_id` | the user's subject, the group's name, or the token's `def_id`; omitted for `tenant` |
| `expires_at` | optional RFC 3339; omitted (or `""`) = no expiry |

A binding to a list no layer has (a retired list and a `builtin:` name count as
missing), or with an `expires_at` already in the past, is refused with
**`400 acl_binding_invalid`**.

**Resolution:** a principal's rules are compiled from its groups (transitively),
the bindings that reach it, and its token class's built-in list, and cached until
the tenant's `acl_version` moves. Every write invalidates the caches on every
replica over the cluster bus.

---

## Declaring access control in config

Three top-level yaml blocks, validated at load by the engine's own strict parser —
a bad entry fails `loomcycle validate` and the boot:

```yaml
acls:
  support-tier-1:
    description: Support staff
    rules:
      - { effect: allow, actions: [run],       resources: ["agent:chat/*", "agent:support/**"] }
      - { effect: allow, actions: [read],      resources: ["agent:*"] }   # type-level only: must be agent:*
      - { effect: allow, actions: [read],      resources: ["volume:shared-ro"] }
      - { effect: deny,  actions: [invoke],    resources: ["tool:Workspace"] }
      - { effect: deny,  actions: [run],       resources: ["agent:admin/**"] }
      - effect: deny                   # no support agents at weekends
        actions: [run]
        resources: ["agent:support/**"]
        when: { time: { days: [sat, sun], tz: "Europe/Berlin" } }
groups:
  support:
    tenant: acme
    members: [alice, bob]
    groups: [support-contractors]     # nested group
  support-contractors:
    tenant: acme
    members: [carol]
acl_bindings:
  - { acl: support-tier-1, group: support, tenant: acme }
  - { acl: support-tier-1, user: dave, tenant: acme, expires_at: "2026-12-31T00:00:00Z" }
```

| Block | Shape |
|---|---|
| `acls:` | name → `{description, rules}` |
| `groups:` | name → `{tenant, description, external_id, members: [subjects], groups: [member groups]}` |
| `acl_bindings:` | list of `{acl, user \| group \| token \| tenant_wide: true, tenant, expires_at}` |

- Config rows merge **under** stored rows. **Since v1.140.0 a stored list may not
  take a config list's name, nor a tenant's list a shared list's name**
  (`409 acl_name_reserved`). A shadow stored before that still wins; boot and a
  config reload warn of each, and `explain` reports it as `shadowed_lists`. A
  binding in a tenant to a name both the tenant and a config or shared list hold is
  refused as ambiguous (`409 acl_name_shadowed`). A config list is reachable from a
  binding in any tenant; a config group or binding belongs to the tenant it names
  (`""` = shared).
- When the store also has a group of the same name, the members of both are unioned.
- Listings mark config rows `"source": "config"`; they are read-only over the API.
- A config reload applies on the next evaluation.

---

## Rollout: `LOOMCYCLE_ACL`

| Mode | Who decides | What happens |
|---|---|---|
| `compat` (default) | the scope gates, as before | an **explicit deny** bound to the caller is honoured on top |
| `shadow` | the scope gates | every disagreement with the engine is logged and audited `acl_shadow_diverged`; nothing is refused because of it |
| `enforce` | the engine | a question no rule allows → `403 acl_denied`; rules that could not be read → `503 acl_unavailable` (gRPC `Unavailable`), never admitted |

Under `shadow`, a run keeps every grant its agent gives, and each narrowing
`enforce` would apply at run start (a tool withheld, a volume made read-only or
dropped, a memory / SQL memory / history scope dropped or made read-only, a skill
deny) and each `spawn agent:` it would refuse is logged with the run id
(`acl_run_id`) and an `outcome` telling a deny from no match — once per question
per run tree; a resumed run records again.

### Built-in lists

Each token class carries a read-only built-in list that reproduces its reach, so
**`enforce` with no lists written behaves like `compat`**. A token's scopes remain
the ceiling. Names carry the `builtin:` prefix, which a stored list can never use.

| List | Applies to | Reach |
|---|---|---|
| `builtin:admin` | `substrate:admin` | every verb on every type |
| `builtin:tenant-operator` | `substrate:tenant` | every verb in its tenant except the operator plane; its MCP meta-tools by name |
| `builtin:member` | a non-isolated member | the collaboration plane: runs (shown as `run:*` since v1.146.0 — which runs is still its own, by tier), agents, its definitions, memory/SQL/documents in its own user scope and the shared scopes, `browse` only of itself, channels, its MCP tools by name (incl. `authz` and `review`, not `groupdef`/`acldef`/`aclbinding`/`ontology`/`telemetry`). Reaching `review` is not ruling: each statement asks the `review` verb, which this list does not hold |
| `builtin:isolated` | `substrate:user` | own scope only; denies tenant and global memory, tenant SQL memory and documents, tenant/global history; on MCP only `credentialdef`, `evaluation`, `authz` |
| `builtin:run-plane` | a token limited to certain agents | denies definition writes, `run team:*`, the gateways, schedule/webhook `manage`, and run deletion |

There is also `builtin:auth-manager` for the `auth:manage` user-management
credential (the user roster only), `builtin:metrics-reader` (v1.148.0) for a
`metrics:read` scrape token (`read runtime:metrics`; see
[observability.md](observability.md)), and `builtin:scim-provisioner` (v1.127.0)
for a `scim:provision` credential: `read` / `manage` on `principal:scim:*` in
its own tenant, `mint` denied on every principal — what `/scim/v2` asks (see
[identity.md](identity.md)).

Two consequences worth knowing: `builtin:run-plane`'s `deny run team:*` holds in
`compat` too, so **an agent-limited token's runs cannot start team walks** (and it
denies `use` on every gateway kind but the speech surfaces the token was granted);
and in `enforce` an isolated user is refused `GET /v1/_users`, which `compat`
admits.

**When the rules cannot be read in `compat`** (v1.140.0), a request keeps its class
baseline's explicit denies — an isolated user's tenant-wide data stays out of
reach — and each failure is counted in `loomcycle_acl_resolution_failures_total`
and audited `acl_resolution_failed`.

### Related environment variables

| Variable | Default | Meaning |
|---|---|---|
| `LOOMCYCLE_ACL` | `compat` | `compat`, `shadow` or `enforce` |
| `LOOMCYCLE_ACL_CACHE_TTL_SECONDS` | `5` | how long a replica trusts a compiled set before re-reading `acl_version`; `0` re-reads every request. Worst-case lag if a bus message is lost |
| `LOOMCYCLE_ACL_LIVE` (v1.126.0) | off | `1` makes a run in flight follow its caller's rules as they change (below) |
| `LOOMCYCLE_TOKEN_AUTHORITY_INHERIT` (v1.126.0) | off | `1` mints per-user and gate-issued tokens as `inherit` (see "Token authority") |

---

## Where the rules are asked

- **HTTP** middleware (after every existing check), **every gRPC RPC**, and the
  **MCP meta-tools**. A run intake also asks `run agent:<name>`.
- **MCP meta-tools are `mcp-tool:<name>`, verb `invoke`.** A tool a rule denies is
  **absent from `tools/list` and refused on call — for an admin too** (deny holds
  for every class). In `enforce`, an unmatched tool is refused.
- **Each MCP and gRPC operation asks the same question as its HTTP twin**
  (v1.140.0, completed v1.146.0), held by tests derived from the source. A tool
  whose ops are separate routes asks per op: `channeldef` create / update / delete
  / purge → `manage channel:<name>`; `retention_override` list → `read
  runtime:retention`, set / clear → `manage`; `erasure` report → `read
  runtime:erasure`, execute → `manage`; `telemetry` → `runtime:telemetry`. On
  these tools (and `review`, `ontology`) an unmapped op is refused `unknown_op`,
  and an `op` or `name` given twice or in two spellings is refused
  `ambiguous_arguments`. A Memory write over MCP or gRPC asks `write memory:*`
  (`write sqlmem:*` for `sql_exec` / `sql_begin`); a channel op asks the channel
  it names; releasing a team channel's held messages asks `manage channel`;
  `POST /v1/_memory/search` asks `read memory`.
- **`operatortokendef`** (v1.149.0) asks each op's own verb: `mint` for create and
  rotate, `manage` for retire, `read` for get and list, of `principal:token:*` (a
  tenant's scrape tokens: `principal:token:metrics`). The route itself asks only
  `read`, so an existing `deny mint principal:token:*` no longer hides token
  metadata — add `deny read principal:token:*` for that.
- **`use tier:` / `use model:`** (v1.140.0) are asked wherever a model is resolved:
  run start, a sub-agent, a provider fallback, a resume, a manual compaction or
  recap, OCR, image description, the LLM gateway; a decision model and the
  embedding model ask `use model:`. A denied tier refuses; a denied model is passed
  over for the tier's next candidate (a pinned model has none).
- **Git** asks `fetch` or `push` of `git:<host>/<path>` after the operator's host
  lists and the agent's `git_remote` (see [git.md](git.md)).
- **`mount volume:<name>`** is asked of each volume a member's agent grants; a deny
  keeps that volume out of the member's agents.
- **Per-instance checks**, on every transport and inside a run:

| Where | Question |
|---|---|
| Definitions (all families) | `get`/`list`/`verify`/`render_diagram` → `read def:<family>/<name>`; `retire`/`delete`/`purge` → `retire`; `create`/`fork`/`promote`/hook edits/any other op → `author`. A `def_id` is asked of the name it resolves to |
| Document | `read` / `write` / `delete` / `link` (and `propose` / `review` for statements) of `document:<scope>:<path>` at each Path name it is filed under (the bare scope if filed nowhere); a new document is checked against the name it is about to get. Ops that reach a whole scope (search, recall, upsert…) are refused when any rule denies part of it |
| Path | the type each entry names: `document:`, `memory:<scope>`, `volume:<name>`; `rm`/`mv` cover the whole subtree, `mv` under both names |
| CredentialDef | `get` → `use credential:<scope>:<name>`; every write → `manage` |
| TeamDef | `run` → `run team:<name>`; `poll` → `read`; `cancel` → `cancel` |
| Run-plane cancels | `cancel_run`, `POST /v1/runs/{id}/cancel`, gRPC `CancelTurn` of a team walk → `cancel team:<name>` |

Listings filter instead of refusing: Document `query_documents`,
`documents_summary`, `search`, `get_edges`, Path `ls` and CredentialDef `list` leave
out what the caller may not read.

---

## Inside a run

The agent's grants are **intersected** with the originating caller's rules, and
the caller's rules bind every sub-agent:

- a tool (built-in or mounted MCP / A2A / client) the caller may not `invoke` is
  **withheld from the model** and reported once as a **`capability_inert`** event
  with **gate `acl`**;
- a volume it may not `write` is bound **read-only**; one it may not `read` is
  **dropped**;
- memory, SQL memory and history scopes it may not `read` are **dropped**;
- **(v1.126.0) a write deny on `memory:<scope>` or `sqlmem:<scope>` makes that scope
  read-only**: `set`, `delete`, `merge`, `add`, `supersede`, `pending_ack`, the cursor
  ops, `sql_exec` and `sql_begin` are refused, reads still work, and
  `Context op=permissions` lists `read_only_scopes` / `sql_read_only_scopes`
  (before v1.126.0 such a deny left writes open);
- skill denies are appended to the agent's `skills:` patterns;
- the `Agent` tool asks **`spawn agent:<child>`** before starting a child;
- `Context op=self` reports an `acl` block: mode, version, groups, removed tools.

The set is taken at run start and kept for the run. With **`LOOMCYCLE_ACL_LIVE=1`**
the run re-reads its caller's rules before each model call and each tool call (a
cached lookup while `acl_version` is unchanged) and takes away what is no longer
allowed — tools, volumes, scopes, skills, and the per-call checks. It **only
narrows**: a binding added mid-run grants nothing new. Each change is a
`capability_inert` event (gate `acl`). If the rules cannot be read, `compat` and
`shadow` keep the last reading; `enforce` refuses tool calls with `acl_unavailable`
until a read succeeds. A tool call already running finishes.

### Runs that keep someone's rules after the request

| Run | Whose rules |
|---|---|
| resumed, snapshot-restored, crash-recovered, paused across a restart, queued at restart | the original caller's **current** rules (the run records who, never the rules or a bearer). Unreadable rules → the run stays paused or queued (`acl_unavailable`) |
| ScheduleDef / WebhookDef fire | the trigger's `acl_owner` (server-set at create/fork; a hook edit rebinds to the editor); asked `run agent:` or `run team:` |
| A2A run | the peer's own credential |
| team walk started over HTTP / gRPC / MCP | its starter's rules |
| team subscription walk (v1.126.0) | the **promoter's** rules; asked `run team:` for the promoter |

yaml-declared triggers record no owner and fire as before. A team **promoted
before v1.126.0** walks unbound (with a warning) until it is **promoted again** —
re-promote subscribed teams after upgrading. A denied schedule fire is recorded
`failed` (counts against `max_fires`); a denied webhook answers
`403 agent_not_allowed`, an unreadable one `503`.

---

## Refusal codes

| Code | Meaning |
|---|---|
| `acl_denied` (403) | a rule denied, or (`enforce`) none allowed. Body names `action`, `resource` and the denying `reasons` only |
| `acl_unavailable` (503, retryable) | the caller's rules could not be read; never admitted in `enforce` |
| `acl_self_elevation` (403) | a delegated writer tried to bind, join or edit what shapes its own authority |
| `acl_binding_invalid` (400) | binding to a missing/retired/built-in list, or an expiry in the past |
| `rule_not_enforceable` (400) | a rule (or an `authz` question, or a simulator draft) names a pair, condition or transport no surface evaluates, or names some instances of a type-level-only verb (v1.140.0 / v1.146.0) |
| `acl_name_reserved` (409) | a stored list would take a config list's name, or a tenant list a shared list's (v1.140.0) |
| `acl_name_shadowed` (409) | a binding names a list both the tenant and a config / shared layer hold |
| `audit_unavailable` (503) | an access-control write whose audit record cannot be written is refused (v1.147.0) |
| `unknown_op` / `ambiguous_arguments` | an MCP tool op with no HTTP twin, or `op` / `name` given twice (v1.146.0) |
| `group_external` (409) | member change or upsert on an IdP-owned group |
| `operator_plane` (403) | management called from inside a run |

Refusals and divergences are audited (`acl_denied`, `acl_unavailable`,
`acl_shadow_diverged`), never with a bearer.

---

## Managing access

One implementation behind four transports, so every gate holds on each.

| Family | MCP tool | Ops | HTTP |
|---|---|---|---|
| groups | `groupdef` | `list`, `get`, `effective`, `create`, `delete`, `add_member`, `remove_member` | `/v1/_groups`, `/v1/_groups/{name}`, `/v1/_groups/{name}/effective`, `/v1/_groups/{name}/members[/{kind}/{id}]` |
| lists | `acldef` | `create`, `update`, `put`, `get`, `list`, `retire`, `validate`, `catalog`, `names` | `POST /v1/_acldef`, `GET /v1/_acldef/names` |
| bindings | `aclbinding` | `list`, `create`, `delete` | `/v1/_aclbinding`, `/v1/_aclbinding/{id}` |
| questions | `authz` | `evaluation`, `evaluations`, `explain`, `simulate` | `POST /v1/_authz/{evaluation,evaluations,explain,simulate}` |

- **`groupdef` / `acldef` / `aclbinding` need `substrate:tenant`** (or admin); a
  member's or isolated user's `tools/list` does not show them. Confined to the
  caller's tenant; an admin focuses another with `tenant`.
- `acldef`: `create`, `update` and `put` are one write that bumps the version;
  `retire` takes a list out of force (a later `create` brings it back as a new
  version); `list` includes the built-in lists, `include_retired` the retired ones;
  `validate` checks rules without storing.
- Each op asks its own question: list writes need `author def:acl/<name>`, `retire`
  needs `retire`, `get` needs `read`; group writes need `manage`; binding writes need
  `author`. **A deny on authoring a list holds for a tenant operator too** — the way
  to stop an operator lifting a list that binds it.
- Every write is audited (`acl_written`, `group_written`, `binding_written`,
  `*_retired`, `*_deleted`) and takes effect on the next request on every replica.
  Since v1.147.0 the intent is recorded **before** the change, and a write whose
  audit record cannot be written fails with `503 audit_unavailable`.
- **An admin's list lock holds (v1.140.0).** Retiring a binding, deleting a group,
  removing a member, deleting / re-enabling / erasing a user and setting a group's
  `external_id` each ask `retire def:acl/<list>` of every list they would drop — so
  a deny on retiring a list keeps a tenant operator bound by it from escaping it
  that way. The removal sweeper, SCIM and gate group sync keep a deny-only list
  that is locked (audited `auth_unbind_kept_locked`). `explain` on
  `principal:group:<name>` names those lists (`governed_by`).
- **`authz`** is open to **any principal about itself**; naming another subject
  (`subject: {id}`) needs a tenant operator. `evaluation` takes `action: {name}`,
  `resource: {type, id?, owner?}`, optional `context` (transport, interactive, agent,
  depth, `source_ip`) and answers `decision`, `outcome` (`allow`, `deny`,
  `no_match`) and the deciding rules. `evaluations` batches up to 256 with
  `options.evaluations_semantic` (`execute_all`, `deny_on_first_deny`,
  `permit_on_first_permit`). `explain` shows every rule of the type and why it did
  or did not match, plus the applied bindings and groups. `simulate` evaluates
  `requests` now and against draft `acls` / `bindings` — **nothing is written**.
  `decision: false` with `no_match` in `compat`/`shadow` means the scope gate still
  decides.
- **gRPC:** `GroupDef`, `AclDef`, `AclBinding`, `Authz` RPCs (op-dispatched JSON).
- **CLI:** `loomcycle acl groups|policies|bindings|check|explain|simulate`, over
  HTTP; it never prints a bearer.
- **Web UI:** Settings → Access (groups, policies, bindings, a simulator); config
  rows show a "config · read-only" pill.
- `GET /v1/_me` reports `acl_mode`, `groups`, `acl_version` and `effective.surfaces`.

```
acldef      { "op": "catalog" }
acldef      { "op": "create", "name": "no-shell", "rules": [
              { "effect": "deny", "actions": ["invoke"], "resources": ["tool:Workspace"] } ] }
groupdef    { "op": "create", "name": "support" }
groupdef    { "op": "add_member", "name": "support", "kind": "user", "id": "alice" }
aclbinding  { "op": "create", "acl": "no-shell", "subject_kind": "group", "subject_id": "support" }
authz       { "op": "explain", "subject": { "id": "alice" },
              "action": { "name": "invoke" }, "resource": { "type": "tool", "id": "Workspace" } }
```

**Agent-side self-checks:** inside a run an agent asks its own rules with
`Context op=can` (one question or up to 32) and `op=reach` (the allow/deny patterns
for one type and action) — v1.126.0; [identity.md](identity.md) covers them.

**Erasure:** a tier-2 subject erasure removes the subject's user memberships and
user bindings and revokes its member tokens (tokens holding `substrate:tenant` or
`substrate:admin` are kept and named). Group bindings, groups, lists and
config-declared rows stay — remove those from the config file.

**Snapshots (v1.126.0)** carry lists, groups, members and bindings and restore them
before any paused run resumes; on a key the target already holds, the target's row
wins. Before v1.126.0 a restore on another instance had none.

---

## Token authority: frozen or inherit (v1.126.0)

| Mode | The token's scopes |
|---|---|
| `frozen` (default) | the user's `access_mode` grant **at mint**, fixed for the token's life |
| `inherit` | the user's **current** `access_mode`, re-read on every request — a promotion or demotion needs no re-mint |

- `LOOMCYCLE_TOKEN_AUTHORITY_INHERIT=1` makes `inherit` the default for
  `POST /v1/_users/{subject}/tokens` and every gate-issued token. A mint may ask for
  either with `"authority": "inherit" | "frozen"`.
- **Operator tokens and config `principals:` are always frozen.** Existing tokens
  keep their mode; a rotation keeps the mode.
- An inherit token stands only while its user exists and is `active`. Restrictions
  (`agents`, overrides, rate, retention) still only narrow.
- `GET /v1/_me` and `Context op=self` report `authority`.

---

## Rolling it out safely

1. **Write lists** (config `acls:` or `acldef`), starting with denies; bind them to
   a small group. `acldef op=validate` before storing.
2. **`authz op=simulate`** the bindings as a draft against real subjects.
3. **`LOOMCYCLE_ACL=shadow`** and run normal traffic, including long runs — shadow
   also reports in-run narrowing.
4. **Read `acl_shadow_diverged`** log lines and audit events; each carries an
   `outcome` (deny vs no match) and, for in-run narrowing, `acl_run_id`. Fix lists until
   only intended divergences remain.
5. **`LOOMCYCLE_ACL=enforce`.** Watch for `acl_unavailable` (store or bus trouble).
   Consider `LOOMCYCLE_ACL_LIVE=1` if long interactive runs must lose access promptly.

Remember that an explicit deny already applies in `compat` the moment it is bound.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| An agent "lost" a tool; transcript shows `capability_inert`, gate `acl` | the caller may not `invoke` it | `authz op=explain` for that caller and `tool:<name>`; adjust the list or binding |
| A memory write fails but reads work (v1.126.0+) | a `deny write` on `memory:<scope>` / `sqlmem:<scope>` | expected; check `Context op=permissions` `read_only_scopes` |
| An MCP meta-tool is missing from `tools/list`, even as admin | a rule denies `invoke mcp-tool:<name>`, or (`enforce`) none allows it | `authz op=explain` with `resource: {type: mcp-tool, id: <name>}`; reload the plugin after fixing |
| `groupdef`/`acldef`/`aclbinding` not listed | the token lacks `substrate:tenant` | use a tenant-operator or admin token |
| `403 acl_self_elevation` | a delegated writer touching a list/group/binding that shapes its own authority | have a tenant operator make the change |
| `400 acl_binding_invalid` | list missing, retired or `builtin:`, or expiry past | create the list first, or fix `expires_at` |
| `409 group_external` | the group has `external_id` (IdP-owned) | change membership at the identity provider |
| `403 operator_plane` | management tool called from inside a run | manage from outside a run (MCP session, HTTP, CLI) |
| Everything refused `503 acl_unavailable` in `enforce` | the rule store cannot be read | restore store connectivity; `compat`/`shadow` do not fail closed at the gate |
| A paused or queued run never resumes | its caller's rules cannot be read | same as above; it starts on a later pass |
| An agent-limited token's run fails `TeamDef run` | `builtin:run-plane` denies `run team:*` | use a token without an agent list for team walks |
| A team subscription ignores the promoter's denies | promoted before v1.126.0 | promote the team again |
| Rule edit not visible on another replica | bus message lost | wait `LOOMCYCLE_ACL_CACHE_TTL_SECONDS` (default 5) |
| A config list has no effect | a stored list of the same name shadows it | retire or edit the stored list |
| A rule with `when: {agent: ...}` never matches a Document/Path/credential check | instance questions supply only transport and clock | express it without `agent`/`depth` |
| `400 rule_not_enforceable` on a list that used to save | it names a verb asked nowhere, a removed verb (`use search:`, `submit evaluation:`, `interruption:`), a `tier` / `user_tier` condition, a `bridge` transport, or an instance of a type-level-only verb (`run:own`, `read agent:x/*`) | use `acldef op=catalog`; write `<type>:*` for run verbs and `read agent:` / `skill:` / `evaluation:`; deny `run agent:<name>` to keep an agent from a caller |
| A `deny … run:own` / `allow cancel run:own` stored before v1.146.0 does nothing / admits everything | type-level-only pair named by instance; flagged `type_level_only` at boot and `note` in `explain` | rewrite it on `run:*`; a member reaches only its own runs regardless |
| A deny written for `transport: [http]` no longer stops MCP or Web UI requests (v1.140.0+) | those transports are now `mcp` and `webui` | list `[http, mcp, webui]` |
| A `source_cidr` deny suddenly refuses (v1.140.0+) | stored `source_cidr` rules now apply | check `auth.trusted_proxies` / `auth.grpc_trusted_proxies` name your proxies, so the client address is the real one |
| `409 acl_name_reserved` | the list name belongs to a config or shared list | choose another name |
| A member gets `404` naming a colleague's `scope_id` | members reach another subject only through an explicit `browse` allow, read-only | bind `allow browse memory:user` / `document:user` (both, for documents) |
| A member's agent refused at create (`statement_methods`, `git_remote`, `*_def_scopes`) | operator-grade fields are above a member's ceiling | have a tenant operator author it |
| A model falls through to another candidate / a run refused naming a tier | a `use model:` / `use tier:` deny bound to the caller | `authz op=explain` with `resource: {type: model, id: <model>}` |
| `deny mint principal:token:*` no longer hides token metadata (v1.149.0+) | `get` / `list` ask `read` | add `deny read principal:token:*` |
| Access-control writes fail `503 audit_unavailable` | the audit store cannot take a row (v1.147.0+) | restore the store; reductions still go ahead |
| A demoted user's token still has old reach | the token is `frozen` | rotate it, or mint `inherit` tokens |
