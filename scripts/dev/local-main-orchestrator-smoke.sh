#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
STATE_DIR="${OPENCLAW_STATE_DIR:-$HOME/.openclaw}"
NODE22_BIN="${OPENCLAW_SELFTEST_NODE_BIN:-$HOME/.node22/current/bin}"
SMOKE_ROOT="$(mktemp -d "$REPO_ROOT/.local-main-orchestrator-smoke.XXXXXX")"
MAIN_JSON="$SMOKE_ROOT/main.json"
PROOF_FILE="$SMOKE_ROOT/proof.txt"
SELFTEST_MANAGER_ID="${OPENCLAW_SELFTEST_MANAGER_ID:-oc-selftest}"
CHILD_AGENT_ID="${OPENCLAW_MAIN_ORCHESTRATOR_CHILD_AGENT_ID:-oc-builder}"
EXPECTED_CHILD_PROVIDER="${OPENCLAW_MAIN_ORCHESTRATOR_EXPECT_CHILD_PROVIDER:-openai-codex}"
EXPECTED_CHILD_MODEL="${OPENCLAW_MAIN_ORCHESTRATOR_EXPECT_CHILD_MODEL:-gpt-5.3-codex-spark}"
EXPECTED_PROOF_TEXT="${OPENCLAW_MAIN_ORCHESTRATOR_EXPECTED_PROOF_TEXT:-MAIN_SUBAGENT_OK}"
SUBAGENT_WAIT_ATTEMPTS="${OPENCLAW_SELFTEST_SUBAGENT_WAIT_ATTEMPTS:-180}"
SUBAGENT_WAIT_DELAY="${OPENCLAW_SELFTEST_SUBAGENT_WAIT_DELAY:-1}"
SMOKE_EXIT_CODE=0

cleanup() {
  if [[ "$SMOKE_EXIT_CODE" -eq 0 ]]; then
    rm -rf "$SMOKE_ROOT"
  else
    echo "preserving main orchestrator smoke artifacts: $SMOKE_ROOT" >&2
  fi
}

on_exit() {
  SMOKE_EXIT_CODE="$1"
  trap - EXIT
  cleanup
  exit "$SMOKE_EXIT_CODE"
}

trap 'on_exit $?' EXIT

if [[ -d "$NODE22_BIN" ]]; then
  PATH="$NODE22_BIN:$PATH"
  export PATH
fi

PATH="$REPO_ROOT/scripts/dev:$REPO_ROOT/../claw-code-parity/scripts:$PATH"
export PATH

source "$SCRIPT_DIR/lib/openclaw-smoke-common.sh"

echo "== bootstrap local coding agents =="
node "$REPO_ROOT/scripts/dev/bootstrap-local-coding-agents.mjs" >/dev/null

echo "== main orchestrator smoke =="
MAIN_SESSION="$(agent_main_session_jsonl "$SELFTEST_MANAGER_ID")"
if [[ -z "$MAIN_SESSION" || ! -f "$MAIN_SESSION" ]]; then
  MAIN_BEFORE_LINES=0
else
  MAIN_BEFORE_LINES="$(session_line_count "$MAIN_SESSION")"
fi

if run_openclaw_agent_json "$MAIN_JSON" --agent "$SELFTEST_MANAGER_ID" --message "Nutze sessions_spawn und starte einen ${CHILD_AGENT_ID}-Subagenten im aktuellen Repo. Child-Task: führe per exec den Befehl 'pwd' aus und überschreibe danach per exec exakt die bereits existierende Datei $PROOF_FILE mit ${EXPECTED_PROOF_TEXT}. Verwende genau diesen Pfad, keine neue Temp-Datei. Antworte exakt mit MAIN_SPAWN_OK, sobald der Child-Run akzeptiert wurde."; then
  :
else
  smoke_status=$?
  if [[ -f "$MAIN_JSON" ]] && rg -q 'OAuth token refresh failed for qwen-portal|Re-authenticate with `openclaw models auth login --provider qwen-portal`' "$MAIN_JSON"; then
    echo "main orchestrator smoke blocked: qwen-portal auth expired or invalid; re-authenticate with openclaw models auth login --provider qwen-portal" >&2
    exit 2
  fi
  exit "$smoke_status"
fi
if [[ -z "$MAIN_SESSION" || ! -f "$MAIN_SESSION" ]]; then
  MAIN_SESSION="$(wait_for_agent_main_session_jsonl "$SELFTEST_MANAGER_ID" "$SUBAGENT_WAIT_ATTEMPTS" "$SUBAGENT_WAIT_DELAY")"
fi
if ! run_json_assert "$MAIN_JSON" "MAIN_SPAWN_OK" >/dev/null; then
  if agent_json_indicates_missing_tool "$MAIN_JSON" "sessions_spawn"; then
    provider="$(agent_json_meta_field "$MAIN_JSON" provider || true)"
    model="$(agent_json_meta_field "$MAIN_JSON" model || true)"
    echo "main orchestrator smoke blocked: ${provider:-unknown}/${model:-unknown} did not expose the sessions_spawn runtime tool" >&2
    exit 2
  fi
  exit 1
fi
assert_agent_json_not_heretic_fallback "$MAIN_JSON" "main orchestrator smoke"

wait_for_session_pattern_after_line "$MAIN_SESSION" "$MAIN_BEFORE_LINES" '"name":"sessions_spawn"|"toolName":"sessions_spawn"' "$SUBAGENT_WAIT_ATTEMPTS" "$SUBAGENT_WAIT_DELAY"
wait_for_session_pattern_after_line "$MAIN_SESSION" "$MAIN_BEFORE_LINES" "$PROOF_FILE" "$SUBAGENT_WAIT_ATTEMPTS" "$SUBAGENT_WAIT_DELAY"
BUILDER_SESSION="$(wait_for_child_session_from_main_after_line "$MAIN_SESSION" "$MAIN_BEFORE_LINES" "$CHILD_AGENT_ID" "$PROOF_FILE" "$SUBAGENT_WAIT_ATTEMPTS" "$SUBAGENT_WAIT_DELAY")"

wait_for_file_contents "$PROOF_FILE" "$EXPECTED_PROOF_TEXT" "$SUBAGENT_WAIT_ATTEMPTS" "$SUBAGENT_WAIT_DELAY"

assert_session_pattern "$BUILDER_SESSION" "\"provider\":\"$EXPECTED_CHILD_PROVIDER\""
assert_session_pattern "$BUILDER_SESSION" "\"model\":\"$EXPECTED_CHILD_MODEL\""
assert_session_pattern "$BUILDER_SESSION" '"name":"exec"'
assert_session_pattern "$BUILDER_SESSION" 'pwd'
assert_session_pattern "$BUILDER_SESSION" "$PROOF_FILE"

echo "== local main orchestrator smoke passed =="
