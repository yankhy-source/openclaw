#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
STATE_DIR="${OPENCLAW_STATE_DIR:-$HOME/.openclaw}"
NODE22_BIN="${OPENCLAW_SELFTEST_NODE_BIN:-$HOME/.node22/current/bin}"
SMOKE_ROOT="$(mktemp -d "$REPO_ROOT/.local-main-orchestrator-smoke.XXXXXX")"
MAIN_JSON="$SMOKE_ROOT/main.json"
PROOF_FILE="$(mktemp /tmp/main-orchestrator-smoke.XXXXXX)"
SELFTEST_MANAGER_ID="${OPENCLAW_SELFTEST_MANAGER_ID:-oc-selftest}"
SUBAGENT_WAIT_ATTEMPTS="${OPENCLAW_SELFTEST_SUBAGENT_WAIT_ATTEMPTS:-180}"
SUBAGENT_WAIT_DELAY="${OPENCLAW_SELFTEST_SUBAGENT_WAIT_DELAY:-1}"

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

run_openclaw_agent_json "$MAIN_JSON" --agent "$SELFTEST_MANAGER_ID" --message "Nutze sessions_spawn und starte einen oc-builder-Subagenten im aktuellen Repo. Child-Task: führe per exec den Befehl 'pwd' aus und überschreibe danach per exec exakt die bereits existierende Datei $PROOF_FILE mit MAIN_SUBAGENT_OK. Verwende genau diesen Pfad, keine neue Temp-Datei. Antworte exakt mit MAIN_SPAWN_OK, sobald der Child-Run akzeptiert wurde."
if [[ -z "$MAIN_SESSION" || ! -f "$MAIN_SESSION" ]]; then
  MAIN_SESSION="$(wait_for_agent_main_session_jsonl "$SELFTEST_MANAGER_ID" "$SUBAGENT_WAIT_ATTEMPTS" "$SUBAGENT_WAIT_DELAY")"
fi
run_json_assert "$MAIN_JSON" "MAIN_SPAWN_OK" >/dev/null

wait_for_session_pattern_after_line "$MAIN_SESSION" "$MAIN_BEFORE_LINES" '"name":"sessions_spawn"|"toolName":"sessions_spawn"' "$SUBAGENT_WAIT_ATTEMPTS" "$SUBAGENT_WAIT_DELAY"
wait_for_session_pattern_after_line "$MAIN_SESSION" "$MAIN_BEFORE_LINES" "$PROOF_FILE" "$SUBAGENT_WAIT_ATTEMPTS" "$SUBAGENT_WAIT_DELAY"
BUILDER_SESSION="$(wait_for_child_session_from_main_after_line "$MAIN_SESSION" "$MAIN_BEFORE_LINES" "oc-builder" "$PROOF_FILE" "$SUBAGENT_WAIT_ATTEMPTS" "$SUBAGENT_WAIT_DELAY")"

wait_for_file_contents "$PROOF_FILE" "MAIN_SUBAGENT_OK" "$SUBAGENT_WAIT_ATTEMPTS" "$SUBAGENT_WAIT_DELAY"

assert_session_pattern "$BUILDER_SESSION" '"provider":"openai-codex"'
assert_session_pattern "$BUILDER_SESSION" '"model":"gpt-5.3-codex-spark"'
assert_session_pattern "$BUILDER_SESSION" '"name":"exec"'
assert_session_pattern "$BUILDER_SESSION" 'pwd'
assert_session_pattern "$BUILDER_SESSION" "$PROOF_FILE"

echo "== local main orchestrator smoke passed =="
