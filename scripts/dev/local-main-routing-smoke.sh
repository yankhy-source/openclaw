#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
STATE_DIR="${OPENCLAW_STATE_DIR:-$HOME/.openclaw}"
NODE22_BIN="${OPENCLAW_SELFTEST_NODE_BIN:-$HOME/.node22/current/bin}"
SMOKE_ROOT="$(mktemp -d "$REPO_ROOT/.local-main-routing-smoke.XXXXXX")"
GITHUB_JSON="$SMOKE_ROOT/main-github.json"
CLAW_JSON="$SMOKE_ROOT/main-claw.json"
GITHUB_PROOF="$(mktemp /tmp/main-route-github.XXXXXX.txt)"
CLAW_PROOF="$(mktemp /tmp/main-route-claw.XXXXXX.txt)"

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

find_agent_session_for_proof() {
  local agent_id="$1"
  local proof_file="$2"
  python3 - <<'PY' "$STATE_DIR" "$agent_id" "$proof_file"
import pathlib, sys
state_dir, agent_id, proof_file = sys.argv[1], sys.argv[2], sys.argv[3]
session_dir = pathlib.Path(state_dir) / "agents" / agent_id / "sessions"
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

echo "== main -> oc-github routing smoke =="
openclaw agent --agent main --message "Nutze sessions_spawn und starte einen oc-github-Subagenten. Child-Task: führe per exec 'gh repo view yankhy-source/claw-code-parity --json nameWithOwner --jq .nameWithOwner' aus und überschreibe danach per exec exakt die bereits existierende Datei $GITHUB_PROOF mit ROUTE_GITHUB_OK:yankhy-source/claw-code-parity. Verwende genau diesen Pfad, keine neue Temp-Datei. Antworte exakt mit MAIN_ROUTE_GITHUB_OK, sobald der Child-Run akzeptiert wurde." --json >"$GITHUB_JSON"
run_json_assert "$GITHUB_JSON" "MAIN_ROUTE_GITHUB_OK" >/dev/null

MAIN_SESSION="$(latest_session_jsonl "main")"
assert_session_pattern "$MAIN_SESSION" '"name":"sessions_spawn"'
assert_session_pattern "$MAIN_SESSION" "$GITHUB_PROOF"

GITHUB_SESSION=""
for _ in $(seq 1 40); do
  GITHUB_SESSION="$(find_agent_session_for_proof "oc-github" "$GITHUB_PROOF")"
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
  CLAW_SESSION="$(find_agent_session_for_proof "claw-code" "$CLAW_PROOF")"
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
