#!/usr/bin/env bash
# capture-run-telemetry.sh — PostToolUse hook (OPT-IN).
#
# Records loomcycle run telemetry (run_id / agent_id / duration) to the
# plugin data dir for cross-session reference. No-op unless the operator
# opts in with LOOMCYCLE_PLUGIN_TELEMETRY=1 — defaults stay quiet, mirroring
# loomcycle's own default-deny posture.
#
# Reads the PostToolUse event JSON on stdin. ALWAYS exits 0 — a telemetry
# hook must never fail or block the underlying tool call.
set -u

[ "${LOOMCYCLE_PLUGIN_TELEMETRY:-0}" = "1" ] || exit 0

input="$(cat)"
data_dir="${CLAUDE_PLUGIN_DATA:-${HOME}/.cache/loomcycle-plugin}"
mkdir -p "$data_dir" 2>/dev/null || exit 0
out="$data_dir/run-telemetry.jsonl"
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

if command -v jq >/dev/null 2>&1; then
  # tool_response shape varies; probe the common keys and degrade to null.
  line="$(printf '%s' "$input" | jq -c --arg ts "$ts" '{
    ts: $ts,
    tool: (.tool_name // null),
    run_id: (.tool_response.run_id // .tool_response.runId // null),
    agent_id: (.tool_response.agent_id // .tool_response.agentId // null)
  }' 2>/dev/null)"
  [ -n "$line" ] && printf '%s\n' "$line" >> "$out"
else
  # No jq: record a timestamped marker so the operator at least sees activity.
  printf '{"ts":"%s","note":"jq not available; install jq for full telemetry"}\n' "$ts" >> "$out"
fi

exit 0
