#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
STATE_DIR="${OPENCLAW_STATE_DIR:-$HOME/.openclaw}"
NODE22_BIN="${OPENCLAW_SELFTEST_NODE_BIN:-$HOME/.node22/current/bin}"
SMOKE_ROOT="$(mktemp -d "$REPO_ROOT/.local-main-orchestrator-smoke.XXXXXX")"
MAIN_JSON="$SMOKE_ROOT/main.json"
PROOF_FILE="$(mktemp /tmp/main-orchestrator-smoke.XXXXXX)"

cleanup() {
  rm -rf "$SMOKE_ROOT"
  rm -f "$PROOF_FILE"
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

find_builder_session_for_proof() {
  local proof_file="$1"
  python3 - <<'PY' "$STATE_DIR" "$proof_file"
import pathlib, sys
state_dir, proof_file = sys.argv[1], sys.argv[2]
session_dir = pathlib.Path(state_dir) / "agents" / "oc-builder" / "sessions"
matches = []
for path in session_dir.glob("*.jsonl"):
    try:
        text = path.read_text(encoding="utf-8")
    except Exception:
        continue
    if proof_file in text:
        matches.append(path)
matches.sort(key=lambda item: item.stat().st_mtime, reverse=True)
print(matches[0] if matches else "")
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

echo "== main orchestrator smoke =="
openclaw agent --agent main --message "Nutze sessions_spawn und starte einen oc-builder-Subagenten im aktuellen Repo. Child-Task: führe per exec den Befehl 'pwd' aus und überschreibe danach per exec exakt die bereits existierende Datei $PROOF_FILE mit MAIN_SUBAGENT_OK. Verwende genau diesen Pfad, keine neue Temp-Datei. Antworte exakt mit MAIN_SPAWN_OK, sobald der Child-Run akzeptiert wurde." --json >"$MAIN_JSON"
run_json_assert "$MAIN_JSON" "MAIN_SPAWN_OK" >/dev/null

MAIN_SESSION="$(latest_session_jsonl "main")"
assert_session_pattern "$MAIN_SESSION" '"name":"sessions_spawn"'
assert_session_pattern "$MAIN_SESSION" "$PROOF_FILE"

BUILDER_SESSION=""
for _ in $(seq 1 40); do
  BUILDER_SESSION="$(find_builder_session_for_proof "$PROOF_FILE")"
  if [[ -n "$BUILDER_SESSION" && -f "$BUILDER_SESSION" ]]; then
    break
  fi
  sleep 1
done

if [[ -z "$BUILDER_SESSION" || ! -f "$BUILDER_SESSION" ]]; then
  echo "could not find oc-builder subagent session for $PROOF_FILE" >&2
  exit 1
fi

wait_for_file_contents "$PROOF_FILE" "MAIN_SUBAGENT_OK"

assert_session_pattern "$BUILDER_SESSION" '"provider":"openai-codex"'
assert_session_pattern "$BUILDER_SESSION" '"model":"gpt-5.3-codex-spark"'
assert_session_pattern "$BUILDER_SESSION" '"name":"exec"'
assert_session_pattern "$BUILDER_SESSION" 'pwd'
assert_session_pattern "$BUILDER_SESSION" "$PROOF_FILE"

echo "== local main orchestrator smoke passed =="
