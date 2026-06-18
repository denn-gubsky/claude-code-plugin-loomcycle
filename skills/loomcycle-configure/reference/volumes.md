# Volume primitive reference — RFC AH (v1.0.3+)

Volumes replaced the legacy env-var file jail (`LOOMCYCLE_READ_ROOT` / `WRITE_ROOT` / `BASH_CWD`)
starting with RFC AH Phase 1. All four phases shipped in **v1.0.3**.

**Phase 3 (v1.0.3) is a BREAKING CHANGE.** Any of the three retired env vars present at startup
now causes a **fatal config-load error** — loomcycle refuses to start. Remove them from env files
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

Remove the three env vars from `.env.local` / `.env.insecure`. Keep them commented out if you
need to roll back to a v0.x binary.

---

## `volumes:` block — full reference (Phase 1)

```yaml
volumes:
  # Every agent without an explicit `volumes:` list inherits the `default:` volume automatically.
  default:
    path: ./work          # absolute or relative to the server's launch cwd
    mode: rw              # rw or ro
    default: true         # at most ONE volume may carry default: true

  # Second static volume — separate read-only repo snapshot.
  readonly-src:
    path: ./loomcycle-src
    mode: ro              # ro: Read/Grep/Glob work; Bash/Write/Edit refuse inside this volume

  # REQUIRED when any agent uses VolumeDef (Phase 2a/2b).
  # Create the directory before first server start: mkdir -p ./work/dynamic
  dynamic-root:
    path: ./work/dynamic
    mode: rw
    dynamic_root: true    # marks this as the backing dir for runtime-provisioned volumes
```

### Field reference

| Field | Required | Values | Meaning |
|---|---|---|---|
| `path` | Yes | string | Directory path. Absolute, or relative to the server launch cwd. Must exist at startup. |
| `mode` | Yes | `rw` \| `ro` | `rw` allows Read + Write + Edit + Bash. `ro` allows Read/Grep/Glob only; Write/Edit/Bash refuse. |
| `default` | No | bool | If `true`, agents with no explicit `volumes:` list bind here. At most one volume may set this. |
| `dynamic_root` | No | bool | Marks this volume as the backing store for VolumeDef-provisioned volumes. Required for Phase 2a/2b. |

### Per-agent binding

Agents inherit the `default:` volume implicitly. Override explicitly when an agent needs a
different set:

```yaml
agents:
  dispatcher:
    allowed_tools: [VolumeDef, Bash, Agent]
    volumes: [default, dynamic-root]     # explicit list

  reviewer:
    allowed_tools: [Read, Grep, Glob]
    # volumes: omitted → binds to default automatically
```

When `volumes:` is explicitly set (even to `[]`), the implicit `default:` binding is suppressed.
Use an explicit list whenever an agent needs `dynamic-root` or a named non-default volume.

---

## VolumeDef tool — Phase 2a (persistent) and Phase 2b (ephemeral)

The `VolumeDef` tool lets an **agent** provision volumes at runtime, not just consume static ones.
Two gates must be open before it works:

1. **`volume_def_scopes: [any]`** on the agent — the per-agent capability gate, analogous to
   `memory_scopes:`. Without it every `VolumeDef` call is refused with "not enabled for this agent".
2. **A `dynamic-root` volume** in `volumes:` — VolumeDef stores provisioned volumes under it.
   The directory must exist before the server starts (`mkdir -p`).

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
    allowed_tools: [Context, VolumeDef, Bash, Agent, Memory]
    volume_def_scopes: [any]          # gate 1
    volumes: [default, dynamic-root]  # gate 2: dynamic-root in the binding list
```

### VolumeDef operations (agent system_prompt usage)

```
VolumeDef op=create name="ws" mode=rw                        # persistent
VolumeDef op=create name="ws" mode=rw ephemeral=true         # ephemeral (Phase 2b)
VolumeDef op=get    name="ws"                                 # get path + metadata
VolumeDef op=list                                             # list all volumes for this run's tenant
VolumeDef op=purge  name="ws"                                 # delete DB row + directory tree
```

The `create` result includes a `path` field — the absolute path the agent should pass to Bash
(`git clone <url> <path>/repo`) and to sub-agents as `ephemeral_path=<path>`.

### Ephemeral volumes (Phase 2b)

`ephemeral: true` means the volume is automatically purged when the **creating run** ends — its
top-level run, not a sub-agent. The dispatcher creates the volume; when the dispatcher's run
completes (or is cancelled), loomcycle removes the directory tree and the DB row. No `rm -rf`
in the system_prompt, no cleanup step.

**Important:** ephemeral volumes are scoped to the creating run, not to a specific sub-agent.
If the dispatcher spawns 8 reviewers, all 8 can see the same ephemeral volume (via spawn
narrowing) — but as soon as the dispatcher finishes, the volume is gone, even if a stray
sub-agent is still running.

### Spawn narrowing — sub-agents inherit volumes

Sub-agents spawned by a dispatcher **inherit the dispatcher's full volume binding set**, including
any VolumeDef-provisioned volumes. A reviewer spawned by a dispatcher that holds `lc-src`
automatically has `lc-src` in its bindings.

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
# Validate config including volume block resolution (Phase 3 fatal check runs here):
loomcycle validate loomcycle.yaml

# Live volume list (all VolumeDef-provisioned volumes):
curl -s -H "Authorization: Bearer $LOOMCYCLE_AUTH_TOKEN" \
  http://localhost:8787/v1/_volumes | jq .

# Confirm dynamic-root directory exists before start:
ls work/dynamic/    # should exist and be writable
```

**`loomcycle validate` config-load errors for volumes:**

| Error | Fix |
|---|---|
| `LOOMCYCLE_READ_ROOT (or WRITE_ROOT / BASH_CWD) is set but retired (RFC AH Phase 3)` | Remove the var from env. Use `volumes:` block. |
| `volumes: referenced volume "X" not defined` | Declare `X` under `volumes:` or remove it from the agent's `volumes:` list. |
| `volumes: dynamic-root required for VolumeDef` | Add a `dynamic_root: true` volume to `volumes:`. |
| `volumes: more than one volume has default: true` | Set `default: true` on exactly one volume. |
| `volumes: no default volume and agent has no explicit volumes list` | Either add `default: true` to one volume, or add an explicit `volumes:` list to the agent. |

---

## `defaults:` block — required for `loomcycle validate`

The `loomcycle validate` command runs a **static dry-run model resolver** (the pin path, not the
live tier resolver). Agents using `tier:` are resolved through a fallback chain that requires a
`defaults:` entry when no agent has an explicit `provider:` + `model:` pin:

```yaml
# Add this block to satisfy loomcycle validate. Inert at runtime.
defaults:
  provider: deepseek
  model:    deepseek-v4-pro
```

At runtime the tier resolver ignores `defaults:` entirely — `provider_priority` + `tiers` +
`user_tiers` govern every run. The block's sole purpose is satisfying the validate dry-run.

Without it, `loomcycle validate` errors: `agent "X": no provider resolved`.

---

## Example: ephemeral-volume code review fan-out

See `examples/exp8-ephemeral-volume-review/loomcycle.yaml` in the loomcycle repo for the
canonical Phase 2b pattern: dispatcher creates ephemeral volume → clones repo → fans out 8
reviewers → auto-purge on run end. The `defaults:` block is present so `loomcycle validate`
passes without a live provider.
