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

run_json_assert() {
  local json_path="$1"
  local expected="$2"
  python3 - <<'PY' "$json_path" "$expected"
import json, sys
path, expected = sys.argv[1], sys.argv[2]
with open(path, "r", encoding="utf-8") as handle:
    raw = handle.read()
start = raw.find("{")
if start < 0:
    raise SystemExit(f"{path}: missing JSON payload")
payload = json.loads(raw[start:])
text = payload["result"]["payloads"][0]["text"]
if text != expected:
    raise SystemExit(f"{path}: unexpected text {text!r} != {expected!r}")
print(text)
PY
}

latest_session_jsonl() {
  local agent_id="$1"
  python3 - <<'PY' "$STATE_DIR" "$agent_id"
import pathlib, sys
state_dir, agent_id = sys.argv[1], sys.argv[2]
session_dir = pathlib.Path(state_dir) / "agents" / agent_id / "sessions"
files = sorted(session_dir.glob("*.jsonl"), key=lambda item: item.stat().st_mtime, reverse=True)
print(files[0] if files else "")
PY
}

assert_session_pattern() {
  local agent_id="$1"
  local pattern="$2"
  local session_file
  session_file="$(latest_session_jsonl "$agent_id")"
  if [[ -z "$session_file" || ! -f "$session_file" ]]; then
    echo "missing session log for $agent_id" >&2
    exit 1
  fi
  if ! rg -q "$pattern" "$session_file"; then
    echo "expected pattern $pattern in $session_file" >&2
    exit 1
  fi
}

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

openclaw agent --agent oc-builder --message "Nutze read und lies package.json sowie qa/local-coding-agents.md. Nutze danach apply_patch oder edit und schreibe in $REPORT_FILE exakt diese vier Zeilen:
LOCAL_AGENT_TASK_OK
bootstrap=qa:local-agents:bootstrap
selftest=qa:local-agents:selftest
probe=claw-code-local --version
Antworte exakt mit TASK_SMOKE_OK." --json >"$TASK_JSON"

run_json_assert "$TASK_JSON" "TASK_SMOKE_OK" >/dev/null

ACTUAL_REPORT="$(cat "$REPORT_FILE")"
if [[ "$ACTUAL_REPORT" != "$EXPECTED_REPORT" ]]; then
  echo "unexpected task smoke report contents" >&2
  printf 'expected:\n%s\n---\nactual:\n%s\n' "$EXPECTED_REPORT" "$ACTUAL_REPORT" >&2
  exit 1
fi

assert_session_pattern "oc-builder" '"name":"read"'
assert_session_pattern "oc-builder" 'package\.json'
assert_session_pattern "oc-builder" 'qa/local-coding-agents\.md'
assert_session_pattern "oc-builder" '"name":"apply_patch"|"name":"edit"|"name":"write"'

echo "== local coding agent task smoke passed =="
