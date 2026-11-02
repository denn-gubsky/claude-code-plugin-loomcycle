---
description: Merge two duplicate knowledge-base subjects into one, or bind a subject to the user account it stands for — operator actions on the tenant ontology.
argument-hint: "merge <duplicate> <survivor> [--confirm] | bind <subject> <user_subject> | unbind <subject>"
allowed-tools: mcp__loomcycle__ontology mcp__plugin_loomcycle_loomcycle__ontology mcp__loomcycle__document mcp__plugin_loomcycle_loomcycle__document
---

# loomcycle subjects

A **subject** is a knowledge-base document whose root chunk carries a natural
key, such as `person:ada-lovelace` or `org:acme`. Facts are filed about it, and
statements point at it. Subjects live in the tenant scope. This command wraps
the `ontology` tool of the loomcycle MCP server (loomcycle v1.131.0+).

**Operators only:** an admin, or a tenant operator in its own tenant, with
write on the subject's document (both documents, for a merge). The tool needs
`substrate:tenant`; a member's session does not have it. `tenant` is admin-only
(to act on another tenant); leave it out otherwise.

Name a subject by its **document id** or its **natural key**. For `bind`, a
root chunk id also works.

---

## `merge <duplicate> <survivor>` — two subjects that are the same entity

**This cannot be undone by another call.** Before merging:

1. Show both subjects, with `document` `op=get_document` in `scope: "tenant"`
   (by id, or find them with `op=query_chunks` / `op=search`). Show the title,
   natural key, path, and how many facts each has (`op=list_facts` with `about`
   = the root chunk id).
2. Confirm **which one survives**. The survivor keeps its key; the duplicate's
   key stays on a retired document.
3. Call only after the user confirms, or passed `--confirm`:

```json
{ "op": "merge_subjects", "duplicate": "<id or key>", "survivor": "<id or key>" }
```

In one transaction:
- the duplicate's facts move under the survivor, with their keys unchanged;
- every statement about the duplicate is copied onto the survivor, and the
  original is expired as merged (kept for as-of reads, never deleted);
- the duplicate stays as a retired document with status `merged`, keeping its
  key and path and recording `fields.merged_into`;
- a user bound to the duplicate is bound to the survivor instead.

Render `facts_moved`, `statements_repointed`, `statements_retired` and
`statements_left`.

**`statements_left`** are statements you may not `link`. They are left for the
links agent, which re-points them when it drains the `merged` event. A
`not_announced` value means the event was not published, because your access
rules hide part of the tenant's documents. Say so: the links agent will not
pick the merge up by itself.

| Refusal | Meaning |
|---|---|
| `same_subject` | both names resolve to one subject |
| `not_a_subject` / `subject_not_in_scope` | not a subject of the tenant scope |
| `already_merged` | the duplicate was merged before |
| `principal_conflict` | the two are bound to different users; unbind one first |
| `merge_conflict` | a concurrent change; look again and retry |
| `forbidden` | not an operator, or no write on both documents |

## `bind <subject> <user_subject>` / `unbind <subject>`

This records which user account a subject **is**: for example, that
`person:ada-lovelace` is the user `u-ada`.

```json
{ "op": "bind_principal", "subject": "<id or key>", "principal": "<user subject>" }
```

`unbind` sends `"principal": ""`. Leaving `principal` out does **not** clear
the binding.

- One user per subject and one subject per user. Clear a binding before binding
  someone else (`binding_conflict` names the subject that holds it).
- The user must be registered in the tenant, in any status
  (`principal_not_found` otherwise). `/loomcycle:whoami` and the `identity`
  tool show user subjects.
- Render `natural_key`, `path`, `principal` and `previous`, and whether it
  `changed`.
- **Why it matters:** erasing that user (`/loomcycle:erasure`) then finds the
  subject, reports it, clears the binding and announces `erased`. The subject
  itself is never deleted; that stays an operator's decision.

Other refusals: `subject_not_found`, `not_a_subject`, `forbidden`,
`invalid_request`, `unavailable`.

---

**Not here:** renaming a subject or changing its type. Edit the subject's
document with the `document` tool: `update_chunk` with `type` on the root.
When the tenant has an ontology, re-typing to a type that is not an entity
type in force is refused; a re-type announces `retyped`. Proposing a new subject is `document` `op=propose_subject`.

If the sub-command is missing or unrecognised, list the three and stop rather
than guessing.
