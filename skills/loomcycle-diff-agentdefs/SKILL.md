---
name: loomcycle-diff-agentdefs
description: Diff two loomcycle AgentDef versions by def_id and show what changed in system_prompt, allowed_tools, max_tokens, and other fields. Use when the user wants to compare two versions of a self-evolving agent definition.
---

# Diff two loomcycle AgentDef versions

Use when the operator wants to see what changed between two versions of a
self-evolving agent definition (the loomcycle AgentDef substrate tracks
versioned definitions with lineage).

Steps:

1. **Get the two def_ids.** The operator supplies two `def_id`s (often a
   parent and its descendant). If they only have one and want "the previous
   version," fetch the one they have first and read its `parent_def_id`.

2. **Fetch both** with the `agentdef` tool, `get` op, once per id:

   ```json
   { "op": "get", "def_id": "<def_id>" }
   ```

   Each returns a row whose `definition` field is the agent config —
   `system_prompt`, `allowed_tools`, `max_tokens`, provider/model/tier, etc.

3. **Diff the definitions** field by field. Highlight, in this order:
   - `system_prompt` — show a readable diff (added / removed lines), not the
     two full prompts side by side unless they're short.
   - `allowed_tools` — which tools were added / removed.
   - `max_tokens`, `model`, `provider`, `tier`, `effort` — any scalar changes.
   - Any other changed keys.

4. **Summarise the intent.** In one line, characterise the change ("widened
   tool access + tightened the system prompt's output format"). Note the
   lineage (`parent_def_id`) and which is newer (`version` / `created_at`).

5. **Stay descriptive.** This skill reports a diff; it does **not** promote,
   retire, or pin a version. Selection between AgentDef versions is operator
   policy — if the operator wants to act on the diff, point them at the
   relevant `agentdef` ops, but don't mutate on their behalf without an
   explicit ask.
