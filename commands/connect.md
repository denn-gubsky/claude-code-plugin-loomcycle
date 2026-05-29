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
