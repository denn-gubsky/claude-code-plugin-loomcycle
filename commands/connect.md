---
description: Set the active loomcycle identity (user id, per-run bearer, base URL) for this Claude Code session so subsequent /loomcycle commands reuse it.
argument-hint: "[--user=<id>] [--bearer=<token>] [--base-url=<url>] [--persist]"
allowed-tools: Write
---

# Connect to loomcycle

Establish the **active loomcycle identity** for this session. Subsequent
`/loomcycle:run`, `/loomcycle:runs`, etc. reuse it unless they pass their own
`--user`.

Arguments (parse from `$ARGUMENTS`):

- `--user=<id>` — default `user_id` for run/list operations. **Required by
  `list_runs`**, so set it here once instead of repeating it.
- `--bearer=<token>` — per-run bearer passed as `spawn_run.user_bearer`
  (substituted into `${run.user_bearer}` in the operator's `mcp_servers.*.headers`
  downstream). This is the per-run identity bearer, **not** the loomcycle API
  `LOOMCYCLE_AUTH_TOKEN` — that one is set at plugin install via userConfig
  (stored in your OS keychain).
- `--base-url=<url>` — base URL of the loomcycle instance the optional
  auto-snapshot hook targets (informational here; the hook reads
  `${user_config.base_url}`).
- `--persist` — also write the identity to `.loomcycle/connection.json` in the
  project so it survives across sessions.

Do this:

1. Parse the flags above out of `$ARGUMENTS`.
2. Hold the parsed `user_id`, `user_bearer`, and `base_url` as the active
   loomcycle identity for the rest of this conversation. Refer back to it when
   later `/loomcycle:*` commands run.
3. Echo a short confirmation: the active `user_id`, whether a bearer is set
   (show `set` / `not set` — **never echo the token value**), and the base URL.
4. **Only if `--persist` was passed**, write the non-secret fields
   (`user_id`, `base_url`) to `.loomcycle/connection.json`. Do **not** persist
   the bearer to a project file — tell the user to keep it in the keychain via
   the plugin's userConfig instead. Remind them to add `.loomcycle/` to
   `.gitignore` if it isn't already.

If no flags are given, report the current active identity (or that none is set).

**No `--user`?** The token itself names a user. `/loomcycle:whoami` shows the
token's `subject`. For a per-user token (one issued by `loomcycle login`, the
Web UI or a sign-in gate), that subject is the natural `user_id`, and
`list_runs` for any other user is refused or comes back empty. Suggest it rather
than inventing an id.

**The plugin's own bearer** (what every tool call runs as) is not set here. It
comes from, in order:

1. the `auth_token` userConfig, if set (sent as `LOOMCYCLE_MCP_UPSTREAM_TOKEN`);
2. otherwise, since loomcycle v1.126.0, the token `loomcycle login --url <base_url>`
   stored in the OS keychain (macOS and Linux). The thin client uses it when
   `LOOMCYCLE_MCP_UPSTREAM_TOKEN` is empty.

Claude Code does not document what an unset `auth_token` expands to. If it
reaches the thin client as an empty string, the keychain token is used. If it
arrives as literal text, the runtime refuses that text as a bearer. So after
`loomcycle login`, run `/loomcycle:whoami`. If tools fail with an
authentication error, set `auth_token` instead.

With neither, the thin client connects without a bearer, which only an
open-mode runtime accepts.
