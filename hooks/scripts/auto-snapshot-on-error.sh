#!/usr/bin/env bash
# auto-snapshot-on-error.sh — PostToolUse hook (OPT-IN).
#
# When a loomcycle MCP tool call returns an error AND the operator has opted
# in with LOOMCYCLE_PLUGIN_AUTO_SNAPSHOT=1, capture a runtime snapshot named
# "pre-error-<ts>" so the operator can restore to before the failure.
#
# The bearer is read from the EXISTING environment (LOOMCYCLE_AUTH_TOKEN) —
# we never substitute the secret into a command string. The operator who
# enables this hook is expected to export LOOMCYCLE_BASE_URL +
# LOOMCYCLE_AUTH_TOKEN in the shell that launches Claude Code.
#
# ALWAYS exits 0 — a convenience hook must never fail or block the tool call.
set -u

[ "${LOOMCYCLE_PLUGIN_AUTO_SNAPSHOT:-0}" = "1" ] || exit 0

input="$(cat)"

# Detect an error in the tool response.
is_err=0
if command -v jq >/dev/null 2>&1; then
  err="$(printf '%s' "$input" | jq -r '
    (.tool_response.is_error // .tool_response.error.type // .tool_response.error // empty)
  ' 2>/dev/null)"
  case "$err" in
    "" | "false" | "null") ;;
    *) is_err=1 ;;
  esac
else
  printf '%s' "$input" | grep -q '"is_error"[[:space:]]*:[[:space:]]*true' && is_err=1
fi
[ "$is_err" = "1" ] || exit 0

# Runtime-admin snapshot talks to a running instance via LOOMCYCLE_BASE_URL
# (defaults to http://127.0.0.1:8787) + LOOMCYCLE_AUTH_TOKEN.
bin="${LOOMCYCLE_BIN_PATH:-loomcycle}"
ts="$(date -u +%Y%m%dT%H%M%SZ)"

run_snapshot() { "$bin" snapshot --description "pre-error-$ts"; }

if command -v timeout >/dev/null 2>&1; then
  timeout 10 bash -c "$(declare -f run_snapshot); run_snapshot" >&2 2>&1 \
    || echo "loomcycle auto-snapshot: snapshot failed or timed out (non-fatal)" >&2
else
  run_snapshot >&2 2>&1 \
    || echo "loomcycle auto-snapshot: snapshot failed (non-fatal)" >&2
fi

exit 0
