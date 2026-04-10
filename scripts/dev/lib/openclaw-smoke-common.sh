: "${STATE_DIR:=${OPENCLAW_STATE_DIR:-$HOME/.openclaw}}"

openclaw_transient_gateway_error() {
  local output_path="$1"
  rg -q 'gateway closed \(1012\): service restart|Gateway agent failed; falling back to embedded|service restart|gateway closed \(1006 abnormal closure \(no close frame\)\): no close reason|1006 abnormal closure|no close reason|Gateway target: ws://127\.0\.0\.1:' "$output_path"
}

run_json_assert() {
  local json_path="$1"
  local expected="$2"
  python3 - <<'PY' "$json_path" "$expected"
import json, sys
path, expected = sys.argv[1], sys.argv[2]
decoder = json.JSONDecoder()
best = None
with open(path, "r", encoding="utf-8") as handle:
    raw = handle.read()
for index, char in enumerate(raw):
    if char != "{":
        continue
    try:
        candidate, _ = decoder.raw_decode(raw[index:])
    except json.JSONDecodeError:
        continue
    if isinstance(candidate, dict) and "result" in candidate:
        best = candidate
if best is None:
    raise SystemExit(f"{path}: missing JSON payload")
payload = best
text = payload["result"]["payloads"][0]["text"]
first_line = text.splitlines()[0] if text else ""
if text != expected and first_line != expected:
    raise SystemExit(f"{path}: unexpected text {text!r} != {expected!r}")
print(first_line if first_line == expected else text)
PY
}

json_payload_has_result() {
  local json_path="$1"
  python3 - <<'PY' "$json_path"
import json, sys
path = sys.argv[1]
decoder = json.JSONDecoder()
with open(path, "r", encoding="utf-8") as handle:
    raw = handle.read()
for index, char in enumerate(raw):
    if char != "{":
        continue
    try:
        candidate, _ = decoder.raw_decode(raw[index:])
    except json.JSONDecodeError:
        continue
    if isinstance(candidate, dict) and "result" in candidate:
        raise SystemExit(0)
raise SystemExit(1)
PY
}

run_openclaw_agent_json() {
  local output_path="$1"
  shift
  local attempts="${OPENCLAW_SELFTEST_AGENT_RETRIES:-3}"
  local delay="${OPENCLAW_SELFTEST_AGENT_RETRY_DELAY:-2}"
  local attempt
  local tmp_output
  local status

  for attempt in $(seq 1 "$attempts"); do
    tmp_output="$(mktemp "${TMPDIR:-/tmp}/openclaw-agent-json.XXXXXX")"
    if openclaw agent "$@" --json >"$tmp_output" 2>&1; then
      status=0
    else
      status=$?
    fi

    if json_payload_has_result "$tmp_output"; then
      mv "$tmp_output" "$output_path"
      return 0
    fi

    if [[ "$attempt" -lt "$attempts" ]] && openclaw_transient_gateway_error "$tmp_output"; then
      rm -f "$tmp_output"
      sleep "$delay"
      continue
    fi

    cat "$tmp_output" >&2
    rm -f "$tmp_output"
    return "${status:-1}"
  done

  echo "openclaw agent did not produce a valid JSON result after $attempts attempts" >&2
  return 1
}

openclaw_gateway_health_check() {
  local attempts="${OPENCLAW_SELFTEST_GATEWAY_RETRIES:-4}"
  local delay="${OPENCLAW_SELFTEST_GATEWAY_RETRY_DELAY:-2}"
  local attempt
  local tmp_output

  for attempt in $(seq 1 "$attempts"); do
    tmp_output="$(mktemp "${TMPDIR:-/tmp}/openclaw-gateway-health.XXXXXX")"
    if openclaw gateway health >"$tmp_output" 2>&1; then
      cat "$tmp_output"
      rm -f "$tmp_output"
      return 0
    fi

    if [[ "$attempt" -lt "$attempts" ]] && openclaw_transient_gateway_error "$tmp_output"; then
      rm -f "$tmp_output"
      sleep "$delay"
      continue
    fi

    cat "$tmp_output" >&2
    rm -f "$tmp_output"
    return 1
  done

  echo "openclaw gateway health failed after $attempts attempts" >&2
  return 1
}

openclaw_gateway_restart_with_retry() {
  local attempts="${OPENCLAW_GATEWAY_RESTART_ATTEMPTS:-5}"
  local delay="${OPENCLAW_GATEWAY_RESTART_DELAY:-5}"
  local attempt
  local tmp_output

  for attempt in $(seq 1 "$attempts"); do
    tmp_output="$(mktemp "${TMPDIR:-/tmp}/openclaw-gateway-restart.XXXXXX")"
    if openclaw gateway restart >"$tmp_output" 2>&1; then
      cat "$tmp_output"
      rm -f "$tmp_output"
      return 0
    fi

    if rg -q 'Gateway service not loaded\.|Start with: openclaw gateway install|Service not installed\. Run: openclaw gateway install' "$tmp_output"; then
      rm -f "$tmp_output"
      if openclaw_gateway_install_and_start; then
        return 0
      fi
      return 1
    fi

    if [[ "$attempt" -lt "$attempts" ]] && rg -q 'launchctl bootstrap failed: spawn launchctl EAGAIN|spawn launchctl EAGAIN|Resource temporarily unavailable' "$tmp_output"; then
      rm -f "$tmp_output"
      sleep "$delay"
      continue
    fi

    cat "$tmp_output" >&2
    rm -f "$tmp_output"
    return 1
  done

  echo "gateway restart failed after $attempts attempts" >&2
  return 1
}

openclaw_gateway_install_and_start() {
  local tmp_output

  tmp_output="$(mktemp "${TMPDIR:-/tmp}/openclaw-gateway-install.XXXXXX")"
  if ! openclaw gateway install --force >"$tmp_output" 2>&1; then
    cat "$tmp_output" >&2
    rm -f "$tmp_output"
    return 1
  fi
  rm -f "$tmp_output"

  tmp_output="$(mktemp "${TMPDIR:-/tmp}/openclaw-gateway-start.XXXXXX")"
  if openclaw gateway start >"$tmp_output" 2>&1; then
    rm -f "$tmp_output"
  else
    if ! rg -q 'Gateway service not loaded\.|Start with: openclaw gateway install' "$tmp_output"; then
      cat "$tmp_output" >&2
      rm -f "$tmp_output"
      return 1
    fi
    rm -f "$tmp_output"
  fi

  if [[ "${OSTYPE:-}" == darwin* ]] && command -v launchctl >/dev/null 2>&1; then
    launchctl kickstart -k "gui/$UID/ai.openclaw.gateway" >/dev/null 2>&1 || true
  fi

  return 0
}

openclaw_ensure_gateway_healthy() {
  if openclaw_gateway_health_check >/dev/null 2>&1; then
    return 0
  fi

  openclaw_gateway_restart_with_retry >/dev/null
  openclaw_gateway_health_check >/dev/null
}

openclaw_whatsapp_self_e164() {
  local attempts="${OPENCLAW_SELFTEST_CHANNEL_RETRIES:-4}"
  local delay="${OPENCLAW_SELFTEST_CHANNEL_RETRY_DELAY:-2}"
  local attempt
  local tmp_output

  for attempt in $(seq 1 "$attempts"); do
    tmp_output="$(mktemp "${TMPDIR:-/tmp}/openclaw-channels-status.XXXXXX")"
    if openclaw channels status --json >"$tmp_output" 2>&1; then
      if python3 - <<'PY' "$tmp_output"
import json, sys
raw = open(sys.argv[1], "r", encoding="utf-8").read()
start = raw.find("{")
if start < 0:
    raise SystemExit(1)
payload = json.loads(raw[start:])
print(payload["channels"]["whatsapp"]["self"]["e164"])
PY
      then
        rm -f "$tmp_output"
        return 0
      fi
    fi

    if [[ "$attempt" -lt "$attempts" ]] && openclaw_transient_gateway_error "$tmp_output"; then
      rm -f "$tmp_output"
      sleep "$delay"
      continue
    fi

    cat "$tmp_output" >&2
    rm -f "$tmp_output"
    return 1
  done

  echo "openclaw channels status failed after $attempts attempts" >&2
  return 1
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

agent_main_session_jsonl() {
  local agent_id="${1:-main}"
  session_jsonl_for_key "$agent_id" "agent:${agent_id}:main"
}

main_session_jsonl() {
  agent_main_session_jsonl "main"
}

wait_for_agent_main_session_jsonl() {
  local agent_id="$1"
  local attempts="${2:-40}"
  local delay="${3:-1}"
  local session_file=""

  for _ in $(seq 1 "$attempts"); do
    session_file="$(agent_main_session_jsonl "$agent_id")"
    if [[ -n "$session_file" && -f "$session_file" ]]; then
      printf '%s\n' "$session_file"
      return 0
    fi
    sleep "$delay"
  done

  echo "could not resolve main session file for $agent_id" >&2
  return 1
}

session_jsonl_for_key() {
  local agent_id="$1"
  local session_key="$2"
  python3 - <<'PY' "$STATE_DIR" "$agent_id" "$session_key"
import json, pathlib, sys

state_dir, agent_id, session_key = sys.argv[1:4]
session_dir = pathlib.Path(state_dir) / "agents" / agent_id / "sessions"
sessions_index = session_dir / "sessions.json"

if sessions_index.is_file():
    with open(sessions_index, "r", encoding="utf-8") as handle:
        data = json.load(handle)
    entry = data.get(session_key) or {}
    session_file = entry.get("sessionFile")
    if session_file:
        print(session_file)
        raise SystemExit(0)

print("")
PY
}

session_jsonl_for_id() {
  local agent_id="$1"
  local session_id="$2"
  python3 - <<'PY' "$STATE_DIR" "$agent_id" "$session_id"
import json, pathlib, sys

state_dir, agent_id, session_id = sys.argv[1:4]
session_dir = pathlib.Path(state_dir) / "agents" / agent_id / "sessions"
sessions_index = session_dir / "sessions.json"

if sessions_index.is_file():
    with open(sessions_index, "r", encoding="utf-8") as handle:
        data = json.load(handle)
    entry = data.get(session_id) or {}
    session_file = entry.get("sessionFile")
    if session_file:
        print(session_file)
        raise SystemExit(0)

for candidate in sorted(session_dir.glob("*.jsonl"), key=lambda item: item.stat().st_mtime, reverse=True):
    try:
        with open(candidate, "r", encoding="utf-8") as handle:
            first_line = handle.readline().strip()
        if not first_line:
            continue
        entry = json.loads(first_line)
        if entry.get("id") == session_id or (entry.get("message") or {}).get("id") == session_id:
            print(candidate)
            raise SystemExit(0)
    except (OSError, json.JSONDecodeError):
        continue

print("")
PY
}

wait_for_session_jsonl_for_id() {
  local agent_id="$1"
  local session_id="$2"
  local attempts="${3:-40}"
  local delay="${4:-1}"
  local session_file=""

  for _ in $(seq 1 "$attempts"); do
    session_file="$(session_jsonl_for_id "$agent_id" "$session_id")"
    if [[ -n "$session_file" && -f "$session_file" ]]; then
      printf '%s\n' "$session_file"
      return 0
    fi
    sleep "$delay"
  done

  echo "could not resolve session file for $agent_id/$session_id" >&2
  return 1
}

wait_for_child_session_from_main_after_line() {
  local main_session="$1"
  local start_line="$2"
  local agent_id="$3"
  local target_path="$4"
  local attempts="${5:-40}"
  local delay="${6:-1}"
  local child_session=""

  for _ in $(seq 1 "$attempts"); do
    child_session="$(child_session_file_from_main_after_line "$main_session" "$start_line" "$agent_id" "$target_path")"
    if [[ -n "$child_session" && -f "$child_session" ]]; then
      printf '%s\n' "$child_session"
      return 0
    fi
    sleep "$delay"
  done

  echo "could not find $agent_id subagent session for $target_path" >&2
  return 1
}

workspace_mirror_file() {
  local source_path="$1"
  local prefix="${2:-mirror}"
  local suffix="${3:-$(basename "$source_path")}"
  local mirror_dir="${STATE_DIR}/workspace/.local-agent-mirrors"
  local target_path=""

  mkdir -p "$mirror_dir"
  target_path="$(python3 - <<'PY' "$mirror_dir" "$prefix" "$suffix"
import os
import sys
import tempfile

mirror_dir, prefix, suffix = sys.argv[1:4]
if suffix and "." in suffix:
    extension = "." + suffix.rsplit(".", 1)[1]
else:
    extension = ""
fd, path = tempfile.mkstemp(prefix=f"{prefix}.", suffix=extension, dir=mirror_dir)
os.close(fd)
print(path)
PY
)"
  cp "$source_path" "$target_path"
  printf '%s\n' "$target_path"
}

session_line_count() {
  local session_file="$1"
  if [[ ! -f "$session_file" ]]; then
    echo 0
    return 0
  fi
  wc -l < "$session_file" | tr -d ' '
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

assert_session_pattern_after_line() {
  local session_file="$1"
  local start_line="$2"
  local pattern="$3"
  if [[ -z "$session_file" || ! -f "$session_file" ]]; then
    echo "missing session log $session_file" >&2
    exit 1
  fi
  if ! tail -n "+$((start_line + 1))" "$session_file" | rg -q "$pattern"; then
    echo "expected pattern $pattern after line $start_line in $session_file" >&2
    exit 1
  fi
}

wait_for_session_pattern_after_line() {
  local session_file="$1"
  local start_line="$2"
  local pattern="$3"
  local attempts="${4:-40}"
  local delay="${5:-1}"
  for _ in $(seq 1 "$attempts"); do
    if [[ -n "$session_file" && -f "$session_file" ]] && tail -n "+$((start_line + 1))" "$session_file" | rg -q "$pattern"; then
      return 0
    fi
    sleep "$delay"
  done
  echo "expected pattern $pattern after line $start_line in $session_file" >&2
  exit 1
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

child_session_file_from_main_after_line() {
  local main_session="$1"
  local start_line="$2"
  local agent_id="$3"
  local target_path="$4"
  python3 - <<'PY' "$STATE_DIR" "$main_session" "$start_line" "$agent_id" "$target_path"
import json, pathlib, sys

state_dir, main_session, start_line_raw, agent_id, target_path = sys.argv[1:6]
start_line = int(start_line_raw)
tool_calls = {}
child_session_key = None

with open(main_session, "r", encoding="utf-8") as handle:
    for index, raw_line in enumerate(handle, start=1):
        if index <= start_line:
            continue
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

assert_session_exec_result() {
  local session_file="$1"
  local command_substring="$2"
  local expected_output="$3"
  if [[ -z "$session_file" || ! -f "$session_file" ]]; then
    echo "missing session log $session_file" >&2
    exit 1
  fi
  python3 - <<'PY' "$session_file" "$command_substring" "$expected_output"
import json, sys

session_file, command_substring, expected_output = sys.argv[1], sys.argv[2], sys.argv[3]
tool_calls = {}

with open(session_file, "r", encoding="utf-8") as handle:
    for raw_line in handle:
        raw_line = raw_line.strip()
        if not raw_line:
            continue
        entry = json.loads(raw_line)
        message = entry.get("message") or {}
        role = message.get("role")
        if role == "assistant":
            for item in message.get("content") or []:
                if item.get("type") == "toolCall" and item.get("name") == "exec":
                    tool_calls[item.get("id")] = (item.get("arguments") or {}).get("command", "")
        elif role == "toolResult" and message.get("toolName") == "exec":
            tool_call_id = message.get("toolCallId")
            command = tool_calls.get(tool_call_id, "")
            details = message.get("details") or {}
            aggregated = (details.get("aggregated") or "").strip()
            exit_code = details.get("exitCode")
            if command_substring in command and exit_code == 0 and aggregated == expected_output:
                print(expected_output)
                raise SystemExit(0)

raise SystemExit(
    f"missing exec result for command containing {command_substring!r} with output {expected_output!r} in {session_file}"
)
PY
}

assert_session_read_result() {
  local session_file="$1"
  local path_substring="$2"
  local expected_output="$3"
  if [[ -z "$session_file" || ! -f "$session_file" ]]; then
    echo "missing session log $session_file" >&2
    exit 1
  fi
  python3 - <<'PY' "$session_file" "$path_substring" "$expected_output"
import json, sys

session_file, path_substring, expected_output = sys.argv[1], sys.argv[2], sys.argv[3]
tool_calls = {}

with open(session_file, "r", encoding="utf-8") as handle:
    for raw_line in handle:
        raw_line = raw_line.strip()
        if not raw_line:
            continue
        entry = json.loads(raw_line)
        message = entry.get("message") or {}
        role = message.get("role")
        if role == "assistant":
            for item in message.get("content") or []:
                if item.get("type") == "toolCall" and item.get("name") == "read":
                    tool_calls[item.get("id")] = (item.get("arguments") or {}).get("path", "")
        elif role == "toolResult" and message.get("toolName") == "read":
            tool_call_id = message.get("toolCallId")
            read_path = tool_calls.get(tool_call_id, "")
            content = "".join(
                part.get("text", "")
                for part in message.get("content") or []
                if isinstance(part, dict) and part.get("type") == "text"
            )
            if path_substring in read_path and content.rstrip("\n") == expected_output:
                print(expected_output)
                raise SystemExit(0)

raise SystemExit(
    f"missing read result for path containing {path_substring!r} with output {expected_output!r} in {session_file}"
)
PY
}
