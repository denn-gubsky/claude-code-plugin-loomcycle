# Identity and sign-in reference (v1.123.0+; checked against v1.126.0)

Two questions, one page:

1. **What can an agent know about who it works for?** — `Context op=self` /
   `op=can` / `op=reach`, the read-only `Identity` tool, and the
   `{{identity}}` system-prompt placeholder (all v1.126.0).
2. **How do people and programs sign in?** — stored user records with an
   approval queue, Web UI sessions and `auth.mode` (v1.123.0), and the sign-in
   *gates*: password, OIDC, OAuth (v1.123.0); external, header, AWS IAM and
   device, `loomcycle login`, and app sign-in through `auth.clients` /
   `ClientDef` (v1.126.0).

Users are **stored records** now. Each has a `status` — `active`, `disabled` or
`pending` — an `access_mode` (`isolated`, `tenant`, …), groups, and the sign-in
identities linked to it. A `pending` user has signed in but waits for an
operator's approval and can do nothing else.

---

## Agent side: what a run knows about its person

### `Context` (no extra grant)

Self-knowledge lives in `Context`, keyed only by the run's own identity.

| op | What it returns |
|---|---|
| `self` | Besides the agent/run/scope facts: `principal` (the credential the run acts under: `tenant_id`, `subject`, `scopes`, `is_admin`, `legacy`, `token_def_id`, `token_suffix`, and `authority` = `frozen` or `inherit` — never the token itself); `identity` (below). |
| `can` | "May I do this?" — `action` + `resource: {type, id}`, or `queries` with **at most 32** `{action, resource}` pairs. Answered by the same evaluation the access checks make, so it cannot disagree with them. |
| `reach` | "What of this kind may I act on?" — `type` + `action` → the `allow` / `deny` name patterns (`*` one segment, `**` many; deny overrides), `unmatched` (`scopes` or `denied`), `conditional`, and for `type: tool` the `removed_tools`. |

The `identity` block of `op=self` (absent when the run acts for nobody):

| Field | Meaning |
|---|---|
| `tenant_id`, `subject` | Who the run acts for. |
| `display_name`, `access_mode`, `status`, `created_at` | From the user record; absent when there is none (an operator token, a credential of another tenant). |
| `groups` | Each `{name, via, description?, external_id?}` — `via` is `direct` or the group it comes through. |
| `acl` | `{mode, version, baseline, lists, missing_acls, removed_tools}`; each list is `{name, version, bound_to: {kind, id?}}`. |
| `auth` | How they signed in: `{gate, amr, auth_time}` for a browser sign-in, `{gate}` for a gate-issued token; absent for an operator token. |
| `identities` | Linked sign-in accounts, each `{gate, email_verified, email?, last_login_at?}` — `email` only when the gate verified it. |

`can` returns `{decision, outcome, mode, allowed, reasons?, fallback?}`.
`outcome` is `allow`, `deny` (always wins) or `no_match`. **`allowed` is what
will actually happen**: in `enforce` it equals `decision`; in `compat` a
`no_match` falls back to scopes and grants (`fallback: "scopes"`); in `shadow`
the rules are only observed. `can` and `reach` answer `access control is not
active for this run` when no rules apply — then the definition's grants decide
(`op=permissions`). Being allowed never grants a tool the agent was not given.

### A `pending` account is a hard stop

When `identity.status` is `pending`, the agent must tell the user plainly that
their account awaits approval, and **do no work for them** — no sub-agents, no
memory or document writes, no messages or calls that act for them. Questions
about the account itself are fine; never suggest a way around the approval.
Approval happens outside the run.

### `{{identity}}` in a system prompt

Any definition may put `{{identity}}` in its `system_prompt`. At run start,
sub-agent spawn and resume it expands to an `<identity>` block: display name,
status, groups and the tools the person's access rules withheld — framed as
reference data, not instructions.

- A **snapshot**: a group change mid-run does not reach the prompt; `Context
  op=can` answers live.
- A `pending` account adds a line telling the agent not to do real work.
- Renders **nothing** when the run acts for nobody (open mode, an ownerless
  trigger) and nothing in a team node's `system` / `input` template.
- Values are folded to one line and bounded (16 groups, 16 tools, then a count).

### The `Identity` tool — the tenant directory

`Identity` looks up the **other** people and groups of the run's tenant. It is
granted by name and is **read-only** — no op changes a person, group or
binding; approvals and group changes are an operator's.

```yaml
agents:
  helpdesk:
    tools: [Identity, Context]
    system_prompt: |
      You help the person below find the right colleague.
      {{identity}}
```

| op | What it does | Main arguments |
|---|---|---|
| `profile` | display name, declared names, the profile's **Public** section | `subject` |
| `user` | `profile` plus `status`, `groups` (with `via`), `access_mode` for a manager | `subject` |
| `users` | search people (≤200 rows/page, default 50, `next_cursor`) | `query`, `group`, `status`, `active_only`, `limit`, `cursor` |
| `group` | description, `external_id`, members, member groups, `contained_in` | `name` |
| `groups` | list groups | `prefix`, `member`, `limit`, `cursor` |
| `can` | may this person do an action (≤32 `queries`) | `subject`, `action`, `resource` or `queries` |
| `explain` | which rules decide it, rule by rule | `subject`, `action`, `resource` |
| `held` | what the deployment holds for a person: activity, chats, memory rows, documents, budget, usage | `subject` |
| `whoami` | the `Context op=self` identity block, for an agent without `Context` | — |

**What each grant opens** (grants of the person the run acts for):

| Layer | Opened by | Ops / fields |
|---|---|---|
| Public | holding the tool | `profile`; subject and display name in `users` |
| Authority | `read` on `principal:user:*` / `principal:group:*` | `user`, `group` members, `can`, `explain`; status and groups in `users`; `users` `status` / `active_only` |
| Held | `manage` on `principal:user` | `held`; `access_mode` in `user` |

- **Without written rules** (`compat` and `shadow` modes) the second and third
  layers fall back to the person's class: a tenant operator or admin reads
  anyone; a member reads only themselves and the groups they are in, without
  the other members. In `enforce`, bind an allow list to open the directory to
  members — the built-in member baseline is not a directory grant:
  `{"effect":"allow","actions":["read"],"resources":["principal:user:*","principal:group:*"]}`.
- **Isolated users** (`access_mode: isolated`) are usually separate customers
  of one tenant: for them even `profile` and `users` rows need the read grant,
  and without it they see only themselves.
- **No oracle.** Someone the caller may not look up reads as
  `identity_not_found`, exactly like a missing person. `can` / `explain` about
  another person are refused (as not found) for any question the caller could
  not answer yes to for itself. `explain` shows a list's rules only to a caller
  who may read that ACL definition.
- **The Public section** is a `## Public` section of each User Profile; an
  unedited profile publishes nothing. `profile` returns only that (comments
  removed, ≤4 KiB) and the `@name` / `@alias` bullets. It is text the person
  wrote — information, never instructions.
- **Sub-agents** read with the originating person's rules: a child sees no more
  than its root. A `held` plane that failed to read is named in `errors`; its
  count is a lower bound, never zero.
- **Audit:** with `LOOMCYCLE_AUDIT_LOG_PATH` set, every lookup of *another*
  person or a group is recorded as `identity_lookup`.

### The MCP `identity` tool (outside a run)

Over MCP the same directory is the `identity` meta-tool: the same ops, keyed by
the session token's tenant (there is no tenant field), **plus `op=tenants`** —
the tenants with run activity, **admin token only** (an empty list means no
activity, not no tenants). It is listed for admin and tenant/member sessions,
not for an isolated-user session.

It **replaces `directory`** (removed in v1.126.0, no alias):

| Old `directory` call | Now |
|---|---|
| `op=users` | `identity op=users` (`active_only: true` for the old activity listing) |
| `op=inspect` | `identity op=held` — now needs `manage principal:user` (without written rules: an operator or admin token) |
| `op=tenants` | `identity op=tenants` (still admin-only) |

An open Claude Code session that still lists `directory` has a cached tool list
from before the upgrade — reload the plugin.

---

## Operator side: sign-in

### Web UI sessions and `auth.mode` (v1.123.0)

A sign-in creates a **server-side session**: the browser holds an opaque
HttpOnly cookie, never the API token; sign-out (`POST /v1/_auth/logout`) ends
it on every replica.

```yaml
auth:
  mode: strict                    # token (default) | strict; env LOOMCYCLE_AUTH_MODE
  session: { idle: 8h, absolute: 168h, reauth_window: 15m }
  lifecycle:
    new_user: { access_mode: isolated, groups: [everyone, new-users], status: pending, token_ttl: 12h }
  gates:
    paste: { kind: token, label: "Access token" }
```

- **`token`** (default): the paste box is always offered, gates or not.
- **`strict`**: only the listed gates; the paste box only if a `kind: token`
  gate is listed; the old bearer cookie, login handoff and WebSocket
  subprotocol bearer are off; sessions need HTTPS unless
  `LOOMCYCLE_UI_INSECURE_COOKIES=1`. Strict with no interactive gate fails the
  load; a reload cannot lower the mode (restart). API bearers are unaffected.
- **`LOOMCYCLE_PUBLIC_URL`** is what makes a request behind a TLS terminator
  count as HTTPS (no forwarded header is trusted), and it is **required** by
  the password, OIDC, OAuth, external and device gates and by app sign-in.
- A session never outlives or out-reaches its token: a retired token, a changed
  secret or pepper, or a different User-Agent ends it.
- **Approval queue:** `new_user.status: pending` (recommended for strict)
  lets a newcomer reach only an "awaiting approval" page until an operator
  approves them in the Users console (`POST /v1/_users/{subject}/approve`).

### Gate kinds

A gate name is lowercase letters, digits, `-`, `_` (≤32). Client and gate
secrets are always an **env var name** (`*_env`); a literal or a `$cred:`
reference is refused. `identity_map` decides the tenant and provisioning
(`provision: never | known` (default) `| auto`, auto at the
`auth.lifecycle.new_user` floor); the gate's assertion never picks the tenant.
Only a gate with `trusted: true` may grant more than the floor or sync groups,
and only into its own `<gate>:` groups.

| kind | Use when | Key fields |
|---|---|---|
| `token` | people paste a loomcycle token (at most one) | `label` |
| `password` | loomcycle keeps logins and passwords (own sign-up, invites) | `require_mfa`, `invites`, `resets`, `new_user`, `trusted`; needs `LOOMCYCLE_SECRET_KEY` + `LOOMCYCLE_PUBLIC_URL`. Managed under `/v1/_authgate/{gate}/…`; no route ever takes a password |
| `oidc` | Google Workspace, Entra, Okta, Keycloak, Cognito, IAM Identity Center, Auth0, any OIDC IdP | `preset`, `client_id`, `client_secret_env`, `issuer` (most presets), `allowed_domains` (required for `google`), `identity_map`. Redirect URI `<PUBLIC_URL>/v1/_auth/complete/<gate>` |
| `oauth` | GitHub, GitLab, Gitea, a generic OAuth 2.0 provider (no ID token) | `preset`, `client_id`, `client_secret_env`, `base_url`, `allowed_orgs` + `require_org` (or `allow_any_account`) for public github.com / gitlab.com |
| `external` | a program — chat bridge, website, broker — signs who it talks to with its own key | `public_key` (Ed25519 / P-256 JWK) or `hmac_secret_env`, `issued_token`, `identity_map`, optional `callback_url` for browser login |
| `header` | a proxy already signed the person in | `preset`: `cloudflare-access` (`team_domain`, `audience`), `aws-alb` (`alb_arn`), `forward-auth-hmac` (`secret_env`); `trusted_proxy_cidrs` always required |
| `awsiam` | AWS workloads get API tokens (never on the login page) | `allowed_arns` (literal 12-digit account), `server_id`, `sts_regions`, `identity_map` |
| `device` | a terminal or headless client signs in by device code | needs `LOOMCYCLE_PUBLIC_URL`; approved on the `/ui/device` page |

Subjects are `<gate>:<id>` — the provider's `sub` or numeric user id, never an
e-mail or a renameable login. Password, header and AWS IAM gates are built at
boot: a reload that adds one leaves it refusing until a **restart**.

```yaml
auth:
  mode: strict
  lifecycle:
    new_user: { access_mode: isolated, groups: [everyone, new-users], status: pending }
  gates:
    google:
      kind: oidc
      preset: google
      label: "Sign in with Google"
      client_id: 1234.apps.googleusercontent.com
      client_secret_env: LOOMCYCLE_GATE_GOOGLE_SECRET   # a NAME; the value lives in .env.local
      allowed_domains: [acme.com]
      identity_map: { tenant: acme, provision: auto }
    telegram:
      kind: external
      public_key: { kty: OKP, crv: Ed25519, x: "<the gate key's public x>" }
      issued_token: { ttl: 12h, agents: [chat], max_active: 2 }
      identity_map: { tenant: acme, provision: auto, legacy_subject_prefix: telegram- }
```

### External gates in depth (v1.126.0)

The gate holds **no loomcycle token**; it signs a short JWT (≤5 minutes,
`aud` = `LOOMCYCLE_PUBLIC_URL`, single-use `jti`) and loomcycle provisions the
user and issues the token. A stolen gate key can speak only for that gate's
people, at that gate's ceiling.

| Route (no bearer — the signature authenticates) | Purpose |
|---|---|
| `POST /v1/_auth/assert {gate, assertion}` | a token for one person, held to `issued_token` (`ttl` ≤30 days, `agents`, `overrides`, `rate`, `max_active` 0–100) |
| `POST /v1/_auth/revoke {gate, request}` | the person is gone — starts removal |
| `POST /v1/_auth/sync {gate, request}` | bulk provisioning and group sync; `complete: true` (with `authoritative_for_users`) removes omitted users, capped by `max_sync_removals` (default 10%, never fewer than 5) |
| `GET /v1/_authgate` (admin) | the gates and key fingerprints; `?probe=1` probes them |

- `amr` is always `[ext]` — a gate never stands in for a second factor.
- Two gates may not share a key; a gate is config-only (a key is a trust anchor).
- **Removal** (`auth.lifecycle.on_removed`, or a gate's own `on_removed`):
  `{disable: at_once, unbind_after: 7d, erase_after: never, reactivate: operator}`.
  Disable ends sessions and retires tokens; unbind drops gate-managed groups and
  the user's own ACL bindings; erase (≥24h, needs `LOOMCYCLE_AUDIT_LOG_PATH`)
  runs subject erasure. `dormant_after` (default `never`, ≥24h) starts removal
  for someone with no sign-in for that long. Re-activating returns a user to
  the new-user defaults, not their old groups.
- **Bridges as gates:** `@loomcycle/bridge-core` 0.3+ runs a bridge this way
  (`BRIDGE_GATE*` settings; the bridge's own token is refused then).
  `identity_map.legacy_subject_prefix: telegram-` makes a person's first login
  link the old `telegram-42` user instead of creating `telegram:42` — only a
  user with no password and no gate identity. External gates only.

Every gate-issued token stops at once when its user is no longer `active` or
its gate is taken out of the config, on every replica.

### Per-tenant gate policy

`auth.tenant_policies` (and `GET` / `PUT` / `DELETE /v1/_auth/tenant-policies`,
deployment administration) limits a tenant's people to named gates. It is
checked on every token use, at session creation, token issue and device
approval.

### `loomcycle login` — a terminal signs in (v1.126.0)

`loomcycle login` runs the device-code flow against a `kind: device` gate: it
shows a code, a person approves it on `/ui/device` from a **Web UI session**
(never a bearer), and the token — living no longer than the approving session —
goes into the **OS keychain** (macOS `security`, Linux `secret-tool`). It is
never printed, written to a file or taken from the command line. Windows is
refused (use `LOOMCYCLE_MCP_UPSTREAM_TOKEN`). `loomcycle logout` retires the
token (`POST /v1/_auth/token/revoke`); `loomcycle auth status` reports it.

**Why it matters for this plugin:** `loomcycle mcp --upstream` — the thin client
this plugin launches — uses the keychain token when
`LOOMCYCLE_MCP_UPSTREAM_TOKEN` is not set. The plugin passes that variable from
its `auth_token` setting, so a configured token always wins.

### App sign-in — `auth.clients` and `ClientDef` (v1.126.0)

loomcycle is an **OAuth 2.0 authorization server for its own registered apps**
(authorization code + PKCE S256 only; no OIDC `id_token`, no consent screen).
The app sends the person to loomcycle's login page, which offers the configured
gates, and gets a short-lived token for that same user in that same tenant.

```yaml
auth:
  clients:
    loomboard:
      kind: public                       # the only kind; confidential is refused
      label: loomboard
      redirect_uris: [https://board.example.com/auth/callback, http://127.0.0.1/callback]
      allowed_origins: [https://board.example.com]
      access_token_ttl: 1h               # 1m–24h
      refresh: { idle: 7d, absolute: 30d }
```

- Routes: `GET /v1/_oauth/authorize`, `POST /v1/_oauth/token`,
  `POST /v1/_oauth/revoke`, metadata at
  `/.well-known/oauth-authorization-server` (404 until `LOOMCYCLE_PUBLIC_URL`).
- Redirect URIs are matched exactly: `https`, loopback `http` (any port), or a
  private-use scheme. Codes are single-use, 60 s; a reused refresh token ends
  the whole sign-in. A `pending` user gets `access_denied`, no code.
- The token never exceeds the user: scopes from `access_mode`, capped by the
  session and the client's `restrictions`. Web UI sign-out does not end it.
- **Runtime clients:** the MCP `clientdef` tool (or `POST /v1/_clientdef`) —
  ops `create`, `update`, `get`, `list`, `retire`, `verify`; fields under
  `client`. Needs `substrate:tenant`: a tenant operator registers apps for its
  own tenant (which sign in only its people); an admin for any tenant, or every
  tenant with `tenant` empty. Config clients are read-only. `retire` ends every
  sign-in through the app at once. ClientDefs are not snapshotted.

### Token authority: frozen or inherit

| Mode | Scopes | Default for |
|---|---|---|
| `frozen` | the user's `access_mode` grant **at mint**, fixed | every token unless `LOOMCYCLE_TOKEN_AUTHORITY_INHERIT=1`; operator tokens and config `principals:` always |
| `inherit` | the user's **current** `access_mode`, re-read each request | with the switch on: per-user tokens (`POST /v1/_users/{subject}/tokens`) and every gate-issued token |

A mint may ask `"authority": "inherit" | "frozen"` explicitly. An inherit token
is refused once its user is disabled, pending or deleted; restrictions
(`agents`, `overrides`, `rate`, `retention`) still only narrow. `Context
op=self` reports the mode as `principal.authority`.

### The `auth:manage` scope

A website's user-management token, minted with `scopes: ["auth:manage"]` alone:
it reaches only the password gate's management routes and `/v1/_users` list /
create / update / delete in a tenant it names — no runs, data or gRPC. It may
bootstrap a tenant's owner once and is refused any change to a user above the
gate's provisioning floor (`403 target_beyond_floor`).

---

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `identity_not_found` for a person who exists | The caller lacks the read grant (or is an isolated user). A refusal and a miss look the same on purpose; the audit log tells them apart. |
| MCP `directory` is unknown / `identity` missing | `directory` was removed in v1.126.0. Use `identity`; reload the plugin so the cached tool list refreshes. |
| `identity op=tenants` refused | Admin token only. |
| `identity op=held` refused (as not found) | Needs `manage principal:user` — without written rules, an operator or admin token. |
| `Context op=can`: `access control is not active for this run` | No rules apply; the agent's grants decide — use `op=permissions`. |
| A new user sees only "awaiting approval" | `status: pending`; approve in the Users console or `POST /v1/_users/{subject}/approve`. |
| Strict mode: config fails to load | No interactive gate listed — add a password, OIDC or OAuth gate, or a `kind: token` gate. |
| Strict mode: session cookie refused | Plain HTTP. Serve HTTPS with `LOOMCYCLE_PUBLIC_URL=https://…`, or set `LOOMCYCLE_UI_INSECURE_COOKIES=1` on a trusted path. |
| Password / OIDC / external gate fails to load | `LOOMCYCLE_PUBLIC_URL` unset (password also needs `LOOMCYCLE_SECRET_KEY`), or a literal secret instead of an `*_env` name. |
| OIDC/OAuth provider: redirect URI mismatch | Register exactly `<LOOMCYCLE_PUBLIC_URL>/v1/_auth/complete/<gate>`. |
| `github` / `gitlab` gate refuses to load | On the public instance it needs `allowed_orgs` + `require_org: true`, or `allow_any_account: true`. |
| A gate added by config reload refuses everyone | Password, header and AWS IAM gates are built at boot — restart. |
| Header-gate session ends on its own | Every request must carry a valid assertion for the same person; signing out at the proxy ends it. `503 gate_unavailable` = the key set or replay store is unreachable (sessions are kept). |
| `awsiam`: `401 invalid_assertion` | Opaque on purpose: check `allowed_arns` (literal account), `server_id` signed as `X-Loomcycle-AWS-Server-ID`, `sts_regions`, and no hop-by-hop header among the signed headers. |
| `409 sync_removal_limit` | A `complete` sync would remove more than `max_sync_removals`; nothing changed. |
| Every token of a bridge or app stopped at once | Its gate was taken out of the config, or its `ClientDef` retired. |
| A promoted user's token still has old scopes | The token is `frozen`; re-mint, or use `inherit` (`LOOMCYCLE_TOKEN_AUTHORITY_INHERIT=1` or `"authority": "inherit"`). |
| `/.well-known/oauth-authorization-server` is 404 | `LOOMCYCLE_PUBLIC_URL` is unset. |
| `loomcycle login` refused on Windows | Not supported there; set `LOOMCYCLE_MCP_UPSTREAM_TOKEN`. |
