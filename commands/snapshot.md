---
description: Capture, list, restore, or delete loomcycle runtime snapshots from inside the IDE.
argument-hint: "<create|list|restore|delete> [name-or-id] [--include-history] [--description=<text>]"
allowed-tools: mcp__loomcycle__create_snapshot mcp__loomcycle__list_snapshots mcp__loomcycle__restore_snapshot mcp__loomcycle__delete_snapshot mcp__plugin_loomcycle_loomcycle__create_snapshot mcp__plugin_loomcycle_loomcycle__list_snapshots mcp__plugin_loomcycle_loomcycle__restore_snapshot mcp__plugin_loomcycle_loomcycle__delete_snapshot
---

# loomcycle snapshots

Run one snapshot operation. First token of `$ARGUMENTS` is the subcommand.

**Admin token only.** Snapshots span every tenant, so a tenant or user token
does not see these tools at all. If they are missing from the session, that is
the reason, not a broken runtime.

### `create`
Call `create_snapshot`. All fields optional:

```json
{ "description": "<--description text, or a sensible default>", "include_history": <true if --include-history> }
```

Report the new `snapshot_id` + description, and **print any `warnings` in
full**. They name, by location, every literal-looking credential in a captured
definition (a literal travels in the snapshot as written; replace it with a
`$cred:` or `${LOOMCYCLE_*}` reference) and every paused run parked on a pending
interrupt (which does not travel: resolve or cancel it, then capture again).

A run in flight is captured only if it is **parked**. For a snapshot of a busy
runtime, pause it first (`pause_runtime`), capture, then resume.

### `list`
Call `list_snapshots` (no input). Render a markdown table:
`snapshot_id | description | created | size`. Most-recent first.

### `restore`
Second token = `<snapshot_id>`. Call `restore_snapshot`:

```json
{ "snapshot_id": "<id>", "include_history": <true if --include-history> }
```

**Restore writes into live runtime state.** Before calling, confirm with the
operator which snapshot they are restoring. Do not restore on a guessed id.

**Restore only ever adds.** Existing rows are left alone, so restoring an older
snapshot does **not** roll back rows created since; it is not undo. The returned
counters report what was actually written, so a second restore of the same
snapshot legitimately reports zeros. Restored paused runs resume on this
instance (`paused_runs_resumed`); one that cannot resume, because its agent no
longer exists here, is marked failed and named in `warnings`. Print those.

### `delete`
Second token = `<snapshot_id>`. Call `delete_snapshot`:

```json
{ "snapshot_id": "<id>" }
```

Confirm the id before deleting; report success.

If the subcommand is missing or unrecognised, list the four subcommands and
stop.
