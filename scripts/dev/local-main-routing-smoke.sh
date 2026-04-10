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
SELFTEST_MANAGER_ID="${OPENCLAW_SELFTEST_MANAGER_ID:-oc-selftest}"
SUBAGENT_WAIT_ATTEMPTS="${OPENCLAW_SELFTEST_SUBAGENT_WAIT_ATTEMPTS:-180}"
SUBAGENT_WAIT_DELAY="${OPENCLAW_SELFTEST_SUBAGENT_WAIT_DELAY:-1}"

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

source "$SCRIPT_DIR/lib/openclaw-smoke-common.sh"

echo "== bootstrap local coding agents =="
node "$REPO_ROOT/scripts/dev/bootstrap-local-coding-agents.mjs" >/dev/null

echo "== main -> oc-github routing smoke =="
MAIN_SESSION="$(agent_main_session_jsonl "$SELFTEST_MANAGER_ID")"
if [[ -z "$MAIN_SESSION" || ! -f "$MAIN_SESSION" ]]; then
  MAIN_BEFORE_LINES=0
else
  MAIN_BEFORE_LINES="$(session_line_count "$MAIN_SESSION")"
fi

run_openclaw_agent_json "$GITHUB_JSON" --agent "$SELFTEST_MANAGER_ID" --message "Nutze sessions_spawn und starte einen oc-github-Subagenten. Child-Task: führe per exec 'gh repo view yankhy-source/claw-code-parity --json nameWithOwner --jq .nameWithOwner' aus und überschreibe danach per exec exakt die bereits existierende Datei $GITHUB_PROOF mit ROUTE_GITHUB_OK:yankhy-source/claw-code-parity. Verwende genau diesen Pfad, keine neue Temp-Datei. Antworte exakt mit MAIN_ROUTE_GITHUB_OK, sobald der Child-Run akzeptiert wurde."
if [[ -z "$MAIN_SESSION" || ! -f "$MAIN_SESSION" ]]; then
  MAIN_SESSION="$(wait_for_agent_main_session_jsonl "$SELFTEST_MANAGER_ID" "$SUBAGENT_WAIT_ATTEMPTS" "$SUBAGENT_WAIT_DELAY")"
fi
run_json_assert "$GITHUB_JSON" "MAIN_ROUTE_GITHUB_OK" >/dev/null

wait_for_session_pattern_after_line "$MAIN_SESSION" "$MAIN_BEFORE_LINES" '"name":"sessions_spawn"|"toolName":"sessions_spawn"' "$SUBAGENT_WAIT_ATTEMPTS" "$SUBAGENT_WAIT_DELAY"
wait_for_session_pattern_after_line "$MAIN_SESSION" "$MAIN_BEFORE_LINES" "$GITHUB_PROOF" "$SUBAGENT_WAIT_ATTEMPTS" "$SUBAGENT_WAIT_DELAY"
GITHUB_SESSION="$(wait_for_child_session_from_main_after_line "$MAIN_SESSION" "$MAIN_BEFORE_LINES" "oc-github" "$GITHUB_PROOF" "$SUBAGENT_WAIT_ATTEMPTS" "$SUBAGENT_WAIT_DELAY")"

wait_for_file_contents "$GITHUB_PROOF" "ROUTE_GITHUB_OK:yankhy-source/claw-code-parity" "$SUBAGENT_WAIT_ATTEMPTS" "$SUBAGENT_WAIT_DELAY"

assert_session_pattern "$GITHUB_SESSION" '"provider":"openai-codex"'
assert_session_pattern "$GITHUB_SESSION" '"model":"gpt-5.3-codex-spark"'
assert_session_pattern "$GITHUB_SESSION" '"name":"exec"'
assert_session_pattern "$GITHUB_SESSION" 'gh repo view yankhy-source/claw-code-parity'
assert_session_pattern "$GITHUB_SESSION" "$GITHUB_PROOF"

echo "== main -> claw-code routing smoke =="
MAIN_BEFORE_LINES="$(session_line_count "$MAIN_SESSION")"

run_openclaw_agent_json "$CLAW_JSON" --agent "$SELFTEST_MANAGER_ID" --message "Nutze sessions_spawn und starte einen claw-code-Subagenten. Child-Task: führe per exec 'claw-code-local status' aus und überschreibe danach per exec exakt die bereits existierende Datei $CLAW_PROOF mit ROUTE_CLAW_OK. Verwende genau diesen Pfad, keine neue Temp-Datei. Antworte exakt mit MAIN_ROUTE_CLAW_OK, sobald der Child-Run akzeptiert wurde."
run_json_assert "$CLAW_JSON" "MAIN_ROUTE_CLAW_OK" >/dev/null

wait_for_session_pattern_after_line "$MAIN_SESSION" "$MAIN_BEFORE_LINES" '"name":"sessions_spawn"|"toolName":"sessions_spawn"' "$SUBAGENT_WAIT_ATTEMPTS" "$SUBAGENT_WAIT_DELAY"
wait_for_session_pattern_after_line "$MAIN_SESSION" "$MAIN_BEFORE_LINES" "$CLAW_PROOF" "$SUBAGENT_WAIT_ATTEMPTS" "$SUBAGENT_WAIT_DELAY"
CLAW_SESSION="$(wait_for_child_session_from_main_after_line "$MAIN_SESSION" "$MAIN_BEFORE_LINES" "claw-code" "$CLAW_PROOF" "$SUBAGENT_WAIT_ATTEMPTS" "$SUBAGENT_WAIT_DELAY")"

wait_for_file_contents "$CLAW_PROOF" "ROUTE_CLAW_OK" "$SUBAGENT_WAIT_ATTEMPTS" "$SUBAGENT_WAIT_DELAY"

assert_session_pattern "$CLAW_SESSION" '"provider":"openai-codex"'
assert_session_pattern "$CLAW_SESSION" '"model":"gpt-5.3-codex-spark"'
assert_session_pattern "$CLAW_SESSION" '"name":"exec"'
assert_session_pattern "$CLAW_SESSION" 'claw-code-local status'
assert_session_pattern "$CLAW_SESSION" "$CLAW_PROOF"

echo "== local main routing smoke passed =="
