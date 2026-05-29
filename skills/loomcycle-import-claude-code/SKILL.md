---
name: loomcycle-import-claude-code
description: Guide the user through importing a .claude/ directory into loomcycle yaml using the `loomcycle import claude-code` CLI — dry-run first, review the report, then write. Use when the user wants to move Claude Code agents/skills/MCP servers into a loomcycle config.
allowed-tools: Bash(loomcycle import claude-code*) Bash(loomcycle validate*)
---

# Import a .claude/ repo into loomcycle

Guide the operator through RFC C2's `loomcycle import claude-code` CLI without
them having to remember its flags. This wraps the **CLI**, not an MCP tool —
the importer is a loomcycle subcommand.

Steps:

1. **Locate the source.** Confirm the path to the `.claude/` directory to
   import (default `./.claude/`). Confirm `loomcycle` is on PATH (or the
   operator's `${user_config.bin_path}`).

2. **Dry-run first — always.** Run the importer in report mode and show the
   operator what *would* be imported before touching any file:

   ```bash
   loomcycle import claude-code --from=<path-to-.claude/>
   ```

   Render the report: agents (+ any v0.12.7 substrate-field heuristics like
   `# credentials:` comments or `schedule_def_scopes` stubs), skills (flag
   multi-file ones), MCP servers (note C1 recipe-library rewrites), skipped
   slash commands, and the **unmapped fields** list. Call out anything lossy —
   the importer is loud about it for a reason.

3. **Decide on options with the operator:**
   - `--no-recipe-match` if they want literal `.mcp.json` ports instead of
     curated C1 recipe rewrites.
   - `--emit-recipes` (requires `LOOMCYCLE_MCP_RECIPES_ROOT`) to also write
     reusable recipe JSON to the overlay.
   - `--skills-dest=<dir>` for where SKILL.md files land.

4. **Write when they're ready.** Re-run with `--write` (add `--force` only if
   they accept clobbering existing entries), targeting their config:

   ```bash
   loomcycle import claude-code --from=<path> --write --diff=<loomcycle.yaml>
   ```

5. **Validate the result.** Run `loomcycle validate <loomcycle.yaml>` and
   report the outcome. A "no provider resolved" error is expected if the
   operator hasn't wired tier→provider→model policy yet — that's a config step,
   not an import defect; point them at their `user_tiers` config.

This skill moves **authoring content** into loomcycle (the data-movement
direction). It is the counterpart to this plugin's runtime-control commands —
keep the two roles distinct and don't try to push definitions back out to
`.claude/` (there is no reverse export).
