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
WA_JSON="$SELFTEST_ROOT/whatsapp.json"
MAIN_JSON="$SELFTEST_ROOT/main.json"
TOOL_PROVIDER_PREFLIGHT_JSON="$SELFTEST_ROOT/tool-provider-preflight.json"
EXEC_PROOF="$SELFTEST_ROOT/exec-proof.txt"
READ_PROOF="$SELFTEST_ROOT/read-proof.txt"
READ_RESULT="$SELFTEST_ROOT/read-result.txt"
PATCH_TARGET="$SELFTEST_ROOT/patch-target.txt"
MAIN_STRUCTURED_PROOF="$SELFTEST_ROOT/main-structured-proof.json"
MAIN_WORKSPACE_PROOF=""
SKIP_WHATSAPP="${OPENCLAW_SELFTEST_SKIP_WHATSAPP:-0}"
SELFTEST_MANAGER_ID="${OPENCLAW_SELFTEST_MANAGER_ID:-oc-selftest}"
SELFTEST_MANAGER_SESSION_ID="${OPENCLAW_SELFTEST_MANAGER_SESSION_ID:-local-selftest-$(date +%s)-$RANDOM}"
SUBAGENT_WAIT_ATTEMPTS="${OPENCLAW_SELFTEST_SUBAGENT_WAIT_ATTEMPTS:-180}"
SUBAGENT_WAIT_DELAY="${OPENCLAW_SELFTEST_SUBAGENT_WAIT_DELAY:-1}"
SELFTEST_MODE="live"
SELFTEST_STARTED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
SELFTEST_CURRENT_STEP="init"
SELFTEST_FAILED_STEP=""
SELFTEST_FAILED_COMMAND=""
SELFTEST_WHATSAPP_TOKEN=""
SELFTEST_EXIT_CODE=0
declare -a SELFTEST_COMPLETED_STEPS=()

if [[ "$SKIP_WHATSAPP" == "1" ]]; then
  SELFTEST_MODE="core"
fi

cleanup() {
  if [[ -n "$MAIN_WORKSPACE_PROOF" && -f "$MAIN_WORKSPACE_PROOF" ]]; then
    rm -f "$MAIN_WORKSPACE_PROOF"
  fi
  if [[ "$SELFTEST_EXIT_CODE" -eq 0 && "$SELFTEST_CURRENT_STEP" == "done" ]]; then
    rm -rf "$SELFTEST_ROOT"
  else
    echo "preserving selftest artifacts: $SELFTEST_ROOT" >&2
  fi
}

mark_step_completed() {
  SELFTEST_COMPLETED_STEPS+=("$1")
}

write_selftest_summary() {
  local exit_code="$1"
  local status="failed"
  if [[ "$exit_code" -eq 0 && "$SELFTEST_CURRENT_STEP" == "done" ]]; then
    status="passed"
  elif [[ "$exit_code" -eq 2 ]]; then
    status="blocked"
  fi
  python3 - <<'PY' \
    "$SELFTEST_SUMMARY_PATH" \
    "$SELFTEST_MODE" \
    "$status" \
    "$SELFTEST_STARTED_AT" \
    "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    "$REPO_ROOT" \
    "$SELFTEST_ROOT" \
    "$SELFTEST_MANAGER_SESSION_ID" \
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
artifact_root = sys.argv[7]
manager_session_id = sys.argv[8]
current_step = sys.argv[9]
failed_step = sys.argv[10] or None
failed_command = sys.argv[11] or None
whatsapp_token = sys.argv[12] or None
steps = sys.argv[13:]

summary = {
    "summaryVersion": 1,
    "mode": mode,
    "status": status,
    "startedAt": started_at,
    "finishedAt": finished_at,
    "repoRoot": repo_root,
    "summaryPath": str(summary_path),
    "artifactRoot": artifact_root,
    "managerSessionId": manager_session_id,
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
  SELFTEST_EXIT_CODE="$exit_code"
  if [[ "$exit_code" -ne 0 && -z "$SELFTEST_FAILED_STEP" ]]; then
    SELFTEST_FAILED_STEP="$SELFTEST_CURRENT_STEP"
  fi
  if [[ "$exit_code" -ne 0 && -z "$SELFTEST_FAILED_COMMAND" ]]; then
    SELFTEST_FAILED_COMMAND="selftest exited with code $exit_code during $SELFTEST_CURRENT_STEP"
  fi
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
decoder = json.JSONDecoder()
payload = None
for index, char in enumerate(raw):
    if char != "{":
        continue
    try:
        candidate, _ = decoder.raw_decode(raw[index:])
    except json.JSONDecodeError:
        continue
    if isinstance(candidate, dict) and "result" in candidate:
        payload = candidate
if payload is None:
    raise SystemExit(f"{path}: missing JSON payload")
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

assert_exec_result() {
  local agent_id="$1"
  local command_substring="$2"
  local expected_output="$3"
  local session_file
  session_file="$(latest_session_jsonl "$agent_id")"
  assert_session_exec_result "$session_file" "$command_substring" "$expected_output"
}

assert_read_result() {
  local agent_id="$1"
  local path_substring="$2"
  local expected_output="$3"
  local session_file
  session_file="$(latest_session_jsonl "$agent_id")"
  assert_session_read_result "$session_file" "$path_substring" "$expected_output"
}

workspace_relative_path() {
  local target_path="$1"
  python3 - <<'PY' "$REPO_ROOT" "$target_path"
import pathlib, sys

repo_root = pathlib.Path(sys.argv[1]).resolve()
target_path = pathlib.Path(sys.argv[2]).resolve()
try:
    relative = target_path.relative_to(repo_root)
except ValueError as exc:
    raise SystemExit(f"path is outside repo root: {target_path} ({exc})")
print(relative.as_posix())
PY
}

archive_selftest_manager_sessions() {
  local session_dir="$STATE_DIR/agents/$SELFTEST_MANAGER_ID/sessions"
  local archive_dir="$STATE_DIR/agents/$SELFTEST_MANAGER_ID/session-archives/$SELFTEST_MANAGER_SESSION_ID"
  if [[ ! -d "$session_dir" ]]; then
    mkdir -p "$session_dir"
    return 0
  fi

  shopt -s nullglob
  local files=("$session_dir"/*)
  shopt -u nullglob
  if ((${#files[@]} == 0)); then
    return 0
  fi

  mkdir -p "$archive_dir"
  mv "${files[@]}" "$archive_dir"/
  mkdir -p "$session_dir"
}

spawn_specialist_child_session() {
  local json_path="$1"
  local agent_id="$2"
  local accept_token="$3"
  local target_path="$4"
  local child_task="$5"
  local main_session
  local main_before_lines

  main_session="$(session_jsonl_for_id "$SELFTEST_MANAGER_ID" "$SELFTEST_MANAGER_SESSION_ID")"
  if [[ -z "$main_session" || ! -f "$main_session" ]]; then
    main_session="$(agent_main_session_jsonl "$SELFTEST_MANAGER_ID")"
  fi
  if [[ -z "$main_session" || ! -f "$main_session" ]]; then
    main_before_lines=0
  else
    main_before_lines="$(session_line_count "$main_session")"
  fi

  run_openclaw_agent_json "$json_path" --agent "$SELFTEST_MANAGER_ID" --session-id "$SELFTEST_MANAGER_SESSION_ID" --message "Harter Selftest: Der Tool-Katalog enthält sessions_spawn. Nutze zwingend einen echten sessions_spawn-Toolcall und starte einen ${agent_id}-Subagenten. Führe den Child-Task nicht selbst aus. Behaupte nicht, sessions_spawn sei nicht verfügbar. Child-Task: ${child_task} Antworte exakt mit ${accept_token}, aber erst nachdem der sessions_spawn-Toolresult status=accepted geliefert hat." || exit $?
  if [[ -z "$main_session" || ! -f "$main_session" ]]; then
    main_session="$(session_jsonl_for_id "$SELFTEST_MANAGER_ID" "$SELFTEST_MANAGER_SESSION_ID")"
    if [[ -z "$main_session" || ! -f "$main_session" ]]; then
      main_session="$(wait_for_agent_main_session_jsonl "$SELFTEST_MANAGER_ID" "$SUBAGENT_WAIT_ATTEMPTS" "$SUBAGENT_WAIT_DELAY")" || exit $?
    fi
  fi
  if ! run_json_assert "$json_path" "$accept_token" >/dev/null; then
    if agent_json_indicates_missing_tool "$json_path" "sessions_spawn"; then
      local provider
      local model
      provider="$(agent_json_meta_field "$json_path" provider || true)"
      model="$(agent_json_meta_field "$json_path" model || true)"
      echo "sessions_spawn proof blocked: ${provider:-unknown}/${model:-unknown} did not expose the sessions_spawn runtime tool" >&2
      SELFTEST_FAILED_STEP="$SELFTEST_CURRENT_STEP"
      SELFTEST_FAILED_COMMAND="sessions_spawn unavailable in ${provider:-unknown}/${model:-unknown}"
      exit 2
    fi
    exit 1
  fi
  assert_agent_json_not_heretic_fallback "$json_path" "sessions_spawn proof for $agent_id" || exit $?
  wait_for_session_pattern_after_line "$main_session" "$main_before_lines" '"name":"sessions_spawn"|"toolName":"sessions_spawn"' "$SUBAGENT_WAIT_ATTEMPTS" "$SUBAGENT_WAIT_DELAY" || exit $?
  wait_for_session_pattern_after_line "$main_session" "$main_before_lines" "$target_path" "$SUBAGENT_WAIT_ATTEMPTS" "$SUBAGENT_WAIT_DELAY" || exit $?
  wait_for_child_session_from_main_after_line "$main_session" "$main_before_lines" "$agent_id" "$target_path" "$SUBAGENT_WAIT_ATTEMPTS" "$SUBAGENT_WAIT_DELAY" || exit $?
}

echo "== bootstrap local coding agents =="
SELFTEST_CURRENT_STEP="bootstrap"
node "$REPO_ROOT/scripts/dev/bootstrap-local-coding-agents.mjs" >/dev/null
mark_step_completed "bootstrap"

echo "== gateway health =="
SELFTEST_CURRENT_STEP="gateway_health"
openclaw_ensure_gateway_healthy
mark_step_completed "gateway_health"

echo "== tool provider preflight =="
SELFTEST_CURRENT_STEP="tool_provider_preflight"
if OPENCLAW_TOOL_PROVIDER_PREFLIGHT_PROVIDERS="${OPENCLAW_SESSIONS_PROVIDER_PREFLIGHT_PROVIDERS:-openai-codex}" \
  openclaw_tool_provider_preflight "$TOOL_PROVIDER_PREFLIGHT_JSON" "$SELFTEST_MANAGER_ID"; then
  :
else
  preflight_status=$?
  SELFTEST_FAILED_STEP="$SELFTEST_CURRENT_STEP"
  SELFTEST_FAILED_COMMAND="sessions provider preflight did not find an available openai-codex tool runtime"
  exit "$preflight_status"
fi
mark_step_completed "tool_provider_preflight"

echo "== isolate selftest manager session =="
SELFTEST_CURRENT_STEP="manager_session_isolation"
archive_selftest_manager_sessions
mark_step_completed "manager_session_isolation"

echo "== exec proof =="
SELFTEST_CURRENT_STEP="exec_proof"
EXEC_EXPECTED="EXEC_OK:$(cd "$REPO_ROOT" && pwd)"
printf 'before\n' >"$EXEC_PROOF"
EXEC_PROOF_REL="$(workspace_relative_path "$EXEC_PROOF")"
BUILDER_EXEC_SESSION="$(spawn_specialist_child_session "$EXEC_JSON" "oc-builder" "EXEC_SPAWN_OK" "$EXEC_PROOF_REL" "führe per exec den Befehl 'pwd' aus und überschreibe danach per exec exakt die bereits existierende Datei $EXEC_PROOF_REL mit $EXEC_EXPECTED. Verwende genau diesen relativen Workspace-Pfad, keine neue Temp-Datei.")"
wait_for_file_contents "$EXEC_PROOF" "$EXEC_EXPECTED" "$SUBAGENT_WAIT_ATTEMPTS" "$SUBAGENT_WAIT_DELAY"
assert_session_pattern "$BUILDER_EXEC_SESSION" '"name":"exec"'
assert_session_exec_result "$BUILDER_EXEC_SESSION" "pwd" "$(cd "$REPO_ROOT" && pwd)" >/dev/null
mark_step_completed "exec_proof"

echo "== read proof =="
SELFTEST_CURRENT_STEP="read_proof"
READ_EXPECTED="READ_OK_$(python3 - <<'PY'
import uuid
print(uuid.uuid4().hex)
PY
)"
printf '%s\n' "$READ_EXPECTED" >"$READ_PROOF"
printf 'before\n' >"$READ_RESULT"
READ_PROOF_REL="$(workspace_relative_path "$READ_PROOF")"
READ_RESULT_REL="$(workspace_relative_path "$READ_RESULT")"
BUILDER_READ_SESSION="$(spawn_specialist_child_session "$READ_JSON" "oc-builder" "READ_SPAWN_OK" "$READ_RESULT_REL" "nutze zwingend read, lies exakt $READ_PROOF_REL und überschreibe danach per exec exakt die bereits existierende Datei $READ_RESULT_REL mit dem gelesenen Inhalt. Verwende genau diese relativen Workspace-Pfade, keine neue Temp-Datei. Ohne echten read-Toolcall darfst du den Auftrag nicht abschließen.")"
wait_for_file_contents "$READ_RESULT" "$READ_EXPECTED" "$SUBAGENT_WAIT_ATTEMPTS" "$SUBAGENT_WAIT_DELAY"
assert_session_pattern "$BUILDER_READ_SESSION" '"name":"read"'
assert_session_read_result "$BUILDER_READ_SESSION" "$READ_PROOF_REL" "$READ_EXPECTED" >/dev/null
mark_step_completed "read_proof"

echo "== main exact-read proof =="
SELFTEST_CURRENT_STEP="main_exact_read"
MAIN_DEFAULT="openai-codex/gpt-5.3-codex-spark"
MAIN_FALLBACK="qwen-portal/coder-model"
MAIN_SESSION="$(main_session_jsonl)"
if [[ -z "$MAIN_SESSION" || ! -f "$MAIN_SESSION" ]]; then
  echo "could not resolve main session file" >&2
  exit 1
fi
MAIN_BEFORE_LINES="$(session_line_count "$MAIN_SESSION")"
cat >"$MAIN_STRUCTURED_PROOF" <<EOF
{"default":"$MAIN_DEFAULT","fallback":"$MAIN_FALLBACK"}
EOF
MAIN_WORKSPACE_PROOF="$(workspace_mirror_file "$MAIN_STRUCTURED_PROOF" "main-structured-proof" "main-structured-proof.json")"
MAIN_EXPECTED="DEFAULT=$MAIN_DEFAULT;FALLBACK=$MAIN_FALLBACK"
run_openclaw_agent_json "$MAIN_JSON" --agent main --message "Nutze read, lies $MAIN_WORKSPACE_PROOF als JSON und antworte exakt mit $MAIN_EXPECTED. Gib nur diese eine Zeile aus. Kein weiterer Text. Ohne echten read-Toolcall darfst du den Auftrag nicht abschließen."
run_json_assert "$MAIN_JSON" "$MAIN_EXPECTED" >/dev/null
run_json_meta_assert "$MAIN_JSON" "openai-codex" "gpt-5.3-codex-spark" >/dev/null
wait_for_session_pattern_after_line "$MAIN_SESSION" "$MAIN_BEFORE_LINES" '"name":"read"|"toolName":"read"' "$SUBAGENT_WAIT_ATTEMPTS" "$SUBAGENT_WAIT_DELAY"
wait_for_session_pattern_after_line "$MAIN_SESSION" "$MAIN_BEFORE_LINES" "$MAIN_WORKSPACE_PROOF" "$SUBAGENT_WAIT_ATTEMPTS" "$SUBAGENT_WAIT_DELAY"
mark_step_completed "main_exact_read"

echo "== patch proof =="
SELFTEST_CURRENT_STEP="patch_proof"
PATCH_EXPECTED="PATCH_OK_$(date +%s)"
printf 'before\n' >"$PATCH_TARGET"
PATCH_TARGET_REL="$(workspace_relative_path "$PATCH_TARGET")"
BUILDER_PATCH_SESSION="$(spawn_specialist_child_session "$PATCH_JSON" "oc-builder" "PATCH_SPAWN_OK" "$PATCH_TARGET_REL" "ändere per apply_patch, edit oder write exakt die bereits existierende Datei $PATCH_TARGET_REL so, dass sie nur noch die Zeile $PATCH_EXPECTED enthält. Verwende genau diesen relativen Workspace-Pfad.")"
wait_for_file_contents "$PATCH_TARGET" "$PATCH_EXPECTED" "$SUBAGENT_WAIT_ATTEMPTS" "$SUBAGENT_WAIT_DELAY"
assert_session_pattern "$BUILDER_PATCH_SESSION" '"name":"apply_patch"|"name":"edit"|"name":"write"'
mark_step_completed "patch_proof"

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
SELF_E164="${OPENCLAW_SELFTEST_WHATSAPP_TO:-$(openclaw_whatsapp_self_e164)}"
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
