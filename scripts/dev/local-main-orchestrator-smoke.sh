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

source "$SCRIPT_DIR/lib/openclaw-smoke-common.sh"

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
  BUILDER_SESSION="$(child_session_file_from_main "$MAIN_SESSION" "oc-builder" "$PROOF_FILE")"
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
