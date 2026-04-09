#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
STATE_DIR="${OPENCLAW_STATE_DIR:-$HOME/.openclaw}"
NODE22_BIN="${OPENCLAW_SELFTEST_NODE_BIN:-$HOME/.node22/current/bin}"
SMOKE_ROOT="$(mktemp -d "$REPO_ROOT/.local-main-task-smoke.XXXXXX")"
MAIN_JSON="$SMOKE_ROOT/main.json"
REPORT_FILE="$SMOKE_ROOT/report.txt"

cleanup() {
  rm -rf "$SMOKE_ROOT"
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
first_line = text.splitlines()[0] if text else ""
if text != expected and first_line != expected:
    raise SystemExit(f"{path}: unexpected text {text!r} != {expected!r}")
print(first_line if first_line == expected else text)
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
  local session_file="$1"
  local pattern="$2"
  if [[ -z "$session_file" || ! -f "$session_file" ]]; then
    echo "missing session log $session_file" >&2
    exit 1
  fi
  if ! rg -q "$pattern" "$session_file"; then
    echo "expected pattern $pattern in $session_file" >&2
    exit 1
  fi
}

child_session_file_from_main() {
  local main_session="$1"
  local agent_id="$2"
  local target_path="$3"
  python3 - <<'PY' "$STATE_DIR" "$main_session" "$agent_id" "$target_path"
import json, pathlib, sys

state_dir, main_session, agent_id, target_path = sys.argv[1:5]
tool_calls = {}
child_session_key = None

with open(main_session, "r", encoding="utf-8") as handle:
    for raw_line in handle:
        raw_line = raw_line.strip()
        if not raw_line:
            continue
        entry = json.loads(raw_line)
        message = entry.get("message") or {}
        role = message.get("role")
        if role == "assistant":
            for item in message.get("content") or []:
                if item.get("type") != "toolCall" or item.get("name") != "sessions_spawn":
                    continue
                arguments = item.get("arguments") or {}
                if arguments.get("agentId") == agent_id and target_path in (arguments.get("task") or ""):
                    tool_calls[item.get("id")] = True
        elif role == "toolResult" and message.get("toolName") == "sessions_spawn":
            tool_call_id = message.get("toolCallId")
            if tool_call_id in tool_calls:
                details = message.get("details") or {}
                child_session_key = details.get("childSessionKey")

if not child_session_key:
    print("")
    raise SystemExit(0)

sessions_index = pathlib.Path(state_dir) / "agents" / agent_id / "sessions" / "sessions.json"
if not sessions_index.is_file():
    print("")
    raise SystemExit(0)

with open(sessions_index, "r", encoding="utf-8") as handle:
    data = json.load(handle)
entry = data.get(child_session_key) or {}
print(entry.get("sessionFile", ""))
PY
}

wait_for_file_contents() {
  local target="$1"
  local expected="$2"
  local attempts="${3:-40}"
  local delay="${4:-1}"
  for _ in $(seq 1 "$attempts"); do
    if [[ -f "$target" ]]; then
      local content
      content="$(cat "$target")"
      if [[ "$content" == "$expected" ]]; then
        return 0
      fi
    fi
    sleep "$delay"
  done
  echo "timed out waiting for expected contents in $target" >&2
  if [[ -f "$target" ]]; then
    printf 'actual contents:\n%s\n' "$(cat "$target")" >&2
  fi
  exit 1
}

echo "== bootstrap local coding agents =="
node "$REPO_ROOT/scripts/dev/bootstrap-local-coding-agents.mjs" >/dev/null

printf 'before\n' >"$REPORT_FILE"

EXPECTED_REPORT="$(cat <<'EOF'
MAIN_TASK_SMOKE_OK
bootstrap=qa:local-agents:bootstrap
selftest=qa:local-agents:selftest
probe=claw-code-local --version
EOF
)"

echo "== main delegated task smoke =="
openclaw agent --agent main --message "Nutze sessions_spawn und starte einen oc-builder-Subagenten im aktuellen Repo. Child-Task: lies package.json und qa/local-coding-agents.md. Überschreibe danach per apply_patch, edit oder write exakt die bereits existierende Datei $REPORT_FILE mit diesen vier Zeilen:
MAIN_TASK_SMOKE_OK
bootstrap=qa:local-agents:bootstrap
selftest=qa:local-agents:selftest
probe=claw-code-local --version
Verwende genau diesen Pfad. Antworte exakt mit MAIN_TASK_OK, sobald der Child-Run akzeptiert wurde." --json >"$MAIN_JSON"
run_json_assert "$MAIN_JSON" "MAIN_TASK_OK" >/dev/null

MAIN_SESSION="$(latest_session_jsonl "main")"
assert_session_pattern "$MAIN_SESSION" '"name":"sessions_spawn"'
assert_session_pattern "$MAIN_SESSION" "$REPORT_FILE"

BUILDER_SESSION=""
for _ in $(seq 1 40); do
  BUILDER_SESSION="$(child_session_file_from_main "$MAIN_SESSION" "oc-builder" "$REPORT_FILE")"
  if [[ -n "$BUILDER_SESSION" && -f "$BUILDER_SESSION" ]]; then
    break
  fi
  sleep 1
done

if [[ -z "$BUILDER_SESSION" || ! -f "$BUILDER_SESSION" ]]; then
  echo "could not find oc-builder subagent session for $REPORT_FILE" >&2
  exit 1
fi

wait_for_file_contents "$REPORT_FILE" "$EXPECTED_REPORT"

assert_session_pattern "$BUILDER_SESSION" '"provider":"openai-codex"'
assert_session_pattern "$BUILDER_SESSION" '"model":"gpt-5.3-codex-spark"'
assert_session_pattern "$BUILDER_SESSION" '"name":"read"'
assert_session_pattern "$BUILDER_SESSION" 'package\.json'
assert_session_pattern "$BUILDER_SESSION" 'qa/local-coding-agents\.md'
assert_session_pattern "$BUILDER_SESSION" '"name":"apply_patch"|"name":"edit"|"name":"write"'
assert_session_pattern "$BUILDER_SESSION" "$REPORT_FILE"

echo "== local main delegated task smoke passed =="
