#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
STATE_DIR="${OPENCLAW_STATE_DIR:-$HOME/.openclaw}"
CONFIG_PATH="${OPENCLAW_CONFIG_PATH:-$STATE_DIR/openclaw.json}"
GATEWAY_LOG="$STATE_DIR/logs/gateway.log"
NODE22_BIN="${OPENCLAW_SELFTEST_NODE_BIN:-$HOME/.node22/current/bin}"
SELFTEST_ROOT="$(mktemp -d "$REPO_ROOT/.local-agent-selftest.XXXXXX")"
EXEC_JSON="$SELFTEST_ROOT/exec.json"
READ_JSON="$SELFTEST_ROOT/read.json"
PATCH_JSON="$SELFTEST_ROOT/patch.json"
GITHUB_JSON="$SELFTEST_ROOT/github.json"
CLAW_JSON="$SELFTEST_ROOT/claw-code.json"
WA_JSON="$SELFTEST_ROOT/whatsapp.json"
MAIN_JSON="$SELFTEST_ROOT/main.json"
READ_PROOF="$SELFTEST_ROOT/read-proof.txt"
PATCH_TARGET="$SELFTEST_ROOT/patch-target.txt"
MAIN_STRUCTURED_PROOF="$SELFTEST_ROOT/main-structured-proof.json"

cleanup() {
  rm -rf "$SELFTEST_ROOT"
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

run_json_meta_assert() {
  local json_path="$1"
  local expected_provider="$2"
  local expected_model="$3"
  python3 - <<'PY' "$json_path" "$expected_provider" "$expected_model"
import json, sys
path, expected_provider, expected_model = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path, "r", encoding="utf-8") as handle:
    raw = handle.read()
start = raw.find("{")
if start < 0:
    raise SystemExit(f"{path}: missing JSON payload")
payload = json.loads(raw[start:])
meta = payload["result"]["meta"]["agentMeta"]
provider = meta["provider"]
model = meta["model"]
if provider != expected_provider or model != expected_model:
    raise SystemExit(
        f"{path}: unexpected agent meta provider/model {(provider, model)!r} != {(expected_provider, expected_model)!r}"
    )
print(f"{provider}/{model}")
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

assert_tool_call() {
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

# Wir prüfen exec-Ergebnisse direkt im Session-Log, weil Tool-Outputs gelegentlich vom Modell leicht paraphrasiert werden.
assert_exec_result() {
  local agent_id="$1"
  local command_substring="$2"
  local expected_output="$3"
  local session_file
  session_file="$(latest_session_jsonl "$agent_id")"
  if [[ -z "$session_file" || ! -f "$session_file" ]]; then
    echo "missing session log for $agent_id" >&2
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

echo "== bootstrap local coding agents =="
node "$REPO_ROOT/scripts/dev/bootstrap-local-coding-agents.mjs" >/dev/null

echo "== gateway health =="
openclaw gateway health

echo "== claw-code wrapper proof =="
CLAW_NORMALIZE_CMD="claw-code-local --version | sed -n '/Version/p' | tr -s ' ' | sed 's/^ //'"
CLAW_EXPECTED="$(eval "$CLAW_NORMALIZE_CMD")"
openclaw agent --agent claw-code --message "Nutze exec, führe \"$CLAW_NORMALIZE_CMD\" aus und antworte exakt mit der ausgegebenen Zeile." --json >"$CLAW_JSON"
assert_tool_call "claw-code" '"name":"exec"'
assert_exec_result "claw-code" "claw-code-local --version" "$CLAW_EXPECTED" >/dev/null

echo "== exec proof =="
EXEC_EXPECTED="EXEC_OK:$(cd "$REPO_ROOT" && pwd)"
openclaw agent --agent oc-builder --message "Nutze exec, führe 'pwd' aus und antworte exakt mit $EXEC_EXPECTED." --json >"$EXEC_JSON"
run_json_assert "$EXEC_JSON" "$EXEC_EXPECTED" >/dev/null
assert_tool_call "oc-builder" '"name":"exec"'

echo "== read proof =="
READ_EXPECTED="READ_OK_$(date +%s)"
printf '%s\n' "$READ_EXPECTED" >"$READ_PROOF"
openclaw agent --agent oc-builder --message "Nutze read, lies $READ_PROOF und antworte exakt mit dem Inhalt." --json >"$READ_JSON"
run_json_assert "$READ_JSON" "$READ_EXPECTED" >/dev/null
assert_tool_call "oc-builder" '"name":"read"'

echo "== main exact-read proof =="
MAIN_DEFAULT="heretic-local/qwen3-4b-instruct-2507"
MAIN_FALLBACK="openai-codex/gpt-5.3-codex-spark"
cat >"$MAIN_STRUCTURED_PROOF" <<EOF
{"default":"$MAIN_DEFAULT","fallback":"$MAIN_FALLBACK"}
EOF
MAIN_EXPECTED="DEFAULT=$MAIN_DEFAULT;FALLBACK=$MAIN_FALLBACK"
openclaw agent --agent main --message "Nutze read, lies $MAIN_STRUCTURED_PROOF als JSON und antworte exakt mit $MAIN_EXPECTED." --json >"$MAIN_JSON"
run_json_assert "$MAIN_JSON" "$MAIN_EXPECTED" >/dev/null
run_json_meta_assert "$MAIN_JSON" "openai-codex" "gpt-5.3-codex-spark" >/dev/null
assert_tool_call "main" "\"name\":\"read\""
assert_tool_call "main" "$MAIN_STRUCTURED_PROOF"

echo "== patch proof =="
PATCH_EXPECTED="PATCH_OK_$(date +%s)"
printf 'before\n' >"$PATCH_TARGET"
openclaw agent --agent oc-builder --message "Nutze apply_patch oder edit, ändere $PATCH_TARGET so dass die Datei exakt '$PATCH_EXPECTED' enthält. Antworte exakt mit PATCH_DONE." --json >"$PATCH_JSON"
run_json_assert "$PATCH_JSON" "PATCH_DONE" >/dev/null
ACTUAL_PATCH="$(tr -d '\r' <"$PATCH_TARGET" | tr -d '\n')"
if [[ "$ACTUAL_PATCH" != "$PATCH_EXPECTED" ]]; then
  echo "patch proof failed: $ACTUAL_PATCH != $PATCH_EXPECTED" >&2
  exit 1
fi
assert_tool_call "oc-builder" '"name":"apply_patch"|"name":"edit"|"name":"write"'

echo "== github proof =="
GITHUB_EXPECTED="GITHUB_OK:yankhy-source/claw-code-parity"
GITHUB_CMD="gh repo view yankhy-source/claw-code-parity --json nameWithOwner --jq '\"GITHUB_OK:\" + .nameWithOwner'"
openclaw agent --agent oc-github --message "Nutze exec und führe \"$GITHUB_CMD\" aus. Antworte exakt mit $GITHUB_EXPECTED." --json >"$GITHUB_JSON"
assert_tool_call "oc-github" '"name":"exec"'
assert_exec_result "oc-github" "gh repo view yankhy-source/claw-code-parity" "$GITHUB_EXPECTED" >/dev/null

echo "== whatsapp reply proof =="
SELF_E164="${OPENCLAW_SELFTEST_WHATSAPP_TO:-$(openclaw channels status --json | python3 -c 'import json, sys; raw=sys.stdin.read(); start=raw.find("{"); assert start >= 0, raw; print(json.loads(raw[start:])["channels"]["whatsapp"]["self"]["e164"])')}"
WA_EXPECTED="WA_SELFTEST_$(date +%s)"
if [[ ! -f "$GATEWAY_LOG" ]]; then
  echo "missing gateway log at $GATEWAY_LOG" >&2
  exit 1
fi
WA_LOG_MARKER="$(wc -c <"$GATEWAY_LOG")"
openclaw agent --agent main --channel whatsapp --to "$SELF_E164" --deliver --message "Antworte exakt: $WA_EXPECTED" --json >"$WA_JSON"
run_json_assert "$WA_JSON" "$WA_EXPECTED" >/dev/null
python3 - <<'PY' "$GATEWAY_LOG" "$WA_LOG_MARKER" "$WA_EXPECTED"
import sys
log_path = sys.argv[1]
offset = int(sys.argv[2])
expected = sys.argv[3]
with open(log_path, "rb") as handle:
    handle.seek(offset)
    tail = handle.read().decode("utf-8", errors="replace")
if expected not in tail or "Sent message" not in tail:
    raise SystemExit(f"whatsapp delivery proof missing token or sent marker for {expected!r}")
print(expected)
PY

echo "== all local coding agent selftests passed =="
