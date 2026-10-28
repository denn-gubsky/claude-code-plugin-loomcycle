---
description: Mint, rotate, retire, or inspect loomcycle OperatorTokenDef bearer tokens — per-principal multi-tenant auth.
argument-hint: "<create|rotate|retire|get|list> [--name=<n>] [--tenant=<id>] [--subject=<s>] [--scopes=a,b] [--ttl=<sec>] [--agents=a,b] [--overrides=none|a,b] [--rate=<per_min>[/<burst>]] [--no-trace] [--def-id=<id>] [--grace=<sec>]"
allowed-tools: mcp__loomcycle__operatortokendef mcp__plugin_loomcycle_loomcycle__operatortokendef
---

# loomcycle operator-token

Manage the **OperatorTokenDef** substrate (loomcycle's multi-tenant
authorization). Each token binds an **authoritative principal**
`{tenant_id, subject, scopes}` resolved *from the token* — it overrides
the wire `tenant_id` / `user_id`, so per-subject fairness and per-tenant
isolation become real boundaries. Wraps the `operatortokendef` meta-tool.

**Operator-admin only.** The calling MCP bearer must carry `substrate:admin`
(see the note at the end). Parse `$ARGUMENTS`:

- First token = the op: one of `create | rotate | retire | get | list`.
- `--name=<n>` — token name (required for `create` and `list`; `create` /
  `rotate` / `retire` accept either `--name` or `--def-id`).
- `--tenant=<id>` — authoritative tenant (**required for `create`**;
  `[a-zA-Z0-9_-]{1,64}`).
- `--subject=<s>` — authoritative subject (optional on `create`; defaults to
  `tok-<name>`). Becomes the principal's authoritative `user_id`.
- `--scopes=a,b,c` — comma-separated scopes from the closed catalog.
  **Required for `create`**: an omitted list is refused. It used to default to
  `[substrate:admin]`, which turned a mistyped key into a full-power token. If
  the operator gave no scopes, ask which they want; never fill in admin.
- `--ttl=<sec>` — `ttl_seconds` (`create`). The token stops authenticating when
  it runs out, and a rotate does not extend it. Refused for a token holding
  `substrate:admin`. Omit for a token that never expires.
- `--agents=a,b` — `agents` (`create`). Limits the token to starting these agents
  as top-level runs, and to the run endpoints: definitions, team walks,
  schedules, channels, memory, documents, credentials and the model gateways are
  refused (`restricted_token`) whatever its scopes. An empty list is refused.
- `--overrides=none` or `--overrides=a,b` — `overrides` (`create`). `"none"` locks
  every per-run setting (model, provider, tier, effort, sampling, limits, …) for
  runs this token starts; a list names the settings it may still set. A locked
  setting is refused (`override_not_allowed`), never ignored.
- `--rate=<per_min>[/<burst>]` — `rate: {per_minute, burst}` (`create`). Past it
  a start is refused `rate_limited` with a time to wait.
- `--no-trace` — `retention: "none"` (`create`). Every run this token starts is
  a no-trace run: delivered to the caller, stored nowhere. No-trace runs refuse
  everything that needs stored content (interactive, review, sessions, steering,
  compaction, team walks).
- `--def-id=<id>` — existing def id (target for `get`; alternative target for
  `rotate` / `retire`).
- `--grace=<sec>` — rotation grace-window override (`rotate`); the old token
  keeps working this long after the new one is minted.

Call the `operatortokendef` tool of the loomcycle MCP server with the matching
shape; render results as markdown, not raw JSON.

### `create` — mint a new token
```json
{ "op": "create", "name": "<n>", "tenant_id": "<id>",
  "subject": "<s, optional>", "scopes": ["<scope>", …],
  "ttl_seconds": <sec, optional>, "agents": ["<agent>", …],
  "overrides": "none", "rate": {"per_minute": <n>, "burst": <m>},
  "retention": "none" }
```
Send only the restriction fields the operator asked for. A token that will
leave your hands (a bridge, a CI job, a customer's machine) is the case for
them: an expiry, an agent list and a locked override set make a leaked token
worth little.
Returns the def metadata **plus the token plaintext, shown ONCE**. The request
field is `scopes`; the response echoes it as `allowed_scopes`. Sending
`allowed_scopes` in a request is not the same key and is refused.

### `rotate` — mint a replacement, old token valid during the grace window
```json
{ "op": "rotate", "name": "<n>", "grace_seconds": <sec, optional> }
```
Also returns a **one-time plaintext** for the new token.

### `retire` / `get` / `list`
```json
{ "op": "retire", "name": "<n>" }          // or {"def_id": "<id>"}
{ "op": "get",    "def_id": "<id>" }
{ "op": "list",   "name": "<n>" }          // versions/lineage for a name
```
These never return a plaintext — only metadata (def_id, tenant, subject,
scopes, status, created/retired timestamps).

## Handling the one-time token plaintext — SECURITY

`create` and `rotate` return the secret **once and never again**. When you get a
plaintext back:

1. Surface it to the operator **exactly once**, clearly labelled, with the
   warning: *"Shown once — store it now (password manager / secret store); it
   is not retrievable later. Rotate if lost."*
2. **Never** write it to a file, commit it, or persist it anywhere on disk.
3. **Never** re-echo it in a later turn, summary, or confirmation — refer to it
   as "the token (already shown)".
4. It is the secret `LOOMCYCLE_AUTH_TOKEN`-class bearer for that principal —
   treat it like any `*_TOKEN`.

## The scope catalogue

The catalogue is closed; an unknown name is refused. Scopes are bound at mint
time, so authorising differently means minting a new token and retiring the old
one.

| Scope | Grants |
|---|---|
| `substrate:admin` | Everything, including minting tokens, snapshots and pausing the runtime. Satisfies every other scope. |
| `substrate:tenant` | Full power **inside one tenant**: runs, channels, and authoring every definition kind. Implies the four `runs:*` / `channel:*` scopes and `providers:operator-key`. No operator plane. |
| `substrate:user` | An **isolated member**: confined to its own user scope and its own runs. Implies `runs:create` and `runs:read`, and nothing tenant-shared. |
| `runs:create` | Start runs, and every write on a run: cancel, compact, retune, review, steer, resolve an interruption, run a team, ask a decision model. |
| `runs:read` | Read and list runs, and watch run state. |
| `channel:publish` | Publish to a channel and acknowledge a cursor. |
| `channel:read` | Subscribe to and peek a channel. |
| `providers:operator-key` | Lets a run fall back to the operator's own provider API key. Matters only where the operator turned key restriction on; omit it to make a tenant bring its own key. |
| `runs:delete` | Permanently delete a run tree (`delete_run_tree`). Implied by `substrate:tenant`; a member or isolated user has it only when granted at mint. |
| `llm:gateway` | The raw model endpoints (LLM gateway, OpenAI-compatible chat and embeddings). Implied by `substrate:tenant`; an isolated user needs it by name. |
| `auth:manage` | A sign-up website's user-management credential: the password gate's management API and user create/list/update/delete, across tenants, and nothing else. Minted **alone**. |

Pass the **narrowest** set. Omitted scopes are not granted.

**What a token for this plugin needs.** The plugin's commands map to scopes one
to one, and a token that lacks a tool's scope does not see that tool:

| To use | The token needs |
|---|---|
| `/loomcycle:run`, `fanout`, `cancel`, `compact`, `retune`, `review`, `steer`, `decide` | `runs:create` |
| `/loomcycle:runs`, `/loomcycle:files`, and reading a run | `runs:read` |
| `/loomcycle:whoami`, memory, documents, paths, definitions | nothing beyond being a non-isolated token of the tenant |
| `/loomcycle:access check` / `explain` / `simulate` | any token not limited to certain agents (it asks about itself) |
| `/loomcycle:access` groups, policies, bindings | `substrate:tenant` |
| `/loomcycle:operator-token`, `/loomcycle:snapshot` | `substrate:admin` |

Access-control rules can narrow any of this further. An explicit deny bound to
the token removes the tool from the session in every `LOOMCYCLE_ACL` mode, even
for an admin; under `enforce`, anything no rule allows is refused too.

So a token for day-to-day use from the IDE is `runs:create,runs:read` at the
least, or `substrate:tenant` for the whole tenant surface. A token minted with
`runs:create` alone can start a run and then cannot read it back.

## Static alternative — declared principals

Minting is the **runtime** way to create a per-principal token. For a **stable
service identity** you don't want to mint and rotate at runtime, the operator
can **declare** one in `loomcycle.yaml` instead:

```yaml
principals:
  marketing: { tenant: acme, subject: marketing, scopes: [runs:create, runs:read, substrate:tenant], token_env: LOOMCYCLE_TOKEN_MARKETING }
```

The secret lives in `.env.local` (`LOOMCYCLE_TOKEN_MARKETING=lct_…`); the same
token works for the plugin's `auth_token` **and** the Web UI login, so both act
as one `(tenant, subject)` identity. Resolution order is minted token → declared
principal → legacy. This is **not** an `operatortokendef` op — it is operator
config; suggest it when the user wants a fixed plugin/UI login rather than a
runtime-minted, rotatable token. See the README *"Tenant & declared-principal
tokens"* section and `examples/README.md`.

## Scope note — depends on the transport

`operatortokendef` is operator-admin-only. Since 0.21.0 the default stdio
transport is a **thin client** that proxies to the runtime's `/v1/_mcp`, so
authority is governed by the **`auth_token` principal on the upstream** — the
same enforcement as the direct HTTP transport:

- **admin `auth_token`** (or an **open-mode** runtime with no auth) — the
  principal carries `substrate:admin`, so this command works. The legacy
  `LOOMCYCLE_AUTH_TOKEN` resolves to an admin principal, so an operator driving
  their own runtime keeps full access.
- **scoped `lct_…` `auth_token`** — a narrow per-tenant bearer lacks
  `substrate:admin` and gets a `scope` refusal. Surface it plainly; it is **not**
  a plugin bug (a confined per-tenant key is *meant* to be unable to mint
  tokens). This applies to **both** the default stdio thin client and the direct
  HTTP transport in `examples/mcp-http-tenant.json` — both route through the
  principal-enforced `/v1/_mcp`.

## After `create` / `rotate` — if this is the plugin's own bearer

Creating the **first** admin `OperatorTokenDef` disables the legacy
`LOOMCYCLE_AUTH_TOKEN` for inbound HTTP. If the plugin's `auth_token` userConfig
is that legacy token, remind the operator to update it to a valid `lct_…` admin
bearer and **restart Claude Code** so the MCP server (and the HTTP-authed
auto-snapshot hook) picks up the new value — rotate within the grace window to
avoid a gap. See the README's *Token rotation runbook*. Never write the new
token to a file on the operator's behalf.

## Not every bearer is an operator token

Since v1.126.0 people and programs also get tokens through **sign-in gates**
(`loomcycle login`, the Web UI, a bridge signing in as an external gate). Those
are per-user tokens issued by the server, often with `authority: inherit`
(scopes follow the user's current access mode). They are not managed here; see
the `loomcycle-configure` skill's identity reference.

If the op is missing or unrecognised, list the five ops and stop rather than
guessing.
