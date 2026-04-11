#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
STATE_DIR="${OPENCLAW_STATE_DIR:-$HOME/.openclaw}"
NODE22_BIN="${OPENCLAW_SELFTEST_NODE_BIN:-$HOME/.node22/current/bin}"
SUMMARY_PATH="${OPENCLAW_SELFTEST_SUMMARY_PATH:-$REPO_ROOT/.local-agent-last-selftest.json}"
EVAL_BASE="${OPENCLAW_HUMAN_WHATSAPP_EVAL_BASE:-$REPO_ROOT/.local-human-whatsapp-eval}"
EVAL_SUMMARY_PATH="${OPENCLAW_HUMAN_WHATSAPP_EVAL_SUMMARY_PATH:-$REPO_ROOT/.local-agent-last-human-whatsapp-eval.json}"
MAX_AGE_SECONDS="${OPENCLAW_SELFTEST_MAX_AGE_SECONDS:-21600}"
ENSURE_SCRIPT="$SCRIPT_DIR/local-coding-agents-ensure.sh"
WHATSAPP_AGENT_ID="${OPENCLAW_HUMAN_WHATSAPP_AGENT_ID:-oc-human-main}"
SUMMARY_SNAPSHOT_OVERRIDE="${OPENCLAW_HUMAN_WHATSAPP_SUMMARY_SNAPSHOT_PATH:-}"
SUMMARY_SNAPSHOT_PATH=""
STATUS_JSON=""
PLAN_JSON=""
STATUS_CONTEXT_PATH=""
STATUS_CONTEXT_REPORT_PATH=""
SELF_E164=""
EVAL_STARTED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
EVAL_STATUS="failed"
EVAL_FAILED_COMMAND=""
STATUS_TEXT=""
PLAN_TEXT=""
VERIFIED_WHATSAPP_TOKEN=""
VERIFIED_MANAGER_SESSION_ID=""
VERIFIED_SELFTEST_ARTIFACT_ROOT=""
STATUS_CONTEXT_REPORT_STATUS=""
STATUS_CONTEXT_REPORT_REASON_CODES=""
STATUS_CONTEXT_REPORT_REASON_SUMMARY=""
STATUS_CONTEXT_REPORT_DECISION_SOURCE=""
STATUS_CONTEXT_REPORT_CAUSE_LINE=""

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
STATUS_JSON="$EVAL_ROOT/status.json"
PLAN_JSON="$EVAL_ROOT/plan.json"
STATUS_CONTEXT_PATH="$EVAL_ROOT/status-context.json"
STATUS_CONTEXT_REPORT_PATH="$EVAL_ROOT/status-consistency.json"

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
    "$STATUS_JSON" \
    "$PLAN_JSON" \
    "$EVAL_FAILED_COMMAND" \
    "$STATUS_TEXT" \
    "$PLAN_TEXT" \
    "$SELF_E164" \
    "$VERIFIED_WHATSAPP_TOKEN" \
    "$VERIFIED_MANAGER_SESSION_ID" \
    "$STATUS_CONTEXT_REPORT_PATH" \
    "$STATUS_CONTEXT_REPORT_STATUS" \
    "$STATUS_CONTEXT_REPORT_REASON_CODES" \
    "$STATUS_CONTEXT_REPORT_REASON_SUMMARY" \
    "$STATUS_CONTEXT_REPORT_DECISION_SOURCE" \
    "$STATUS_CONTEXT_REPORT_CAUSE_LINE"
import json, pathlib, sys

summary_paths = [pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])]

def load_report_fields(prefix, report_path_value):
    if not report_path_value:
        return {}
    report_path = pathlib.Path(report_path_value)
    if not report_path.is_file():
        return {}
    try:
        report = json.loads(report_path.read_text(encoding="utf-8"))
    except Exception:
        return {}
    return {
        f"{prefix}ExpectedSummary": report.get("expectedSummary"),
        f"{prefix}ActualSummary": report.get("actualSummary"),
        f"{prefix}DeviationSummary": report.get("deviationSummary"),
        f"{prefix}DecisionReason": report.get("decisionReason"),
        f"{prefix}UserFacingReport": report.get("userFacingReport"),
    }

payload = {
    "summaryVersion": 1,
    "status": sys.argv[3],
    "startedAt": sys.argv[4],
    "finishedAt": sys.argv[5],
    "repoRoot": sys.argv[6],
    "evalRoot": sys.argv[7],
    "selftestSummaryPath": sys.argv[8],
    "statusPath": sys.argv[9],
    "planPath": sys.argv[10],
    "failedCommand": sys.argv[11] or None,
    "statusText": sys.argv[12] or None,
    "planText": sys.argv[13] or None,
    "selfE164": sys.argv[14] or None,
    "verifiedWhatsappToken": sys.argv[15] or None,
    "verifiedManagerSessionId": sys.argv[16] or None,
    "statusContextReportPath": sys.argv[17] or None,
    "statusContextReportStatus": sys.argv[18] or None,
    "statusContextReportReasonCodes": sys.argv[19] or None,
    "statusContextReportReasonSummary": sys.argv[20] or None,
    "statusContextReportDecisionSource": sys.argv[21] or None,
    "statusContextReportCauseLine": sys.argv[22] or None,
}
payload.update(load_report_fields("statusContextReport", payload["statusContextReportPath"]))
for summary_path in summary_paths:
    summary_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY
}

on_exit() {
  local exit_code="$1"
  trap - EXIT ERR
  set +e
  write_eval_summary "$exit_code"
  exit "$exit_code"
}

trap on_error ERR
trap 'on_exit $?' EXIT

echo "== ensure fresh live selftest =="
bash "$ENSURE_SCRIPT" --live --max-age-seconds "$MAX_AGE_SECONDS" >/dev/null

if [[ ! -f "$SUMMARY_PATH" ]]; then
  echo "missing selftest summary at $SUMMARY_PATH" >&2
  exit 1
fi

cp "$SUMMARY_PATH" "$SUMMARY_SNAPSHOT_PATH"
eval "$(verify_live_selftest_summary_snapshot "$SUMMARY_SNAPSHOT_PATH")"

echo "== gateway health =="
openclaw_ensure_gateway_healthy >/dev/null

SELF_E164="$(openclaw_whatsapp_self_e164)"
python3 - <<'PY' \
  "$STATUS_CONTEXT_PATH" \
  "$SUMMARY_SNAPSHOT_PATH" \
  "$STATUS_JSON" \
  "$PLAN_JSON" \
  "$SELF_E164" \
  "$VERIFIED_WHATSAPP_TOKEN" \
  "$VERIFIED_MANAGER_SESSION_ID"
import json
import pathlib
import sys

(
    context_path,
    summary_snapshot_path,
    status_path,
    plan_path,
    self_e164,
    whatsapp_token,
    manager_session_id,
) = sys.argv[1:8]

payload = {
    "kind": "whatsapp-status",
    "summarySnapshotPath": summary_snapshot_path,
    "statusPath": status_path,
    "planPath": plan_path,
    "selfE164": self_e164,
    "whatsappToken": whatsapp_token,
    "managerSessionId": manager_session_id,
}
path = pathlib.Path(context_path)
path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY
eval "$(inspect_whatsapp_run_context_json "$STATUS_CONTEXT_PATH" "$STATUS_CONTEXT_REPORT_PATH" "validated_snapshot" "abort_run")"
STATUS_CONTEXT_REPORT_STATUS="$WHATSAPP_CONTEXT_STATUS"
STATUS_CONTEXT_REPORT_REASON_CODES="$WHATSAPP_CONTEXT_REASON_CODES"
STATUS_CONTEXT_REPORT_REASON_SUMMARY="$WHATSAPP_CONTEXT_REASON_SUMMARY"
STATUS_CONTEXT_REPORT_DECISION_SOURCE="$WHATSAPP_CONTEXT_DECISION_SOURCE"
STATUS_CONTEXT_REPORT_CAUSE_LINE="$WHATSAPP_CONTEXT_CAUSE_LINE"
if [[ "$WHATSAPP_CONTEXT_OK" != "1" ]]; then
  echo "status context consistency failed: $STATUS_CONTEXT_REPORT_REASON_SUMMARY" >&2
  exit 1
fi

echo "== whatsapp human status eval =="
MAIN_SESSION="$(agent_main_session_jsonl "$WHATSAPP_AGENT_ID")"
if [[ -z "$MAIN_SESSION" || ! -f "$MAIN_SESSION" ]]; then
  echo "could not resolve session file for $WHATSAPP_AGENT_ID" >&2
  exit 1
fi
MAIN_BEFORE_LINES="$(session_line_count "$MAIN_SESSION")"
run_main_whatsapp_json "$STATUS_JSON" \
  --message "Ich bin der Nutzer. Lies zuerst per read exakt $SUMMARY_SNAPSHOT_PATH. Antworte danach auf Deutsch in genau 3 kurzen Zeilen mit genau 1 Satz pro Zeile. Zeile 1 beantwortet, ob mein lokaler Agent stabil läuft. Zeile 2 beantwortet, ob WhatsApp verbunden ist. Zeile 3 nennt den wichtigsten nächsten Schritt. Wenn der letzte Test fehlgeschlagen ist oder WhatsApp nicht belegt ist, sag das klar, aber normal. Keine Testreport-Sprache, keine Dateinamen, keine JSON-Feldnamen, keine Labels wie DONE oder IN ARBEIT, keine Bulletpoints, keine zusätzliche vierte Zeile. Ohne echten read-Toolcall darfst du den Auftrag nicht abschließen."

STATUS_TEXT="$(python3 - <<'PY' "$STATUS_JSON"
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
    raise SystemExit(f"status task missing JSON result payload in {sys.argv[1]}")
text = payload["payloads"][0]["text"].strip()
lines = [line.strip() for line in text.splitlines() if line.strip()]
if len(lines) != 3:
    raise SystemExit(f"status task expected exactly 3 lines, got {len(lines)} in {text!r}")
if any(line.startswith("- ") for line in lines):
    raise SystemExit(f"status task must not use bullets in {text!r}")
core_terms = [item for item in ["WhatsApp"] if item.lower() not in text.lower()]
if core_terms:
    raise SystemExit(f"status task missing expected concepts in {text!r}")
if not any(token in text.lower() for token in ["lokal", "agent"]):
    raise SystemExit(f"status task missing agent/local stability wording in {text!r}")
if not any(token in text.lower() for token in ["schritt", "nächste", "nächstes"]):
    raise SystemExit(f"status task missing next-step wording in {text!r}")
blocked = ["DONE:", "IN ARBEIT:", ".local-agent-last-selftest.json", "failedStep", "stepsCompleted"]
found = [item for item in blocked if item.lower() in text.lower()]
if found:
    raise SystemExit(f"status task contains internal wording: {found} in {text!r}")
sentence_counts = [sum(line.count(mark) for mark in ".!?") for line in lines]
if sentence_counts != [1, 1, 1]:
    raise SystemExit(f"status task expected exactly 1 sentence per line, got {sentence_counts} in {text!r}")
print(text)
PY
)"
printf '%s\n' "$STATUS_TEXT"
wait_for_session_pattern_after_line "$MAIN_SESSION" "$MAIN_BEFORE_LINES" '"name":"read"|"toolName":"read"'
wait_for_session_pattern_after_line "$MAIN_SESSION" "$MAIN_BEFORE_LINES" "$SUMMARY_SNAPSHOT_PATH"

echo "== whatsapp human next-step eval =="
run_main_whatsapp_json "$PLAN_JSON" \
  --message "Ich will wissen, was ich jetzt tun sollte. Antworte auf Deutsch aus meiner Perspektive mit genau 3 knappen Bulletpoints. Jede einzelne Zeile muss wörtlich mit '- Ich ' beginnen. Nutze Tools nur wenn nötig und bleib bei normaler Sprache ohne Testreport-Ton."

PLAN_TEXT="$(python3 - <<'PY' "$PLAN_JSON"
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
    raise SystemExit(f"plan task missing JSON result payload in {sys.argv[1]}")
text = payload["payloads"][0]["text"].strip()
lines = [line.strip() for line in text.splitlines() if line.strip()]
bullets = [line for line in lines if line.startswith("- ")]
if len(bullets) != 3:
    raise SystemExit(f"plan task expected exactly 3 bullets, got {len(bullets)} in {text!r}")
bad = [line for line in bullets if not line.startswith("- Ich ")]
if bad:
    raise SystemExit(f"plan task must stay in first person, got {bad!r}")
blocked = ["DONE:", "IN ARBEIT:"]
found = [item for item in blocked if item.lower() in text.lower()]
if found:
    raise SystemExit(f"plan task contains internal wording: {found} in {text!r}")
print(text)
PY
)"
printf '%s\n' "$PLAN_TEXT"

EVAL_STATUS="passed"

echo "== human whatsapp eval artifacts =="
printf 'status_answer=%s\n' "$STATUS_JSON"
printf 'plan_answer=%s\n' "$PLAN_JSON"
printf 'human_whatsapp_eval_summary=%s\n' "$EVAL_SUMMARY_PATH"
echo "== local human whatsapp eval passed =="
