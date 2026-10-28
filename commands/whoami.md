---
description: Show who the plugin's loomcycle token signs in as — tenant, subject, status, groups, sign-in gate and the access-control lists that apply.
argument-hint: "[--tools]"
allowed-tools: mcp__loomcycle__identity mcp__plugin_loomcycle_loomcycle__identity mcp__loomcycle__context mcp__plugin_loomcycle_loomcycle__context
---

# loomcycle whoami

Answers *"who is this session acting as, and what may it do?"*. Every loomcycle
tool this plugin calls runs as the principal behind the plugin's bearer (the
`auth_token` userConfig, or the token `loomcycle login` stored in the OS
keychain). Wraps the `identity` tool (`op=whoami`) of the loomcycle MCP server.

Parse `$ARGUMENTS`: `--tools` also lists the tools this session may call.

## Call

```json
{ "op": "whoami" }
```

Render as a short block, not raw JSON:

| Field | Show |
|---|---|
| `tenant_id`, `subject` | Always. The subject is the `user_id` to use with `/loomcycle:runs` and `/loomcycle:connect --user`. |
| `display_name` | If present. |
| `access_mode`, `status` | `status` is `active`, `disabled` or `pending`. |
| `auth` | The sign-in gate and method (`amr`), and when. Absent for an operator token. |
| `identities` | Linked sign-ins (OIDC, OAuth, a bridge), one line each. |
| `groups` | Each group and how the user is in it (`via`: `direct`, or the nested group it comes through). |
| `acl` | The access-control mode (`compat`, `shadow`, `enforce`), the lists that apply and any tools they remove. |

- **`status: pending`** means an operator has not approved the account yet.
  Say so plainly. Runs started under it will be refused or told to do nothing.
- **A `note` saying it acts for no person** means the server runs in open mode,
  or the token has no user behind it. That is not an error.
- With `--tools`, also call `context` with `{"op": "tools"}` and list the tool
  names. A tool missing from that list is missing from this session: the token's
  scopes or an access rule removed it (see `reference/mcp-tools.md`, *What your
  token can reach*).

## When the tool is missing

`identity` replaced `directory` in loomcycle v1.126.0. If the session has no
`identity` tool:

- the runtime is older than v1.126.0 (it has `directory` instead), or
- the plugin connected before the runtime was upgraded; Claude Code reads the
  tool list once, at connection. Reload the plugin.

Fall back to `context` with `{"op": "self"}`, which reports the principal on
every version.

## Related

- `/loomcycle:access check` — may I do one specific thing?
- `/loomcycle:connect` — set the `user_id` the run commands default to.
