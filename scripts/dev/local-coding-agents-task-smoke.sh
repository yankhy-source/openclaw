#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
STATE_DIR="${OPENCLAW_STATE_DIR:-$HOME/.openclaw}"
NODE22_BIN="${OPENCLAW_SELFTEST_NODE_BIN:-$HOME/.node22/current/bin}"
TASK_ROOT="$(mktemp -d "$REPO_ROOT/.local-agent-task-smoke.XXXXXX")"
TASK_JSON="$TASK_ROOT/task.json"
REPORT_FILE="$TASK_ROOT/report.txt"

cleanup() {
  rm -rf "$TASK_ROOT"
}
trap cleanup EXIT

if [[ -d "$NODE22_BIN" ]]; then
  PATH="$NODE22_BIN:$PATH"
  export PATH
fi

PATH="$REPO_ROOT/scripts/dev:$REPO_ROOT/../claw-code-parity/scripts:$PATH"
export PATH

source "$SCRIPT_DIR/lib/openclaw-smoke-common.sh"

echo "== bootstrap local coding agents =="
node "$REPO_ROOT/scripts/dev/bootstrap-local-coding-agents.mjs" >/dev/null

echo "== builder real task smoke =="
EXPECTED_REPORT="$(cat <<'EOF'
LOCAL_AGENT_TASK_OK
bootstrap=qa:local-agents:bootstrap
selftest=qa:local-agents:selftest
probe=claw-code-local --version
EOF
)"

run_openclaw_agent_json "$TASK_JSON" --agent oc-builder --message "Nutze read und lies package.json sowie qa/local-coding-agents.md. Nutze danach apply_patch oder edit und schreibe in $REPORT_FILE exakt diese vier Zeilen:
LOCAL_AGENT_TASK_OK
bootstrap=qa:local-agents:bootstrap
selftest=qa:local-agents:selftest
probe=claw-code-local --version
Antworte exakt mit TASK_SMOKE_OK."

run_json_assert "$TASK_JSON" "TASK_SMOKE_OK" >/dev/null

ACTUAL_REPORT="$(cat "$REPORT_FILE")"
if [[ "$ACTUAL_REPORT" != "$EXPECTED_REPORT" ]]; then
  echo "unexpected task smoke report contents" >&2
  printf 'expected:\n%s\n---\nactual:\n%s\n' "$EXPECTED_REPORT" "$ACTUAL_REPORT" >&2
  exit 1
fi

assert_latest_session_pattern "oc-builder" '"name":"read"'
assert_latest_session_pattern "oc-builder" 'package\.json'
assert_latest_session_pattern "oc-builder" 'qa/local-coding-agents\.md'
assert_latest_session_pattern "oc-builder" '"name":"apply_patch"|"name":"edit"|"name":"write"'

echo "== local coding agent task smoke passed =="
