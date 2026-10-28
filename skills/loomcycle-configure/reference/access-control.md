# Access control reference (v1.122.0+; checked against v1.126.0)

A token's scopes name **kinds** of thing (`runs:create`, `substrate:tenant`), never
instances, and never deny. Access control adds authority **per user and per group**:
named **rule lists** (ACLs) of allow and deny rules, **groups** that nest, and
**bindings** that attach a list to a user, a group, a token or a whole tenant. That
is how an operator says "the support group may run `chat/*` but not `admin/*`, may
read the `shared-ro` volume but not write it, and never gets `Bash`".

The rules are asked at every HTTP, gRPC and MCP gate, and **intersected with an
agent's own grants inside a run**. Nothing changes until an operator writes or
declares a list, or switches the rollout mode: `LOOMCYCLE_ACL` defaults to
`compat`, where the scope gates decide exactly as before.

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
| `/`-glob | `agent:chat/*`, `agent:chat/**`, `tool:Bash`, `mcp:jobs/patch*` | `*` is one segment, `**` any depth |
| scoped name | `memory:tenant`, `document:tenant:/kb/**`, `def:agent/chat/*`, `principal:user:support-*`, `credential:user:*` | `<scope><sep><glob>`; scope may be `*`; omitting the glob means every instance of the scope |
| enum | `run:own`, `gateway:chat`, `history:self` | exactly one of the type's values, or `*` |

### The catalog (types and verbs)

The catalog is closed: adding a type or verb is a code change. **`acldef op=catalog`
is the authoritative list** for the running build — ask it before writing a rule.
At v1.126.0:

| Type | Verbs | Selector |
|---|---|---|
| `agent` | run, read, spawn, steer, cancel, review | glob |
| `volume` | read, write, provision, mount | glob |
| `tool` | invoke | glob (built-in tools: `tool:Bash`, `tool:Git`) |
| `skill` | invoke, read, author | glob |
| `mcp` / `mcp-tool` | invoke, read / invoke | glob (`mcp-tool:<name>` = a loomcycle MCP meta-tool) |
| `a2a` | invoke, expose, author | glob |
| `client`, `localapi` | invoke | glob |
| `search` | use | glob |
| `memory` | read, write, recall, browse | `user`, `agent`, `tenant`, `global` |
| `sqlmem` | read, write | `user`, `agent`, `tenant` |
| `document` | read, write, delete, link, browse | `agent`, `user`, `tenant` (then `:<path glob>`) |
| `history` | read | enum `self`, `user`, `tenant`, `global` |
| `channel` | publish, subscribe, ack, await, broadcast, manage | glob |
| `def` | author, retire, read, manage | `def:<family>/<glob>`; families: agent, skill, team, mcpserver, schedule, webhook, volume, a2a, a2aserver, hook, credential, memorybackend, documentsource, acl, group, client |
| `team` | run, read, cancel, author | glob |
| `credential` | use, manage | `tenant`, `user`, `agent` |
| `crypto` | use, manage | enum `tenant`, `user`, `agent` |
| `model`, `tier`, `transport` | use | glob |
| `gateway` | use | enum `chat`, `embeddings`, `decide` |
| `evaluation` | submit, read | enum `self`, `siblings`, `descendants`, `any` |
| `interruption` | raise, resolve | glob |
| `run` | read, delete, steer, cancel, compact, retune, review | enum `own`, `tenant` |
| `principal` | read, manage, mint | `user`, `group`, `token` |
| `runtime` | read, manage | enum: pause, snapshot, limits, retention, erasure, usage, routing, events, config, tenants, metrics |
| `git` | fetch, push | glob (remote host and path) |

Because `acl` and `group` are `def:` families, authoring a list is itself an
access-control decision (`author def:acl/<name>`).

### `when` — the closed condition set

Every field narrows; an absent field is always true. **A condition the request
cannot answer never holds.**

| Field | Shape |
|---|---|
| `transport` | list of `http`, `grpc`, `mcp`, `webui`, `a2a`, `webhook`, `schedule`, `bridge`, or `bridge:<name>` |
| `time` | `{days: [mon..sun], between: ["HH:MM","HH:MM"], tz: "Europe/Berlin"}` |
| `interactive` | bool |
| `tier` / `user_tier` | list of tier names |
| `source_cidr` | list of CIDRs |
| `owner_is_self` | bool |
| `agent` | glob on the run's agent (inside a run) |
| `depth` | `{max: N}` — spawn depth |

In a per-instance question (a Document, Path, credential or definition check) only
transport and clock are supplied, so a rule conditioned on `agent`, `depth` or
`tier` never holds there.

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
      - { effect: allow, actions: [run, read], resources: ["agent:chat/*", "agent:support/**"] }
      - { effect: allow, actions: [read],      resources: ["volume:shared-ro"] }
      - { effect: deny,  actions: [invoke],    resources: ["tool:Bash", "tool:Bashbox"] }
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

- Config rows merge **under** stored rows: **a stored list of the same name shadows
  the config one** (as for agents). A config list is reachable from a binding in any
  tenant; a config group or binding belongs to the tenant it names (`""` = shared).
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
| `builtin:member` | a non-isolated member | the collaboration plane: runs, agents, its definitions, memory/SQL/documents in user, agent and tenant scopes, channels, its MCP tools by name (incl. `authz`, not `groupdef`/`acldef`/`aclbinding`) |
| `builtin:isolated` | `substrate:user` | own scope only; denies tenant and global memory, tenant SQL memory and documents, tenant/global history; on MCP only `credentialdef`, `evaluation`, `authz` |
| `builtin:run-plane` | a token limited to certain agents | denies definition writes, `run team:*`, the gateways, schedule/webhook `manage`, and run deletion |

There is also `builtin:auth-manager` for the `auth:manage` user-management
credential (the user roster only).

Two consequences worth knowing: `builtin:run-plane`'s `deny run team:*` holds in
`compat` too, so **an agent-limited token's runs cannot start team walks**; and in
`enforce` an isolated user is refused `GET /v1/_users`, which `compat` admits.

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
- **Per-instance checks**, on every transport and inside a run:

| Where | Question |
|---|---|
| Definitions (all families) | `get`/`list`/`verify`/`render_diagram` → `read def:<family>/<name>`; `retire`/`delete`/`purge` → `retire`; `create`/`fork`/`promote`/hook edits/any other op → `author`. A `def_id` is asked of the name it resolves to |
| Document | `read` / `write` / `delete` / `link` of `document:<scope>:<path>` at each Path name it is filed under (the bare scope if filed nowhere); a new document is checked against the name it is about to get. Ops that reach a whole scope (search, recall, upsert…) are refused when any rule denies part of it |
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
- **`authz`** is open to **any principal about itself**; naming another subject
  (`subject: {id}`) needs a tenant operator. `evaluation` takes `action: {name}`,
  `resource: {type, id?, owner?}`, optional `context` (transport, interactive, tier,
  user_tier, agent, depth) and answers `decision`, `outcome` (`allow`, `deny`,
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
              { "effect": "deny", "actions": ["invoke"], "resources": ["tool:Bash", "tool:Bashbox"] } ] }
groupdef    { "op": "create", "name": "support" }
groupdef    { "op": "add_member", "name": "support", "kind": "user", "id": "alice" }
aclbinding  { "op": "create", "acl": "no-shell", "subject_kind": "group", "subject_id": "support" }
authz       { "op": "explain", "subject": { "id": "alice" },
              "action": { "name": "invoke" }, "resource": { "type": "tool", "id": "Bash" } }
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
| A rule with `when: {agent: ...}` never matches a Document/Path/credential check | instance questions supply only transport and clock | express it without `agent`/`depth`/`tier` |
| A demoted user's token still has old reach | the token is `frozen` | rotate it, or mint `inherit` tokens |
