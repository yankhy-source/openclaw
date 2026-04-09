#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
STATE_DIR="${OPENCLAW_STATE_DIR:-$HOME/.openclaw}"
NODE22_BIN="${OPENCLAW_SELFTEST_NODE_BIN:-$HOME/.node22/current/bin}"
SMOKE_ROOT="$(mktemp -d "$REPO_ROOT/.local-main-routing-smoke.XXXXXX")"
GITHUB_JSON="$SMOKE_ROOT/main-github.json"
CLAW_JSON="$SMOKE_ROOT/main-claw.json"
GITHUB_PROOF="$(mktemp /tmp/main-route-github.XXXXXX)"
CLAW_PROOF="$(mktemp /tmp/main-route-claw.XXXXXX)"

cleanup() {
  rm -rf "$SMOKE_ROOT"
  rm -f "$GITHUB_PROOF" "$CLAW_PROOF"
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

echo "== main -> oc-github routing smoke =="
openclaw agent --agent main --message "Nutze sessions_spawn und starte einen oc-github-Subagenten. Child-Task: führe per exec 'gh repo view yankhy-source/claw-code-parity --json nameWithOwner --jq .nameWithOwner' aus und überschreibe danach per exec exakt die bereits existierende Datei $GITHUB_PROOF mit ROUTE_GITHUB_OK:yankhy-source/claw-code-parity. Verwende genau diesen Pfad, keine neue Temp-Datei. Antworte exakt mit MAIN_ROUTE_GITHUB_OK, sobald der Child-Run akzeptiert wurde." --json >"$GITHUB_JSON"
run_json_assert "$GITHUB_JSON" "MAIN_ROUTE_GITHUB_OK" >/dev/null

MAIN_SESSION="$(latest_session_jsonl "main")"
assert_session_pattern "$MAIN_SESSION" '"name":"sessions_spawn"'
assert_session_pattern "$MAIN_SESSION" "$GITHUB_PROOF"

GITHUB_SESSION=""
for _ in $(seq 1 40); do
  GITHUB_SESSION="$(child_session_file_from_main "$MAIN_SESSION" "oc-github" "$GITHUB_PROOF")"
  if [[ -n "$GITHUB_SESSION" && -f "$GITHUB_SESSION" ]]; then
    break
  fi
  sleep 1
done

if [[ -z "$GITHUB_SESSION" || ! -f "$GITHUB_SESSION" ]]; then
  echo "could not find oc-github subagent session for $GITHUB_PROOF" >&2
  exit 1
fi

wait_for_file_contents "$GITHUB_PROOF" "ROUTE_GITHUB_OK:yankhy-source/claw-code-parity"

assert_session_pattern "$GITHUB_SESSION" '"provider":"openai-codex"'
assert_session_pattern "$GITHUB_SESSION" '"model":"gpt-5.3-codex-spark"'
assert_session_pattern "$GITHUB_SESSION" '"name":"exec"'
assert_session_pattern "$GITHUB_SESSION" 'gh repo view yankhy-source/claw-code-parity'
assert_session_pattern "$GITHUB_SESSION" "$GITHUB_PROOF"

echo "== main -> claw-code routing smoke =="
openclaw agent --agent main --message "Nutze sessions_spawn und starte einen claw-code-Subagenten. Child-Task: führe per exec 'claw-code-local status' aus und überschreibe danach per exec exakt die bereits existierende Datei $CLAW_PROOF mit ROUTE_CLAW_OK. Verwende genau diesen Pfad, keine neue Temp-Datei. Antworte exakt mit MAIN_ROUTE_CLAW_OK, sobald der Child-Run akzeptiert wurde." --json >"$CLAW_JSON"
run_json_assert "$CLAW_JSON" "MAIN_ROUTE_CLAW_OK" >/dev/null

MAIN_SESSION="$(latest_session_jsonl "main")"
assert_session_pattern "$MAIN_SESSION" '"name":"sessions_spawn"'
assert_session_pattern "$MAIN_SESSION" "$CLAW_PROOF"

CLAW_SESSION=""
for _ in $(seq 1 40); do
  CLAW_SESSION="$(child_session_file_from_main "$MAIN_SESSION" "claw-code" "$CLAW_PROOF")"
  if [[ -n "$CLAW_SESSION" && -f "$CLAW_SESSION" ]]; then
    break
  fi
  sleep 1
done

if [[ -z "$CLAW_SESSION" || ! -f "$CLAW_SESSION" ]]; then
  echo "could not find claw-code subagent session for $CLAW_PROOF" >&2
  exit 1
fi

wait_for_file_contents "$CLAW_PROOF" "ROUTE_CLAW_OK"

assert_session_pattern "$CLAW_SESSION" '"provider":"openai-codex"'
assert_session_pattern "$CLAW_SESSION" '"model":"gpt-5.3-codex-spark"'
assert_session_pattern "$CLAW_SESSION" '"name":"exec"'
assert_session_pattern "$CLAW_SESSION" 'claw-code-local status'
assert_session_pattern "$CLAW_SESSION" "$CLAW_PROOF"

echo "== local main routing smoke passed =="
