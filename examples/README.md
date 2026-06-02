# examples/

Drop-in configurations you apply by hand — they are **not** loaded automatically.

## `mcp-http-tenant.json` — per-tenant confinement (HTTP transport)

By default the plugin's `.mcp.json` runs `loomcycle mcp` over **stdio**, which
loomcycle treats as **single-operator / admin** — the launching process has full
authority, so wire `tenant_id` / `user_id` are trusted verbatim and no
per-tenant boundary is enforced (see the README's *Multi-tenant authorization*
section). That is the right model for an operator driving their own runtime.

To instead run the plugin **confined to one tenant** — every command bound to an
authoritative `{tenant_id, subject, scopes}` resolved from a scoped
`OperatorTokenDef` (`lct_…`) bearer — point the **same** `loomcycle` server at
loomcycle's HTTP MCP transport (`POST /v1/_mcp`), which *is* principal-enforced.

This file is that transport. It keeps the server name `loomcycle`, so all the
slash commands work unchanged — they now run under the token's principal:

1. Mint a scoped token (from an admin operator):
   `/loomcycle:operator-token create --name=acme-ide --tenant=acme --scopes=runs:create`
2. Store that `lct_…` plaintext in the plugin's `auth_token` userConfig (keychain).
3. Set `base_url` to the loomcycle instance's HTTP address.
4. Replace the plugin's `.mcp.json` contents with this file (or override the
   `loomcycle` server at the Claude Code project level), then restart Claude Code.

Now `/loomcycle:run`, `/loomcycle:runs`, etc. cannot widen beyond the token's
tenant/scopes — loomcycle's `applyPrincipal` overrides any wider wire value, and
under-scoped calls get a `scope` refusal. Do **not** define both a stdio and an
HTTP `loomcycle` server: a second server name (e.g. `loomcycle-http`) would not
back the `mcp__loomcycle__*` commands, and two servers named `loomcycle` is
invalid. It is a swap, not an addition.
