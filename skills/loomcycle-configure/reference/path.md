# Path primitive reference — RFC AL (v1.4.0+)

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

`Path` is **always registered**; the only gate is the per-agent `allowed_tools`:

```yaml
agents:
  organizer:
    allowed_tools: [Path, Memory, Document]
```

There is **no** env flag and **no** separate scope policy (v1) — `allowed_tools:
[Path]` grants all three scopes (`agent`/`user`/`tenant`). Because a dirent is a
name and not an authority grant, the risk is integrity, not confidentiality.

---

## Operations

`Path` is op-discriminated (six ops):

| op | what it does |
|---|---|
| `resolve` | path → the dirent + its `resource_ref` (the backing id). |
| `ls` | list a directory's entries (`recursive:true` walks descendants; `kind_filter` narrows by kind). |
| `stat` | one entry's metadata (name, kind, resource_ref). |
| `mkdir` | **no-op in v1** — directories are implicit (S3-style); kept for forward-compat. |
| `mv` | re-parent / rename a dirent (a move into the path's own subtree is refused — it would orphan the tree). |
| `rm` | remove a dirent (`recursive:true` **required** to remove a path with descendants). |

`scope` selects the tree: `agent` (default), `user` (needs a `user_id` on the
run), or `tenant` (shared across the tenant). **Path grammar:** slash-rooted and
absolute; segments `[a-zA-Z0-9._-]+`; **no `..`** (rejected, not resolved); ≤64
segments / ≤1024 chars. Resource kinds: `directory` (implicit), `document`,
`volume_mount`, `memory_entry`.

---

## How resources get a name

Path never creates resources — each one **opts in** to a name at create time:

| Resource | How it registers a dirent |
|---|---|
| Memory entry | `Memory op=set ... path="/notes/today"` |
| Volume mount | `VolumeDef op=create ... mount_at="/vol/repo"` (default `/vol/<name>`) |
| Document | `Document op=create_document ... path="/docs/launch"` |

SQL Memory deliberately stays **out** of the tree (it's a per-scope database, not
a named resource).

---

## Off-run: callable directly from the plugin (MCP meta-tool)

Besides in-band agent use, Path is a first-class MCP meta-tool, so you can call
it directly through the thin client without spawning a run:

```
mcp__loomcycle__path  { "op": "ls", "scope": "user", "path": "/docs" }
mcp__loomcycle__path  { "op": "mv", "scope": "user", "path": "/docs/launch", "to": "/archive/launch" }
```

It's also on HTTP (`POST /v1/_path`), gRPC (`Path` RPC), and the TS/Python
adapters (`client.path(...)`). **Scope and tenant are resolved server-side from
the authenticated principal — never sent on the wire.** Off-run `scope:"user"`
ops key on the principal's subject, so they interoperate with that user's agent
runs. The endpoint is tenant-confined (`ScopeTenant`; `substrate:admin` also
satisfies). `.mcp.json` needs no edit — the thin client auto-advertises the tool.

---

## Caveats (v1)

- **`mv` can't orphan a tree** — a move into the path's own subtree is refused.
- **`rm` is dirent-only** — it removes the *name*, not the backing resource (the
  Memory entry / Volume / Document survives, re-nameable). `resource_too`
  (cascade-delete the resource) is **not supported in v1**.
- **No per-agent `path_scopes` ACL yet** — `allowed_tools: [Path]` grants all
  scopes; a finer ACL is a follow-up.
- **Pre-existing volumes don't auto-mount** — `mount_at` registers a dirent at
  *create* time only.

Full runtime reference: the loomcycle `path` `Context op=help` topic and
`docs/PATH.md`.
