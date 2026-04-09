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

assert_latest_session_pattern() {
  local agent_id="$1"
  local pattern="$2"
  local session_file
  session_file="$(latest_session_jsonl "$agent_id")"
  if [[ -z "$session_file" || ! -f "$session_file" ]]; then
    echo "missing session log for $agent_id" >&2
    exit 1
  fi
  assert_session_pattern "$session_file" "$pattern"
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
