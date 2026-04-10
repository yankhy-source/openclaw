#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
STATE_DIR="${OPENCLAW_STATE_DIR:-$HOME/.openclaw}"
NODE22_BIN="${OPENCLAW_SELFTEST_NODE_BIN:-$HOME/.node22/current/bin}"
SUMMARY_PATH="${OPENCLAW_SELFTEST_SUMMARY_PATH:-$REPO_ROOT/.local-agent-last-selftest.json}"
EVAL_BASE="${OPENCLAW_HUMAN_WHATSAPP_RESUME_FAILURE_EVAL_BASE:-$REPO_ROOT/.local-human-whatsapp-resume-failure-eval}"
EVAL_SUMMARY_PATH="${OPENCLAW_HUMAN_WHATSAPP_RESUME_FAILURE_EVAL_SUMMARY_PATH:-$REPO_ROOT/.local-agent-last-human-whatsapp-resume-failure-eval.json}"
MAX_AGE_SECONDS="${OPENCLAW_SELFTEST_MAX_AGE_SECONDS:-21600}"
BOOTSTRAP_SCRIPT="$SCRIPT_DIR/bootstrap-local-coding-agents.mjs"
ENSURE_SCRIPT="$SCRIPT_DIR/local-coding-agents-ensure.sh"
SOURCE_AGENT_ID="${OPENCLAW_HUMAN_WHATSAPP_RESUME_FAILURE_SOURCE_AGENT_ID:-main}"
RECOVERY_AGENT_ID="${OPENCLAW_HUMAN_WHATSAPP_RESUME_FAILURE_RECOVERY_AGENT_ID:-oc-human-recovery}"
SUMMARY_SNAPSHOT_OVERRIDE="${OPENCLAW_HUMAN_WHATSAPP_RESUME_FAILURE_SUMMARY_SNAPSHOT_PATH:-}"
SUMMARY_SNAPSHOT_PATH=""
SOURCE_SUMMARY_WORKSPACE_PATH=""
SOURCE_TURN_PATH=""
EVAL_ROOT=""
TURN1_JSON=""
TURN2_JSON=""
ARTIFACT_PATH=""
ARTIFACT_REL=""
SELF_E164=""
TURN1_TEXT=""
TURN2_TEXT=""
ARTIFACT_TEXT=""
RESUME_FAILURE_MARKER="nebelstern-$(python3 - <<'PY'
import uuid
print(uuid.uuid4().hex[:10])
PY
)"
SOURCE_TAG="resume-failure-quelle-$(python3 - <<'PY'
import uuid
print(uuid.uuid4().hex[:8])
PY
)"
SOURCE_SESSION_KEY="agent:${SOURCE_AGENT_ID}:main"
EVAL_STARTED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
GATEWAY_RESTARTED_AT=""
EVAL_STATUS="failed"
EVAL_FAILED_COMMAND=""

if [[ -d "$NODE22_BIN" ]]; then
  PATH="$NODE22_BIN:$PATH"
  export PATH
fi

PATH="$REPO_ROOT/scripts/dev:$REPO_ROOT/../claw-code-parity/scripts:$PATH"
export PATH

mkdir -p "$EVAL_BASE"
EVAL_ROOT="$(mktemp -d "$EVAL_BASE/run.XXXXXX")"
if [[ -n "$SUMMARY_SNAPSHOT_OVERRIDE" ]]; then
  mkdir -p "$(dirname "$SUMMARY_SNAPSHOT_OVERRIDE")"
  SUMMARY_SNAPSHOT_PATH="$SUMMARY_SNAPSHOT_OVERRIDE"
else
  SUMMARY_SNAPSHOT_PATH="$EVAL_ROOT/selftest-summary.json"
fi
TURN1_JSON="$EVAL_ROOT/turn1-source.json"
TURN2_JSON="$EVAL_ROOT/turn2-rebuild.json"
ARTIFACT_PATH="$EVAL_ROOT/recovery-note.md"
ARTIFACT_REL="${ARTIFACT_PATH#"$REPO_ROOT/"}"

source "$SCRIPT_DIR/lib/openclaw-smoke-common.sh"

run_source_whatsapp_json() {
  local output_path="$1"
  shift
  run_openclaw_agent_json \
    "$output_path" \
    --agent "$SOURCE_AGENT_ID" \
    --thinking medium \
    --channel whatsapp \
    --to "$SELF_E164" \
    --deliver \
    "$@"
}

run_recovery_whatsapp_json() {
  local output_path="$1"
  shift
  run_openclaw_agent_json \
    "$output_path" \
    --agent "$RECOVERY_AGENT_ID" \
    --thinking medium \
    --channel whatsapp \
    --to "$SELF_E164" \
    --deliver \
    "$@"
}

extract_result_text() {
  python3 - <<'PY' "$1"
import json, sys
from pathlib import Path

raw = Path(sys.argv[1]).read_text(encoding="utf-8")
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
    raise SystemExit(f"missing JSON result payload in {sys.argv[1]}")
texts = [item.get("text", "") for item in payload["result"]["payloads"] if item.get("text")]
if not texts:
    raise SystemExit(f"missing text payloads in {sys.argv[1]}")
text = texts[-1]
if "✅ Subagent " in text:
    text = text.split("✅ Subagent ", 1)[0]
print(text.strip())
PY
}

wait_for_valid_artifact() {
  local artifact_path="$1"
  local marker="$2"
  local attempts="${3:-120}"
  local delay="${4:-1}"

  for _ in $(seq 1 "$attempts"); do
    if python3 - <<'PY' "$artifact_path" "$marker" >/dev/null 2>&1
from pathlib import Path
import sys

artifact_path = Path(sys.argv[1])
marker = sys.argv[2]
if not artifact_path.is_file():
    raise SystemExit(1)
text = artifact_path.read_text(encoding="utf-8")
required = ["# Recovery Note", "## Rekonstruktion", "## Nächster Schritt"]
missing = [item for item in required if item not in text]
if missing:
    raise SystemExit(1)
if text.count(marker) != 1:
    raise SystemExit(1)
blocked = [
    ".local-agent-last-selftest.json",
    ".local-agent-last-human-whatsapp-resume-failure-eval.json",
    "failedStep",
    "stepsCompleted",
    "DONE:",
    "IN ARBEIT:",
]
if any(item.lower() in text.lower() for item in blocked):
    raise SystemExit(1)
raise SystemExit(0)
PY
    then
      return 0
    fi
    sleep "$delay"
  done

  python3 - <<'PY' "$artifact_path" "$marker"
from pathlib import Path
import sys

artifact_path = Path(sys.argv[1])
marker = sys.argv[2]
if not artifact_path.is_file():
    raise SystemExit(f"artifact was not created: {artifact_path}")
text = artifact_path.read_text(encoding="utf-8")
required = ["# Recovery Note", "## Rekonstruktion", "## Nächster Schritt"]
missing = [item for item in required if item not in text]
if missing:
    raise SystemExit(f"artifact missing headings {missing!r}: {text!r}")
if text.count(marker) != 1:
    raise SystemExit(f"artifact must contain marker exactly once: {marker!r} in {text!r}")
blocked = [
    ".local-agent-last-selftest.json",
    ".local-agent-last-human-whatsapp-resume-failure-eval.json",
    "failedStep",
    "stepsCompleted",
    "DONE:",
    "IN ARBEIT:",
]
found = [item for item in blocked if item.lower() in text.lower()]
if found:
    raise SystemExit(f"artifact contains internal wording {found!r}: {text!r}")
raise SystemExit(1)
PY
}

assert_valid_artifact() {
  local artifact_path="$1"
  local marker="$2"
  python3 - <<'PY' "$artifact_path" "$marker"
from pathlib import Path
import sys

artifact_path = Path(sys.argv[1])
marker = sys.argv[2]
if not artifact_path.is_file():
    raise SystemExit(f"artifact was not created: {artifact_path}")
text = artifact_path.read_text(encoding="utf-8")
required = ["# Recovery Note", "## Rekonstruktion", "## Nächster Schritt"]
missing = [item for item in required if item not in text]
if missing:
    raise SystemExit(f"artifact missing headings {missing!r}: {text!r}")
if text.count(marker) != 1:
    raise SystemExit(f"artifact must contain marker exactly once: {marker!r} in {text!r}")
blocked = [
    ".local-agent-last-selftest.json",
    ".local-agent-last-human-whatsapp-resume-failure-eval.json",
    "failedStep",
    "stepsCompleted",
    "DONE:",
    "IN ARBEIT:",
]
found = [item for item in blocked if item.lower() in text.lower()]
if found:
    raise SystemExit(f"artifact contains internal wording {found!r}: {text!r}")
PY
}

cleanup() {
  if [[ -n "$SOURCE_SUMMARY_WORKSPACE_PATH" && -f "$SOURCE_SUMMARY_WORKSPACE_PATH" ]]; then
    rm -f "$SOURCE_SUMMARY_WORKSPACE_PATH"
  fi
}

on_error() {
  EVAL_FAILED_COMMAND="${BASH_COMMAND}"
}

write_eval_summary() {
  local exit_code="$1"
  if [[ "$exit_code" -eq 0 ]]; then
    EVAL_STATUS="passed"
  fi
  if [[ -f "$ARTIFACT_PATH" ]]; then
    ARTIFACT_TEXT="$(cat "$ARTIFACT_PATH")"
  fi
  python3 - <<'PY' \
    "$EVAL_SUMMARY_PATH" \
    "$EVAL_ROOT/summary.json" \
    "$EVAL_STATUS" \
    "$EVAL_STARTED_AT" \
    "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    "$REPO_ROOT" \
    "$EVAL_ROOT" \
    "$SUMMARY_PATH" \
    "$TURN1_JSON" \
    "$TURN2_JSON" \
    "$SUMMARY_SNAPSHOT_PATH" \
    "$SOURCE_TURN_PATH" \
    "$SOURCE_SESSION_KEY" \
    "$SOURCE_TAG" \
    "$RESUME_FAILURE_MARKER" \
    "$GATEWAY_RESTARTED_AT" \
    "$EVAL_FAILED_COMMAND" \
    "$TURN1_TEXT" \
    "$TURN2_TEXT" \
    "$ARTIFACT_PATH" \
    "$ARTIFACT_REL" \
    "$ARTIFACT_TEXT" \
    "$SELF_E164" \
    "$SOURCE_AGENT_ID" \
    "$RECOVERY_AGENT_ID"
import json, pathlib, sys

summary_paths = [pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])]
payload = {
    "summaryVersion": 1,
    "status": sys.argv[3],
    "startedAt": sys.argv[4],
    "finishedAt": sys.argv[5],
    "repoRoot": sys.argv[6],
    "evalRoot": sys.argv[7],
    "selftestSummaryPath": sys.argv[8],
    "turn1Path": sys.argv[9],
    "turn2Path": sys.argv[10],
    "summarySnapshotPath": sys.argv[11],
    "sourceTurnPath": sys.argv[12],
    "sourceSessionKey": sys.argv[13],
    "sourceTag": sys.argv[14],
    "resumeMarker": sys.argv[15],
    "gatewayRestartedAt": sys.argv[16] or None,
    "failedCommand": sys.argv[17] or None,
    "turn1Text": sys.argv[18] or None,
    "turn2Text": sys.argv[19] or None,
    "artifactPath": sys.argv[20] or None,
    "artifactRelativePath": sys.argv[21] or None,
    "artifactText": sys.argv[22] or None,
    "selfE164": sys.argv[23] or None,
    "sourceAgentId": sys.argv[24] or None,
    "recoveryAgentId": sys.argv[25] or None,
}
for summary_path in summary_paths:
    summary_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY
}

on_exit() {
  local exit_code="$1"
  trap - EXIT ERR
  set +e
  write_eval_summary "$exit_code"
  cleanup
  exit "$exit_code"
}

trap on_error ERR
trap 'on_exit $?' EXIT

echo "== bootstrap local coding agents =="
node "$BOOTSTRAP_SCRIPT" >/dev/null

echo "== ensure fresh live selftest =="
bash "$ENSURE_SCRIPT" --live --max-age-seconds "$MAX_AGE_SECONDS" >/dev/null

if [[ ! -f "$SUMMARY_PATH" ]]; then
  echo "missing selftest summary at $SUMMARY_PATH" >&2
  exit 1
fi

cp "$SUMMARY_PATH" "$SUMMARY_SNAPSHOT_PATH"
SOURCE_TURN_PATH="$SUMMARY_SNAPSHOT_PATH"
if [[ "$SOURCE_AGENT_ID" == "main" ]]; then
  SOURCE_SUMMARY_WORKSPACE_PATH="$(workspace_mirror_file "$SUMMARY_SNAPSHOT_PATH" "human-whatsapp-resume-failure-summary" "selftest-summary.json")"
  SOURCE_TURN_PATH="$SOURCE_SUMMARY_WORKSPACE_PATH"
fi

mkdir -p "$(dirname "$ARTIFACT_PATH")"
printf 'before\n' >"$ARTIFACT_PATH"

echo "== gateway health =="
openclaw_ensure_gateway_healthy >/dev/null
SELF_E164="$(openclaw_whatsapp_self_e164)"

echo "== resume-failure source turn =="
SOURCE_SESSION="$(agent_main_session_jsonl "$SOURCE_AGENT_ID")"
if [[ -z "$SOURCE_SESSION" || ! -f "$SOURCE_SESSION" ]]; then
  SOURCE_BEFORE_LINES=0
else
  SOURCE_BEFORE_LINES="$(session_line_count "$SOURCE_SESSION")"
fi
run_source_whatsapp_json "$TURN1_JSON" \
  --message "Ich bin der Nutzer. Das ist die Resume-Failure-Quelle mit Kennung $SOURCE_TAG. Lies zuerst per read exakt $SOURCE_TURN_PATH. Antworte danach auf Deutsch in genau 2 kurzen Sätzen: Läuft mein lokaler Agent stabil und welches Merkwort nutzen wir jetzt? Verwende das Merkwort $RESUME_FAILURE_MARKER genau einmal. Keine Testreport-Sprache, keine Dateinamen, keine JSON-Feldnamen, keine Labels wie DONE oder IN ARBEIT."
if [[ -z "$SOURCE_SESSION" || ! -f "$SOURCE_SESSION" ]]; then
  SOURCE_SESSION="$(wait_for_agent_main_session_jsonl "$SOURCE_AGENT_ID" 40 1)"
fi
TURN1_TEXT="$(extract_result_text "$TURN1_JSON")"
python3 - <<'PY' "$TURN1_TEXT" "$RESUME_FAILURE_MARKER"
import sys

text = sys.argv[1]
marker = sys.argv[2]
if "whatsapp" in text.lower():
    pass
if not any(term in text.lower() for term in ["lokal", "agent"]):
    raise SystemExit(f"turn 1 missing agent/local wording in {text!r}")
if text.count(marker) != 1:
    raise SystemExit(f"turn 1 must contain marker exactly once: {marker!r} in {text!r}")
blocked = ["DONE:", "IN ARBEIT:", ".local-agent-last-selftest.json", "failedStep", "stepsCompleted"]
found = [item for item in blocked if item.lower() in text.lower()]
if found:
    raise SystemExit(f"turn 1 contains internal wording {found!r}: {text!r}")
sentence_count = sum(text.count(mark) for mark in ".!?")
if sentence_count != 2:
    raise SystemExit(f"turn 1 expected exactly 2 sentences, got {sentence_count} in {text!r}")
PY
printf '%s\n' "$TURN1_TEXT"
wait_for_session_pattern_after_line "$SOURCE_SESSION" "$SOURCE_BEFORE_LINES" '"name":"read"|"toolName":"read"'
wait_for_session_pattern_after_line "$SOURCE_SESSION" "$SOURCE_BEFORE_LINES" "$SOURCE_TURN_PATH"
wait_for_session_pattern_after_line "$SOURCE_SESSION" "$SOURCE_BEFORE_LINES" "$SOURCE_TAG"

echo "== restart gateway for failure-style break =="
openclaw_gateway_restart_with_retry >/dev/null
GATEWAY_RESTARTED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
openclaw_ensure_gateway_healthy >/dev/null

echo "== resume-failure recovery turn =="
RECOVERY_SESSION="$(agent_main_session_jsonl "$RECOVERY_AGENT_ID")"
if [[ -z "$RECOVERY_SESSION" || ! -f "$RECOVERY_SESSION" ]]; then
  RECOVERY_BEFORE_LINES=0
else
  RECOVERY_BEFORE_LINES="$(session_line_count "$RECOVERY_SESSION")"
fi
run_recovery_whatsapp_json "$TURN2_JSON" \
  --message "Ich komme in einer frischen Agent-Session nach einer Unterbrechung zurück. Dein eigener Chatkontext enthält das Merkwort nicht. Rufe als allerersten Toolschritt genau sessions_history für sessionKey $SOURCE_SESSION_KEY mit includeTools=true und limit 120 auf. Benutze nicht sessions_list. Rekonstruiere daraus den neuesten Lauf mit der Kennung $SOURCE_TAG und bestimme das genaue Merkwort plus den nächsten Schritt ausschließlich aus den Nachrichten in dieser History. Du brauchst dafür keine alten Dateien erneut zu öffnen. Wenn in der History ein Pfad außerhalb deines Workspace auftaucht, ignoriere ihn. Benutze kein process und keine langen Suchläufe über ~/.openclaw. Falls du exec nutzt, dann nur kurz und lokal im aktuellen Workspace. Überschreibe danach exakt die bereits existierende Datei $ARTIFACT_REL mit Markdown: '# Recovery Note', '## Rekonstruktion', '## Nächster Schritt'. Nutze das rekonstruierte Merkwort genau einmal im Dateiinhalt. Lies die geschriebene Datei danach per read zur Verifikation. Antworte mir danach auf Deutsch in genau 2 kurzen Sätzen: welches Merkwort wir benutzt haben und was ich als Nächstes tun sollte. Verwende das Merkwort genau einmal. Keine Dateipfade, keine Testreport-Sprache, keine JSON-Feldnamen, keine Labels wie DONE oder IN ARBEIT. Ohne sessions_history darfst du nicht abschließen."
if [[ -z "$RECOVERY_SESSION" || ! -f "$RECOVERY_SESSION" ]]; then
  RECOVERY_SESSION="$(wait_for_agent_main_session_jsonl "$RECOVERY_AGENT_ID" 40 1)"
fi
TURN2_TEXT="$(extract_result_text "$TURN2_JSON")"
python3 - <<'PY' "$TURN2_TEXT" "$RESUME_FAILURE_MARKER"
import sys

text = sys.argv[1]
marker = sys.argv[2]
if text.count(marker) != 1:
    raise SystemExit(f"turn 2 must repeat marker exactly once: {marker!r} in {text!r}")
if not any(term in text.lower() for term in ["schritt", "nächste", "nächstes", "tun"]):
    raise SystemExit(f"turn 2 missing next-step wording in {text!r}")
blocked = ["DONE:", "IN ARBEIT:", ".local-agent-last-selftest.json", "failedStep", "stepsCompleted", "sessionKey", "toolCall"]
found = [item for item in blocked if item.lower() in text.lower()]
if found:
    raise SystemExit(f"turn 2 contains internal wording {found!r}: {text!r}")
sentence_count = sum(text.count(mark) for mark in ".!?")
if sentence_count != 2:
    raise SystemExit(f"turn 2 expected exactly 2 sentences, got {sentence_count} in {text!r}")
PY
printf '%s\n' "$TURN2_TEXT"

sleep 1
assert_session_pattern_after_line "$RECOVERY_SESSION" "$RECOVERY_BEFORE_LINES" '"name":"sessions_history"|"toolName":"sessions_history"'
assert_session_pattern_after_line "$RECOVERY_SESSION" "$RECOVERY_BEFORE_LINES" "$SOURCE_SESSION_KEY"
assert_session_pattern_after_line "$RECOVERY_SESSION" "$RECOVERY_BEFORE_LINES" "$SOURCE_TAG"
assert_session_pattern_after_line "$RECOVERY_SESSION" "$RECOVERY_BEFORE_LINES" "\"name\":\"apply_patch\"|\"name\":\"edit\"|\"name\":\"write\"|\"name\":\"exec\"|\"toolName\":\"apply_patch\"|\"toolName\":\"edit\"|\"toolName\":\"write\"|\"toolName\":\"exec\""
assert_session_pattern_after_line "$RECOVERY_SESSION" "$RECOVERY_BEFORE_LINES" "$ARTIFACT_REL"
assert_session_pattern_after_line "$RECOVERY_SESSION" "$RECOVERY_BEFORE_LINES" '"name":"read"|"toolName":"read"'

HISTORY_LINE="$(session_pattern_line_after_line "$RECOVERY_SESSION" "$RECOVERY_BEFORE_LINES" '"name":"sessions_history"|"toolName":"sessions_history"')"
WRITE_LINE="$(session_pattern_line_after_line "$RECOVERY_SESSION" "$RECOVERY_BEFORE_LINES" '"name":"apply_patch"|"name":"edit"|"name":"write"|"name":"exec"|"toolName":"apply_patch"|"toolName":"edit"|"toolName":"write"|"toolName":"exec"')"
if [[ -z "$HISTORY_LINE" || -z "$WRITE_LINE" || "$HISTORY_LINE" -gt "$WRITE_LINE" ]]; then
  echo "recovery run did not reconstruct via sessions_history before writing artifact" >&2
  exit 1
fi

assert_valid_artifact "$ARTIFACT_PATH" "$RESUME_FAILURE_MARKER"
ARTIFACT_TEXT="$(cat "$ARTIFACT_PATH")"
assert_session_read_result "$RECOVERY_SESSION" "$ARTIFACT_REL" "$ARTIFACT_TEXT" >/dev/null

EVAL_STATUS="passed"

echo "== human whatsapp resume-failure eval artifacts =="
printf 'turn1_answer=%s\n' "$TURN1_JSON"
printf 'turn2_answer=%s\n' "$TURN2_JSON"
printf 'artifact_path=%s\n' "$ARTIFACT_PATH"
printf 'resume_failure_summary=%s\n' "$EVAL_SUMMARY_PATH"
printf 'source_tag=%s\n' "$SOURCE_TAG"
printf 'resume_marker=%s\n' "$RESUME_FAILURE_MARKER"
echo "== local human whatsapp resume-failure eval passed =="
