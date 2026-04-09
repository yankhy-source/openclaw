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
openclaw agent --agent main --message "Nutze sessions_spawn und starte einen oc-builder-Subagenten. Child-Task: lies zuerst exakt die Datei $PACKAGE_JSON und danach die Datei $INPUT_PROOF. Überschreibe danach per apply_patch, edit oder write exakt die bereits existierende Datei $REPORT_FILE mit diesen vier Zeilen:
MAIN_TASK_SMOKE_OK
package=<name aus package.json>
version=<version aus package.json>
token=<exakter Inhalt von $INPUT_PROOF>
Verwende genau diesen Pfad. Antworte exakt mit MAIN_TASK_OK, sobald der Child-Run akzeptiert wurde." --json >"$MAIN_JSON"
run_json_assert "$MAIN_JSON" "MAIN_TASK_OK" >/dev/null

MAIN_SESSION="$(latest_session_jsonl "main")"
assert_session_pattern "$MAIN_SESSION" '"name":"sessions_spawn"'
assert_session_pattern "$MAIN_SESSION" "$REPORT_FILE"

BUILDER_SESSION=""
for _ in $(seq 1 40); do
  BUILDER_SESSION="$(child_session_file_from_main "$MAIN_SESSION" "oc-builder" "$REPORT_FILE")"
  if [[ -n "$BUILDER_SESSION" && -f "$BUILDER_SESSION" ]]; then
    break
  fi
  sleep 1
done

if [[ -z "$BUILDER_SESSION" || ! -f "$BUILDER_SESSION" ]]; then
  echo "could not find oc-builder subagent session for $REPORT_FILE" >&2
  exit 1
fi

wait_for_file_contents "$REPORT_FILE" "$EXPECTED_REPORT"

assert_session_pattern "$BUILDER_SESSION" '"provider":"openai-codex"'
assert_session_pattern "$BUILDER_SESSION" '"model":"gpt-5.3-codex-spark"'
assert_session_pattern "$BUILDER_SESSION" '"name":"read"'
assert_session_pattern "$BUILDER_SESSION" "$PACKAGE_JSON"
assert_session_pattern "$BUILDER_SESSION" "$INPUT_PROOF"
assert_session_pattern "$BUILDER_SESSION" '"name":"apply_patch"|"name":"edit"|"name":"write"'
assert_session_pattern "$BUILDER_SESSION" "$REPORT_FILE"

echo "== local main delegated task smoke passed =="
