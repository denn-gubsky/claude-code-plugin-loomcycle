---
description: Send this tenant's own traces and metrics to the tenant's own OpenTelemetry collector — show, set, test or stop the export policy.
argument-hint: "[get] | set --endpoint=<https://…> [--protocol=http/protobuf|grpc] [--headers-credential=<name>] [--signals=traces,metrics] [--sampler=<0..1>] [--content=on|off] [--content-max=<n>] | test | delete"
allowed-tools: mcp__loomcycle__telemetry mcp__plugin_loomcycle_loomcycle__telemetry
---

# loomcycle telemetry

A tenant can export **its own** traces, and its own series of the deployment's
metrics, to an OTLP collector it runs (Grafana Cloud, Honeycomb, its own
OpenTelemetry Collector), alongside the deployment's own telemetry. Wraps the
`telemetry` tool of the loomcycle MCP server (loomcycle v1.151.0+).

**Who and when.** An admin or a tenant operator only; the tool needs
`substrate:tenant`. It is listed only when the deployment's operator turned
tenant export on. Otherwise the tool is missing, or a call fails with
`feature_disabled`; say so, as it is operator configuration, not a plugin
fault. `tenant` is admin-only (to act on another tenant); leave it out
otherwise.

Parse `$ARGUMENTS`. The first token is the op (default `get`).

## `get` — the policy and whether exports work

```json
{ "op": "get" }
```

Render:
- the policy: endpoint, protocol, signals, sampler ratio, content capture and
  its length cap, headers credential name;
- the export status: spans exported and dropped, failed exports, the last
  success, the last error.

A rising failure count with an old last success means the collector refuses
the export: check the endpoint and the credential.

## `set` — store the policy

```json
{ "op": "set", "endpoint": "https://otlp.example.net/otlp",
  "protocol": "http/protobuf", "headers_credential": "<credential name>",
  "signals": ["traces", "metrics"], "sampler_ratio": 0.2,
  "content_capture": "off" }
```

- **A `set` replaces the whole policy.** Fields left out return to their
  defaults: traces only, ratio 1 (or the deployment's cap if that is lower; a ratio above
  the cap is refused), protocol `http/protobuf`, capture off. Run
  `get` first and carry over what should stay.
- **`endpoint`** is an https OTLP base URL, with **no user, password, query or
  fragment**. With `protocol: grpc` it must be a host and port with no path.
  Plain http is accepted only where the operator set a lab override.
- **Never put a token in the call.** Store the header block
  (`authorization=Basic …,x-scope-orgid=…`) as a tenant credential with
  `credentialdef`, **restricted by `allowed_urls` to the endpoint**, and pass
  only its name as `headers_credential`. If the user pastes a token, stop and
  tell them to store it as a credential instead; do not echo it.
- **`--content=on`** also sends the prompts, answers and tool calls of the
  tenant's runs, with secrets masked and each field cut to `content_max_chars`
  (default 4096). It needs `traces` in `signals`, and is refused unless the
  operator allows it. **Warn before setting it:** content sent to the collector
  is outside loomcycle's erasure, so a later subject erasure cannot reach it.
- What is never sent:
  - spans of no-trace runs;
  - content from an agent defined with telemetry `content_capture: never`;
  - the deployment's own resource attributes and error text.

## `test` — does it arrive?

```json
{ "op": "test" }
```

Sends one test span (and one test metric, with `metrics` in signals) to the
stored endpoint. Report whether it arrived, and the collector's error if not.

## `delete` — stop exporting

```json
{ "op": "delete" }
```

Confirm first. It removes the policy, and nothing more is sent.

---

**Not here:** the deployment's own telemetry and metrics (operator config, see
the `loomcycle-configure` skill's `reference/observability.md`), and scraping
`/metrics` with a `metrics:read` token (mint it with `/loomcycle:operator-token`).
Run transcripts are read with `get_run`, not here.

If the op is missing or unrecognised, list the four and stop rather than
guessing.
