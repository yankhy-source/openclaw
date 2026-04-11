#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
STATE_DIR="${OPENCLAW_STATE_DIR:-$HOME/.openclaw}"
NODE22_BIN="${OPENCLAW_SELFTEST_NODE_BIN:-$HOME/.node22/current/bin}"
SUMMARY_PATH="${OPENCLAW_SELFTEST_SUMMARY_PATH:-$REPO_ROOT/.local-agent-last-selftest.json}"
EVAL_BASE="${OPENCLAW_HUMAN_WHATSAPP_RESUME_EVAL_BASE:-$REPO_ROOT/.local-human-whatsapp-resume-eval}"
EVAL_SUMMARY_PATH="${OPENCLAW_HUMAN_WHATSAPP_RESUME_EVAL_SUMMARY_PATH:-$REPO_ROOT/.local-agent-last-human-whatsapp-resume-eval.json}"
MAX_AGE_SECONDS="${OPENCLAW_SELFTEST_MAX_AGE_SECONDS:-21600}"
BOOTSTRAP_SCRIPT="$SCRIPT_DIR/bootstrap-local-coding-agents.mjs"
ENSURE_SCRIPT="$SCRIPT_DIR/local-coding-agents-ensure.sh"
WHATSAPP_AGENT_ID="${OPENCLAW_HUMAN_WHATSAPP_RESUME_AGENT_ID:-main}"
SUMMARY_SNAPSHOT_OVERRIDE="${OPENCLAW_HUMAN_WHATSAPP_RESUME_SUMMARY_SNAPSHOT_PATH:-}"
SUMMARY_SNAPSHOT_PATH=""
MAIN_SUMMARY_WORKSPACE_PATH=""
TURN1_SOURCE_PATH=""
EVAL_ROOT=""
TURN1_JSON=""
TURN2_JSON=""
TURN2_CONTEXT_PATH=""
TURN2_CONTEXT_REPORT_PATH=""
SELF_E164=""
TURN1_TEXT=""
TURN2_TEXT=""
MAIN_SESSION_KEY=""
TURN2_CONTEXT_MODE="memory"
VERIFIED_WHATSAPP_TOKEN=""
VERIFIED_MANAGER_SESSION_ID=""
VERIFIED_SELFTEST_ARTIFACT_ROOT=""
TURN2_CONTEXT_FAULT="${OPENCLAW_HUMAN_WHATSAPP_RESUME_TURN2_CONTEXT_FAULT:-}"
TURN2_CONTEXT_REPORT_STATUS=""
TURN2_CONTEXT_REPORT_REASON_CODES=""
TURN2_CONTEXT_REPORT_REASON_SUMMARY=""
TURN2_CONTEXT_REPORT_DECISION_SOURCE=""
TURN2_CONTEXT_REPORT_CAUSE_LINE=""
RESUME_MARKER="nebelstern-$(python3 - <<'PY'
import uuid
print(uuid.uuid4().hex[:10])
PY
)"
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
TURN1_JSON="$EVAL_ROOT/turn1-status.json"
TURN2_JSON="$EVAL_ROOT/turn2-resume.json"
TURN2_CONTEXT_PATH="$EVAL_ROOT/turn2-context.json"
TURN2_CONTEXT_REPORT_PATH="$EVAL_ROOT/turn2-consistency.json"

source "$SCRIPT_DIR/lib/openclaw-smoke-common.sh"

run_main_whatsapp_json() {
  local output_path="$1"
  shift
  run_openclaw_agent_json \
    "$output_path" \
    --agent "$WHATSAPP_AGENT_ID" \
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
def result_payload(candidate):
    if not isinstance(candidate, dict):
        return None
    if isinstance(candidate.get("result"), dict):
        return candidate["result"]
    if isinstance(candidate.get("payloads"), list):
        return candidate
    return None
for index, char in enumerate(raw):
    if char != "{":
        continue
    try:
        candidate, _ = decoder.raw_decode(raw[index:])
    except json.JSONDecodeError:
        continue
    result = result_payload(candidate)
    if result is not None:
        payload = result
if payload is None:
    raise SystemExit(f"missing JSON result payload in {sys.argv[1]}")
texts = [item.get("text", "") for item in payload["payloads"] if item.get("text")]
if not texts:
    raise SystemExit(f"missing text payloads in {sys.argv[1]}")
text = texts[-1]
if "✅ Subagent " in text:
    text = text.split("✅ Subagent ", 1)[0]
print(text.strip())
PY
}

cleanup() {
  if [[ -n "$MAIN_SUMMARY_WORKSPACE_PATH" && -f "$MAIN_SUMMARY_WORKSPACE_PATH" ]]; then
    rm -f "$MAIN_SUMMARY_WORKSPACE_PATH"
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
    "$TURN1_SOURCE_PATH" \
    "$RESUME_MARKER" \
    "$GATEWAY_RESTARTED_AT" \
    "$EVAL_FAILED_COMMAND" \
    "$TURN1_TEXT" \
    "$TURN2_TEXT" \
    "$SELF_E164" \
    "$WHATSAPP_AGENT_ID" \
    "$VERIFIED_WHATSAPP_TOKEN" \
    "$VERIFIED_MANAGER_SESSION_ID" \
    "$TURN2_CONTEXT_MODE" \
    "$TURN2_CONTEXT_FAULT" \
    "$TURN2_CONTEXT_REPORT_PATH" \
    "$TURN2_CONTEXT_REPORT_STATUS" \
    "$TURN2_CONTEXT_REPORT_REASON_CODES" \
    "$TURN2_CONTEXT_REPORT_REASON_SUMMARY" \
    "$TURN2_CONTEXT_REPORT_DECISION_SOURCE" \
    "$TURN2_CONTEXT_REPORT_CAUSE_LINE"
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
    "turn1SourcePath": sys.argv[12],
    "resumeMarker": sys.argv[13],
    "gatewayRestartedAt": sys.argv[14] or None,
    "failedCommand": sys.argv[15] or None,
    "turn1Text": sys.argv[16] or None,
    "turn2Text": sys.argv[17] or None,
    "selfE164": sys.argv[18] or None,
    "mainAgentId": sys.argv[19] or None,
    "verifiedWhatsappToken": sys.argv[20] or None,
    "verifiedManagerSessionId": sys.argv[21] or None,
    "turn2ContextMode": sys.argv[22] or None,
    "turn2ContextFault": sys.argv[23] or None,
    "turn2ContextReportPath": sys.argv[24] or None,
    "turn2ContextReportStatus": sys.argv[25] or None,
    "turn2ContextReportReasonCodes": sys.argv[26] or None,
    "turn2ContextReportReasonSummary": sys.argv[27] or None,
    "turn2ContextReportDecisionSource": sys.argv[28] or None,
    "turn2ContextReportCauseLine": sys.argv[29] or None,
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
eval "$(verify_live_selftest_summary_snapshot "$SUMMARY_SNAPSHOT_PATH")"
TURN1_SOURCE_PATH="$SUMMARY_SNAPSHOT_PATH"
if [[ "$WHATSAPP_AGENT_ID" == "main" ]]; then
  MAIN_SUMMARY_WORKSPACE_PATH="$(workspace_mirror_file "$SUMMARY_SNAPSHOT_PATH" "human-whatsapp-resume-summary" "selftest-summary.json")"
  TURN1_SOURCE_PATH="$MAIN_SUMMARY_WORKSPACE_PATH"
fi

echo "== gateway health =="
openclaw_ensure_gateway_healthy >/dev/null
SELF_E164="$(openclaw_whatsapp_self_e164)"
MAIN_SESSION_KEY="agent:${WHATSAPP_AGENT_ID}:main"

echo "== whatsapp resume turn 1 =="
MAIN_SESSION="$(agent_main_session_jsonl "$WHATSAPP_AGENT_ID")"
if [[ -z "$MAIN_SESSION" || ! -f "$MAIN_SESSION" ]]; then
  MAIN_BEFORE_LINES=0
else
  MAIN_BEFORE_LINES="$(session_line_count "$MAIN_SESSION")"
fi
run_main_whatsapp_json "$TURN1_JSON" \
  --message "Ich bin der Nutzer. Lies zuerst per read exakt $TURN1_SOURCE_PATH. Antworte danach auf Deutsch in genau 3 kurzen Sätzen: Läuft mein lokaler Agent stabil, ist WhatsApp verbunden, und was ist der wichtigste nächste Schritt? Baue das Merkwort $RESUME_MARKER genau einmal als normales Wort ein. Keine Testreport-Sprache, keine Dateinamen, keine JSON-Feldnamen, keine Labels wie DONE oder IN ARBEIT."
if [[ -z "$MAIN_SESSION" || ! -f "$MAIN_SESSION" ]]; then
  MAIN_SESSION="$(wait_for_agent_main_session_jsonl "$WHATSAPP_AGENT_ID" 40 1)"
fi
TURN1_TEXT="$(extract_result_text "$TURN1_JSON")"
python3 - <<'PY' "$TURN1_TEXT" "$RESUME_MARKER"
import sys

text = sys.argv[1]
marker = sys.argv[2]
if not all(term in text.lower() for term in ["whatsapp", "lokal"]):
    raise SystemExit(f"turn 1 missing core concepts in {text!r}")
if not any(term in text.lower() for term in ["schritt", "nächste", "nächstes"]):
    raise SystemExit(f"turn 1 missing next-step wording in {text!r}")
if text.count(marker) != 1:
    raise SystemExit(f"turn 1 must contain marker exactly once: {marker!r} in {text!r}")
blocked = ["DONE:", "IN ARBEIT:", ".local-agent-last-selftest.json", "failedStep", "stepsCompleted"]
found = [item for item in blocked if item.lower() in text.lower()]
if found:
    raise SystemExit(f"turn 1 contains internal wording {found!r}: {text!r}")
sentence_count = sum(text.count(mark) for mark in ".!?")
if sentence_count != 3:
    raise SystemExit(f"turn 1 expected exactly 3 sentences, got {sentence_count} in {text!r}")
PY
printf '%s\n' "$TURN1_TEXT"
wait_for_session_pattern_after_line "$MAIN_SESSION" "$MAIN_BEFORE_LINES" '"name":"read"|"toolName":"read"'
wait_for_session_pattern_after_line "$MAIN_SESSION" "$MAIN_BEFORE_LINES" "$TURN1_SOURCE_PATH"
python3 - <<'PY' \
  "$TURN2_CONTEXT_PATH" \
  "$MAIN_SESSION_KEY" \
  "$SUMMARY_SNAPSHOT_PATH" \
  "$TURN1_JSON" \
  "$TURN1_SOURCE_PATH" \
  "$SELF_E164" \
  "$VERIFIED_WHATSAPP_TOKEN" \
  "$VERIFIED_MANAGER_SESSION_ID" \
  "$RESUME_MARKER"
import json
import pathlib
import sys

(
    context_path,
    session_key,
    summary_snapshot_path,
    turn1_path,
    turn1_source_path,
    self_e164,
    whatsapp_token,
    manager_session_id,
    marker,
) = sys.argv[1:10]

payload = {
    "kind": "resume-turn2",
    "sessionKey": session_key,
    "summarySnapshotPath": summary_snapshot_path,
    "turn1Path": turn1_path,
    "turn1SourcePath": turn1_source_path,
    "selfE164": self_e164,
    "whatsappToken": whatsapp_token,
    "managerSessionId": manager_session_id,
    "marker": marker,
}
path = pathlib.Path(context_path)
path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY
apply_whatsapp_run_context_fault "$TURN2_CONTEXT_PATH" "$TURN2_CONTEXT_FAULT"
eval "$(inspect_whatsapp_run_context_json "$TURN2_CONTEXT_PATH" "$TURN2_CONTEXT_REPORT_PATH" "validated_context" "sessions_history")"
TURN2_CONTEXT_REPORT_STATUS="$WHATSAPP_CONTEXT_STATUS"
TURN2_CONTEXT_REPORT_REASON_CODES="$WHATSAPP_CONTEXT_REASON_CODES"
TURN2_CONTEXT_REPORT_REASON_SUMMARY="$WHATSAPP_CONTEXT_REASON_SUMMARY"
TURN2_CONTEXT_REPORT_DECISION_SOURCE="$WHATSAPP_CONTEXT_DECISION_SOURCE"
TURN2_CONTEXT_REPORT_CAUSE_LINE="$WHATSAPP_CONTEXT_CAUSE_LINE"
if [[ "$WHATSAPP_CONTEXT_OK" != "1" ]]; then
  TURN2_CONTEXT_MODE="history"
fi

echo "== restart gateway for resume break =="
openclaw_gateway_restart_with_retry >/dev/null
GATEWAY_RESTARTED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
openclaw_ensure_gateway_healthy >/dev/null

echo "== whatsapp resume turn 2 =="
TURN2_BEFORE_LINES="$(session_line_count "$MAIN_SESSION")"
if [[ "$TURN2_CONTEXT_MODE" == "history" ]]; then
  TURN2_PROMPT="Behandle deinen gespeicherten Kontext nicht als vertrauenswürdig. Rufe als allerersten Toolschritt genau sessions_history für sessionKey $MAIN_SESSION_KEY mit includeTools=true und limit 20 auf. Rekonstruiere ausschließlich aus der neuesten Assistant-Antwort in dieser Session, die das Merkwort $RESUME_MARKER genau einmal enthält, welches Merkwort wir benutzt haben und was ich jetzt als Nächstes tun sollte. Antworte dann in genau 2 kurzen deutschen Sätzen und verwende das Merkwort genau einmal. Keine Testreport-Sprache, keine Dateinamen, keine JSON-Feldnamen, keine Labels wie DONE oder IN ARBEIT."
else
  TURN2_PROMPT="Ich komme nach einer kurzen Unterbrechung zurück. Ich nenne das Merkwort nicht noch einmal. Sag mir in genau 2 kurzen deutschen Sätzen: welches Merkwort wir gerade benutzt haben und was ich jetzt als Nächstes tun sollte. Verwende das Merkwort genau einmal. Keine Testreport-Sprache, keine Dateinamen, keine JSON-Feldnamen, keine Labels wie DONE oder IN ARBEIT."
fi
run_main_whatsapp_json "$TURN2_JSON" --message "$TURN2_PROMPT"
TURN2_TEXT="$(extract_result_text "$TURN2_JSON")"
python3 - <<'PY' "$TURN2_TEXT" "$RESUME_MARKER"
import sys

text = sys.argv[1]
marker = sys.argv[2]
if text.count(marker) != 1:
    raise SystemExit(f"turn 2 must repeat marker exactly once: {marker!r} in {text!r}")
if not any(term in text.lower() for term in ["schritt", "nächste", "nächstes", "tun"]):
    raise SystemExit(f"turn 2 missing next-step wording in {text!r}")
blocked = ["DONE:", "IN ARBEIT:", ".local-agent-last-selftest.json", "failedStep", "stepsCompleted", "sandbox"]
found = [item for item in blocked if item.lower() in text.lower()]
if found:
    raise SystemExit(f"turn 2 contains internal wording {found!r}: {text!r}")
sentence_count = sum(text.count(mark) for mark in ".!?")
if sentence_count != 2:
    raise SystemExit(f"turn 2 expected exactly 2 sentences, got {sentence_count} in {text!r}")
PY
printf '%s\n' "$TURN2_TEXT"
if [[ "$TURN2_CONTEXT_MODE" == "history" ]]; then
  wait_for_session_pattern_after_line "$MAIN_SESSION" "$TURN2_BEFORE_LINES" '"name":"sessions_history"|"toolName":"sessions_history"'
fi

EVAL_STATUS="passed"

echo "== human whatsapp resume eval artifacts =="
printf 'turn1_answer=%s\n' "$TURN1_JSON"
printf 'turn2_answer=%s\n' "$TURN2_JSON"
printf 'resume_summary=%s\n' "$EVAL_SUMMARY_PATH"
printf 'resume_marker=%s\n' "$RESUME_MARKER"
echo "== local human whatsapp resume eval passed =="
