# Path primitive reference (v1.4.0+)

`Path` is a **Unix-like virtual filesystem** over the things loomcycle stores —
Memory entries, Volume mounts, and Documents. Agents (and external callers)
address those resources by human-readable paths like `/docs/launch` instead of
opaque ids, and organize them into a tree.

It borrows the Linux **inode/dirent split**: each resource keeps its permanent id
(the "inode"), and a `dirents` runtime-store row maps `(parent_path, name) →
resource` (the "directory entry"). A rename/move is a cheap dirent update that
never touches the resource, and one tree spans all three resource kinds.

**A dirent is a name, not an authority grant.** Resolving `/docs/launch` to a
Document id does not, by itself, let you read it — the resource's own
scope/tenant check still applies. So the exposure Path adds is *integrity* (a
wrong mapping), not *confidentiality*.

---

## Enablement — one gate

`Path` is **always registered**; the only gate is the per-agent `tools`:

```yaml
agents:
  organizer:
    tools: [Path, Memory, Document]
```

There is **no** env flag and **no** separate scope policy (v1) — `tools:
[Path]` grants all three scopes (`agent`/`user`/`tenant`). Because a dirent is a
name and not an authority grant, the risk is integrity, not confidentiality.

---

## Operations

`Path` is op-discriminated (six ops):

| op | what it does | reply |
|---|---|---|
| `resolve` | path → what it names. Never returns content. | `{name, kind, full_path, resource_ref}` — for a document, `resource_ref` carries the `document_id` |
| `ls` | list a directory, one level by default (`recursive:true` lists every descendant, flat; `kind_filter` narrows by kind). **Paged** — see below. | `{path, entries: [{name, kind, full_path, resource_ref?}]}` |
| `stat` | one entry's full record, with timestamps. | `{full_path, name, kind, scope, resource_ref, created_at, updated_at}` |
| `mkdir` | create an **empty** directory so it persists and lists. Rarely needed — directories are implicit (S3-style). Safe to repeat. | `{ok, path, created}` |
| `mv` | re-parent / rename (`path` → `to`). The destination must not exist; a move into the path's own subtree is refused. A directory moves with everything under it. | `{ok, from, to}` |
| `rm` | remove a **name** (`recursive:true` **required** to remove a path with descendants). | `{ok, removed, n_removed}` |

`scope` selects the tree: `agent` (default), `user` (needs a `user_id` on the
run), or `tenant` (shared across the tenant). One call reads one tree, and the
same path in two scopes is two different entries. **`document` defaults to
`user` while Path defaults to `agent`** — a document created with no scope and
looked up here with no scope is looked up in the wrong tree, so pass `scope` on
both. **Path grammar:** slash-rooted and absolute; segments `[a-zA-Z0-9._-]+`,
each ≤64 chars; **no `..`** (rejected, not resolved); ≤64 segments / ≤1024
chars. Resource kinds: `directory`, `document`, `volume_mount`, `memory_entry`.

### `ls` is paged

```
path  { "op": "ls", "scope": "user", "path": "/facts", "limit": 500 }
→ { "path": "/facts", "entries": [ … ], "truncated": true, "next_cursor": "…" }
path  { "op": "ls", "scope": "user", "path": "/facts", "cursor": "<that next_cursor>" }
```

`limit` is 500 by default and 5000 at most. A listing cut short reports
`truncated: true` and a `next_cursor`; pass it back as `cursor` to continue. The
cursor is opaque — never build one. Page whenever a directory can be large:
`/facts` holds one document per subject, so it grows with the store. An empty
listing is not an error; it means nothing is named there **in this scope**.

A directory that exists only because something lives beneath it shows in `ls`
but has no record of its own, so `stat` reports it missing. `mkdir` gives it
one.

---

## How resources get a name

Path never creates resources — each one **opts in** to a name at create time:

| Resource | How it registers a dirent |
|---|---|
| Memory entry | `Memory op=set ... path="/notes/today"` — read it back with `Memory op=get` and the same `path` |
| Volume mount | `VolumeDef op=create ... mount_at="/vol/repo"` (default `/vol/<name>`) |
| Document | `Document op=create_document ... path="/docs/launch"` — a document is **always** named: `/documents/<title>` when you pass no `path` (also on `import_md` / `import_canvas`). `Document op=set_path` adds a further name to an existing one |

SQL Memory deliberately stays **out** of the tree (it's a per-scope database, not
a named resource).

---

## Off-run: callable directly from the plugin (MCP meta-tool)

Besides in-band agent use, Path is a first-class MCP meta-tool, so you can call
it directly through the thin client without spawning a run:

```
path  { "op": "ls", "scope": "user", "path": "/docs" }
path  { "op": "mv", "scope": "user", "path": "/docs/launch", "to": "/archive/launch" }
```

(`path` here is the MCP tool — in Claude Code it is exposed under the plugin's
or the project's MCP server prefix.) Called this way there is no run, so the
default `agent` scope is the MCP session's own synthetic agent, not an agent you
have in mind — pass `scope: "user"` or `"tenant"`.

It's also on HTTP (`POST /v1/_path`), gRPC (`Path` RPC), and the TS/Python
adapters (`client.path(...)`). **Scope and tenant are resolved server-side from
the authenticated principal — never sent on the wire.** Off-run `scope:"user"`
ops key on the principal's subject, so they interoperate with that user's agent
runs. The endpoint is tenant-confined (`ScopeTenant`; `substrate:admin` also
satisfies). `.mcp.json` needs no edit — the thin client auto-advertises the tool.

---

## Caveats (v1)

- **`mv` can't orphan a tree** — a move into the path's own subtree is refused.
  It also never overwrites: an existing destination is refused, and both paths
  are in one scope.
- **`rm` is dirent-only** — it removes the *name*, not the backing resource (the
  Memory entry / Volume / Document survives, still reachable by id and
  re-nameable). It is not a delete: use the resource's own tool for that (for a
  document, `Document op=delete_document`). `resource_too: true` is **refused**.
- **No per-agent `path_scopes` ACL yet** — `tools: [Path]` grants all
  scopes; a finer ACL is a follow-up.
- **Pre-existing volumes don't auto-mount** — `mount_at` registers a dirent at
  *create* time only.

Full runtime reference: the loomcycle `path` `Context op=help` topic and
`docs/PATH.md`.
