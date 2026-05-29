---
description: Capture, list, restore, or delete loomcycle runtime snapshots from inside the IDE.
argument-hint: "<create|list|restore|delete> [name-or-id] [--include-history] [--description=<text>]"
allowed-tools: mcp__loomcycle__create_snapshot mcp__loomcycle__list_snapshots mcp__loomcycle__restore_snapshot mcp__loomcycle__delete_snapshot
---

# loomcycle snapshots

Run one snapshot operation. First token of `$ARGUMENTS` is the subcommand.

### `create`
Call `mcp__loomcycle__create_snapshot`. All fields optional:

```json
{ "description": "<--description text, or a sensible default>", "include_history": <true if --include-history> }
```

Report the new `snapshot_id` + description.

### `list`
Call `mcp__loomcycle__list_snapshots` (no input). Render a markdown table:
`snapshot_id | description | created | size`. Most-recent first.

### `restore`
Second token = `<snapshot_id>`. Call `mcp__loomcycle__restore_snapshot`:

```json
{ "snapshot_id": "<id>", "include_history": <true if --include-history> }
```

**Restore mutates live runtime state.** Before calling, confirm with the
operator which snapshot they're restoring and that they intend to overwrite
current state. Do not restore on a guessed id.

### `delete`
Second token = `<snapshot_id>`. Call `mcp__loomcycle__delete_snapshot`:

```json
{ "snapshot_id": "<id>" }
```

Confirm the id before deleting; report success.

If the subcommand is missing or unrecognised, list the four subcommands and
stop.
