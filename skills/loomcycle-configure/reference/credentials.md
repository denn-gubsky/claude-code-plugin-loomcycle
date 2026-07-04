# Credential store reference — RFC AR (v1.10.0+)

`CredentialDef` is a **secure, encrypted-at-rest store for named API secrets** —
a tenant (or a user) stores its own provider keys, search-provider keys, and
third-party MCP-server tokens, and other Defs reference them **by name** at bind
time. The model never sees a value: `get`/`list` return metadata only, and a
`$cred:<name>` reference is resolved and bound **server-side** at request time.

It exists so a tenant can bring its own keys without host access — the operator
sets `LOOMCYCLE_*` host env (which a tenant can't), so before RFC AR the only
per-tenant secret channel was the ephemeral `POST /v1/runs credentials` map,
which couldn't back a stored config.

**Encryption:** AES-256-GCM envelope encryption with a per-tenant key derived
(HKDF) from one deployment master key, the GCM AAD binds each ciphertext to its
row, and the store is **fail-closed** — with no master key configured the inline
backend is disabled and *nothing* is stored (never plaintext). CredentialDefs
are excluded from snapshots.

---

## Enablement — one env var (fail-closed)

Set the deployment master key (a base64-encoded 32-byte KEK) in `.env.local`:

```
LOOMCYCLE_SECRET_KEY=<base64 of 32 random bytes>     # openssl rand -base64 32
# optional, for key rotation (decrypt-old / re-encrypt-on-write):
LOOMCYCLE_SECRET_KEY_PREVIOUS=<old base64 key>
```

**Unset ⇒ the credential store is disabled** — `create` fails with `inline
backend disabled (LOOMCYCLE_SECRET_KEY not set)` and no plaintext is ever
written. This is the #1 "credential refused" cause. `LOOMCYCLE_SECRET_KEY` is a
secret — it belongs in `.env.local`, never `.env.insecure`, never yaml.

The `credentialdef` tool is **tenant-confined**: `scope_id` is derived from the
caller's authoritative identity, never the wire, so a user can only author/read
their own user-scoped secrets.

---

## Operations (`mcp__loomcycle__credentialdef`)

Op-discriminated, four ops:

| op | what it does |
|---|---|
| `create` | store (or **rotate** — same name overwrites) a secret value. |
| `get` | one credential's **metadata** (name, scope, updated_at) — **never the value**. |
| `list` | all credentials in scope, **metadata only**. |
| `delete` | remove a credential. |

`scope` selects the bucket — **`scope_id` is derived from your identity, never
supplied**:

| scope | keyed on | use |
|---|---|---|
| `tenant` (default) | the tenant | a secret shared across the whole tenant (a team Slack bot). |
| `user` | **your own subject** | a per-end-user token (a personal Telegram/Slack bot) — user A's runs resolve A's, B's resolve B's. |
| `agent` | the calling agent | a secret scoped to one agent. |

Resolution precedence when a `$cred:<name>` is bound: **agent > user > tenant**,
so a user-scoped token shadows a tenant default of the same name.

```
mcp__loomcycle__credentialdef  { "op": "create", "scope": "user", "name": "telegram_bot_token", "value": "…" }
mcp__loomcycle__credentialdef  { "op": "list",   "scope": "tenant" }
```

Also in-band (agents with `allowed_tools:[CredentialDef]`), on HTTP
(`POST /v1/_credentialdef`), gRPC, and the TS/Python adapters.

---

## Consuming a credential — two paths (the model never sees the value)

### 1. `$cred:<name>` in an MCP server's `env:` / `headers:`

A `MCPServerDef` (static yaml `mcp_servers:` or the `mcpserverdef` tool) references
a stored secret; loomcycle resolves it **at container-start / request-build**,
so the value is injected into the tool call but never into the transcript:

```yaml
mcp_servers:
  telegram:
    transport: http
    url: https://api.telegram.org/...
    headers:
      Authorization: "Bearer $cred:telegram_bot_token"   # scope:user → each user's own token
```

Running on behalf of user X, the runtime resolves X's user-scoped token and the
API posts to X's channel — per-user outbound channels with zero plaintext
exposure. Every resolved value is registered into the run's redactor, so it's
masked even if it surfaces in tool output.

### 2. Provider / tool key **override by env-var name** (RFC AR #632)

Store a credential **named after a well-known key env var** — `ANTHROPIC_API_KEY`,
`OPENAI_API_KEY`, `DEEPSEEK_API_KEY`, `GEMINI_API_KEY`, `BRAVE_API_KEY` — and it
**overrides the operator's host key** for that tenant/user's LLM (all five
drivers) and WebSearch requests. Token usage + cost then attribute to the owning
scope (RFC AV): an operator-key run bills the operator AND counts as tenant
consumption; a tenant-key run counts for the tenant only. An empty/absent
override never blanks the host key (the operator key remains the fallback).

```
mcp__loomcycle__credentialdef  { "op": "create", "scope": "tenant", "name": "ANTHROPIC_API_KEY", "value": "sk-ant-…" }
```

---

## Caveats

- **Requires `LOOMCYCLE_SECRET_KEY`** — the whole tool is inert (fail-closed)
  without it. Advise the operator to set it once at deploy.
- **`get`/`list` never return the value** — there is no model-callable op that
  reveals a secret. A plaintext reveal, if ever needed, is admin/human-only and
  audit-logged.
- **Excluded from snapshots** — a portable snapshot never carries credential
  ciphertext.
- **`$cred:` requires the referenced credential to exist in the resolving run's
  scope** — a missing name fails the bind loudly (it doesn't silently fall back
  to the host key for `$cred:`; the provider-override path *does* fall back).

Full runtime reference: the loomcycle `credentialdef` `Context op=help` topic and
`docs/CREDENTIALS.md`.
