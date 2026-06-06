# examples/

Drop-in configurations you apply by hand — they are **not** loaded automatically.

## `mcp-http-tenant.json` — direct HTTP transport (alternative to the stdio proxy)

Since 0.21.0 the plugin's default `.mcp.json` runs `loomcycle mcp --upstream`, a
**thin stdio client** that proxies to the runtime's `POST /v1/_mcp` — which is
already **principal-enforced**. So to confine the plugin to one tenant you no
longer need to swap transports: just set `auth_token` to a scoped
`OperatorTokenDef` (`lct_…`) bearer in the default config and every command runs
under that token's `{tenant_id, subject, scopes}` principal. An admin token (or
an open-mode runtime) gives full authority; a narrow token is confined.

This file is an **alternative**: point the **same** `loomcycle` server directly
at `POST /v1/_mcp` over HTTP instead of running the local stdio proxy process.
Functionally equivalent (both hit `/v1/_mcp`); use it if you'd rather not spawn
the stdio client. It keeps the server name `loomcycle`, so all the
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
