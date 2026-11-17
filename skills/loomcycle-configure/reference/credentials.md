# Credential store reference (v1.10.0+; checked against v1.156.0)

`CredentialDef` is a **secure, encrypted-at-rest store for named API secrets** —
a tenant (or a user) stores its own provider keys, search-provider keys, and
third-party MCP-server tokens, and other Defs reference them **by name** at bind
time. The model never sees a value: `get`/`list` return metadata only, and a
`$cred:<name>` reference is resolved and bound **server-side** at request time.

It exists so a tenant can bring its own keys without host access — the operator
sets `LOOMCYCLE_*` host env (which a tenant can't), so before the store existed
the only per-tenant secret channel was the ephemeral `POST /v1/runs credentials`
map, which couldn't back a stored config.

Since **v1.143.0** a credential can also be an **OAuth connection** to a remote
MCP server — connected once by its owner, refreshed by the runtime, and sent as
`Bearer $oauth:<name>` (see [OAuth credentials](#oauth-credentials-for-remote-mcp-servers-v11430)).

**Encryption:** AES-256-GCM envelope encryption with a per-tenant key derived
(HKDF) from one deployment master key, the GCM AAD binds each ciphertext to its
row, and the store is **fail-closed** — with no master key configured the inline
backend is disabled and *nothing* is stored (never plaintext). CredentialDefs
are excluded from snapshots — except an OAuth credential's *settings*, never its
secrets (v1.144.0).

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
secret — it belongs in the secrets env file (`.env.local`), never yaml (see
[settings.md](settings.md) for which settings stay in the environment).

The same key does more than seal credentials: it derives the operator-token
pepper, signs the audit chain (required with any sign-in gate since v1.142.0, and with
more than one principal since v1.147.0) and keys the user hash on trace spans
([observability.md](observability.md)). Removing it logs out every operator
token; on rotation keep the old key as `LOOMCYCLE_SECRET_KEY_PREVIOUS`.

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

Op-discriminated. The secret ops:

| op | what it does |
|---|---|
| `create` | store (or **rotate** — same name overwrites) a secret value. `name` must match `^[A-Za-z0-9_-]{1,128}$`. Optional: `expires_at` (RFC3339, **enforced** — from that instant the credential is refused everywhere, and never replaced by the operator's value), `allowed_urls` (the https URLs the value may be sent to; `[]` = sent nowhere, only compared), `username` (sent with the value where a destination takes one, e.g. git basic auth). |
| `get` | one credential's **metadata** (name, scope, backend, timestamps, `expired`, `allowed_urls`) — **never the value**. |
| `list` | all credentials in scope, **metadata only**. |
| `delete` | remove a credential. |
| `oauth_connect_start`, `oauth_connect_status`, `oauth_disconnect` | an OAuth credential's connection (v1.143.0, below). |

Crypto-key ops (`generate`, `rotate`, `set_min_version`, `delete_version`,
`export_key`, `import_key`) belong to the `Crypto` tool's keys and are not covered
here.

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

### 2. Provider / tool key **override by env-var name**

Store a credential **named after a well-known key env var** — `ANTHROPIC_API_KEY`,
`OPENAI_API_KEY`, `DEEPSEEK_API_KEY`, `GEMINI_API_KEY`, `OLLAMA_API_KEY` (hosted
ollama.com), `BRAVE_API_KEY` — and it **overrides the operator's host key** for
that tenant/user's LLM and WebSearch requests. Precedence is the same agent >
user > tenant. The override applies on the inference / tool request only:
model-availability probes stay on the operator key, and `ollama-local` is
unauthenticated so it takes none. Token usage + cost then attribute to the owning
scope (see [token-limits.md](token-limits.md)): an operator-key run bills the operator AND counts as tenant
consumption; a tenant-key run counts for the tenant only. An empty/absent
override never blanks the host key (the operator key remains the fallback).

```
credentialdef  { "op": "create", "scope": "tenant", "name": "ANTHROPIC_API_KEY", "value": "<secret>" }
```

**A vendor key goes only to that vendor's API (v1.143.0).** A provider on a
vendor driver (`openai`, `deepseek`, `anthropic`, `gemini`, `ollama`) whose
`base_url` is **not** that vendor's API and that names no `api_key_env` — a
proxy, vLLM, llama.cpp, a self-hosted speech server — sends **no key**: neither
the operator's `OPENAI_API_KEY` (etc.) nor a tenant's stored credential of that
name. So a tenant's own vendor key never reaches an operator's self-hosted
server. If such a provider needs a key, name it with `api_key_env` — it then
takes overrides under that name, wherever it points. The boot log names each
provider this applies to. The memory embedder's per-id key fallback follows the
same rule.

### 3. Other places a stored credential is read

- **`$ghapp:<name>`** — store a GitHub App config (a JSON object with `app_id`,
  `installation_id`, `private_key`, optional `repositories` / `permissions` /
  `base_url`) as a credential and reference it where a `$cred:` would go.
  loomcycle mints a short-lived installation token and substitutes it; the
  private key never leaves loomcycle.
- **Hook headers** — a webhook hook on an agent may carry `$cred:<name>` in its
  `headers`, resolved for the run each time the hook is called.
- **Bash / Bashbox host commands** — names listed in
  `LOOMCYCLE_BASH_ALLOWED_CREDS` / `LOOMCYCLE_BASHBOX_FALLBACK_ALLOWED_CREDS`
  are resolved for the run's own identity and injected into the shell's
  environment, where **the model can read them**; an agent narrows them with
  `shell_credentials` (see [bashbox.md](bashbox.md)).
- **The Git tool** — `"credential": "$cred:<name>"` or `"$ghapp:<name>"`, which
  must be restricted with `allowed_urls` to the repository (see [git.md](git.md)).
- **A tenant's telemetry collector headers** — `headers_credential` on the
  `telemetry` policy, restricted by `allowed_urls` to the endpoint
  ([observability.md](observability.md)).
- **Remote memory backends and document sources** — `api_key_env:
  "$cred:<name>"` on the definition. This one resolves only a **tenant**-scope
  credential, in the tenant that owns the definition.

---

## OAuth credentials for remote MCP servers (v1.143.0+)

Some MCP servers take no API key: they are protected by OAuth, and their access
tokens live minutes and rotate the refresh token on every use. A copied token
stops working almost at once. An **OAuth credential** holds the connection
instead: its owner connects it **once** by approving a code (the device-code
sign-in), and from then on loomcycle refreshes the access token itself and
substitutes it wherever the credential is named as **`$oauth:<name>`**. Nobody —
the model, the owner, the operator — sees the access token, refresh token or
device code.

**1. Create** it with `usage: "oauth"` and the protected resource (the MCP
server's https URL):

```
credentialdef { "op": "create", "scope": "user", "name": "docs-server", "usage": "oauth",
                "oauth": { "resource": "https://docs.example.com/mcp" } }
```

Optional in `oauth`: `issuer` (when the resource lists more than one
authorization server), `scopes`, `client.token_endpoint_auth`. loomcycle
discovers the authorization server from the resource's metadata and registers
itself as a client dynamically (a static client is not supported); every
endpoint must be https on the issuer's or the resource's host. `allowed_urls`
defaults to `[resource]`, so the token goes only there and a request carrying it
follows no redirect. **Create-only:** to change it, `delete` (the grant is
revoked first, best effort) and create again.

**2. Connect** it — outside a run, because a person must approve:

```
credentialdef { "op": "oauth_connect_start", "scope": "user", "name": "docs-server" }
# → {"user_code": "ABCD-EFGH", "verification_uri": "https://…", "expires_in": 299, "interval": 5}
```

Open `verification_uri`, enter the code, approve. `oauth_connect_status` reports
the state — `pending_connect`, `connected`, `needs_reauth`, `revoked` — the
account it is connected as, when the access token expires and the last error.
Codes last about 5 minutes and each start replaces the previous one: approve the
newest. `oauth_disconnect` revokes the grant at the server (best effort) and
keeps the registration for the next connect.

**3. Use** it where a `$cred:` would go — an MCP server's header, a hook's
webhook header, an A2A peer, a trigger's `user_credentials`:

```yaml
mcp_servers:
  docs:
    transport: streamable-http
    url: https://docs.example.com/mcp
    headers:
      Authorization: "Bearer $oauth:docs-server"
```

Resolution precedence is the same **agent > user > tenant**, so each user's runs
send their own connection. A credential that is not connected, or needs
reconnecting, **refuses the call** — nothing stands in for it, and a reference is
never sent as written. A field that takes a whole `$cred:<name>` (`user_bearer`,
`api_key_env`, a hook's signing secret, the Git tool's `credential`) does **not**
take `$oauth:`.

**What the runtime does for you.**

- **Refresh.** The access token is refreshed before it expires; one refresh runs
  at a time per credential across all replicas, and a rotated refresh token is
  saved before the new access token is used.
- **Refresh-and-retry once (v1.144.0).** When a server answers `401` with a
  Bearer `invalid_token` challenge to an `$oauth:` token (clock skew, a token
  revoked at the server), the client forces one refresh, opens a new MCP session
  if it held one, and sends the request **once** more (a refused request was not
  run, so this is safe). Concurrent refusals share one refresh; the refused token
  is never sent again. A **second** refusal parks the credential in
  `needs_reauth`. Any other `401`, or a server whose headers name no `$oauth:`,
  behaves as before.
- **A revoked or expired grant** turns the credential `needs_reauth`, with an
  audit event (`oauth_needs_reauth`); reconnect to restore it, no restart.
- **The account name.** `connected_as` is display-only: from the server's
  userinfo endpoint, else (v1.144.0) the token response's OpenID Connect
  `id_token` — used only once **verified** (signature from the issuer's key set,
  an algorithm allowlist, exact `iss` / `aud` / `azp`, unexpired) — taking
  `email` (unless `email_verified` is false), else `preferred_username`, else
  `sub`. The `id_token` is never stored, logged or returned. A grant connected
  before v1.144.0 fills the name on its next connect (or a refresh that carries a
  verifiable `id_token`); reconnect once if it stays empty.
- **Snapshots (v1.144.0)** carry each OAuth credential's **settings** (resource,
  issuer, client registration mode, scopes, `allowed_urls`), never its tokens,
  device codes or client secret. A restored credential comes back unconnected —
  `needs_reauth` if it ever had a grant, else `pending_connect` — so its owner
  only connects it again. A same-named credential already on the target is left
  alone, with a warning.
- **Never in** logs, tool results, transcripts, audit events or snapshots.

**In the Web UI (v1.145.0).** Both credentials pages (the tenant's, and *My
credentials*) show each OAuth credential's state and account, with **Connect
account** (or **Reconnect**) and **Disconnect**. A connect shows the code with a
copy button and the sign-in link and waits until it connects. While any OAuth
credential the viewer manages needs reconnecting, a **banner above every page**
names it with a Reconnect link — it reads only the credential lists the viewer
can already see.

**Who may do what.** Create, connect, status, disconnect and delete happen
**outside a run** (a model never starts a sign-in). A **tenant** credential is
managed by a tenant operator (`substrate:tenant`) or an admin, a **user**
credential by its own user, an **agent** credential by an admin only.
`oauth_connect_status` asks `use` of the access-control rules, the others
`manage`. Also on `POST /v1/_credentialdef`, the gRPC `CredentialDef` RPC, and
the TS / Python clients (`createOAuthCredential`, `oauthConnectStart`,
`oauthConnectStatus`, `oauthDisconnect`).

---

## Caveats

- **Requires `LOOMCYCLE_SECRET_KEY`** — the whole tool is inert (fail-closed)
  without it. Advise the operator to set it once at deploy.
- **`get`/`list` never return the value** — there is no op that reads a secret
  back, so record it elsewhere if it will be needed again.
- **Excluded from snapshots** — a portable snapshot never carries credential
  ciphertext; an OAuth credential's settings travel, and it restores unconnected.
- **`$cred:` requires the referenced credential to exist in the resolving run's
  scope** — an unresolved `$cred:` or `$ghapp:` **refuses the call**: no literal
  placeholder and no unauthenticated request is sent, and the tool result is
  classified `business`, not retryable (it doesn't fall back to the host key;
  the provider-override path *does* fall back — but never for an **expired** or
  `allowed_urls`-restricted credential, where the call fails instead of taking
  the operator's key).
- **A `$oauth:` credential must be connected** — `pending_connect` or
  `needs_reauth` refuses the call; reconnect with `oauth_connect_start` (or the
  Web UI's Reconnect).
- **A `${NAME}` host-env reference is not a substitute** for a non-admin author
  of an MCP server definition — only an admin may store one (see `webhooks.md`).
  Tenants provision a credential here and reference it as `$cred:<name>`.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `create` refused: inline credential storage is disabled | `LOOMCYCLE_SECRET_KEY` is not set on the server |
| An MCP call refused naming a `$cred:` | The credential does not exist in the run's scope chain, has expired, or its `allowed_urls` do not cover the server's URL |
| An MCP call refused naming an `$oauth:` credential | Not connected, or `needs_reauth`. Run `oauth_connect_status`, then `oauth_connect_start` and approve the newest code |
| `oauth_connect_start` refused | Called from inside a run (never allowed), or the caller does not manage that scope (agent scope is admin-only) |
| The OAuth credential keeps going to `needs_reauth` | The server refused a freshly refreshed token twice, or the grant was revoked at the provider. Reconnect; check the account still has access |
| `connected_as` is empty | Connected before v1.144.0, or the server has neither userinfo nor a verifiable `id_token`. Reconnect once |
| After a snapshot restore the OAuth credential is `pending_connect` / `needs_reauth` | Expected: tokens never travel. Connect it again |
| A self-hosted OpenAI-compatible provider now gets 401 (v1.143.0+) | A vendor key is no longer sent to a non-vendor host. Name the key with `api_key_env` on that provider |
| A tenant's `OPENAI_API_KEY` credential is ignored for one provider | That provider points at a non-vendor host with no `api_key_env` (by design) |

Full runtime reference: the loomcycle `credentialdef` `Context op=help` topic and
`docs/CREDENTIALS.md`.
