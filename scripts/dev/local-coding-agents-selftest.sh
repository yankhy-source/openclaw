#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
STATE_DIR="${OPENCLAW_STATE_DIR:-$HOME/.openclaw}"
CONFIG_PATH="${OPENCLAW_CONFIG_PATH:-$STATE_DIR/openclaw.json}"
GATEWAY_LOG="$STATE_DIR/logs/gateway.log"
NODE22_BIN="${OPENCLAW_SELFTEST_NODE_BIN:-$HOME/.node22/current/bin}"
SELFTEST_SUMMARY_PATH="${OPENCLAW_SELFTEST_SUMMARY_PATH:-$REPO_ROOT/.local-agent-last-selftest.json}"
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
SKIP_WHATSAPP="${OPENCLAW_SELFTEST_SKIP_WHATSAPP:-0}"
SELFTEST_MODE="live"
SELFTEST_STARTED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
SELFTEST_CURRENT_STEP="init"
SELFTEST_FAILED_STEP=""
SELFTEST_FAILED_COMMAND=""
SELFTEST_WHATSAPP_TOKEN=""
declare -a SELFTEST_COMPLETED_STEPS=()

if [[ "$SKIP_WHATSAPP" == "1" ]]; then
  SELFTEST_MODE="core"
fi

cleanup() {
  rm -rf "$SELFTEST_ROOT"
}

mark_step_completed() {
  SELFTEST_COMPLETED_STEPS+=("$1")
}

write_selftest_summary() {
  local exit_code="$1"
  local status="failed"
  if [[ "$exit_code" -eq 0 ]]; then
    status="passed"
  fi
  python3 - <<'PY' \
    "$SELFTEST_SUMMARY_PATH" \
    "$SELFTEST_MODE" \
    "$status" \
    "$SELFTEST_STARTED_AT" \
    "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    "$REPO_ROOT" \
    "$SELFTEST_CURRENT_STEP" \
    "$SELFTEST_FAILED_STEP" \
    "$SELFTEST_FAILED_COMMAND" \
    "$SELFTEST_WHATSAPP_TOKEN" \
    "${SELFTEST_COMPLETED_STEPS[@]}"
import json, os, pathlib, sys

summary_path = pathlib.Path(sys.argv[1])
mode = sys.argv[2]
status = sys.argv[3]
started_at = sys.argv[4]
finished_at = sys.argv[5]
repo_root = sys.argv[6]
current_step = sys.argv[7]
failed_step = sys.argv[8] or None
failed_command = sys.argv[9] or None
whatsapp_token = sys.argv[10] or None
steps = sys.argv[11:]

summary = {
    "summaryVersion": 1,
    "mode": mode,
    "status": status,
    "startedAt": started_at,
    "finishedAt": finished_at,
    "repoRoot": repo_root,
    "summaryPath": str(summary_path),
    "currentStep": current_step,
    "failedStep": failed_step,
    "failedCommand": failed_command,
    "whatsappToken": whatsapp_token,
    "stepsCompleted": steps,
}

summary_path.parent.mkdir(parents=True, exist_ok=True)
summary_path.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
PY
}

on_error() {
  SELFTEST_FAILED_STEP="${SELFTEST_CURRENT_STEP}"
  SELFTEST_FAILED_COMMAND="${BASH_COMMAND}"
}

on_exit() {
  local exit_code="$1"
  trap - EXIT ERR
  set +e
  write_selftest_summary "$exit_code"
  cleanup
  exit "$exit_code"
}

trap on_error ERR
trap 'on_exit $?' EXIT

if [[ -d "$NODE22_BIN" ]]; then
  PATH="$NODE22_BIN:$PATH"
  export PATH
fi

PATH="$REPO_ROOT/scripts/dev:$REPO_ROOT/../claw-code-parity/scripts:$PATH"
export PATH

source "$SCRIPT_DIR/lib/openclaw-smoke-common.sh"

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

assert_tool_call() {
  local agent_id="$1"
  local pattern="$2"
  assert_latest_session_pattern "$agent_id" "$pattern"
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
SELFTEST_CURRENT_STEP="bootstrap"
node "$REPO_ROOT/scripts/dev/bootstrap-local-coding-agents.mjs" >/dev/null
mark_step_completed "bootstrap"

echo "== gateway health =="
SELFTEST_CURRENT_STEP="gateway_health"
openclaw gateway health
mark_step_completed "gateway_health"

echo "== claw-code wrapper proof =="
SELFTEST_CURRENT_STEP="claw_code_wrapper"
CLAW_NORMALIZE_CMD="claw-code-local --version | sed -n '/Version/p' | tr -s ' ' | sed 's/^ //'"
CLAW_EXPECTED="$(eval "$CLAW_NORMALIZE_CMD")"
run_openclaw_agent_json "$CLAW_JSON" --agent claw-code --message "Nutze exec, führe \"$CLAW_NORMALIZE_CMD\" aus und antworte exakt mit der ausgegebenen Zeile."
assert_tool_call "claw-code" '"name":"exec"'
assert_exec_result "claw-code" "claw-code-local --version" "$CLAW_EXPECTED" >/dev/null
mark_step_completed "claw_code_wrapper"

echo "== exec proof =="
SELFTEST_CURRENT_STEP="exec_proof"
EXEC_EXPECTED="EXEC_OK:$(cd "$REPO_ROOT" && pwd)"
run_openclaw_agent_json "$EXEC_JSON" --agent oc-builder --message "Nutze exec, führe 'pwd' aus und antworte exakt mit $EXEC_EXPECTED."
run_json_assert "$EXEC_JSON" "$EXEC_EXPECTED" >/dev/null
assert_tool_call "oc-builder" '"name":"exec"'
mark_step_completed "exec_proof"

echo "== read proof =="
SELFTEST_CURRENT_STEP="read_proof"
READ_EXPECTED="READ_OK_$(date +%s)"
printf '%s\n' "$READ_EXPECTED" >"$READ_PROOF"
run_openclaw_agent_json "$READ_JSON" --agent oc-builder --message "Nutze read, lies $READ_PROOF und antworte exakt mit dem Inhalt."
run_json_assert "$READ_JSON" "$READ_EXPECTED" >/dev/null
assert_tool_call "oc-builder" '"name":"read"'
mark_step_completed "read_proof"

echo "== main exact-read proof =="
SELFTEST_CURRENT_STEP="main_exact_read"
MAIN_DEFAULT="heretic-local/qwen3-4b-instruct-2507"
MAIN_FALLBACK="openai-codex/gpt-5.3-codex-spark"
cat >"$MAIN_STRUCTURED_PROOF" <<EOF
{"default":"$MAIN_DEFAULT","fallback":"$MAIN_FALLBACK"}
EOF
MAIN_EXPECTED="DEFAULT=$MAIN_DEFAULT;FALLBACK=$MAIN_FALLBACK"
run_openclaw_agent_json "$MAIN_JSON" --agent main --message "Nutze read, lies $MAIN_STRUCTURED_PROOF als JSON und antworte exakt mit $MAIN_EXPECTED."
run_json_assert "$MAIN_JSON" "$MAIN_EXPECTED" >/dev/null
run_json_meta_assert "$MAIN_JSON" "openai-codex" "gpt-5.3-codex-spark" >/dev/null
assert_tool_call "main" "\"name\":\"read\""
assert_tool_call "main" "$MAIN_STRUCTURED_PROOF"
mark_step_completed "main_exact_read"

echo "== patch proof =="
SELFTEST_CURRENT_STEP="patch_proof"
PATCH_EXPECTED="PATCH_OK_$(date +%s)"
printf 'before\n' >"$PATCH_TARGET"
run_openclaw_agent_json "$PATCH_JSON" --agent oc-builder --message "Nutze apply_patch oder edit, ändere $PATCH_TARGET so dass die Datei exakt '$PATCH_EXPECTED' enthält. Antworte exakt mit PATCH_DONE."
run_json_assert "$PATCH_JSON" "PATCH_DONE" >/dev/null
ACTUAL_PATCH="$(tr -d '\r' <"$PATCH_TARGET" | tr -d '\n')"
if [[ "$ACTUAL_PATCH" != "$PATCH_EXPECTED" ]]; then
  echo "patch proof failed: $ACTUAL_PATCH != $PATCH_EXPECTED" >&2
  exit 1
fi
assert_tool_call "oc-builder" '"name":"apply_patch"|"name":"edit"|"name":"write"'
mark_step_completed "patch_proof"

echo "== github proof =="
SELFTEST_CURRENT_STEP="github_proof"
GITHUB_EXPECTED="GITHUB_OK:yankhy-source/claw-code-parity"
GITHUB_CMD="gh repo view yankhy-source/claw-code-parity --json nameWithOwner --jq '\"GITHUB_OK:\" + .nameWithOwner'"
run_openclaw_agent_json "$GITHUB_JSON" --agent oc-github --message "Nutze exec und führe \"$GITHUB_CMD\" aus. Antworte exakt mit $GITHUB_EXPECTED."
assert_tool_call "oc-github" '"name":"exec"'
assert_exec_result "oc-github" "gh repo view yankhy-source/claw-code-parity" "$GITHUB_EXPECTED" >/dev/null
mark_step_completed "github_proof"

echo "== main orchestrator smoke =="
SELFTEST_CURRENT_STEP="main_orchestrator"
bash "$REPO_ROOT/scripts/dev/local-main-orchestrator-smoke.sh"
mark_step_completed "main_orchestrator"

echo "== main specialist routing smoke =="
SELFTEST_CURRENT_STEP="main_routing"
bash "$REPO_ROOT/scripts/dev/local-main-routing-smoke.sh"
mark_step_completed "main_routing"

echo "== main delegated task smoke =="
SELFTEST_CURRENT_STEP="main_delegated_task"
bash "$REPO_ROOT/scripts/dev/local-main-task-smoke.sh"
mark_step_completed "main_delegated_task"

if [[ "$SKIP_WHATSAPP" == "1" ]]; then
  SELFTEST_CURRENT_STEP="whatsapp_skipped"
  mark_step_completed "whatsapp_skipped"
  echo "== whatsapp reply proof skipped =="
  SELFTEST_CURRENT_STEP="done"
  echo "== local coding agent core selftests passed =="
  exit 0
fi

echo "== whatsapp reply proof =="
SELFTEST_CURRENT_STEP="whatsapp_reply"
SELF_E164="${OPENCLAW_SELFTEST_WHATSAPP_TO:-$(openclaw channels status --json | python3 -c 'import json, sys; raw=sys.stdin.read(); start=raw.find("{"); assert start >= 0, raw; print(json.loads(raw[start:])["channels"]["whatsapp"]["self"]["e164"])')}"
WA_EXPECTED="WA_SELFTEST_$(date +%s)"
if [[ ! -f "$GATEWAY_LOG" ]]; then
  echo "missing gateway log at $GATEWAY_LOG" >&2
  exit 1
fi
WA_LOG_MARKER="$(wc -c <"$GATEWAY_LOG")"
run_openclaw_agent_json "$WA_JSON" --agent main --channel whatsapp --to "$SELF_E164" --deliver --message "Antworte exakt: $WA_EXPECTED"
run_json_assert "$WA_JSON" "$WA_EXPECTED" >/dev/null
SELFTEST_WHATSAPP_TOKEN="$WA_EXPECTED"
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
mark_step_completed "whatsapp_reply"

SELFTEST_CURRENT_STEP="done"
echo "== all local coding agent selftests passed =="
