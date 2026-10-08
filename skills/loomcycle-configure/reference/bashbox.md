# Bashbox reference — RFC AJ (v1.3.0+; checked against v1.107.0)

`Bashbox` is a **TRUE in-process shell sandbox** — the isolated alternative to
the `Bash` tool. It runs shell commands via [gbash](https://github.com/ewhauser/gbash)
(pure-Go, Apache-2.0): **no OS process is spawned**, every path is rooted at the
bound volume, and there is **no network**. Where `Bash` is "restricted, not
isolated" (it shells out via `os/exec`, leaking the host), Bashbox's isolation is
real — so it can do something `Bash` can't: **honor read-only volumes**.

Opt-in exactly like Bash, in two layers:

1. **`LOOMCYCLE_BASHBOX_ENABLED=1`** — the operator env flag (per deployment).
2. **`tools: [Bashbox]`** — the per-agent gate.

Stateless per call (no shell state persists between invocations). Input:
`command` (required; use paths relative to the volume root), `volume` (optional),
and `timeout_seconds` (optional per-call cap, ceiling 300 s). A non-zero exit is
returned as an error with the output kept.

> Bashbox is an **in-band** tool — an agent calls it during a run. It is **not**
> an MCP meta-tool, so (unlike `path`/`document`) there is no `bashbox` tool you
> can call from Claude Code; you enable it and let agents use it. Reach for it from a `system_prompt`, an `AgentDef`, or a
> `loomcycle.yaml` agent block.

---

## Bash vs Bashbox — which to use

| | `Bash` | `Bashbox` |
|---|---|---|
| Isolation | cwd-restricted, env-scrubbed — **not a sandbox** | **true in-process sandbox** (gbash; no OS process, no network) |
| Read-only volume | **refuses** a `ro` volume (can't enforce it) | **honors** `ro` — writes hit an in-RAM overlay, never the host |
| Host binaries | yes (real `/bin/sh`, `git`, `curl`, …) | only gbash builtins + bundled `awk`/`jq` (~97% `/bin/sh` parity); `git`/network absent by default |
| Network | yes (subject to no tool-level guard) | **none** |
| Enable | `LOOMCYCLE_BASH_ENABLED=1` + `tools:[Bash]` | `LOOMCYCLE_BASHBOX_ENABLED=1` + `tools:[Bashbox]` |

**Recommendation:** prefer **Bashbox** for untrusted prompts or read-only work
(it's the sandbox `Bash` only pretends to be). Use **Bash** only when the agent
genuinely needs an actual host binary or network — and only inside a
containerized deployment (profile 2/3).

---

## Volume binding (same model as Bash + the file tools)

Bashbox resolves all paths against the agent's bound **Volume** (see
[volumes.md](volumes.md)). It accepts the same optional `volume="name"` argument
as the file tools; omitted → the agent's `default` volume.

The key asymmetry: **Bashbox accepts a `ro` volume.** A `ro` binding mounts under
an in-RAM write overlay, so a script's writes succeed *in-run* but never touch
the host tree — the read-only guarantee RFC AH left open for `Bash` (which
refuses `ro` rather than ship a false promise).

```yaml
volumes:
  src:
    path: ./repo-snapshot
    mode: ro            # Bashbox can still "write" here (overlay); Bash would refuse
    default: true

agents:
  analyzer:
    tools: [Read, Grep, Glob, Bashbox]   # no Bash — true-sandbox posture
    # binds to `src` (default) automatically
```

---

## Host-command fallback — RFC AJ §13 (operator opt-in, OFF by default)

Commands gbash doesn't implement (`git`, `gh`, …) normally **fail** inside
Bashbox. An operator can allowlist specific ones to fall through to the **real
host shell**:

```bash
# .env.insecure (names only — safe to commit/read; NOT secrets)
LOOMCYCLE_BASHBOX_FALLBACK_COMMANDS=git,gh
# Credentials those host commands may see (injected into the host child ONLY,
# never the sandbox env — the model can't read them via `env`):
LOOMCYCLE_BASHBOX_FALLBACK_ALLOWED_ENV=GH_TOKEN,HOME,SSH_AUTH_SOCK
# Per-tenant counterpart: stored credentials (by name, see credentials.md) resolved
# for the run's own tenant/user/agent and injected the same way. A resolved
# credential overrides a same-named host env var. Needs LOOMCYCLE_SECRET_KEY.
LOOMCYCLE_BASHBOX_FALLBACK_ALLOWED_CREDS=GITHUB_TOKEN
```

`PATH` always passes to a fallback command.

How it stays contained:

- **Only the allowlisted names escape.** `git status; curl evil.com` runs `git`
  on the host but `curl` stays sandboxed — no smuggling.
- **Requires a read-write volume.** A host process can't honor the in-RAM `ro`
  overlay, so a fallback command on a `ro` volume is refused.
- **cwd is mapped to the host path** for the script's working directory
  (containment-checked against the volume root).
- **Inherently has host filesystem + network** for the allowlisted command — it
  *is* a real host process. A loud boot `WARNING:` fires whenever it's
  configured. Treat enabling it as moving that command back to profile-1 trust.

`GH_TOKEN` etc. are still referenced by **env-var name** — never put a token
value in any file (SKILL.md safety rule #2). The plugin never reads `.env.local`.

---

## Caveats

- **gbash is alpha and pinned** to an exact version. Coverage is high (~97%
  `/bin/sh` on a representative agent corpus) but not total — a missing builtin
  fails the command (use the host-command fallback for the few you need, or
  fall back to `Bash` in a contained deployment). The per-agent `tools`
  gate is the escape hatch.
- **No network** without the fallback — agents that fetch should use the
  `HTTP`/`WebFetch`/`WebSearch` tools (host-allowlisted), not Bashbox.
- Like every exec/file tool, Bashbox refuses entirely if the agent has **no**
  volume binding (sandbox-by-default, RFC AH Phase 3).

---

## When the agent needs a real toolchain

Bashbox has no compilers, interpreters or package managers, and the default
`denngubsky/loomcycle` image is distroless, so `Bash` has no `/bin/sh` there
either. Two operator options, traded off on isolation:

| Option | What it is | Use when |
|---|---|---|
| `denngubsky/loomcycle-toolbox` image | The same loomcycle binary on a Debian base with Python, Go, Rust, C/C++, Node + npm, `git`, `gh`, `curl` baked in. Code runs **inside loomcycle's own container** — no per-command sandbox | A trusted, single-tenant deployment |
| Builder-sidecar sandbox | Each session runs in a separate, ephemeral container (network off by default, read-only rootfs, resource caps). loomcycle drives it over HTTP-MCP: enable `LOOMCYCLE_PRESETS=base,sandbox,dev-exec`; the tools are `mcp__sandbox__sandbox_open` / `_exec` / `_write` / `_read` / `_close` / `_list` | Untrusted code, or a multi-tenant deployment |

A headless browser for web-UI testing (`mcp__browser__*`) needs the runtime run
as the `denngubsky/loomcycle-browser` image plus a `pinchtab/pinchtab` sidecar,
and the sidecar sandbox also needs `LOOMCYCLE_CODE_AGENTS_ENABLED=1` for its
`dev/exec` agent. Setup for all three is in the
loomcycle repo's `docs/TOOLBOX_IMAGE.md` and `docs/SANDBOX.md`.

See the loomcycle `bashbox` `Context op=help` topic and `docs/TOOLS.md` for the
runtime-side detail.
