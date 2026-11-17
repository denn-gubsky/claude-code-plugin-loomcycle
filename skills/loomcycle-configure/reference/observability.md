# Observability reference — traces, metrics, tenant telemetry (v1.148.0+; checked against v1.156.0)

What an operator watches a loomcycle deployment with, and what a tenant may watch of its own work:

| Layer | Since | What it is |
|---|---|---|
| **Traces** | v1.148.0 | Standard `OTEL_*` configuration, OTLP over HTTP or gRPC, inbound `traceparent`, tenant-safe spans with OpenTelemetry GenAI names |
| **Metrics** | v1.148.0 | `/metrics` (Prometheus text): runs, tokens, cost, provider outcomes and latency, tool calls, pools — counted in process, right at any trace sampling ratio. Optional OTLP export |
| **Scrape credential** | v1.148.0 / v1.149.0 | The single-purpose `metrics:read` scope; a tenant operator mints one confined to its own tenant's series |
| **Shipped assets** | v1.148.0 | Grafana dashboards, Prometheus alert rules and an Alloy collector config, versioned with the binary |
| **Tenant telemetry** | v1.151.0 | A tenant sends its own traces and metrics to its own OTLP collector (the MCP `telemetry` tool), off unless the operator allows it |
| **Settings home** | v1.153.0 | Policy moved to the yaml (`metrics:`, `observability:`); secrets, addresses and gates stay in the environment |

Where each setting lives (environment vs yaml) is in [settings.md](settings.md); the variables themselves are
listed in [env-vars.md](env-vars.md). Every variable below that is still read is live at v1.156.0.

---

## Traces — the standard OpenTelemetry environment

Tracing is **off** until an OTLP endpoint is set. loomcycle reads the standard variables; the OTLP exporter itself
reads the rest of `OTEL_EXPORTER_OTLP_*` (and the `_TRACES_` forms): `_TIMEOUT`, `_COMPRESSION`, `_CERTIFICATE`,
`_CLIENT_CERTIFICATE`, `_CLIENT_KEY`, `_INSECURE` — so TLS and mTLS to the collector are configured there.

| Variable | Default | Effect |
|---|---|---|
| `OTEL_EXPORTER_OTLP_ENDPOINT` | unset | A URL **with its scheme** (`http://otel-collector:4318`). Setting it (or `OTEL_EXPORTER_OTLP_TRACES_ENDPOINT`) turns tracing on: a span per run, iteration, provider call and tool call |
| `OTEL_EXPORTER_OTLP_PROTOCOL` | `http/protobuf` | or `grpc`. `OTEL_EXPORTER_OTLP_TRACES_PROTOCOL` wins when set. `http/json` stops the startup |
| `OTEL_EXPORTER_OTLP_HEADERS` | — | Collector headers `key=value,key2=value2`. A secret: never interpolated into config |
| `LOOMCYCLE_OTEL_EXPORTER_OTLP_HEADERS_FILE` | — | The headers from a file (comma- or newline-separated, `#` comments, values URL-decoded), read once, so the secret stays out of the environment. Set beside the headers variable, or unreadable, it stops the startup |
| `OTEL_TRACES_EXPORTER` | `otlp` | `none` (or only exporters loomcycle does not ship, such as `console`, `zipkin`) turns tracing off |
| `OTEL_SDK_DISABLED` | `false` | `true` turns tracing off — a tenant's own trace export included |
| `OTEL_TRACES_SAMPLER` / `_ARG` | `parentbased_always_on` / `1` | `always_on`, `always_off`, `traceidratio`, `parentbased_always_on`, `parentbased_always_off`, `parentbased_traceidratio`; the ratio is 0–1, anything else stops the startup |
| `OTEL_SERVICE_NAME`, `OTEL_RESOURCE_ATTRIBUTES` | `loomcycle` | Override the resource (`service.name`, `service.version`, `service.instance.id` = `LOOMCYCLE_REPLICA_ID`, `deployment.environment.name` = `LOOMCYCLE_ENVIRONMENT`) |
| `OTEL_PROPAGATORS` | `tracecontext,baggage` | `none` alone turns propagation off; others (`b3`, `jaeger`) are ignored with a log line |
| `OTEL_BSP_MAX_QUEUE_SIZE`, `_MAX_EXPORT_BATCH_SIZE`, `_EXPORT_TIMEOUT`, `_SCHEDULE_DELAY` | 2048, 512, 10000 ms, 5000 ms | The batch queue. A full queue **drops** spans (counted); a run never waits on an export |
| `LOOMCYCLE_OTEL_INBOUND_CONTEXT` | `parent` | What an authenticated caller's `traceparent` does: `parent` joins the run to the caller's trace, `link` starts a new trace linked to it (the caller cannot steer sampling), `ignore` reads nothing |
| `LOOMCYCLE_OTEL_RAW_USER_ID` | off | `1` also puts the raw `loomcycle.user_id` on spans beside the hash (below) |
| `LOOMCYCLE_TRACE_URL_TEMPLATE` | — | An http(s) URL with `{trace_id}` (`https://grafana.example/explore?traceId={trace_id}`): the Web UI's run view links each traced run there |

```bash
# .env.local — tracing to a local collector over gRPC, 10% of root traces
OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4317
OTEL_EXPORTER_OTLP_PROTOCOL=grpc
OTEL_TRACES_SAMPLER=parentbased_traceidratio
OTEL_TRACES_SAMPLER_ARG=0.1
LOOMCYCLE_OTEL_EXPORTER_OTLP_HEADERS_FILE=/run/secrets/otlp-headers   # holds: Authorization=Bearer%20<token>
```

**Fail-loud with tracing on.** An endpoint that is not an http(s) URL with a host, an unknown protocol or sampler,
a ratio outside 0–1, a non-positive batch bound, a malformed header (the error gives its position, never its
content), or headers set in both the environment and a file **stops the startup**. With tracing off no `OTEL_*`
value stops it (the environment may be shared with other OpenTelemetry programs).

**Renamed in v1.148.0, no fallback.** The four `LOOMCYCLE_OTEL_*` tracing variables of earlier releases are no
longer read; a deployment that sets only them runs with tracing **off**. Use `OTEL_EXPORTER_OTLP_ENDPOINT` (with
its scheme now), `OTEL_EXPORTER_OTLP_HEADERS` or the headers file, `OTEL_SERVICE_NAME`, and
`OTEL_TRACES_SAMPLER=parentbased_traceidratio` + `OTEL_TRACES_SAMPLER_ARG`. `loomcycle validate` / `doctor` name
any retired variable still set.

**Inbound trace context** is read only from an authenticated request — a bearer over HTTP, gRPC or MCP, a webhook
whose signature verified, an accepted A2A peer; open mode reads none. A run's `traceparent` goes on to the
operator's own HTTP MCP servers (yaml, or saved with operator authority), **never** to a model provider, a server
a tenant registered, or the HTTP and WebFetch tools. A sampled run's id is returned as **`trace_id`** by `get_run`
and the run's `started` event.

### What is on a span

- **`loomcycle.tenant`** on every span.
- **GenAI semantic-convention names** beside loomcycle's own: `invoke_agent`, `chat`, `execute_tool`.
- **`loomcycle.model.call`** covers each streamed model call: usage, finish reason, cost, time to first token,
  lane wait, `loomcycle.model.purpose` (`turn`, `compaction`, `recap`, `summary`, `emit_state`, `gateway`).
- **Provider attempts** carry the HTTP status, attempt number and `retry_after_ms`; `error.type` is one of
  `rate_limited`, `overloaded`, `timeout`, `network`, `cancelled`, `client_error`, `server_error`.
- **No content** on the operator's spans — prompts, answers and tool arguments never reach the operator's
  collector (tenant content capture, below, goes to the tenant's collector only, and the operator's exporter
  strips those keys).
- **Users by hash.** A span names its user as `loomcycle.user_hash`: a keyed HMAC of tenant and user, keyed from
  `LOOMCYCLE_SECRET_KEY`, stable per user. To find one user's traces run
  `loomcycle otel user-hash <tenant> <user>` with the secret key in the environment (never on the command line)
  and search `loomcycle.user_hash=<printed value>`. Without a secret key spans carry the raw `loomcycle.user_id`
  (boot warns). Rotating the key changes every hash. A query on `loomcycle.user_id` written before v1.148.0
  matches nothing once a key is set.
- **No-trace runs** export nothing, to anyone.
- **Erasure does not reach exported spans** — they live for the backend's retention. Spans carry no content and
  only the user hash, which is why that is acceptable.

### Sampling per tenant

```yaml
observability:
  tracing:
    tenant_sampler_ratios:
      acme: 1        # every acme trace
      beta: 0.1      # one in ten
```

The yaml is the only source (v1.153.0 retired the environment form). It applies to every span that **starts** a
trace and names its tenant (a run, a consolidation pass, an off-run tool call, a gateway call); a span with a
parent follows its trace's decision, and an unlisted tenant uses `OTEL_TRACES_SAMPLER`. Read at startup — a config
reload does not change it. To keep every failed or slow run whatever the ratio, tail-sample at the collector
(the shipped Alloy config does).

**Export health.** An unreachable collector drops spans; the outage is logged once (`otel: span export failing`),
summarised every five minutes, and its end logged. `/metrics` counts `loomcycle_otel_spans_ended_total`,
`_exported_total`, `_dropped_total` and `loomcycle_otel_span_export_failures_total`.

---

## Metrics — `/metrics`

`GET /metrics` serves the Prometheus text format: the **substrate** (process, concurrency, provider lanes, model
throughput, trace-export pipeline, build info), then **in-process instruments** counted where the work happens. A
scrape runs no database scan.

| Series | Labels | Counts |
|---|---|---|
| `loomcycle_runs_total` | `tenant`, `status`, `trigger` | Runs that ended (`completed`, `failed`, `cancelled`, `rejected`); `trigger` is `http`, `grpc`, `mcp`, `schedule`, `webhook`, `a2a`, `subagent`, `resume` |
| `loomcycle_run_duration_seconds` | `tenant`, `status` | Histogram of a run's wall time |
| `loomcycle_runs_active` | `tenant` | Runs started and not yet ended on this replica |
| `loomcycle_tokens_total` | `tenant`, `provider`, `model`, `type`, `key` | Tokens written to the usage ledger; `type` input / output / cache_read / cache_write; `key` = who paid (`operator`, `tenant`, `user`) |
| `loomcycle_cost_usd_total` | `tenant`, `provider`, `model` | The ledger's cost, for USD-priced calls |
| `loomcycle_provider_requests_total` | `provider`, `model`, `outcome` | Provider attempts by outcome (`ok`, `rate_limited`, `overloaded`, `client_error`, `server_error`, `timeout`, `network`, `cancelled`) |
| `loomcycle_provider_request_duration_seconds` | `provider`, `model` | Time to response headers |
| `loomcycle_provider_retries_total`, `loomcycle_provider_fallbacks_total` | `provider`, `reason` / `from`, `to` | Rate-limit retries; mid-run provider fallbacks |
| `loomcycle_model_call_duration_seconds`, `loomcycle_model_ttft_seconds` | `provider`, `model`, `purpose` | Whole model call; time to first streamed event |
| `loomcycle_tool_calls_total`, `loomcycle_tool_call_duration_seconds` | `tool`, `outcome` | Tool calls. An operator-declared MCP server is `mcp:<server>`; a runtime-defined one is `mcp`, so a tenant cannot add series by naming servers |
| `loomcycle_db_pool_open` / `_in_use` / `_idle`, `loomcycle_db_pool_wait_total`, `…_wait_duration_seconds_total` | `db` | The store's connection pool |
| `loomcycle_memory_consolidation_lag_seconds`, `loomcycle_memory_consolidation_pending` | `backend` | Consolidation backlog — a backlog only while `pending` is above 0 |
| `loomcycle_token_budget_used_ratio` | `tenant`, `period` | Month-to-date use of a tenant budget (see [token-limits.md](token-limits.md)) |
| `loomcycle_conversion_workers`, `_slots`, `_idle_slots`, `_inflight`, `_waiting`, `_quarantined_files`; `loomcycle_conversion_jobs_total{kind,outcome}`, `loomcycle_conversion_worker_deaths_total`, `…_respawns_total` | — | The conversion-worker pool (v1.153.0+; see [files.md](files.md)). `outcome="crashed"` = files killing workers, `"busy"` = callers turned away, `"no_worker"` = none attached |
| `loomcycle_audio_engine_inflight`, `loomcycle_audio_engine_queued` | — | The speech routes' engine queues (v1.140.0) |
| `loomcycle_goroutine_panics_total` | `goroutine` | Background work that panicked (below) — alert when non-zero |

Other counters worth an alert: `loomcycle_tool_panics_total{tool}`, `loomcycle_acl_resolution_failures_total`,
`loomcycle_audit_unrecorded_total`, the `loomcycle_tenant_telemetry_*` export counters.

**Bounded labels.** A run, user, session or (by default) agent is never a label. A `model` label names only models
the operator configured; anything else is `model="other"` (a `model_pattern` match is labelled with the pattern).
`LOOMCYCLE_METRICS_AGENT_LABEL=1` adds `agent` to `loomcycle_runs_total` and `loomcycle_tokens_total` — only for a
bounded agent catalogue. Each instrument holds at most `LOOMCYCLE_METRICS_CARDINALITY_LIMIT` series (default 2000);
past it, new label sets fold into one `otel_metric_overflow="true"` series with **no tenant label** for the life of
the process — with many tenants, raise the limit. `loomcycle_concurrency_per_user` names users by `user_hash` and
is left out without a secret key.

**OTLP export.** `OTEL_METRICS_EXPORTER=otlp` also pushes the same instruments over OTLP, plus the GenAI
histograms `gen_ai.client.token.usage` and `gen_ai.client.operation.duration` (on this path only). It needs an OTLP
endpoint (or `OTEL_EXPORTER_OTLP_METRICS_ENDPOINT`) or the startup stops; interval and timeout are
`OTEL_METRIC_EXPORT_INTERVAL` / `_TIMEOUT` (60000 / 30000 ms). Points carry exemplars with a sampled run's
`trace_id`. Off by default, even when traces are exported.

**A background panic is contained (v1.148.0–v1.149.0).** Sweepers, subscribers, heartbeats, run loops and fan-out
children run under a panic net: the panic is logged with its stack, counted in
`loomcycle_goroutine_panics_total{goroutine}`, and fails only its own work; supervised loops restart with back-off.

### The `metrics:` block — process samples for the Web UI

Separate from `/metrics`: an optional sampler that stores process samples for the Web UI activity page
(`/v1/_metrics/*`). v1.153.0 moved its switches to the yaml:

```yaml
metrics:
  enabled: true           # default false; the `server` preset turns it on
  sample_interval: 5s     # under 1s stops the load
  collect_system: false   # true also samples host CPU/memory (Linux only)
```

`LOOMCYCLE_METRICS_RETENTION_DAYS` (default 7) and `LOOMCYCLE_METRICS_LISTEN` stay in the environment. A
deployment that still sets the old sampler variables to anything but their defaults is refused at boot until the yaml names the matching key; a default value only warns.

---

## Scraping with `metrics:read`

Two kinds of token reach `/metrics`: `substrate:admin` (the legacy `LOOMCYCLE_AUTH_TOKEN` counts) and the
single-purpose **`metrics:read`**, which opens **no other route**. Give Prometheus the second, so a leaked scrape
file exposes metrics and nothing more.

```bash
loomcycle operator-token create --name prometheus --tenant ops --scopes metrics:read
```

or, from Claude Code with an admin token, the `operatortokendef` tool:

```
operatortokendef { "op": "create", "name": "prometheus", "tenant_id": "ops", "scopes": ["metrics:read"] }
```

Point Prometheus at a **file** holding the token (it re-reads `credentials_file` on every scrape, so a rotation
needs no restart):

```yaml
scrape_configs:
  - job_name: loomcycle
    metrics_path: /metrics
    authorization: { type: Bearer, credentials_file: /etc/prometheus/loomcycle.token }
    static_configs: [{ targets: ["loomcycle:8787"] }]
```

Rotate: mint a new token (or `rotate`, which keeps the old secret for its grace window), write it to the file,
retire the old one. Under `LOOMCYCLE_ACL=enforce` a `metrics:read` token needs no rule — its baseline
`builtin:metrics-reader` allows `read runtime:metrics`; a deny on `read runtime:metrics` still refuses it, but no
allow can open `/metrics` to a token holding neither scope (the scope gate comes first).

**A tenant's own scrape token (v1.149.0).** A **tenant operator** (`substrate:tenant`) may mint one — and only
this kind — for its own tenant, over HTTP, gRPC or MCP (`operatortokendef`):

```
operatortokendef { "op": "create", "name": "prom", "scopes": ["metrics:read"] }
```

- It gets the **`tenant_metrics`** restriction: `/metrics` then shows only the instrument series labelled with its
  tenant — no process, lane, pool, export-pipeline or `build_info` series, no other tenant's. The dashboards'
  runtime panels stay empty for it.
- Scopes must be exactly `["metrics:read"]`; `tenant_metrics: false` and another `tenant_id` are refused. The
  stored name is `u-metrics-<name>`, the subject `metrics-<name>` (an explicit one must start `metrics-` and may
  not be an existing user's). At most **32** live scrape tokens per tenant. Its lifetime is bounded by the
  minting token's.
- The same operator lists, gets, rotates and retires them; every other token reads as missing to it. A retired
  token cannot be rotated back to life.
- Access control asks `mint` (create, rotate), `manage` (retire) or `read` (get, list) of
  `principal:token:metrics`. An admin can mint a confined one with `"tenant_metrics": true`
  (`--tenant-metrics` on the CLI). An unmarked `metrics:read` token keeps the full view.

**Without a token.** `LOOMCYCLE_METRICS_LISTEN=127.0.0.1:9464` opens a second, **unauthenticated** listener
serving only `GET`/`HEAD /metrics`, minus every user-labelled series. Only for a scraper on the same host or a
network only it reaches; boot warns when it is not loopback.

---

## Dashboards and alert rules

Shipped in the loomcycle repository under **`deploy/observability/`**, versioned with the binary (a build test
fails when a dashboard or rule names a series `/metrics` no longer emits):

| File | What it is |
|---|---|
| `grafana/dashboards/loomcycle-overview.json` | Runs, failure rate, p95, queue; tokens and cost by tenant and model; provider outcomes; retries, fallbacks; tool calls; DB pool; consolidation lag; trace drops |
| `grafana/dashboards/loomcycle-genai.json` | Model calls: the GenAI histograms (OTLP only) beside time-to-first-token |
| `grafana/provisioning/dashboards.yaml` | Grafana provisioning for both |
| `prometheus/prometheus.yml` | Scrape with a `metrics:read` token from `credentials_file`, load the rules |
| `prometheus/rules/loomcycle-alerts.yml` | Seven rules: run failure rate, rate-limited ratio, queue saturated 5 min, DB pool waits, consolidation lag, dropped spans, token budget at 90 % |
| `alloy/config.alloy` | Grafana Alloy: OTLP in behind a bearer, tail sampling (every failed run, every run over 30 s, 10 % of the rest) to Tempo, OTLP metrics to Prometheus |

For Alloy, keep loomcycle's sampler at `parentbased_always_on` so the collector sees every trace it chooses from,
and set Alloy's `decision_wait` above the longest usual run. `examples/observability/grafana-tempo/` runs a whole
demo stack in one `docker compose up`.

---

## Tenant telemetry — a tenant's own collector (v1.151.0)

A tenant sends **its own** traces (and optionally its own metric series) to **its own** OTLP collector, beside the
operator's export. The operator's export, sampling and resource do not change.

### The operator's switches

| Setting | Where | Effect |
|---|---|---|
| `LOOMCYCLE_TENANT_TELEMETRY=1` | env | Turns the feature on. Off: `/v1/_telemetry` answers `404 feature_disabled`, the MCP `telemetry` tool is not listed and the Web UI page is hidden |
| `LOOMCYCLE_TENANT_CONTENT_CAPTURE=1` | env | Lets a tenant turn content capture on (below). Off: a policy asking for it is refused with 400 |
| `LOOMCYCLE_TENANT_TELEMETRY_ALLOW_HTTP=1` | env | Accepts an `http://` collector (a lab). Such an endpoint can carry no header credential |
| `LOOMCYCLE_TENANT_TELEMETRY_MAX_RATIO` | env | The highest `sampler_ratio` a tenant may set (default 1) |
| `observability.tenant_telemetry.allowed_hosts` | yaml | Hosts a tenant's endpoint may name: exact, or a quoted `"*.suffix"`. Empty = any host the address guard admits |

A stored policy is re-checked against these every time it is used: tighten a rule and a policy that no longer
passes stops exporting (`policy no longer valid: <reason>` in its status).

### The MCP `telemetry` tool

For an **admin or a tenant operator only** (`substrate:tenant`; absent from a member's `tools/list`). The tenant is
the caller's own; an admin may pass `tenant`. Errors with `feature_disabled` when the operator has not turned it on.

| op | What it does |
|---|---|
| `get` (default) | The policy and this replica's export status: spans exported and dropped, failed exports, last success, last error category |
| `set` | Store the policy — **a set replaces the whole policy** |
| `test` | Send one test span (and with metrics one test metric) to the stored endpoint; answers at once. One per 10 s per replica (`429 rate_limited`) |
| `delete` | Stop the export |

`set` fields:

| Field | Meaning |
|---|---|
| `endpoint` | The collector's OTLP base URL, `https://` (no user, password or query) |
| `protocol` | `http/protobuf` (default; spans to `<endpoint>/v1/traces`) or `grpc` |
| `headers_credential` | The **name** of a tenant credential whose value is the header block (`authorization=Basic …,x-scope-orgid=…`), restricted by its **`allowed_urls`** to the endpoint — the URL of every signal sent. A credential that may be sent anywhere is refused. Never put header values here |
| `signals` | `traces` (default), `metrics`, or both. Metrics are this tenant's own series, pushed every 60 s |
| `sampler_ratio` | 0–1, at most the operator's cap; default 1 |
| `content_capture` | `off` (default) or `on` — only where the operator allows it, and only with `traces` in `signals` |
| `content_max_chars` | 256–65536, default 4096: each captured field is cut to this |

```
# 1. the header block, as a tenant credential bound to the endpoint
credentialdef { "op": "create", "scope": "tenant", "name": "otel-headers",
                "value": "<header block>", "allowed_urls": ["https://otlp.example.net/otlp"] }
# 2. the policy
telemetry { "op": "set", "endpoint": "https://otlp.example.net/otlp",
            "headers_credential": "otel-headers", "signals": ["traces", "metrics"], "sampler_ratio": 0.2 }
# 3. check it arrives
telemetry { "op": "test" }
```

The same operations are `GET/PUT/DELETE /v1/_telemetry` and `POST /v1/_telemetry:test`, the `TenantTelemetry`
gRPC call, the TS / Python clients and Settings → Telemetry in the Web UI. A set is audited
(`tenant_telemetry_set`) **before** it takes effect, and refused when the record cannot be written. Access control
asks of `runtime:telemetry`. See [credentials.md](credentials.md) for `allowed_urls`.

### What a tenant receives

- **Only its own spans**, as a copy with a minimal resource (`service.name`, `service.version`,
  `loomcycle.tenant`), only the attributes classified as the tenant's (run, agent, model, token, tool, `gen_ai.*`),
  no error text. Spans without a tenant, and **no-trace runs, are never sent**.
- **Metrics** are exactly what the tenant's confined `/metrics` scrape shows, pushed as cumulative OTLP.
- **Egress** goes through the same private-address guard as the HTTP tool, never follows a redirect, and never
  carries the operator's OTLP headers or certificates. Each tenant has its own bounded queue; a black-hole
  collector delays nobody else.
- **Sampling for two destinations.** A root span is kept if the operator's sampler keeps it **or** the tenant's
  ratio does; a trace kept only for the tenant never reaches the operator's exporter, so the operator's volume does
  not change when a tenant raises its ratio. Spans under a caller's `traceparent`, and webhook-started runs, follow
  the operator's decision.
- **Errors** are reported to the tenant as a category only: `blocked`, `dns`, `connect`, `timeout`, `tls`,
  `redirect`, `http_<status>`, `grpc_<code>`, `rejected`, `busy`, `export_failed`. The raw error is in the
  operator's log.
- **Snapshots** carry the policies, never the header credential: restore it on the target for exports to resume.

### Content capture

With both gates on, a tenant's runs record on the spans **its** collector receives: `gen_ai.system_instructions`,
`gen_ai.input.messages`, `gen_ai.output.messages` on `loomcycle.model.call`, and `gen_ai.tool.call.arguments` /
`.result` on `loomcycle.tool.call`.

- **Redacted, then cut** — the same redactor as the stored transcript (secret values, resolved credentials,
  secret-shaped patterns), then each field to `content_max_chars`. Images are recorded as type and size only.
  `LOOMCYCLE_REDACT_SECRETS=0` captures nothing.
- **The operator's exporter strips every content key**, whatever the tenant's policy.
- **An agent opts out for good:**

  ```yaml
  agents:
    hr-assistant:
      telemetry: { content_capture: never }
  ```

  A fork cannot remove it and no run request changes it. It covers the spawn tree: a sub-run of a `never` run
  captures nothing, and a `never` sub-run's answer is recorded as `[content not captured]` on its parent's spans.
- **Turning capture off** stops it at once, for runs already going too.
- **Outside erasure.** Content in the tenant's backend is beyond loomcycle's reach; an erasure report names the
  window ("content exported to the tenant telemetry destination between … and …").
- Capture costs CPU in proportion to each model call's input.

---

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| No traces after upgrading past v1.147.0 | The `LOOMCYCLE_OTEL_*` tracing variables are no longer read. Set `OTEL_EXPORTER_OTLP_ENDPOINT` (with `http://` / `https://`) and the other standard names |
| Boot stops naming an `OTEL_*` variable | Tracing is on and the value would export nowhere (endpoint without scheme or host, `http/json`, ratio outside 0–1, malformed header, headers both in env and file) |
| Spans dropped, `otel: span export failing` in the log | Collector unreachable or slow. Check `loomcycle_otel_spans_dropped_total`; raise `OTEL_BSP_MAX_QUEUE_SIZE` only if bursts, not outages |
| Trace search by `loomcycle.user_id` finds nothing | Spans carry `loomcycle.user_hash`. Run `loomcycle otel user-hash <tenant> <user>` with the secret key set |
| Caller's `traceparent` ignored | Unauthenticated request (open mode), or `LOOMCYCLE_OTEL_INBOUND_CONTEXT=ignore` |
| `/metrics` answers 401/403 to Prometheus | Not a `metrics:read` or admin token, or an ACL deny on `read runtime:metrics` |
| A tenant scrape shows no runtime panels | Expected: a `tenant_metrics` token sees only its tenant's series |
| A tenant's series vanished, an `otel_metric_overflow` series grows | Cardinality limit reached; raise `LOOMCYCLE_METRICS_CARDINALITY_LIMIT` |
| Tenant operator cannot mint a scrape token | Scopes not exactly `["metrics:read"]`, another `tenant_id`, 32 live tokens already, or a member token (`substrate:tenant` needed) |
| Web UI activity page empty after upgrading to v1.153.0+ | Write `metrics: { enabled: true }` in the yaml; the environment switch is retired |
| `telemetry` tool missing from `tools/list` | Tenant telemetry is off (`LOOMCYCLE_TENANT_TELEMETRY` unset), or the token lacks `substrate:tenant`; reload the plugin after the operator changes it |
| `telemetry op=set` refused | Endpoint not https (and no http override) or not in `allowed_hosts`; ratio above the cap; header credential missing or not restricted by `allowed_urls` to the endpoint (and `/v1/metrics` with metrics); content capture not allowed by the operator, or without `traces` |
| `test` answers `blocked` / `redirect` | The address guard refused every address (a private collector needs the operator's allowlist), or the collector redirected |
| Status says `policy no longer valid` | The operator tightened `allowed_hosts`, the ratio cap or the http override; set a policy that passes |
| No content on a tenant's spans | Operator gate off, `content_capture` off, a `never` agent in the spawn tree, a no-trace run, or `LOOMCYCLE_REDACT_SECRETS=0` |
| `loomcycle_goroutine_panics_total` rises | A background loop panicked and was contained; the log has the stack. Report it |
| `loomcycle_conversion_jobs_total{outcome="crashed"}` rises | Files are killing conversion workers; see [files.md](files.md) |
