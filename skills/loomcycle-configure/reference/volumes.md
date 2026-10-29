# Volume primitive reference — RFC AH (v1.1.0+; checked against v1.126.0)

Volumes replaced the legacy env-var file jail (`LOOMCYCLE_READ_ROOT` / `WRITE_ROOT` / `BASH_CWD`)
in **v1.1.0**. A volume is the *only* way an agent gets filesystem access: an agent bound to no
volume has every file/exec tool (Read / Write / Edit / Glob / Grep / NotebookEdit / Bash /
Bashbox) refuse.

**Retiring the jail was a BREAKING CHANGE.** Any of the three retired env vars present at startup
causes a **fatal config-load error** — loomcycle refuses to start. Remove them from env files
before upgrading a running instance.

---

## Migration from legacy jail (30-second version)

The three retired vars mapped to a single directory in most configs. Collapse them:

| Retired env var | New `volumes:` equivalent |
|---|---|
| `LOOMCYCLE_READ_ROOT=/path` | `volumes: default: {path: /path, mode: ro, default: true}` |
| `LOOMCYCLE_WRITE_ROOT=/path` | `volumes: default: {path: /path, mode: rw, default: true}` |
| `LOOMCYCLE_BASH_CWD=/path` | Same directory as `WRITE_ROOT` — the volume root becomes the Bash cwd |

If all three pointed at the same dir (the typical setup), one entry does it:

```yaml
volumes:
  default:
    path: ./work     # relative to where `loomcycle serve` is run from (usually run.sh's cd)
    mode: rw         # rw covers Read + Write + Edit + Bash; ro covers Read/Grep/Glob only
    default: true
```

The operator removes the three env vars from their env files. There is no automatic conversion
from the old vars: declare the replacement volume explicitly.

---

## `volumes:` block — full reference (Phase 1)

```yaml
volumes:
  # Every agent without an explicit `volumes:` list inherits the `default:` volume automatically.
  default:
    path: ./work          # absolute or relative to the server's launch cwd
    mode: rw              # rw or ro (omitted = rw)
    default: true         # at most ONE volume may carry default: true

  # Second static volume — separate read-only repo snapshot.
  readonly-src:
    path: ./loomcycle-src
    mode: ro              # ro: Read/Grep/Glob (and Bashbox) work; Bash/Write/Edit refuse inside this volume

  # REQUIRED when any agent uses VolumeDef (Phase 2a/2b), and for the run inbox
  # (v1.122.0: files tools return are kept there — without it they are not kept).
  # Create the directory before first server start: mkdir -p ./work/dynamic
  dynamic-root:
    path: ./work/dynamic
    mode: rw
    dynamic_root: true    # backing dir for runtime-provisioned volumes; at most ONE volume may set it
```

### Field reference

| Field | Required | Values | Meaning |
|---|---|---|---|
| `path` | Yes | string | Directory path. Absolute, or relative to the server launch cwd. Must already exist and be a directory at startup; the runtime never creates it. |
| `mode` | No | `rw` \| `ro` | Omitted = `rw`. `rw` allows Read + Write + Edit + NotebookEdit + Bash. `ro` allows Read/Grep/Glob only; Write/Edit/NotebookEdit/Bash refuse. Bashbox is the exception: it accepts `ro` (writes land in an in-RAM overlay; see [bashbox.md](bashbox.md)). |
| `default` | No | bool | If `true`, agents with no explicit `volumes:` list bind here, and a tool call that omits `volume` uses it. At most one volume may set this. |
| `dynamic_root` | No | bool | Marks this volume as the backing store for VolumeDef-provisioned volumes **and the run inbox** (v1.122.0). Required for Phase 2a/2b and for keeping files tools return. At most one volume may set this. |

### Per-agent binding

Agents inherit the `default:` volume implicitly. Override explicitly when an agent needs a
different set:

```yaml
agents:
  dispatcher:
    tools: [VolumeDef, Bash, Agent]
    volumes: [default, dynamic-root]     # explicit list

  reviewer:
    tools: [Read, Grep, Glob]
    # volumes: omitted → binds to default automatically
```

An agent that declares `volumes:` is confined to **exactly those** — it does not also get
`default`. With no `default` volume declared, an agent with no `volumes:` list has no filesystem
access at all. An agent reads its own bindings with `Context op=self` (`volumes.bindings`: name,
path, mode, default).

**Access control can narrow a binding (v1.122.0).** Under `LOOMCYCLE_ACL`, a volume the run's
caller may not `write` (`volume:<name>`) is bound **read-only**, and one it may not `read` is
**dropped** — reported once at run start as a `capability_inert` event (gate `acl`). Under
`shadow` the binding is kept and the would-be narrowing only logged; with `LOOMCYCLE_ACL_LIVE=1`
(v1.126.0) the narrowing also applies mid-run. See [access-control.md](access-control.md).

**`Read` by line range (v1.113.0).** `Read` takes `offset` (first line, from 1), `limit`
(lines) and `line_numbers`; any of them turns on line mode — whole lines and a closing line
saying where it stopped (`[lines 1-2210 of 3044; cut at 256 KiB, continue with offset 2211]`).
Without them `Read` returns the first 256 KiB as before. Useful on a read-only volume of code
under review.

---

## VolumeDef tool — Phase 2a (persistent) and Phase 2b (ephemeral)

The `VolumeDef` tool lets an **agent** provision volumes at runtime, not just consume static ones.
Two gates must be open before it works:

1. **`volume_def_scopes`** on the agent — the per-agent capability gate, analogous to
   `memory_scopes:`. Values: `any` (any name) or `named:<volume>` (one name). Without a grant,
   `create` / `delete` / `purge` are refused ("agent has no volume_def_scopes (default-deny)");
   `get` and `list` are tenant-scoped reads and stay available.
2. **A volume marked `dynamic_root: true`** in the top-level `volumes:` map — VolumeDef derives
   every provisioned path under it. The directory must exist before the server starts
   (`mkdir -p`). Without one, `create` is refused.

```yaml
volumes:
  default:
    path: ./work
    mode: rw
    default: true
  dynamic-root:
    path: ./work/dynamic
    mode: rw
    dynamic_root: true

agents:
  dispatcher:
    tools: [Context, VolumeDef, Bash, Agent, Memory]
    volume_def_scopes: [any]          # gate 1 (or [named:ws] for one name)
    volumes: [default, dynamic-root]  # explicit list, so `default` must be named too
```

### VolumeDef operations (agent system_prompt usage)

```
VolumeDef op=create name="ws" mode=rw                        # persistent (tenant-scoped)
VolumeDef op=create name="ws" mode=rw ephemeral=true         # ephemeral (Phase 2b)
VolumeDef op=get    name="ws"                                 # get path + metadata
VolumeDef op=list                                             # list the tenant's dynamic volumes
VolumeDef op=delete name="ws"                                 # unmap: remove the row, KEEP the files
VolumeDef op=purge  name="ws"                                 # remove the row AND delete the directory tree
VolumeDef op=set_mode name="ws" mode=ro                       # ephemeral only: make it ro for the whole run tree (one way; v1.113.0)
```

`delete` and `purge` are not the same, and `purge` is not recoverable. `create` takes a **name and
a mode only** — never a host path. The runtime derives the location
(`<dynamic_root>/<tenant>/<name>`, or `<dynamic_root>/_shared/<name>` for the shared tenant).
Names must match `^[a-z0-9][a-z0-9_-]{0,63}$`. `create` is idempotent (same mode is a no-op, a
different mode updates the mapping) and is refused for a name that collides with a static
`volumes:` entry. **`inbox` is reserved (v1.122.0)** — it names the run tree's file inbox (an
ephemeral volume under the `dynamic_root`, made on the first captured file and purged with the
tree), so `create` refuses it. See [files.md](files.md).

The `create` result includes a `path` field — the absolute path the agent should pass to Bash
(`git clone <url> <path>/repo`) and to sub-agents as `ephemeral_path=<path>`.

Outside a run, an operator provisions the same volumes with the `volumedef` tool
(`create` / `get` / `list` / `delete` / `purge`) or `POST /v1/_volumedef` (`substrate:tenant`).
A snapshot carries a persistent dynamic volume's name and mode, never its files: restoring
re-creates an **empty** directory on the target host.

### Ephemeral volumes (Phase 2b)

`ephemeral: true` means the volume is automatically purged when the **creating run** ends — its
top-level run, not a sub-agent. The dispatcher creates the volume; when the dispatcher's run
completes (or is cancelled), loomcycle removes the directory tree and the DB row. No `rm -rf`
in the system_prompt, no cleanup step.

The path is `<dynamic_root>/_ephemeral/<root_run_id>/<name>`, so two concurrent runs never
collide on a name. It needs an active run (refused outside one), and there is no `delete` /
`purge` for an ephemeral volume — its lifetime is the run. A sweeper purges the volumes of
crashed runs (`LOOMCYCLE_EPHEMERAL_VOLUME_SWEEP_MS`, default 60 s; `0` disables the sweeper, not
the purge at run end). A paused run keeps its ephemeral volumes.

**Read-only scratch (v1.113.0).** `VolumeDef op=set_mode {name, mode: "ro"}` makes an ephemeral
volume read-only for the whole run tree at once, children already running included (`rw` is
refused). `ephemeral_volumes: ro` on an agent gives it, and every agent it spawns, all of the
run's ephemeral volumes read-only (its own `volumes:` keep their modes; a fork cannot clear it).
The mode holds across resume and replicas; `Context op=self` lists `ephemeral_volumes`.

**A repository fetched by the runtime (v1.113.0).** `VolumeDef op=create` on an ephemeral volume
can take a git source, so the forge token never enters a shell:

```json
{"op": "create", "name": "repo", "ephemeral": true, "mode": "ro",
 "source": {"git": {"url": "https://github.com/acme/app", "commit": "<40-digit sha>",
                    "credential": "$cred:repo-acme-app", "diff_base": "merge-base:default"}}}
```

Off unless `LOOMCYCLE_GIT_SOURCE_HOSTS` lists the host; the agent needs `source:git` in
`volume_def_scopes` (`any` does not include it); a credential must carry `allowed_urls` covering
the repository. Regular files only, no `.git`; `_meta/omitted.json` lists what was left out, and
`diff_base` adds `_meta/diff.patch` + `_meta/numstat.json`. A failed clone leaves nothing. Limits
are the `LOOMCYCLE_GIT_SOURCE_*` vars ([env-vars.md](env-vars.md)). For an agent that commits and
pushes, see the `Git` tool in [git.md](git.md).

**Important:** ephemeral volumes are scoped to the creating run, not to a specific sub-agent.
If the dispatcher spawns 8 reviewers, all 8 can see the same ephemeral volume (via spawn
narrowing) — but as soon as the dispatcher finishes, the volume is gone, even if a stray
sub-agent is still running.

### Spawn narrowing — sub-agents inherit volumes

A sub-agent that declares **no** `volumes:` inherits the dispatcher's volume bindings verbatim,
including any VolumeDef-provisioned volumes. A reviewer spawned by a dispatcher that holds
`lc-src` then has `lc-src` in its bindings. A sub-agent that **does** declare `volumes:` is
narrowed to (what it declares) ∩ (what the parent holds), with the more restrictive mode (`ro`)
winning. A child can never gain a volume its parent lacks; a child that shares none of the
parent's volumes has its file tools denied.

Reviewers address files via the `volume=` parameter on Read/Grep/Glob:
```
Read path="loomcycle/internal/api/server.go" volume="lc-src"
Glob pattern="loomcycle/**/*.go" volume="lc-src"
```

If the sub-agent omits `volume=`, it resolves against the `default` volume. The `lc-src` volume
is only reachable by its name — it doesn't replace `default`.

---

## Validation and diagnostics

```bash
# Validate config including volume block resolution (the retired-env fatal check runs here):
loomcycle validate loomcycle.yaml

# Volume list: static volumes plus the caller's tenant's dynamic ones (substrate:tenant):
curl -s -H "Authorization: Bearer $LOOMCYCLE_AUTH_TOKEN" \
  http://localhost:8787/v1/_volumes | jq .
# Live ephemeral volumes of the caller's tenant: GET /v1/_volumes/ephemeral

# Confirm dynamic-root directory exists before start:
ls work/dynamic/    # should exist and be writable
```

**Config-load errors for volumes** (`loomcycle validate` and startup):

| Error | Fix |
|---|---|
| `LOOMCYCLE_READ_ROOT … retired in RFC AH Phase 3 — declare a volumes: block instead …` | Remove the var from env. Use a `volumes:` block. |
| `agent "X": volumes[N]: unknown volume "Y" (declare it in the top-level volumes: map)` | Declare `Y` under `volumes:` or remove it from the agent's `volumes:` list. |
| `volumes.X: path "…" must already exist` / `… is not a directory` | Create the directory before starting. |
| `volumes.X: invalid mode "…" (want "rw", "ro", or empty for rw)` | Fix the mode. |
| `volumes: at most one volume may be default:true` | Set `default: true` on exactly one volume. |
| `volumes: at most one volume may be dynamic_root:true` | Mark exactly one volume `dynamic_root: true`. |
| `agent "X": volume_def_scopes[N]: unknown scope "…" (want "any" or "named:<volume-name>")` | Use `any` or `named:<volume>` (plus `source:git` for an agent that fills a volume from a git source). |

Not config errors, but refusals at run time: `VolumeDef create` answers "no dynamic volume root
configured" when no volume is marked `dynamic_root: true`, and every file/exec tool refuses when
the agent is bound to no volume (no `default` volume and no `volumes:` list). With no
`dynamic_root`, a file a tool returns is not kept — the model sees `[file not kept: …]`. A git
source with `LOOMCYCLE_GIT_SOURCE_HOSTS` unset answers `git_source_disabled`. Since v1.119.0 a
traverse-only directory inside a volume (mode `0100`, or a `0300` drop box) is refused.

---

## Example: ephemeral-volume code review fan-out

See `examples/exp8-ephemeral-volume-review/loomcycle.yaml` in the loomcycle repo for the
canonical Phase 2b pattern: dispatcher creates ephemeral volume → clones repo → fans out 8
reviewers → auto-purge on run end.
