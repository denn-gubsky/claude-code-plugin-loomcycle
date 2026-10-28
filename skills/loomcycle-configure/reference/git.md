# Git tool reference (v1.122.0+; checked against v1.126.0)

`Git` works on a git repository inside a volume an agent is bound to. It runs
git **inside the loomcycle process** (go-git), not as a program on the host:

- **No `git` process.** Nothing a repository's configuration names ever runs:
  no hooks, no `core.fsmonitor`, no filter drivers, no credential helpers.
  System git config is never read.
- **No token in the model's shell.** A network op names a stored credential;
  the runtime resolves it and sends it to one host. The model never sees the
  value, and it is never written into `.git/config`, a URL, or the result.
- **No server text.** A network failure reaches the model as a class
  (`auth_failed`, `not_found`, …); the remote's own words go to the operator log.

It is the safe alternative to allowlisting `git` as a Bashbox host command or
giving `Bash` a `GITHUB_TOKEN`, where the model can print the credential.

Enable it per agent with `tools: [Git]` — it is always registered, with no
deployment flag. Local work needs only a bound volume; the network has its own
gates (below).

> `Git` is an **in-band** tool — an agent calls it during a run. There is no
> MCP meta-tool for it; you enable it on an agent and let the agent use it.
> The `Git` help topic (`Context op=help`) lists every argument of every op.

---

## Choosing the repository

Every op takes:

| Argument | Meaning |
|---|---|
| `volume` | the volume (omit for the agent's default volume). `Context op=self` lists the agent's volumes |
| `repo` | the repository's directory, relative to the volume root (omit for the root). `init` and `clone` create it when missing; a clone needs it empty |

Read ops work on a read-only volume. Everything that changes the repository
needs a **read-write** volume; on a `ro` one it fails with `volume_refused`.

---

## Operations

### Read (any volume mode)

| op | What it does | Main arguments |
|---|---|---|
| `status` | current branch, every changed or untracked file | — |
| `log` | commits, newest first | `rev`, `paths`, `max` (default 20, at most 200), `since`, `until`, `all` |
| `show` | one commit and its patch | `rev` (default HEAD), `max_bytes` |
| `diff` | unified diff | none = unstaged; `staged`; `from` (worktree vs a revision); `from` + `to`; `paths`, `max_bytes` |
| `blame` | who last changed each line | `paths` (one file), `rev`, `max` (default 500, at most 2000) |
| `grep` | search a **commit's** files, not uncommitted changes | `pattern`, `rev`, `paths`, `ignore_case`, `invert`, `max` (default 100, at most 500) |
| `branch_list`, `tag_list`, `remote_list` | what exists | — |
| `notes_list` | git notes on recent commits | `rev`, `max` |
| `submodule_list` | submodules and their recorded commits | — |
| `merge_base` | common ancestor | `from`, `to` |
| `rev_parse` | a revision's full hash | `rev` |

Read file contents with the `Read` tool, not `Git`.

### Change (read-write volume)

| op | What it does | Main arguments |
|---|---|---|
| `init` | new repository | `initial_branch` (default `main`) |
| `add` / `rm` / `mv` | stage / delete and stage / rename | `paths` (`.` = everything); `cached` on `rm`; `from`, `to` on `mv` |
| `restore` | discard worktree changes, or unstage with `staged` | `paths` |
| `reset` | move the branch | `mode` soft / mixed (default) / hard, `rev`, `paths` (mixed only) |
| `commit` | record the staged changes | `message`, `all`, `amend`, `allow_empty`, `sign_key`, `sign_key_scope` |
| `checkout` | switch branch or detach at a revision | `branch` or `rev`, `create`, `force`, `sparse` (directories for a sparse checkout) |
| `branch_create`, `branch_delete` | | `branch`, `rev`, `force` |
| `tag_create`, `tag_delete` | lightweight tag, or annotated with `message` | `tag`, `rev`, `message`, `force`, `sign_key` |
| `remote_add`, `remote_remove`, `remote_set_url` | manage remotes | `remote`, `url` (https only; the host is checked at use, not here) |
| `merge` | **fast-forward only** | `rev` |
| `clean` | remove untracked files | `dirs`, `dry_run` |

`checkout` is stricter than the git program: any uncommitted change to a
tracked file refuses it (`worktree_dirty`) unless `force`.

### Network (gated — see next section)

| op | What it does | Needs |
|---|---|---|
| `clone` | copy a repository into the volume (`url`, `credential`, `branch`, `depth`, `single_branch`, `no_checkout`). A failed clone leaves nothing behind | rw, `fetch` |
| `fetch` | update remote-tracking branches (`remote`, `credential`, `refspecs`, `prune`, `tags`) | rw, `fetch` |
| `pull` | fetch and **fast-forward** the current branch | rw, `fetch` |
| `ls_remote` | list a remote's refs, no repository needed | `fetch` |
| `submodule_update` | clone/fetch one submodule at its recorded commit (`submodule`, `credential`) | rw, `fetch` |
| `push` | publish (`remote`, `credential`, `refspecs`, `force`, `force_with_lease`, `tags`); `":refs/heads/x"` deletes a remote branch | rw, `fetch` + `push` |

### Not available

**Cherry-pick, rebase, revert, stash, and any merge or pull that is not a
fast-forward** (go-git v5 has no three-way merge). On `non_fast_forward` the
branches diverged: fetch, inspect with `log` / `diff`, and continue another
way (e.g. a new branch from the remote's tip).

---

## Network access

Off by default. Three layers must all agree:

| Layer | Setting | Effect |
|---|---|---|
| Agent | `git_remote: [fetch]` | `clone`, `fetch`, `pull`, `ls_remote`, `submodule_update` |
| Agent | `git_remote: [fetch, push]` | also `push`. `[push]` alone is refused, as is any other value |
| Deployment | `LOOMCYCLE_GIT_SOURCE_HOSTS` | hosts a fetch may reach (`host` or `host:port`, comma-separated). Unset = no network (`git_network_disabled`) |
| Deployment | `LOOMCYCLE_GIT_PUSH_HOSTS` | hosts a push may reach — a **separate** list. Unset = no push (`git_push_disabled`) |
| Deployment | `LOOMCYCLE_GIT_PUSH_MAX_BYTES` | bytes one push may send (default 100 MiB; a malformed or non-positive value refuses the boot) |

- `git_remote` unset or `[]` = local repositories only. It is **not
  overridable per run**, and a sub-agent may do an op only when both it and its
  parent may (also on resume). `Context op=self` reports the effective
  `git_remote`. A boot warning flags `push` granted while `LOOMCYCLE_GIT_PUSH_HOSTS`
  is empty.
- **https only.** The runtime replaces go-git's `file`, `git`, `ssh` and plain
  `http` transports with refusing ones. Clone URLs may carry no user,
  password, query or fragment.
- **Checked at use.** A fetch, pull or push dials the remote URL as the
  repository's config gives it (`url.<base>.insteadOf` rewrites included) and
  checks it against the host list **every time**, so editing `.git/config`
  between calls changes nothing. No redirect is followed.
- Fetches share the git-source limits (bytes, object size, timeout,
  concurrency — see "Runtime-fetched git sources" below).

---

## Credentials

A network op takes `credential: "$cred:<name>"` or `"$ghapp:<name>"`. Omit it
for a public repository.

- **Must be restricted with `allowed_urls`** covering the repository. An
  unrestricted credential is refused (`credential_url_not_allowed`): whoever can
  write `.git/config` can change the remote URL, and the restriction is what
  keeps the token from following it. Matching is by host and whole path
  segments — `https://github.com/acme/app` covers `…/acme/app.git`, not
  `…/acme/app-fork`. For a submodule the credential must cover the
  **submodule's** URL.
- Sent as HTTP basic auth over https to that one host, masked in the
  transcript. User name: the credential's `username` if set, else `oauth2` for a
  host with a `gitlab` label and `x-access-token` otherwise; `$ghapp:` always
  uses `x-access-token`.
- **`$ghapp:` (GitHub App)** mints a token for the one repository:
  `contents: read` for clone/fetch/pull/ls_remote, `contents: write` for push
  only, from a resolver no read path uses. A push is refused without asking
  GitHub when the stored config's `permissions` grant contents less than
  `write`; a config without `permissions` gets what the installation was
  granted. A GitHub Enterprise `base_url` on a private network must be in
  `LOOMCYCLE_HTTP_PRIVATE_HOST_ALLOWLIST`.
- **`$cred:`** is used as stored — give push a token that may write, and keep
  read-only agents on a read-only token.
- Expired credentials (`expires_at`) are refused wherever they resolve.
- **Audit.** With `LOOMCYCLE_AUDIT_LOG_PATH` set, every network op writes a
  record (`git_clone`, `git_push`, …) with host, repository, refs updated,
  outcome and the credential's **reference**, never its value.

```jsonc
// store a token restricted to one repository (CredentialDef / credentialdef)
{"op":"create","scope":"tenant","name":"github-acme-app","value":"<token>",
 "allowed_urls":["https://github.com/acme/app"]}
```

See [credentials.md](credentials.md).

---

## Commits: identity, trailer, signing

- **Author and committer** are `LOOMCYCLE_GIT_AUTHOR_NAME` /
  `LOOMCYCLE_GIT_AUTHOR_EMAIL` (default: the agent's name at
  `<agent>@loomcycle.invalid`). The model cannot choose them.
- Every commit message gets a **`Loomcycle-Run: <run id>`** trailer, so a
  reviewer can trace it to the run.
- **Signing.** `commit` and `tag_create` (annotated) take `sign_key`: the name
  of an **`ed25519`** crypto key the run's **`crypto_scopes`** reach
  (`sign_key_scope` = `agent` / `user` / `tenant` when the name exists in more
  than one). Make the key with `CredentialDef op=generate key_type=ed25519` —
  nobody ever sees the material.
  - `crypto_scopes` is the gate; the agent does **not** need `Crypto` in
    its tools.
  - The signature is git's SSH format (`gpg.format=ssh`). The result's
    `signed_by` is the public half as an `ssh-ed25519 …` line, for an
    allowed-signers file.
  - Each signature spends one op of the run's Crypto budget and is audited as
    `crypto_op` `git_sign`.
  - Errors: `sign_key_refused` (out of scope, not an ed25519 key the runtime
    holds, or budget spent — the detail says which), `signing_unavailable`.

---

## Submodules

`submodule_list` reads `.gitmodules` (a relative URL resolves against
`origin`). `submodule_update` clones or fetches **one** submodule at the commit
the superproject records, as a repository with its own `.git`. Its URL is
repository content, so it is checked like any remote: https, a host in
`LOOMCYCLE_GIT_SOURCE_HOSTS`, `git_remote: [fetch]`. **Not recursive.**

---

## Bounds and safety

| Bound | Value |
|---|---|
| Entries a checkout / merge / pull / reset / restore may write | `LOOMCYCLE_GIT_SOURCE_MAX_FILES` (default 100000) |
| Bytes such a tree may expand to | 1 GiB (fixed) |
| `blame`, `grep`, `notes_list` | the same expansion limits plus a 2-minute deadline (`source_too_large`, `timeout`) |
| Lists (status files, branches, tags, remotes, submodules) | cut at 1000 with `truncated: true` |
| `show` / `diff` patch | `max_bytes`, at most 1 MiB, with `truncated` |
| One push | `LOOMCYCLE_GIT_PUSH_MAX_BYTES` (`upload_too_large`) |

- The target tree is walked **before** anything moves; over a limit the op is
  refused with `source_too_large` and HEAD, the index and the files are as they
  were. A failed reset, checkout or merge restores HEAD, the branch and index.
- `LOOMCYCLE_GIT_SOURCE_MAX_FILE_BYTES` does **not** apply to the Git tool.
- **Path safety.** The worktree and `.git` are walked one verified directory
  handle at a time (same as `Write`), so a symlink swapped into a path cannot
  carry a write out of the volume, and no write lands inside `.git` (a tree
  holding a path into `.git` is refused).
- Ops on one repository run one at a time.
- **Unix only** (Linux, macOS). Elsewhere the tool refuses.

---

## Runtime-fetched git sources (v1.113.0+)

Before the Git tool, an agent could be handed a repository the runtime fetched
itself — still the right choice for **read-only review** of one commit. An
agent with `VolumeDef` creates an **ephemeral** volume with a git source; the
runtime fetches the commit and writes its tree; every agent of the run tree
reaches it by name.

```jsonc
{"op": "create", "name": "repo", "ephemeral": true, "mode": "ro",
 "source": {"git": {"url": "https://github.com/acme/app",
                    "commit": "<40-digit sha>",
                    "ref": "refs/heads/feature-x",
                    "credential": "$cred:github-acme-app",
                    "diff_base": "merge-base:default"}}}
```

| `source.git` field | Meaning |
|---|---|
| `url` | https repository URL; host must be in `LOOMCYCLE_GIT_SOURCE_HOSTS` |
| `commit` | full 40-digit sha — one commit is fetched |
| `ref` | optional ref to look for the commit on |
| `credential` | `$cred:` / `$ghapp:` with `allowed_urls` covering the URL (a `$ghapp:` token is narrowed to the repo, `contents: read`) |
| `max_bytes` | may lower `LOOMCYCLE_GIT_SOURCE_MAX_BYTES` |
| `diff_base` | `merge-base:default` or a sha → `_meta/diff.patch` + `_meta/numstat.json` |
| `outputs` | `{diff, numstat}`: other names for those files under `_meta/` |

- **Who may ask:** `VolumeDef` in `tools`, `source:git` in
  `volume_def_scopes` (`any` does **not** include it), the usual grant for the
  name, and a `dynamic_root` volume. Needs an active run.
- **What lands:** regular files (mode `0644`), relative in-tree symlinks only,
  submodules as empty directories, **no `.git`**, and `_meta/omitted.json`
  listing what was left out (`symlink`, `submodule`, `too_large`,
  `unsafe_path`, `collision`). Nothing from the repository runs; no LFS.
- **All or nothing:** a failure leaves no directory or row; the error is one
  word (`git_source_disabled`, `auth_failed`, `not_found`, `commit_not_found`,
  `merge_base_not_found`, `source_too_large`, `timeout`, `fetch_failed`, …).
- Pair with `Read` by line range (`offset`, `limit`, `line_numbers`) and
  `ephemeral_volumes: ro` on reviewer agents. See [volumes.md](volumes.md).

| Setting (shared with the Git tool's fetches) | Default |
|---|---|
| `LOOMCYCLE_GIT_SOURCE_HOSTS` | unset: off |
| `LOOMCYCLE_GIT_SOURCE_MAX_BYTES` | 256 MiB fetched, and written, per clone |
| `LOOMCYCLE_GIT_SOURCE_MAX_OBJECT_BYTES` | 64 MiB inflated object — what bounds memory |
| `LOOMCYCLE_GIT_SOURCE_MAX_FILE_BYTES` | 5 MiB (git sources only) |
| `LOOMCYCLE_GIT_SOURCE_MAX_FILES` | 100000 |
| `LOOMCYCLE_GIT_SOURCE_TIMEOUT_SECONDS` | 120, waiting for a slot included |
| `LOOMCYCLE_GIT_SOURCE_MAX_CONCURRENT` | 1 per replica |
| `LOOMCYCLE_GIT_SOURCE_MAX_HISTORY` | 500 commits |

---

## Git vs git source vs Bash with `shell_credentials`

| Need | Use |
|---|---|
| Read one commit under review, no write-back | **git source** volume (`mode: ro`) |
| Branch, commit, push a change | **`Git`** with a rw volume and `git_remote: [fetch, push]` |
| Rebase, cherry-pick, stash, a three-way merge, SSH remotes, running build/test tools | **`Bash`** (real `git`) |

`Bash` / Bashbox host commands receive credentials by name from
`LOOMCYCLE_BASH_ALLOWED_CREDS` / `LOOMCYCLE_BASHBOX_FALLBACK_ALLOWED_CREDS`,
and **the model can read them** (`env`, or `git -c alias.x='!env' x` through
an allowlisted host `git`). Since v1.122.0 the per-agent **`shell_credentials`**
field narrows that set: unset = every listed credential, `[]` = none, a list =
only those names. It only narrows, a sub-agent gets the intersection with its
parent, and it is not overridable per run. Give a shell only credentials you
would hand the model; prefer `Git` for anything that pushes.

---

## Example

```yaml
volumes:
  work:
    path: /srv/loomcycle/work
    mode: rw
    default: true

agents:
  fixer:
    description: Fixes a bug on a branch and pushes it for review.
    tools: [Read, Write, Edit, Grep, Glob, Git]
    volumes: [work]
    git_remote: [fetch, push]        # needs LOOMCYCLE_GIT_PUSH_HOSTS too
    crypto_scopes: [tenant]          # only to sign with sign_key
    shell_credentials: []            # no shell secrets, belt and braces

  reviewer:
    tools: [Read, Grep, Git]
    git_remote: [fetch]              # can clone/fetch, never push
```

```bash
# .env — names only, no secrets
LOOMCYCLE_GIT_SOURCE_HOSTS=github.com
LOOMCYCLE_GIT_PUSH_HOSTS=github.com
LOOMCYCLE_GIT_AUTHOR_NAME=loomcycle-bot
LOOMCYCLE_GIT_AUTHOR_EMAIL=bot@example.com
```

The agent then calls, e.g.:

```json
{"op": "clone", "repo": "app", "url": "https://github.com/acme/app.git", "credential": "$cred:github-acme-app"}
{"op": "checkout", "repo": "app", "branch": "fix-retry", "create": true}
{"op": "commit", "repo": "app", "message": "Fix the retry loop", "all": true, "sign_key": "release-signing"}
{"op": "push", "repo": "app", "credential": "$cred:github-acme-app"}
```

---

## Troubleshooting

Every failure is `{"error": "<class>", "detail": "..."}`.

| Error | Cause / fix |
|---|---|
| `volume_refused` | no such volume, or a change on a `ro` volume — bind a rw one |
| `not_a_repository` | `repo` points at no repository — `init` or `clone` first |
| `git_remote_not_allowed` | the agent (or its parent) lacks `git_remote: [fetch]` / `[fetch, push]` |
| `git_network_disabled` | `LOOMCYCLE_GIT_SOURCE_HOSTS` unset |
| `git_push_disabled` | `LOOMCYCLE_GIT_PUSH_HOSTS` unset |
| `host_not_allowed` | the remote's host (after `insteadOf` rewrites) is not on the fetch or push host list |
| `credential_url_not_allowed` | the credential has no `allowed_urls`, or they don't cover this repository (or submodule) URL |
| `credential_unresolvable` | the reference could not be resolved for this run — check the name and scope with `credentialdef list` |
| `auth_failed` / `not_found` | server refused the credential; a private repo without one looks like `not_found` |
| `push_rejected` | not a fast-forward or a protected branch — fetch, then `merge` / `pull` |
| `non_fast_forward` | diverged history; no three-way merge — see "Not available" |
| `worktree_dirty` | local changes would be lost — commit, `restore`, or `force` |
| `nothing_to_commit` | nothing staged — `add`, or `all: true` |
| `source_too_large` | a tree passed `LOOMCYCLE_GIT_SOURCE_MAX_FILES` / 1 GiB, or a fetch passed the byte limits — try `depth` / `single_branch` |
| `upload_too_large` | push over `LOOMCYCLE_GIT_PUSH_MAX_BYTES` |
| `sign_key_refused` / `signing_unavailable` | key not in `crypto_scopes`, not ed25519, or Crypto budget spent / deployment cannot sign |
| `invalid_argument` on a URL | only plain `https://` URLs (no user, password, query or fragment) — re-add the remote with an https URL |
| Tool refuses on every op on Windows | Unix only |
