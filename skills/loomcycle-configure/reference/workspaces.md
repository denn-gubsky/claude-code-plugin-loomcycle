# Workspaces — where an agent runs commands (v1.172.0+)

Since loomcycle **v1.172.0** an agent runs shell commands, scripts and servers
only in a **workspace**: a directory on a *workspace worker*, a process apart
from the runtime, reached through the `Workspace` tool. The `Bash` tool,
Bashbox (with its host-command fallback), the `shell_credentials` agent field,
the `sandbox` and `dev-exec` bundles with their builder sidecar
(`mcp__sandbox__*`), and the `loomcycle-toolbox` image are **removed**.

The authoritative guides are in the loomcycle repo: `docs/WORKSPACES.md`
(the tool, grants, engines, egress), `docs/WORKERS.md` (running workers and
their images) and `docs/MIGRATING-FROM-BASH.md` (every removed item and its
replacement). This page is the short version.

## What refuses the start

Operator config that still names a removed item stops the server at start,
with one error listing every use and the line to change (`loomcycle doctor`
shows the same lines under its "Removed" check):

- Any of these variables set to a non-empty value: `LOOMCYCLE_BASH_ENABLED`,
  `LOOMCYCLE_BASH_ALLOWED_CREDS`, `LOOMCYCLE_BASHBOX_ENABLED`,
  `LOOMCYCLE_BASHBOX_FALLBACK_COMMANDS`, `LOOMCYCLE_BASHBOX_FALLBACK_ALLOWED_ENV`,
  `LOOMCYCLE_BASHBOX_FALLBACK_ALLOWED_CREDS`, `LOOMCYCLE_BASHBOX_OVERLAY_MAX_BYTES`.
  (Set but empty, each is reported as a dead line.)
- `LOOMCYCLE_PRESETS` (or `presets:`) naming `sandbox` or `dev-exec`: select
  `dev-workspace` instead. Its `dev/exec` takes the old sandbox command envelope
  and runs it in a workspace.
- A yaml or markdown agent whose `tools` names `Bash` or `Bashbox`, or that sets
  `shell_credentials` (even `[]`).

**Stored definitions keep running.** An `AgentDef` (or a TeamDef's inline
agent) already in the store that names `Bash`, `Bashbox` or `shell_credentials`
runs without the item; each run starts with one `capability_inert` event,
gate `removed`, naming it, and `Context op=self` lists it under `deprecations`.
A new `create`, `register_agent` or `fork` overlay naming one is refused; a
fork that only inherits one has it stripped. Fork such a definition without
the item, and with `Workspace`, so its runs can still run commands.

ACL rules and hook definitions naming `tool:Bash` stay valid and match
nothing; rewrite them for `tool:Workspace` if they still mean something.

## Turning workspaces on

`workspace.mode` in `loomcycle.yaml`: `off` (default) | `local` | `remote` |
`local+remote`.

- **`local`** — the runtime starts one worker itself as a child, on a private
  Unix socket; no endpoint or token to set up. It runs every command **as the
  runtime's own user, with no isolation** (like the old `Bash`): it can read
  the runtime's data directory, config and secrets. Only for a single machine
  where you trust every agent.
- **`remote`** — workers run as their own processes (`loomcycle worker --role
  workspace`) and attach to `worker_endpoint.listen`, each with a token whose
  only scope is `workers:attach`. Run them with
  `LOOMCYCLE_WORKSPACE_ENGINE=container` to give each workspace its own
  container: no network but egress routes, read-only root, no capabilities,
  non-root, memory/CPU/process limits.

Images for a containerized worker: `denngubsky/loomcycle-ws-worker:<version>`
(the worker plus a docker client; drives the host's daemon through its socket)
starts sessions from `denngubsky/loomcycle-workspace:<version>` (Python, Node,
git, document helpers) or `denngubsky/loomcycle-workspace-browser:<version>`.
Use the tag of the runtime's own version. The runtime itself stays on the
distroless `denngubsky/loomcycle` image.

```yaml
# runtime — a remote, containerized worker attaches here
worker_endpoint:
  listen: 0.0.0.0:7788     # off loopback: worker_endpoint.tls, or insecure: true on a private network
workspace:
  mode: remote
```

```sh
# the worker's machine (or a loomcycle-ws-worker container)
LOOMCYCLE_WORKER_DISPATCHER=runtime.internal:7788 \
LOOMCYCLE_WORKER_TOKEN=<a workers:attach token> \
LOOMCYCLE_WORKSPACE_ROOT=/var/lib/loomcycle/workspaces \
LOOMCYCLE_WORKSPACE_ENGINE=container \
LOOMCYCLE_WORKSPACE_CONTAINER_IMAGE=denngubsky/loomcycle-workspace:<version> \
loomcycle worker --role workspace
```

Mint the worker token with `loomcycle operator-token create --name <n>
--tenant <t> --subject <n> --scopes workers:attach` (the legacy
`LOOMCYCLE_AUTH_TOKEN` and admin tokens are refused); the worker presents it
as its `LOOMCYCLE_WORKER_TOKEN`.

## The agent grant

An agent reaches workspaces only with `Workspace` in `tools` **and** a
`workspace` grant; one without the other does nothing (boot and `doctor` name
such agents):

```yaml
agents:
  coder:
    tools: [Read, Write, Edit, Workspace, File]
    workspace:
      ops: [read, write, exec]   # any of read, write, exec
      open: true                 # may open workspaces of its own
      egress: [pypi, pypi-files, npm]   # only if it installs packages
```

The agent opens a workspace (`Workspace op=open`), runs commands in it
(`op=exec`), and moves files in and out with the `File` tool. A workspace
belongs to the run that opened it and is deleted when that run ends. The grant
is not per-run overridable, and a tenant member cannot set it on an agent they
author.

## Credentials: egress routes, not shell variables

A workspace session receives no credential and no host variable. A script
reaches an API through an **egress route** (`workspace.egress.routes` in yaml,
or a tenant's `EgressRouteDef`); the core adds the route's credential to the
request on the way out:

```yaml
workspace:
  egress:
    routes:
      crm:
        url: "https://api.crm.example/v2/"
        credential: "$cred:crm_token"
agents:
  coder:
    workspace: {ops: [read, write, exec], open: true, egress: [crm]}
```

A script then calls `"${LOOMCYCLE_EGRESS}crm/deals"`. The embedded `workspace`
preset declares read-only `pypi`, `pypi-files` and `npm` routes. On the `local`
worker (the `host` engine) egress also needs `LOOMCYCLE_WORKSPACE_HOST_EGRESS=1`,
and there it is a convenience, not a boundary. For git work, prefer the `Git`
tool ([git.md](git.md)) or a git workspace opened with a credential
(`Workspace op=open {repo, credential}`).

## Choosing a posture

| Need | Use |
|---|---|
| Read files only | Volumes + `Read`/`Grep`/`Glob` ([volumes.md](volumes.md)); no workspace |
| Run code, trusted prompts, one machine | `workspace.mode: local` |
| Run code from untrusted or model-authored prompts | `remote` workers on the `container` engine (optionally gVisor/Kata via `LOOMCYCLE_WORKSPACE_CONTAINER_RUNTIME`); grant `engine: container` |
| Pure logic, no toolchain | code-js agents ([profiles.md §3](profiles.md)) |

A workspace is not reachable over loomcycle's MCP server: it is pinned to a
run, and an MCP session has none.
