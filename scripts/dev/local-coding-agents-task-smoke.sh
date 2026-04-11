#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
STATE_DIR="${OPENCLAW_STATE_DIR:-$HOME/.openclaw}"
NODE22_BIN="${OPENCLAW_SELFTEST_NODE_BIN:-$HOME/.node22/current/bin}"
TASK_ROOT="$(mktemp -d "$REPO_ROOT/.local-agent-task-smoke.XXXXXX")"
TASK_JSON="$TASK_ROOT/task.json"
REPORT_FILE="$TASK_ROOT/report.txt"
PROOF_FILE="$TASK_ROOT/input-proof.txt"
TASK_EXIT_CODE=0

cleanup() {
  if [[ "$TASK_EXIT_CODE" -eq 0 ]]; then
    rm -rf "$TASK_ROOT"
  else
    echo "preserving task smoke artifacts: $TASK_ROOT" >&2
  fi
}

on_exit() {
  TASK_EXIT_CODE="$1"
  trap - EXIT
  cleanup
  exit "$TASK_EXIT_CODE"
}

trap 'on_exit $?' EXIT

if [[ -d "$NODE22_BIN" ]]; then
  PATH="$NODE22_BIN:$PATH"
  export PATH
fi

PATH="$REPO_ROOT/scripts/dev:$REPO_ROOT/../claw-code-parity/scripts:$PATH"
export PATH

source "$SCRIPT_DIR/lib/openclaw-smoke-common.sh"

archive_task_smoke_agent_sessions() {
  local agent_id="$1"
  local session_dir="$STATE_DIR/agents/$agent_id/sessions"
  local archive_dir="$STATE_DIR/agents/$agent_id/session-archives/local-task-smoke-$(date +%s)-$RANDOM"
  if [[ ! -d "$session_dir" ]]; then
    mkdir -p "$session_dir"
    return 0
  fi

  shopt -s nullglob
  local files=("$session_dir"/*)
  shopt -u nullglob
  if ((${#files[@]} == 0)); then
    return 0
  fi

  mkdir -p "$archive_dir"
  mv "${files[@]}" "$archive_dir"/
  mkdir -p "$session_dir"
}

echo "== bootstrap local coding agents =="
node "$REPO_ROOT/scripts/dev/bootstrap-local-coding-agents.mjs" >/dev/null

echo "== builder real task smoke =="
archive_task_smoke_agent_sessions "oc-builder"
PROOF_TOKEN="TASK_PROOF_$(python3 - <<'PY'
import uuid
print(uuid.uuid4().hex)
PY
)"
printf '%s\n' "$PROOF_TOKEN" >"$PROOF_FILE"
EXPECTED_REPORT="$(cat <<EOF
LOCAL_AGENT_TASK_OK
bootstrap=qa:local-agents:bootstrap
selftest=qa:local-agents:selftest
probe=claw-code-local --version
proof=$PROOF_TOKEN
EOF
)"
BUILDER_SESSION="$(agent_main_session_jsonl "oc-builder")"
if [[ -z "$BUILDER_SESSION" || ! -f "$BUILDER_SESSION" ]]; then
  BUILDER_BEFORE_LINES=0
else
  BUILDER_BEFORE_LINES="$(session_line_count "$BUILDER_SESSION")"
fi

run_openclaw_agent_json "$TASK_JSON" --agent oc-builder --message "Nutze read und lies package.json, qa/local-coding-agents.md sowie exakt die Datei $PROOF_FILE. Nutze danach apply_patch oder edit und schreibe in $REPORT_FILE exakt diese fünf Zeilen:
LOCAL_AGENT_TASK_OK
bootstrap=qa:local-agents:bootstrap
selftest=qa:local-agents:selftest
probe=claw-code-local --version
proof=<exakter gelesener Inhalt aus $PROOF_FILE ohne zusätzliche Leerzeichen>
Antworte exakt mit TASK_SMOKE_OK."

run_json_assert "$TASK_JSON" "TASK_SMOKE_OK" >/dev/null
if [[ -z "$BUILDER_SESSION" || ! -f "$BUILDER_SESSION" ]]; then
  BUILDER_SESSION="$(wait_for_agent_main_session_jsonl "oc-builder" 40 1)"
fi

ACTUAL_REPORT="$(cat "$REPORT_FILE")"
if [[ "$ACTUAL_REPORT" != "$EXPECTED_REPORT" ]]; then
  echo "unexpected task smoke report contents" >&2
  printf 'expected:\n%s\n---\nactual:\n%s\n' "$EXPECTED_REPORT" "$ACTUAL_REPORT" >&2
  exit 1
fi

wait_for_session_pattern_after_line "$BUILDER_SESSION" "$BUILDER_BEFORE_LINES" '"name":"read"|"toolName":"read"'
wait_for_session_pattern_after_line "$BUILDER_SESSION" "$BUILDER_BEFORE_LINES" 'package\.json'
wait_for_session_pattern_after_line "$BUILDER_SESSION" "$BUILDER_BEFORE_LINES" 'qa/local-coding-agents\.md'
assert_session_read_result "$BUILDER_SESSION" "$PROOF_FILE" "$PROOF_TOKEN" >/dev/null
wait_for_session_pattern_after_line "$BUILDER_SESSION" "$BUILDER_BEFORE_LINES" '"name":"apply_patch"|"name":"edit"|"name":"write"|"toolName":"apply_patch"|"toolName":"edit"|"toolName":"write"'

echo "== local coding agent task smoke passed =="
