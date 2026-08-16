---
description: Report what loomcycle holds about one subject, or erase it — three tiers, dry-run by default, with an honest account of what it cannot reach.
argument-hint: "<report|execute> <subject> [--confirm]"
allowed-tools: mcp__loomcycle__erasure
---

# loomcycle erasure

Answers *"what does this deployment hold about this person"*, and removes what it
can. Wraps the `erasure` meta-tool (loomcycle v1.45.0+).

Parse `$ARGUMENTS`:

- First token = `report` (default) or `execute`.
- Second token = the **subject**: a user id, not a name.
- `--confirm` is required to actually delete (see below).

**There is no tenant argument.** The tenant comes from your credentials, because a
subject id is only unique within one. If you need another tenant's subject, you
need a token for that tenant.

## `report` — read-only

```json
{ "op": "report", "subject": "<user id>" }
```

Returns three tiers. Render them as three sections, and **do not sum them** — they
differ in what they guarantee, which is the whole point:

| tier | meaning |
|---|---|
| `tier1_covered` | subject-keyed, and existing primitives delete it |
| `tier2_uncovered` | subject-keyed, and **nothing** deleted it before this feature. The `credentials` count is the one that matters — a subject's encrypted keys surviving an "erasure" is the worst residue on the list |
| `tier3_residue` | **not subject-keyed at all** — facts *about* the subject living in scopes they do not own, found only by tracing provenance from their chats |

In each tier's `counts`, a key's **presence** means the plane was examined and its
value is the row count. A **missing** key means NOT examined — that is a different
statement from zero, and the report says which in `notes`.

If `errors` is non-empty, every count is a **lower bound**. Say so; do not present
the numbers as complete.

## `execute` — removes tiers 1 and 2

```json
{ "op": "execute", "subject": "<user id>", "dry_run": false, "confirm": "<same subject>" }
```

**It defaults to a dry run.** Omitting `dry_run` does nothing and reports what
*would* go. A live run additionally needs `confirm` to equal `subject` exactly.

Only pass `dry_run: false` when the user said `--confirm`. If they asked to erase
someone without it, run the dry run, show what would go, and ask. This is
irreversible.

## ⚠️ The residue report is one-shot — keep the response

Tier-3 residue is traceable **only** through the subject's chats, and a live run
deletes those chats. So afterwards the trace handle is gone:

```
a report run AFTER an erasure shows  residue: 0
while those facts are still stored
```

That is not a bug to work around; it is what "the subject's chats are deleted"
means when chats are the only index into derived facts. **The execute response is
the only durable record of what was not reached.** Print it in full and tell the
user to keep it. Do not re-run a report afterwards and report `0` as
confirmation — the tool will mark tier 3 `UNDETERMINABLE` in that state, and you
should relay that word rather than the zero.

## What it deliberately does not delete

The usage/cost ledger, reported under `retained` with the reason: cost rows are
accounting records an operator may be legally required to keep. The correct
treatment is to break the personal linkage rather than destroy the totals, and
that is not implemented yet. Relay `retained` — an erasure that lists only its
successes reads as complete.

## Related

- `/loomcycle:memory` — the memory keyspaces an erasure removes, and the
  `provenance` field on `set` that makes tier-3 residue findable at all.
- A fact written **without** provenance is not reachable by any mechanism and is
  not counted in tier 3. If you are writing durable facts about a person, record
  provenance or accept that no erasure will ever find them.
