#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
STATE_DIR="${OPENCLAW_STATE_DIR:-$HOME/.openclaw}"
NODE22_BIN="${OPENCLAW_SELFTEST_NODE_BIN:-$HOME/.node22/current/bin}"
SMOKE_ROOT="$(mktemp -d "$REPO_ROOT/.local-main-task-smoke.XXXXXX")"
MAIN_JSON="$SMOKE_ROOT/main.json"
REPORT_FILE="$SMOKE_ROOT/report.txt"
INPUT_PROOF="$SMOKE_ROOT/input-proof.txt"
PACKAGE_JSON="$REPO_ROOT/package.json"
SELFTEST_MANAGER_ID="${OPENCLAW_SELFTEST_MANAGER_ID:-oc-selftest}"
SUBAGENT_WAIT_ATTEMPTS="${OPENCLAW_SELFTEST_SUBAGENT_WAIT_ATTEMPTS:-180}"
SUBAGENT_WAIT_DELAY="${OPENCLAW_SELFTEST_SUBAGENT_WAIT_DELAY:-1}"

cleanup() {
  rm -rf "$SMOKE_ROOT"
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

printf 'before\n' >"$REPORT_FILE"
PROOF_TOKEN="MAIN_TASK_PROOF_$(date +%s)"
printf '%s\n' "$PROOF_TOKEN" >"$INPUT_PROOF"

PACKAGE_NAME="$(python3 - <<'PY' "$PACKAGE_JSON"
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as handle:
    data = json.load(handle)
print(data["name"])
PY
)"

PACKAGE_VERSION="$(python3 - <<'PY' "$PACKAGE_JSON"
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as handle:
    data = json.load(handle)
print(data["version"])
PY
)"

EXPECTED_REPORT="$(cat <<EOF
MAIN_TASK_SMOKE_OK
package=$PACKAGE_NAME
version=$PACKAGE_VERSION
token=$PROOF_TOKEN
EOF
)"

echo "== main delegated task smoke =="
MAIN_SESSION="$(agent_main_session_jsonl "$SELFTEST_MANAGER_ID")"
if [[ -z "$MAIN_SESSION" || ! -f "$MAIN_SESSION" ]]; then
  MAIN_BEFORE_LINES=0
else
  MAIN_BEFORE_LINES="$(session_line_count "$MAIN_SESSION")"
fi

run_openclaw_agent_json "$MAIN_JSON" --agent "$SELFTEST_MANAGER_ID" --message "Nutze sessions_spawn und starte einen oc-builder-Subagenten. Child-Task: lies zuerst exakt die Datei $PACKAGE_JSON und danach die Datei $INPUT_PROOF. Überschreibe danach per apply_patch, edit oder write exakt die bereits existierende Datei $REPORT_FILE mit diesen vier Zeilen:
MAIN_TASK_SMOKE_OK
package=<name aus package.json>
version=<version aus package.json>
token=<exakter Inhalt von $INPUT_PROOF>
Verwende genau diesen Pfad. Antworte exakt mit MAIN_TASK_OK, sobald der Child-Run akzeptiert wurde."
if [[ -z "$MAIN_SESSION" || ! -f "$MAIN_SESSION" ]]; then
  MAIN_SESSION="$(wait_for_agent_main_session_jsonl "$SELFTEST_MANAGER_ID" "$SUBAGENT_WAIT_ATTEMPTS" "$SUBAGENT_WAIT_DELAY")"
fi
run_json_assert "$MAIN_JSON" "MAIN_TASK_OK" >/dev/null

wait_for_session_pattern_after_line "$MAIN_SESSION" "$MAIN_BEFORE_LINES" '"name":"sessions_spawn"|"toolName":"sessions_spawn"' "$SUBAGENT_WAIT_ATTEMPTS" "$SUBAGENT_WAIT_DELAY"
wait_for_session_pattern_after_line "$MAIN_SESSION" "$MAIN_BEFORE_LINES" "$REPORT_FILE" "$SUBAGENT_WAIT_ATTEMPTS" "$SUBAGENT_WAIT_DELAY"
BUILDER_SESSION="$(wait_for_child_session_from_main_after_line "$MAIN_SESSION" "$MAIN_BEFORE_LINES" "oc-builder" "$REPORT_FILE" "$SUBAGENT_WAIT_ATTEMPTS" "$SUBAGENT_WAIT_DELAY")"

wait_for_file_contents "$REPORT_FILE" "$EXPECTED_REPORT" "$SUBAGENT_WAIT_ATTEMPTS" "$SUBAGENT_WAIT_DELAY"

assert_session_pattern "$BUILDER_SESSION" '"provider":"openai-codex"'
assert_session_pattern "$BUILDER_SESSION" '"model":"gpt-5.3-codex-spark"'
assert_session_pattern "$BUILDER_SESSION" '"name":"read"'
assert_session_pattern "$BUILDER_SESSION" "$PACKAGE_JSON"
assert_session_pattern "$BUILDER_SESSION" "$INPUT_PROOF"
assert_session_pattern "$BUILDER_SESSION" '"name":"apply_patch"|"name":"edit"|"name":"write"'
assert_session_pattern "$BUILDER_SESSION" "$REPORT_FILE"

echo "== local main delegated task smoke passed =="
