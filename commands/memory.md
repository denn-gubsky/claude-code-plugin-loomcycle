---
description: Inspect and edit a loomcycle agent's memory — semantic recall/search, add conversation facts, or plain key/value get/set/list.
argument-hint: "<recall|search|add|get|set|list> [--scope=agent|user] [args…]"
allowed-tools: mcp__loomcycle__memory
---

# loomcycle memory

Read or write a loomcycle agent's memory keyspace from the IDE. Wraps the
`memory` meta-tool, which is a multi-op tool: every call MUST carry an `op`
discriminator and a `scope`.

Parse `$ARGUMENTS`:

- First token = the op: one of `recall | search | add | get | set | list`.
- `--scope=<agent|user>` selects the keyspace. **Default to `agent`** when
  omitted (this agent's cross-run store); use `user` for the per-user,
  cross-agent store. There is no other scope.
- Remaining tokens are the op's payload (below).

Call `mcp__loomcycle__memory` with the matching shape. Render results as
markdown, not raw JSON.

### `recall` — natural-language semantic memory (v0.16 MemoryLayer)
Free-text query over LLM-extracted durable facts.

```json
{ "op": "recall", "scope": "<agent|user>", "query": "<text>", "top_k": <n, default 10, max 50> }
```

Returns `{facts: [{id, memory, score}]}`. Render a table:
`score | memory | id`, highest score first. Optional `--threshold=<0..1>` sets
a relevance floor.

### `search` — vector similarity over stored key/value rows (v0.9)
```json
{ "op": "search", "scope": "<agent|user>", "query": "<text>", "top_k": <n> }
```

Returns ranked `{key, value, score}` rows (each carries a `rank_score`).

### `add` — ingest conversation turns as memory (v0.16 MemoryLayer)
```json
{ "op": "add", "scope": "<agent|user>",
  "messages": [ { "role": "user", "content": "<text>" } ],
  "infer": true }
```

`infer: true` (default) lets the backend LLM-extract durable facts; `false`
stores verbatim. Returns the extracted `{facts: […]}`.

### `get` / `set` / `list` — plain key/value
```json
{ "op": "get",  "scope": "<agent|user>", "key": "<key>" }
{ "op": "set",  "scope": "<agent|user>", "key": "<key>", "value": <json> }
{ "op": "list", "scope": "<agent|user>", "prefix": "<optional>", "limit": <n> }
```

## Capability note — `add` / `recall` need a memory-layer backend

`add` and `recall` only work when the agent's memory backend is a **memory
layer** (e.g. Mem9 smart-mode). Against loomcycle's default in-process
key/value + vector store they refuse with `capability_unsupported` — that is
**not** a plugin bug. If you hit it, tell the operator to route the agent at a
`MemoryBackendDef` memory-layer backend (or use `search` / `get` / `set` /
`list`, which work on the default store). Surface the refusal text plainly;
never retry a different op silently.

If the op is missing or unrecognised, list the six ops and stop rather than
guessing.
