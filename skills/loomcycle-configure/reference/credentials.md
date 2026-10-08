# Credential store reference — RFC AR (v1.10.0+; checked against v1.107.0)

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
credential storage is disabled — the operator must set LOOMCYCLE_SECRET_KEY`
and no plaintext is ever written. This is the #1 "credential refused" cause. `LOOMCYCLE_SECRET_KEY` is a
secret — it belongs in `.env.local`, never `.env.insecure`, never yaml.

The `credentialdef` tool is **tenant-confined**: `scope_id` is derived from the
caller's authoritative identity, never the wire, so a user can only author/read
their own user-scoped secrets.

**Who may call it over MCP.** A `substrate:tenant` or admin session manages
every scope in its own tenant. An **isolated user** (a token holding only
`substrate:user`) may also open an MCP session (v1.67.0), but it sees and may
call **only** `credentialdef`, and only for `scope: "user"` credentials keyed on
its own subject: an omitted `scope` defaults to `user` for it, and an explicit
`scope: "tenant"` or `"agent"` is refused. The same confinement applies to that
caller on `POST /v1/_credentialdef`. The Web UI has a matching "My Credentials"
page.

---

## Operations (the `credentialdef` tool)

Op-discriminated, four ops:

| op | what it does |
|---|---|
| `create` | store (or **rotate** — same name overwrites) a secret value. `name` must match `^[A-Za-z0-9_-]{1,128}$`; optional `expires_at` (RFC3339) is an advisory rotation reminder. |
| `get` | one credential's **metadata** (name, scope, backend, created_at, updated_at) — **never the value**. |
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
credentialdef  { "op": "create", "scope": "user", "name": "telegram_bot_token", "value": "<secret>" }
credentialdef  { "op": "list",   "scope": "tenant" }
```

Also in-band (agents with `tools:[CredentialDef]`), on HTTP
(`POST /v1/_credentialdef`), gRPC, and the TS/Python adapters.

---

## Consuming a credential (the model never sees the value)

### 1. `$cred:<name>` in an http MCP server's `headers:`

An **http / streamable-http** MCP server (static yaml `mcp_servers:` or the
`mcpserverdef` tool) references a stored secret in a header; loomcycle resolves
it **per request** from the run's identity, so the value is injected into the
tool call but never into the transcript. A stdio MCP server cannot carry
per-user tokens (its env is set once at spawn), so use an http server for the
per-user case:

```yaml
mcp_servers:
  telegram:
    transport: streamable-http
    url: https://your-telegram-mcp.example.com/mcp
    headers:
      Authorization: "Bearer $cred:telegram_bot_token"   # scope:user → each user's own token
```

Running on behalf of user X, the runtime resolves X's user-scoped token and the
API posts to X's channel — per-user outbound channels with zero plaintext
exposure. Every resolved value is registered into the run's redactor, so it's
masked even if it surfaces in tool output.

### 2. Provider / tool key **override by env-var name** (RFC AR #632)

Store a credential **named after a well-known key env var** — `ANTHROPIC_API_KEY`,
`OPENAI_API_KEY`, `DEEPSEEK_API_KEY`, `GEMINI_API_KEY`, `OLLAMA_API_KEY` (hosted
ollama.com), `BRAVE_API_KEY` — and it **overrides the operator's host key** for
that tenant/user's LLM and WebSearch requests. Precedence is the same agent >
user > tenant. The override applies on the inference / tool request only:
model-availability probes stay on the operator key, and `ollama-local` is
unauthenticated so it takes none. Token usage + cost then attribute to the owning
scope (RFC AV): an operator-key run bills the operator AND counts as tenant
consumption; a tenant-key run counts for the tenant only. An empty/absent
override never blanks the host key (the operator key remains the fallback).

```
credentialdef  { "op": "create", "scope": "tenant", "name": "ANTHROPIC_API_KEY", "value": "<secret>" }
```

### 3. Other places a stored credential is read

- **`$ghapp:<name>`** — store a GitHub App config (a JSON object with `app_id`,
  `installation_id`, `private_key`, optional `repositories` / `permissions` /
  `base_url`) as a credential and reference it where a `$cred:` would go.
  loomcycle mints a short-lived installation token and substitutes it; the
  private key never leaves loomcycle.
- **Hook headers** — a webhook hook on an agent may carry `$cred:<name>` in its
  `headers`, resolved for the run each time the hook is called.
- **Bashbox host-command fallback** — names listed in
  `LOOMCYCLE_BASHBOX_FALLBACK_ALLOWED_CREDS` are resolved for the run's own
  identity and injected into `git` / `gh` (see `bashbox.md`).
- **Remote memory backends and document sources** — `api_key_env:
  "$cred:<name>"` on the definition. This one resolves only a **tenant**-scope
  credential, in the tenant that owns the definition.

---

## Caveats

- **Requires `LOOMCYCLE_SECRET_KEY`** — the whole tool is inert (fail-closed)
  without it. Advise the operator to set it once at deploy.
- **`get`/`list` never return the value** — there is no op that reads a secret
  back, so record it elsewhere if it will be needed again.
- **Excluded from snapshots** — a portable snapshot never carries credential
  ciphertext.
- **`$cred:` requires the referenced credential to exist in the resolving run's
  scope** — an unresolved `$cred:` or `$ghapp:` **refuses the call**: no literal
  placeholder and no unauthenticated request is sent, and the tool result is
  classified `business`, not retryable (it doesn't fall back to the host key;
  the provider-override path *does* fall back).
- **A `${NAME}` host-env reference is not a substitute** for a non-admin author
  of an MCP server definition — only an admin may store one (see `webhooks.md`).
  Tenants provision a credential here and reference it as `$cred:<name>`.

Full runtime reference: the loomcycle `credentialdef` `Context op=help` topic and
`docs/CREDENTIALS.md`.
