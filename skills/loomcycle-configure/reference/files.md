# Files reference — the run inbox and the File tool (v1.122.0+; checked against v1.126.0)

A tool call is text, so a file cannot reach a model as one: base64 is too long to hold, too easy
to corrupt, and unreadable anyway. Since **v1.122.0**, when a tool returns a file loomcycle keeps
it as a file in the run's **inbox** and the model gets one line in its place:

```
[file: volume:inbox:documents/board-papers.pdf · application/pdf · 1.8 MiB · sha256:3f9a1c2b4d5e… · from mcp:ms365/get-attachment]
```

`volume:inbox:documents/board-papers.pdf` is the file's reference, relative to the volume root as
every file tool's path is. Read opens it as `volume: "inbox"`, `path: "documents/board-papers.pdf"`;
Crypto's `from` / `to` and the `File` tool take the reference as written. A file that cannot be
kept gives `[file not kept: <why> · …]`. Either way, **its bytes never reach the model**.

Version map: v1.122.0 inbox, capture, `File` tool, extraction · v1.123.0 OCR on `extract`, the
`transcription` event · v1.124.0 the download/upload URL check · v1.125.0 `transcribe`, import
provenance and `source`, the HTTP route and inbox downloads · v1.126.0 import `headings`.

---

## The inbox

An ephemeral volume of the run tree named `inbox`, at
`<dynamic_root>/_ephemeral/<root_run_id>/inbox`. It is made on the first capture and deleted with
the run tree (the ephemeral-volume crash sweeper is the backstop).

- **Needs a `dynamic_root` volume.** Without one nothing is kept: every file becomes a
  `[file not kept: …]` line. The agent does not have to bind the `dynamic_root` volume; the inbox is
  the runtime's. See [volumes.md](volumes.md).
- **Folders:** `documents/`, `images/`, `web/<host>/`, `extracted/` (what `extract` / `transcribe`
  write).
- **Belongs to the whole run tree.** Sub-agents see it. A sub-agent given the tree's volumes
  read-only still has its tool results kept (those writes are the runtime's), but its own `File rm` /
  `clear` are refused.
- **`inbox` is a reserved name.** `VolumeDef op=create` refuses it (persistent or ephemeral). A
  tenant volume or a configured `volumes:` entry already named `inbox` makes **every capture
  refuse** rather than be shadowed — rename it.
- **Gone when the run ends.** `keep` what must outlive the run into a durable read-write volume.
- **Visible to operators:** the Web UI Volumes page lists a live inbox with its tenant's ephemeral
  volumes.

### Caps

A bad value refuses the boot.

| Variable | Default | Bounds |
|---|---|---|
| `LOOMCYCLE_FILE_MAX_BYTES` | 64 MiB | one kept or downloaded file |
| `LOOMCYCLE_FILE_INBOX_MAX_BYTES` | 1 GiB | the tree's whole inbox (a resumed tree counts what it already holds) |
| `LOOMCYCLE_MCP_MAX_FRAME_BYTES` | 16 MiB | one MCP response: a stdio JSON-RPC line, or an MCP HTTP body |
| `LOOMCYCLE_FILE_BASE64_MIN_BYTES` | 4096 | the shortest base64 string a `binary_results: capture` server's text is searched for |

---

## What is captured

| Source | Captured when |
|---|---|
| MCP result `image`, `audio`, `resource` blob blocks | always. A `resource` with text is kept as text; a `resource_link` is shown as one line |
| Base64 inside an MCP **text** block | only for a server with `binary_results: capture`. Strings ≥ `LOOMCYCLE_FILE_BASE64_MIN_BYTES` that decode to a recognisable file or readable text are replaced by the stub; opaque tokens are left alone and the rest of the block is byte-identical |
| HTTP and WebFetch responses | the body is binary (by Content-Type, then a sniff, then the URL extension). The text path is unchanged |
| WebFetch with `assets: true` | the page's images and its links to PDFs, images and Office files, under the page's own host policy and WebFetch's hooks, at most `assets_max` (default 20, ceiling 100) |

`binary_results` is `passthrough` (default) or `capture`, set on yaml `mcp_servers.<name>` or on an
`MCPServerDef` (create / fork); it is part of the def's content hash. Opt in only for a server that
returns files as base64 text — a long opaque token could otherwise look like one.

```yaml
mcp_servers:
  ms365:
    transport: http
    url: https://mcp.example.internal/ms365
    binary_results: capture
```

**Names.** Only the last segment of the producer's name, %-unescaped, Cyrillic transliterated
(`Протокол засідання №3.pdf` → `Protokol-zasidannya-3.pdf`), reduced to `[A-Za-z0-9._-]`,
de-duplicated with a numeric suffix. A file an MCP result does not name takes its name from the
call's `fileName` / `filename` / `file_name` / `name` / `path` argument before the tool's name (so a
`download-bytes` result is named after the file it fetched; v1.125.0).

---

## The `file_captured` event

Each capture emits `file_captured` — on SSE, in the transcript, on gRPC (`Event.file`), in the TS
and Python clients, and as one line in the Web UI's run views with a download button. It carries the
ref, type, size, sha256 and origin, **never the bytes or a URL's query**. A `download`'s record keeps
its URL as scheme, host and path, with `?…` in place of any query and no fragment.

---

## The `File` tool — ops

Granted by name (`tools: [File]`). Handles these files without their bytes passing through the
model. A path is `volume:inbox:<path>`, `volume:<name>:<path>` for a bound volume, `volume:<path>`
for the default volume, or a bare path (= the inbox).

| op | What it does | Main arguments | Grants beyond `File` |
|---|---|---|---|
| `stat` | size, type, sha256, origin, `captured_at` of one file; `page` / `slide` for a picture `extract` found. A file changed since capture reports origin `unknown` | `path` | `Read` for a non-inbox volume |
| `ls` | the inbox (default) or a folder of a bound volume; ≤ 1000 entries, `truncated` | `path`, `recursive` | `Read` for a non-inbox volume |
| `keep` | copy an inbox file into a read-write volume; never over an existing file unless `overwrite`; the target folder must exist | `from`, `to`, `overwrite` | `Write` |
| `rm` | delete one inbox file | `path` | — |
| `clear` | empty the inbox, or one folder of it | `prefix` | — |
| `download` | GET a URL into the inbox (or a volume) | `url`, `to`, `overwrite`, `headers`, `max_bytes` | `HTTP`; plus `Write` into a volume |
| `upload` | PUT/POST a file to a URL, whole or ranged for an upload session | `from`, `url`, `method`, `content_type`, `headers`, `ranged`, `chunk_bytes` | `HTTP`; plus `Read` from a volume |
| `extract` | DOCX / XLSX / PPTX / PDF / HTML / CSV / TSV / text / captions / image → Markdown in `extracted/`, pictures kept as files, plus a fenced excerpt; a recording is handed to `transcribe` | `path`, `images`, `max_rows`, `excerpt_chars`, `ocr`, `language`, `dry_run` | `Read` for a non-inbox source |
| `transcribe` | audio / video → timed Markdown transcript in `extracted/` via the speech-to-text engine | `path`, `language`, `vocabulary`, `diarize`, `timestamps`, `to`, `dry_run` | `Read` for a non-inbox source |
| `import` | build a Document from such Markdown, `extract`'s pictures attached as image chunks | `path`, `title`, `doc_path`, `scope`, `tags`, `source`, `headings` | `Document` and its scope grants |

The inbox itself needs only `File`. Any other volume is reached with the run's own grants, and that
tool's pre-hooks judge the call on the final path. `download` / `upload` go out under the HTTP
tool's rules: they pass HTTP's pre-hooks (which see the full URL, the headers and, for an upload,
`{from, size, sha256}`), the host must be in the run's `allowed_hosts`, private / loopback addresses
are refused unless opted in, and a redirect is followed only to the same host (never `https` →
`http`).

- **No credential headers.** An `Authorization`, cookie, API key or bearer value in `headers` is
  refused: use the service's pre-authenticated URL.
- **Ranged upload:** each chunk carries `Content-Range: bytes <first>-<last>/<total>`, following
  the server's `nextExpectedRanges`; a 200 / 201 ends it. `chunk_bytes` is rounded down to a
  multiple of 327680 (320 KiB, as Microsoft Graph requires); default 3932160 (3.75 MiB).
- **The `url` is checked for copying slips (v1.124.0).** A double quote, space, `<`, `>`,
  backslash, backtick or control character in `download`'s or `upload`'s `url` is refused before
  any request, naming the character and its position, never the URL. Usually it is the closing
  quote of the JSON string the URL was copied from (an upload session's `uploadUrl`). Nothing was
  sent, so the same URL still works once corrected.
- **Pre-authenticated URLs are credentials.** Results, errors and records show a URL's query as
  `?…`; its credential parts (query values and user information of 8+ bytes, at most 32 per run
  tree) are registered with the server's redactor so a transcript that repeats them is masked.

Do not use `File` to read a file's text — Read the `.md` that `extract` wrote.

---

## Extraction (`extract`)

Pure Go, in process. The excerpt returned is at most 30 000 characters, fenced as untrusted
(`<file_content …>`) so the text cannot close its own fence; document text is escaped so it cannot
become Markdown structure. Extraction times out after 60 s.

| Type | Output |
|---|---|
| DOCX | title as `#`, Word headings below it, paragraphs, lists, tables, pictures in place |
| XLSX | a `##` per sheet, one table of computed values (not formulas), first `max_rows` rows (default 1000) then `[+N rows omitted]` |
| PPTX | `## Slide N — <title>` per slide, text and tables, pictures, speaker notes as a quote |
| PDF | `## Page N` per page from the text layer; JPEG / JPEG 2000 pictures copied byte for byte, other encodings counted in `notes` |
| HTML | headings, paragraphs, lists, tables; images become links, nothing is fetched |
| CSV, TSV | one table |
| text, Markdown | the text; Markdown keeps structure, without raw HTML or embedded images |
| PNG, JPEG, GIF, WebP, BMP | a one-section file embedding the image (read by OCR when enabled) |
| VTT, SRT captions | timed sections, `<v Speaker>` voice tags as speaker labels — **no engine needed** (a transcribed Teams meeting reads this way) |
| audio, video | handed to `transcribe` |

Pictures land at `volume:inbox:extracted/<name>/img-<n>.<ext>` and remember the page or slide they
were on. `images: false` writes only their descriptions.

**Limits and refusals.** Zip formats go through one bounded reader (entry count, total size,
per-entry ratio, no entry name used as a path); XML is parsed strictly with no DTD entities. PDF:
2000 pages, 200 000 characters and 32 MiB of decoded content per page; **every encrypted PDF is
refused**, even one that opens without a password. Old binary `.doc` and archives cannot be
extracted.

**Spotting a scan.** `yield_chars_per_page` is reported where pages are known; `low_yield_pages`
lists a PDF's likely scanned pages and `notes` says so in words. A near-zero yield is the trigger
for OCR.

---

## OCR on scanned PDFs and images (v1.123.0)

**Off unless both sides opt in:** the operator configures `transcription.ocr` (engine `vision`)
**and** the agent's definition sets `transcription: {ocr: auto | always}` (default `never` — OCR is
billed per page).

```yaml
transcription:
  ocr:
    engine: vision            # required: vision | off
    tier: middle              # default middle; or pin `model:` (a chat alias)
    language: uk+ru           # default uk+ru; up to three ISO 639-1 codes joined by +
    max_pages_per_call: 100   # default 100
    max_pages_per_run: 300    # default 300 (the run tree's cap, shared by sub-agents)
    ocr_min_chars_per_page: 40   # below this a page counts as a scan
    max_tokens_per_page: 2000
    rasterize: { command: "pdftoppm -r 150 -png {in} {out_prefix}" }   # needed for non-Claude vision models on PDFs
```

- **Mode.** `auto` reads only PDF pages under `ocr_min_chars_per_page`; `always` reads every page;
  `never` reads the text layer only. An image is read whenever the mode is not `never`. The call's
  `ocr` defaults to the agent's setting, which is also its **ceiling** (`never` < `auto` <
  `always`): a call may lower it, never raise it. `language` overrides the operator's.
- **Engine.** Resolved like the run's own model, under the run's user tier and tenant keys. A model
  that cannot see images is refused before any call. A Claude model (API or Bedrock) gets a page
  range as one PDF `document` block; any other vision model (Ollama) gets one rendered page image
  per call and refuses a PDF without `rasterize.command`.
- **Caps.** Pages are reserved before each call against the agent's `max_pages_per_run` and the
  operator's tree-wide one. A call over either is not made; the pass stops with a JSON error
  (`cap`, `limit`, `used`, `requested`) and the Markdown written so far stays at `ref`.
- **Output.** Each page read becomes `## Page N` with the model's text (empty → `[no text]`), under
  a `<!-- loom: ocr engine=… -->` line. The result adds `low_yield_pages` and
  `ocr: {mode, engine, provider, model, pages, pages_sent, units, status, input_tokens, output_tokens, cost, currency}`.
- **Cost.** Each model call is a usage-ledger row with `purpose=ocr`, counting against token
  budgets. **`dry_run: true`** estimates pages, units, tokens and cost with no model call and
  nothing written — use it on a long file first.

---

## Speech-to-text (`transcribe`, v1.125.0)

Off unless the operator configures `transcription.stt` (engine `openai-audio`: any server with the
OpenAI `/v1/audio/transcriptions` shape — a self-hosted whisper server such as speaches or
whisper.cpp, or OpenAI). On by default for agents once configured; an agent may turn it off
(`stt: off`) or lower `max_minutes_per_run`. Reads M4A, MP3, WAV, FLAC, OGG/Opus, MP4, WebM (only
the sound of a video).

```yaml
providers:
  whisper-local:
    driver: openai
    base_url: http://speaches:8000/v1
models:
  whisper: { provider: whisper-local, model: <model id your server serves>, kind: transcriber }
transcription:
  stt:
    engine: openai-audio      # required: openai-audio | off
    provider: whisper-local   # a provider on the openai driver
    model: whisper            # an alias tagged kind: transcriber (untagged is refused)
    language: uk              # default uk; exactly one code
    diarize: auto             # auto | on | off
    max_minutes_per_call: 120
    max_minutes_per_run: 300
    chunk_minutes: 10
    timeout_s: 1800
    media: { command: "ffmpeg -nostdin -loglevel error -i {in} -ac 1 -ar 16000 -f wav {out}" }
```

- **Sending.** A PCM WAV is cut by the runtime into `chunk_minutes` pieces under 25 MB with a 2 s
  overlap. With `media.command` (ffmpeg) every other format is converted to WAV first. Without it, a
  file goes whole only if the engine reads its format, it is under 25 MB and within
  `max_minutes_per_call`; otherwise it is refused naming `transcription.stt.media.command` — never
  truncated. The `loomcycle-media` image carries ffmpeg and poppler-utils.
- **Output.** `# <file>`, a `<!-- loom: stt … -->` line, a `## [hh:mm:ss – hh:mm:ss]` section per
  piece, passages with start times, `**Speaker N**` labels where the model separates speakers.
  `timestamps: none` drops the times.
- **Cost.** One ledger row per request, `purpose=stt`, priced by `per_minute` in `pricing:`;
  `dry_run` estimates minutes and cost with nothing sent. A minute cap stops before sending.

**The `transcription` event.** Each OCR or speech-to-text pass emits one: source `ref`, `out` ref,
`purpose` (`ocr` | `stt`), engine, provider, model, `pages` or `seconds`, tokens, `cost` (absent when
unpriced), `status` (`ok` | `partial` | `failed`), `dry_run`, `error`, `run_id` — never the text. It
is an operator record, not model input.

---

## Import into a Document

`import` reads the Markdown (its text never passes through the model) and builds a Document as
`import_md` does: headings become the chunk hierarchy. It needs `Document` plus scope grants for
the chosen `scope` (`agent`, `user` default, `tenant`), and SQL Memory enabled — see
[document.md](document.md).

- **Untrusted.** Only the one-line `![alt](volume:inbox:extracted/…)` pictures `extract` wrote are
  followed (each becomes an image chunk under its own sub-heading, with its `page` / `slide`); any
  other `volume:` reference, raw HTML or loom comment stays text and is counted in `skipped`. Image
  chunks take PNG / JPEG / GIF / WebP, so a JPEG 2000 stays a link. The document is tagged
  `untrusted` and `source/<origin>` (e.g. `source/mcp/ms365`).
- **Provenance (v1.125.0).** The root carries a server-written `provenance`: `origin: import` and,
  while the file still hashes to its capture record, `file`, `media_type`, `sha256`,
  `captured_from` (`mcp:<server>/<tool>`, `download:<host>`, `http`, `webfetch`), `captured_at`,
  `run_id`. A caller can never set or change it. Imported rows carry origin `import`: found by
  `sources=documents`, never returned as facts.
- **A changed file loses its record.** An inbox file edited since capture records none of the
  above, gets no `source/…` tag, and the result carries `provenance_note`.
- **`source: {url, kind, title}`** links back to where the file lives. `kind`: `sharepoint`,
  `email`, `attachment`, `web`, `other` (default); adds a `source/<kind>` tag. `url` is http(s),
  ≤ 2 KiB, no user info; signed query parameters are masked. Pass the item's web link (SharePoint
  `webUrl`, a message's `webLink`), **never a download or upload link**.
- **`headings` (v1.126.0)** structures a file whose sections show only by numbering (a PDF export),
  applied to the text as read — the file is untouched, so provenance holds:
  - `{line, level, as: "heading"}` — line N becomes a heading; `lines` (≤ 10) joins a wrapped title.
  - `{line, level, as: "marker", title}` — a one-line `title` (≤ 300 chars) is inserted before line
    N, which stays body text (a numbered paragraph).
  - Levels 2–6, increasing line order, ≤ 10 000 entries; one bad entry refuses the whole import.
    `provenance.structured: {headings, by}` records the count and the run.

```json
{"op": "import", "path": "volume:inbox:extracted/NBU-064.md", "scope": "tenant",
 "doc_path": "/board/regulations/nbu-064",
 "source": {"url": "https://tenant.sharepoint.com/sites/board/Shared%20Documents/nbu-064.pdf", "kind": "sharepoint"},
 "headings": [
   {"line": 593, "level": 2, "as": "heading"},
   {"line": 594, "level": 3, "as": "marker", "title": "1. Scope of the regulation"}
 ]}
```

---

## Agent yaml example

```yaml
volumes:
  default:
    path: ./work
    mode: rw
    default: true
  dynamic-root:              # REQUIRED for the inbox; mkdir -p ./work/dynamic before start
    path: ./work/dynamic
    mode: rw
    dynamic_root: true
  docs:
    path: ./work/docs
    mode: rw

agents:
  mail-intake:
    model: middle
    tools: [File, Read, Write, HTTP, WebFetch, Document, mcp__ms365__*]
    volumes: [default, docs]      # keep targets; the inbox needs no binding
    memory_scopes: [agent, user]  # Document's scope grants (both planes)
    sql_scopes: [agent, user]
    transcription:
      ocr: auto                   # opt in; default never
      max_pages_per_run: 50       # at most the operator's cap
      max_minutes_per_run: 60
```

With `LOOMCYCLE_SQLMEM_ENABLED=1` for Document. `download` / `upload` reach only hosts in the run's
`allowed_hosts`.

---

## From Claude Code — the MCP `file` tool

An operator session has no inbox of its own, so `file` acts on the inbox of a run it may read,
named by `run_id` (as `get_run` / `list_runs` report it; a sub-run's id reaches its tree's inbox).
It runs the same `File` tool, on that inbox only. Needs **`runs:read`** (like `get_run`) and is
tenant-confined: another tenant's run, or one the caller may not read, answers as missing. Input is
strict — an unknown or repeated field is refused.

| op | Who may |
|---|---|
| `stat`, `ls` | anyone who may read the run |
| `import` | the same; the Document goes into the **caller's** own scopes |
| `extract`, `rm`, `clear` | the run's owner, an admin, or a tenant operator (`substrate:tenant`) of the run's tenant |
| `keep` | the owner (**not an isolated user**), an admin or a tenant operator of the run's tenant — into a read-write **dynamic** volume of the caller's tenant (`volumedef list` shows them) that the caller's access rules let it write |
| `download`, `upload`, `transcribe` | not offered — download/upload need a run's HTTP host policy; give the agent `File` + `HTTP` instead |

**The inbox is gone once the run ends** (it dies with the tree): `keep` or download a file while the
run is still going. An isolated user is refused `keep` because a dynamic volume is shared by the
tenant.

**HTTP twins.** `POST /v1/runs/{run_id}/file` takes the tool's input (`run_id` from the path; a body
that repeats it must match) and answers the op's JSON (200) or a 422 `tool_refused` envelope.
`GET|HEAD /v1/runs/{run_id}/inbox/<path>` returns one file's bytes to anyone who may read the run,
with ranges (`ETag` = sha256), always as an attachment with `nosniff` and a sandbox CSP; HTML, SVG,
XML and scripts go out as `application/octet-stream`. `X-Loomcycle-SHA256` is the hash served,
`X-Loomcycle-Origin` the tool that returned it (`unknown` if changed after capture). A path with
`..`, a leading `/`, a backslash, a hidden segment, a symlink or a folder is refused. The TS client
has `runFile` and `downloadRunInboxFile`.

---

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| Every file shows `[file not kept: …]` | No `dynamic_root` volume. Declare one (and create its directory) — see [volumes.md](volumes.md) |
| Every capture refuses, even with `dynamic_root` | A tenant volume or `volumes:` entry is named `inbox` (reserved). Rename it |
| `[file not kept: …]` for a large file / later files | Over `LOOMCYCLE_FILE_MAX_BYTES` or the tree's `LOOMCYCLE_FILE_INBOX_MAX_BYTES`. Raise the cap, or `rm` / `clear` to free space |
| An MCP server's base64 still reaches the model as text | The server is `passthrough` (default). Set `binary_results: capture` on it |
| An MCP response fails as too large | Over `LOOMCYCLE_MCP_MAX_FRAME_BYTES` (16 MiB) |
| SharePoint / Graph upload answers 401 "invalid signature" (pre-v1.124.0) or `url` is refused naming a quote | The model kept the closing `"` of the JSON `uploadUrl`. Pass the value only; on v1.124.0+ nothing was sent, so retry with the corrected URL |
| `download` / `upload` refused | Agent lacks `HTTP`, the host is not in `allowed_hosts`, a cross-host redirect, or a credential header |
| `keep` refused | Agent lacks `Write`, target volume is read-only / unbound / the inbox, folder missing, or file exists without `overwrite`. Over MCP: isolated user, or not the run's owner / admin |
| `extract` returns near-empty pages | A scan. Enable OCR (`transcription.ocr` + agent `transcription.ocr: auto`) and pass `ocr: auto` |
| `extract` refuses `ocr: always` | The call asked above the agent's setting (its ceiling) |
| `extract` refuses a PDF with OCR on an Ollama model | Set `transcription.ocr.rasterize.command` |
| `extract` refuses an encrypted PDF | Every encrypted PDF is refused; decrypt upstream |
| `transcribe` refused naming `media.command` | The file cannot go whole (format, > 25 MB, or too long). Set `transcription.stt.media.command` (ffmpeg) |
| `import` result has `provenance_note`, no `source/…` tag | The inbox file was changed after capture. Use `headings` instead of rewriting the file |
| MCP `file` says the inbox is gone | The run ended. Keep or download files while it runs |
| MCP `file` call rejected with a type error after upgrading | Claude Code caches tool schemas at connection — reload the plugin |
