---
description: Ask what loomcycle's access-control rules decide (check, explain, simulate), and manage the groups, rule lists and bindings that make them.
argument-hint: "<check|explain|simulate> <action> <type>:<id> [--as=<subject>] | <groups|policies|bindings> <op> [args]"
allowed-tools: mcp__loomcycle__authz mcp__plugin_loomcycle_loomcycle__authz mcp__loomcycle__groupdef mcp__plugin_loomcycle_loomcycle__groupdef mcp__loomcycle__acldef mcp__plugin_loomcycle_loomcycle__acldef mcp__loomcycle__aclbinding mcp__plugin_loomcycle_loomcycle__aclbinding
---

# loomcycle access

loomcycle access control (v1.122.0+) has three parts:

- **rule lists**: allow and deny rules over actions and resources;
- **groups**: nested sets of users;
- **bindings**: these attach a list to a user, a group, a token or a whole tenant.

An explicit deny beats any allow, and the order of rules does not matter. This
command wraps four tools of the loomcycle MCP server:

| Part | Tool | Who sees it |
|---|---|---|
| `check`, `explain`, `simulate` | `authz` | any token not limited to certain agents, asking about itself; naming another subject needs a tenant operator |
| `groups` | `groupdef` | `substrate:tenant` and admin |
| `policies` | `acldef` | `substrate:tenant` and admin |
| `bindings` | `aclbinding` | `substrate:tenant` and admin |

A member's session has only `authz`. If a management tool is missing, the token
is not a tenant operator: say so; it is not a plugin fault.

For the rule language, rollout modes and yaml form, use the
`loomcycle-configure` skill's `reference/access-control.md`.

Parse `$ARGUMENTS`. The first token picks the part. A resource is written
`<type>:<id>` and split at the **first** colon: `tool:Bash` →
`{type: "tool", id: "Bash"}`, `document:tenant:/kb/**` →
`{type: "document", id: "tenant:/kb/**"}`. A bare `<type>` asks about the type as
a whole (no `id`).

---

## Questions — `authz`

### `check <action> <type>:<id> [--as=<subject>]`

```json
{ "op": "evaluation", "action": {"name": "<action>"},
  "resource": {"type": "<type>", "id": "<id>"},
  "subject": {"id": "<subject>"} }
```

Omit `subject` unless `--as` was given. Render one line: **allowed** or
**denied**, the `outcome`, and the rule(s) that decided it ("denied by list
`support` v3, rule 2").

- **`outcome: no_match`** means no rule spoke. In `compat` mode (the default),
  the token's scopes still decide such a request, so `no_match` is **not** a
  refusal there. Under `enforce` it is. Say which applies if the result carries
  the mode, otherwise state both readings.
- Several questions at once: send `op: "evaluations"` with an `evaluations`
  array (up to 256). Each item inherits `action`, `resource` and `context` from
  the top level when it leaves them out. Render the results as a table.
- Conditions (`when`) read the request `context`: `transport`, `interactive`,
  `tier`, `user_tier`, `agent`, `depth`. Pass `context` only when the user asks
  about a specific situation ("from the Web UI", "for a sub-agent").

### `explain <action> <type>:<id> [--as=<subject>]`

Same shape with `op: "explain"`. It returns every rule of that resource type,
whether it matched and why, plus the bindings that applied. Render a table:
list, version, rule index, effect, matched (yes/no), reason. Then say in one
sentence what decided the answer.

### `simulate`

Answers questions against a **draft** of lists and bindings laid over the stored
ones. Nothing is written. Build the call from what the user describes:

```json
{ "op": "simulate",
  "acls":     [{"name": "<list>", "rules": [ … ]}],
  "bindings": [{"acl": "<list>", "subject_kind": "group", "subject_id": "<group>"}],
  "requests": [{"subject": {"id": "<user>"}, "action": {"name": "run"},
                "resource": {"type": "agent", "id": "admin/reset"}}] }
```

A draft list replaces a stored list of the same name. Show each request's answer
**now** and **with the draft** side by side, and flag every one that changes.
Run a simulation before any `policies put` or `bindings create` that could lock
people out.

---

## Groups — `groupdef`

| Sub-op | Call |
|---|---|
| `groups list` | `{"op": "list"}` |
| `groups get <name>` | `{"op": "get", "name": …}`: members, plus the groups it sits in (`contained_in`) |
| `groups effective <name>` | `{"op": "effective", "name": …}`: every user it reaches through nesting, config members included |
| `groups create <name> [--description=…]` | `{"op": "create", "name": …, "description": …}`. **Rewrites** a group of that name. |
| `groups delete <name>` | `{"op": "delete", "name": …}` |
| `groups add <name> <user:id\|group:name>` | `{"op": "add_member", "name": …, "kind": "user"\|"group", "id": …}` |
| `groups remove <name> <user:id\|group:name>` | `{"op": "remove_member", …}`, same shape |

- Nesting is at most 8 deep; a cycle or self-membership is refused.
- A group with an `external_id` belongs to an identity provider or a sign-in
  gate. Changing its members is refused (`group_external`); deleting it is
  allowed.
- You cannot add yourself to a group unless you hold the tenant's whole
  authority (`acl_self_elevation`).

## Policies (rule lists) — `acldef`

| Sub-op | Call |
|---|---|
| `policies list [--retired]` | `{"op": "list", "include_retired": …}`. Built-in lists are included and read-only. |
| `policies names` | `{"op": "names"}` |
| `policies get <name>` | `{"op": "get", "name": …}` |
| `policies catalog` | `{"op": "catalog"}`: every resource type, verb and selector shape a rule may name. **Read this before writing rules.** |
| `policies validate` | `{"op": "validate", "rules": [ … ]}`: checks the rules and stores nothing |
| `policies put <name>` | `{"op": "put", "name": …, "rules": [ … ], "description": …}`. `create`, `update` and `put` are one write that bumps the version. |
| `policies retire <name>` | `{"op": "retire", "name": …}`: bindings to it then apply nothing |

A rule is `{effect: allow|deny, actions: [...], resources: ["<type>:<selector>"], when?: {...}}`.
Before a `put`: run `validate`, then `simulate` with the draft, and show the user
the diff from `get`. Write only after they confirm. A rule list stored at runtime
**shadows** a config-declared list of the same name.

Render lists as a table: name, version, source (`config` rows are read-only),
rule count, description. Render rules as a table: index, effect, actions,
resources, when.

## Bindings — `aclbinding`

| Sub-op | Call |
|---|---|
| `bindings list [--retired]` | `{"op": "list", "include_retired": …}` |
| `bindings create <list> <user\|group\|token\|tenant>[:<id>] [--expires=<RFC3339>]` | `{"op": "create", "acl": …, "subject_kind": …, "subject_id": …, "expires_at": …}`. Omit `subject_id` for `tenant`; a token is named by its `def_id`. |
| `bindings delete <binding_id>` | `{"op": "delete", "id": …}` |

- A binding to a list that does not exist, or with an expiry in the past, is
  refused (`acl_binding_invalid`).
- You cannot bind a list to yourself, your token, a group you are in or your
  tenant unless you hold the tenant's whole authority (`acl_self_elevation`).
- A tenant-wide binding reaches **everyone** in the tenant. Simulate first and
  confirm with the user.

---

## Things to know

- **Every write takes effect on the next request, on every replica.** Runs
  already going keep the rules they started with, unless the server sets
  `LOOMCYCLE_ACL_LIVE=1`; then they lose (never gain) access as rules change.
- **None of this works from inside a run** (`operator_plane`). An agent checks
  its own reach with `Context op=can` / `op=reach`.
- `tenant` is **admin only**: an admin may focus another tenant with it. Anyone
  else always acts in their own tenant, so leave it out.
- Refusals: `acl_denied` (a rule said no), `acl_unavailable` (rules could not be
  read; under `enforce` that refuses rather than admits), `acl_self_elevation`,
  `acl_binding_invalid`, `group_external`. Relay the code and the rule it names.

If the part or op is missing or unrecognised, list the parts and their sub-ops
and stop rather than guessing.
