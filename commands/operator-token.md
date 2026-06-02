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

## Scope note — this command needs an admin bearer

`operatortokendef` is operator-admin-only. The plugin's MCP connection bearer
(`LOOMCYCLE_AUTH_TOKEN`, set at install via userConfig) must resolve to a
principal carrying `substrate:admin`. A narrow-scoped bearer gets a
`scope` refusal — surface that plainly; it is **not** a plugin bug. On a
single-operator deployment the legacy shared token is admin by default.

If the op is missing or unrecognised, list the five ops and stop rather than
guessing.
