---
name: loomcycle-diff-agentdefs
description: Diff two loomcycle AgentDef versions by def_id and show what changed in system_prompt, tools, model routing, grants, hooks and other fields. Use when the user wants to compare two versions of an agent definition.
---

# Diff two loomcycle AgentDef versions

Use when the operator wants to see what changed between two versions of a
self-evolving agent definition (the loomcycle AgentDef substrate tracks
versioned definitions with lineage).

Steps:

1. **Get the two def_ids.** The operator supplies two `def_id`s (often a
   parent and its descendant). If they only have one and want "the previous
   version," fetch the one they have first and read its `parent_def_id`.

   To find ids from a name, `{ "op": "list", "name": "<agent>" }` returns the
   versions. Note which one is **active**: a version that was created or forked
   but never promoted is not what runs.

2. **Fetch both** with the `agentdef` tool, `get` op, once per id:

   ```json
   { "op": "get", "def_id": "<def_id>" }
   ```

   Each returns a row whose `definition` field is the agent config —
   `system_prompt`, `tools`, `max_tokens`, provider/model/tier, etc.

3. **Diff the definitions** field by field. Highlight, in this order:
   - `system_prompt` — show a readable diff (added / removed lines), not the
     two full prompts side by side unless they're short.
   - `tools` — which tools were added / removed.
   - `max_tokens`, `model`, `provider`, `tier`, `effort` — any scalar changes.
   - **Grants** — `memory_scopes`, `sql_scopes`, `channels`, `volumes`,
     `interruption`, and the `*_def_scopes` lists. A widened grant changes what
     the agent can reach even when the prompt is untouched. The `*_def_scopes`
     lists are authority rather than content and are left out of
     `content_sha256`, so compare them explicitly; equal hashes do not prove
     equal reach.
   - `hooks` — a gate added or removed changes which calls are checked.
   - `context`, `compaction`, `sampling`, `tool_choice`, `output_format`,
     `decision` — how the agent manages history, decodes, and is constrained.
   - Any other changed keys.

   **`provider: code-js` (v0.16, RFC J).** If either version sets
   `provider: code-js`, that version is a **synthetic code agent** — it runs
   operator-authored JavaScript (`agent_code/<name>/index.js`) instead of
   calling an LLM, at zero token cost. For such a version `model` / `effort` /
   `max_tokens` are inert (no model is called), so don't read into them; the
   behavioural ground truth is the JS file, not the def fields. Call out a
   `provider` flip **into or out of** `code-js` prominently — it turns the agent
   from model-driven to code-driven (or back), a far bigger change than any
   prompt edit.

4. **Summarise the intent.** In one line, characterise the change ("widened
   tool access + tightened the system prompt's output format"). Note the
   lineage (`parent_def_id`) and which is newer (`version` / `created_at`).

5. **Stay descriptive.** This skill reports a diff; it does **not** promote,
   retire, or pin a version. Selection between AgentDef versions is operator
   policy — if the operator wants to act on the diff, point them at the
   relevant `agentdef` ops, but don't mutate on their behalf without an
   explicit ask.
