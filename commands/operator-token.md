---
description: Mint, rotate, retire, or inspect loomcycle OperatorTokenDef bearer tokens — per-principal multi-tenant auth (RFC L, loomcycle ≥ v0.17.0).
argument-hint: "<create|rotate|retire|get|list> [--name=<n>] [--tenant=<id>] [--subject=<s>] [--scopes=a,b] [--def-id=<id>] [--grace=<sec>]"
allowed-tools: mcp__loomcycle__operatortokendef
---

# loomcycle operator-token

Manage the **OperatorTokenDef** substrate (loomcycle ≥ v0.17.0, RFC L OSS
multi-tenant authorization). Each token binds an **authoritative principal**
`{tenant_id, subject, allowed_scopes}` resolved *from the token* — it overrides
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
- `--scopes=a,b,c` — comma-separated scopes from the closed catalog (`create`;
  default `[substrate:admin]`). Pass the narrowest set the token needs.
- `--def-id=<id>` — existing def id (target for `get`; alternative target for
  `rotate` / `retire`).
- `--grace=<sec>` — rotation grace-window override (`rotate`); the old token
  keeps working this long after the new one is minted.

Call `mcp__loomcycle__operatortokendef` with the matching shape; render results
as markdown, not raw JSON.

### `create` — mint a new token
```json
{ "op": "create", "name": "<n>", "tenant_id": "<id>",
  "subject": "<s, optional>", "scopes": ["<scope>", …] }
```
Returns the def metadata **plus the token plaintext, shown ONCE**.

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

For `--scopes`, pass the **narrowest** set: a per-app key might be
`runs:create`; only an admin/operator key needs `substrate:admin`. Default-deny
— omitted scopes are not granted.

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

If the op is missing or unrecognised, list the five ops and stop rather than
guessing.
