#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
NODE22_BIN="${OPENCLAW_SELFTEST_NODE_BIN:-$HOME/.node22/current/bin}"
CONTEXT_FALLBACK_BASE="${OPENCLAW_CONTEXT_FALLBACK_SMOKE_BASE:-$REPO_ROOT/.local-agent-context-fallback-smoke}"
CONTEXT_FALLBACK_SUMMARY_PATH="${OPENCLAW_CONTEXT_FALLBACK_SMOKE_SUMMARY_PATH:-$REPO_ROOT/.local-agent-last-context-fallback-smoke.json}"
BOOTSTRAP_SCRIPT="$SCRIPT_DIR/bootstrap-local-coding-agents.mjs"
CONVERSATION_SCRIPT="$SCRIPT_DIR/local-human-whatsapp-conversation-eval.sh"
RESUME_SCRIPT="$SCRIPT_DIR/local-human-whatsapp-resume-eval.sh"
CONTEXT_FALLBACK_ROOT=""
CONVERSATION_SUMMARY_PATH=""
RESUME_SUMMARY_PATH=""
CONTEXT_FALLBACK_STARTED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
CONTEXT_FALLBACK_STATUS="failed"
CONTEXT_FALLBACK_FAILED_COMMAND=""
CONVERSATION_STATUS=""
CONVERSATION_TURN2_MODE=""
CONVERSATION_TURN3_MODE=""
CONVERSATION_TURN2_REPORT_STATUS=""
CONVERSATION_TURN3_REPORT_STATUS=""
CONVERSATION_TURN2_REPORT_REASON_SUMMARY=""
CONVERSATION_TURN3_REPORT_REASON_SUMMARY=""
CONVERSATION_TURN2_REPORT_DECISION_SOURCE=""
CONVERSATION_TURN3_REPORT_DECISION_SOURCE=""
CONVERSATION_TURN2_REPORT_CAUSE_LINE=""
CONVERSATION_TURN3_REPORT_CAUSE_LINE=""
CONVERSATION_TURN2_REPORT_DECISION_REASON=""
CONVERSATION_TURN3_REPORT_DECISION_REASON=""
CONVERSATION_TURN2_REPORT_USER_FACING_REPORT=""
CONVERSATION_TURN3_REPORT_USER_FACING_REPORT=""
CONVERSATION_VERIFIED_TOKEN=""
CONVERSATION_VERIFIED_MANAGER=""
RESUME_STATUS=""
RESUME_TURN2_MODE=""
RESUME_TURN2_REPORT_STATUS=""
RESUME_TURN2_REPORT_REASON_SUMMARY=""
RESUME_TURN2_REPORT_DECISION_SOURCE=""
RESUME_TURN2_REPORT_CAUSE_LINE=""
RESUME_TURN2_REPORT_DECISION_REASON=""
RESUME_TURN2_REPORT_USER_FACING_REPORT=""
RESUME_VERIFIED_TOKEN=""
RESUME_VERIFIED_MANAGER=""
CONVERSATION_TURN2_FAULT="${OPENCLAW_CONTEXT_FALLBACK_CONVERSATION_TURN2_FAULT:-whatsapp_token_mismatch}"
CONVERSATION_TURN3_FAULT="${OPENCLAW_CONTEXT_FALLBACK_CONVERSATION_TURN3_FAULT:-manager_session_mismatch}"
RESUME_TURN2_FAULT="${OPENCLAW_CONTEXT_FALLBACK_RESUME_TURN2_FAULT:-whatsapp_token_mismatch}"

if [[ -d "$NODE22_BIN" ]]; then
  PATH="$NODE22_BIN:$PATH"
  export PATH
fi

PATH="$REPO_ROOT/scripts/dev:$REPO_ROOT/../claw-code-parity/scripts:$PATH"
export PATH

mkdir -p "$CONTEXT_FALLBACK_BASE"
CONTEXT_FALLBACK_ROOT="$(mktemp -d "$CONTEXT_FALLBACK_BASE/run.XXXXXX")"
CONVERSATION_SUMMARY_PATH="$CONTEXT_FALLBACK_ROOT/conversation-summary.json"
RESUME_SUMMARY_PATH="$CONTEXT_FALLBACK_ROOT/resume-summary.json"

on_error() {
  CONTEXT_FALLBACK_FAILED_COMMAND="${BASH_COMMAND}"
}

write_context_fallback_summary() {
  local exit_code="$1"
  if [[ "$exit_code" -eq 0 ]]; then
    CONTEXT_FALLBACK_STATUS="passed"
  fi
  python3 - <<'PY' \
    "$CONTEXT_FALLBACK_SUMMARY_PATH" \
    "$CONTEXT_FALLBACK_ROOT/summary.json" \
    "$CONTEXT_FALLBACK_STATUS" \
    "$CONTEXT_FALLBACK_STARTED_AT" \
    "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    "$REPO_ROOT" \
    "$CONTEXT_FALLBACK_ROOT" \
    "$CONVERSATION_SUMMARY_PATH" \
    "$RESUME_SUMMARY_PATH" \
    "$CONVERSATION_STATUS" \
    "$CONVERSATION_TURN2_MODE" \
    "$CONVERSATION_TURN3_MODE" \
    "$CONVERSATION_TURN2_FAULT" \
    "$CONVERSATION_TURN3_FAULT" \
    "$CONVERSATION_TURN2_REPORT_STATUS" \
    "$CONVERSATION_TURN3_REPORT_STATUS" \
    "$CONVERSATION_TURN2_REPORT_REASON_SUMMARY" \
    "$CONVERSATION_TURN3_REPORT_REASON_SUMMARY" \
    "$CONVERSATION_TURN2_REPORT_DECISION_SOURCE" \
    "$CONVERSATION_TURN3_REPORT_DECISION_SOURCE" \
    "$CONVERSATION_TURN2_REPORT_CAUSE_LINE" \
    "$CONVERSATION_TURN3_REPORT_CAUSE_LINE" \
    "$CONVERSATION_TURN2_REPORT_DECISION_REASON" \
    "$CONVERSATION_TURN3_REPORT_DECISION_REASON" \
    "$CONVERSATION_TURN2_REPORT_USER_FACING_REPORT" \
    "$CONVERSATION_TURN3_REPORT_USER_FACING_REPORT" \
    "$CONVERSATION_VERIFIED_TOKEN" \
    "$CONVERSATION_VERIFIED_MANAGER" \
    "$RESUME_STATUS" \
    "$RESUME_TURN2_MODE" \
    "$RESUME_TURN2_FAULT" \
    "$RESUME_TURN2_REPORT_STATUS" \
    "$RESUME_TURN2_REPORT_REASON_SUMMARY" \
    "$RESUME_TURN2_REPORT_DECISION_SOURCE" \
    "$RESUME_TURN2_REPORT_CAUSE_LINE" \
    "$RESUME_TURN2_REPORT_DECISION_REASON" \
    "$RESUME_TURN2_REPORT_USER_FACING_REPORT" \
    "$RESUME_VERIFIED_TOKEN" \
    "$RESUME_VERIFIED_MANAGER" \
    "$CONTEXT_FALLBACK_FAILED_COMMAND"
import json, pathlib, sys

summary_paths = [pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])]
payload = {
    "summaryVersion": 1,
    "status": sys.argv[3],
    "startedAt": sys.argv[4],
    "finishedAt": sys.argv[5],
    "repoRoot": sys.argv[6],
    "smokeRoot": sys.argv[7],
    "conversationSummaryPath": sys.argv[8],
    "resumeSummaryPath": sys.argv[9],
    "conversationStatus": sys.argv[10] or None,
    "conversationTurn2ContextMode": sys.argv[11] or None,
    "conversationTurn3ContextMode": sys.argv[12] or None,
    "conversationTurn2ContextFault": sys.argv[13] or None,
    "conversationTurn3ContextFault": sys.argv[14] or None,
    "conversationTurn2ContextReportStatus": sys.argv[15] or None,
    "conversationTurn3ContextReportStatus": sys.argv[16] or None,
    "conversationTurn2ContextReportReasonSummary": sys.argv[17] or None,
    "conversationTurn3ContextReportReasonSummary": sys.argv[18] or None,
    "conversationTurn2ContextReportDecisionSource": sys.argv[19] or None,
    "conversationTurn3ContextReportDecisionSource": sys.argv[20] or None,
    "conversationTurn2ContextReportCauseLine": sys.argv[21] or None,
    "conversationTurn3ContextReportCauseLine": sys.argv[22] or None,
    "conversationTurn2ContextReportDecisionReason": sys.argv[23] or None,
    "conversationTurn3ContextReportDecisionReason": sys.argv[24] or None,
    "conversationTurn2ContextReportUserFacingReport": sys.argv[25] or None,
    "conversationTurn3ContextReportUserFacingReport": sys.argv[26] or None,
    "conversationVerifiedWhatsappToken": sys.argv[27] or None,
    "conversationVerifiedManagerSessionId": sys.argv[28] or None,
    "resumeStatus": sys.argv[29] or None,
    "resumeTurn2ContextMode": sys.argv[30] or None,
    "resumeTurn2ContextFault": sys.argv[31] or None,
    "resumeTurn2ContextReportStatus": sys.argv[32] or None,
    "resumeTurn2ContextReportReasonSummary": sys.argv[33] or None,
    "resumeTurn2ContextReportDecisionSource": sys.argv[34] or None,
    "resumeTurn2ContextReportCauseLine": sys.argv[35] or None,
    "resumeTurn2ContextReportDecisionReason": sys.argv[36] or None,
    "resumeTurn2ContextReportUserFacingReport": sys.argv[37] or None,
    "resumeVerifiedWhatsappToken": sys.argv[38] or None,
    "resumeVerifiedManagerSessionId": sys.argv[39] or None,
    "failedCommand": sys.argv[40] or None,
}
for summary_path in summary_paths:
    summary_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY
}

on_exit() {
  local exit_code="$1"
  trap - EXIT ERR
  set +e
  write_context_fallback_summary "$exit_code"
  exit "$exit_code"
}

trap on_error ERR
trap 'on_exit $?' EXIT

echo "== bootstrap local coding agents =="
node "$BOOTSTRAP_SCRIPT" >/dev/null

echo "== context fallback conversation path =="
OPENCLAW_HUMAN_WHATSAPP_CONVERSATION_EVAL_BASE="$CONTEXT_FALLBACK_ROOT/conversation-runs" \
  OPENCLAW_HUMAN_WHATSAPP_CONVERSATION_EVAL_SUMMARY_PATH="$CONVERSATION_SUMMARY_PATH" \
  OPENCLAW_HUMAN_WHATSAPP_CONVERSATION_TURN2_CONTEXT_FAULT="$CONVERSATION_TURN2_FAULT" \
  OPENCLAW_HUMAN_WHATSAPP_CONVERSATION_TURN3_CONTEXT_FAULT="$CONVERSATION_TURN3_FAULT" \
  bash "$CONVERSATION_SCRIPT" >/dev/null

echo "== context fallback resume path =="
OPENCLAW_HUMAN_WHATSAPP_RESUME_EVAL_BASE="$CONTEXT_FALLBACK_ROOT/resume-runs" \
  OPENCLAW_HUMAN_WHATSAPP_RESUME_EVAL_SUMMARY_PATH="$RESUME_SUMMARY_PATH" \
  OPENCLAW_HUMAN_WHATSAPP_RESUME_TURN2_CONTEXT_FAULT="$RESUME_TURN2_FAULT" \
  bash "$RESUME_SCRIPT" >/dev/null

if [[ ! -f "$CONVERSATION_SUMMARY_PATH" ]]; then
  echo "missing conversation summary at $CONVERSATION_SUMMARY_PATH" >&2
  exit 1
fi
if [[ ! -f "$RESUME_SUMMARY_PATH" ]]; then
  echo "missing resume summary at $RESUME_SUMMARY_PATH" >&2
  exit 1
fi

eval "$(python3 - <<'PY' "$CONVERSATION_SUMMARY_PATH" "$RESUME_SUMMARY_PATH"
import json
import shlex
import sys
from pathlib import Path

conversation = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
resume = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))

values = {
    "CONVERSATION_STATUS": conversation.get("status", ""),
    "CONVERSATION_TURN2_MODE": conversation.get("turn2ContextMode", ""),
    "CONVERSATION_TURN3_MODE": conversation.get("turn3ContextMode", ""),
    "CONVERSATION_TURN2_REPORT_STATUS": conversation.get("turn2ContextReportStatus", ""),
    "CONVERSATION_TURN3_REPORT_STATUS": conversation.get("turn3ContextReportStatus", ""),
    "CONVERSATION_TURN2_REPORT_REASON_SUMMARY": conversation.get("turn2ContextReportReasonSummary", ""),
    "CONVERSATION_TURN3_REPORT_REASON_SUMMARY": conversation.get("turn3ContextReportReasonSummary", ""),
    "CONVERSATION_TURN2_REPORT_DECISION_SOURCE": conversation.get("turn2ContextReportDecisionSource", ""),
    "CONVERSATION_TURN3_REPORT_DECISION_SOURCE": conversation.get("turn3ContextReportDecisionSource", ""),
    "CONVERSATION_TURN2_REPORT_CAUSE_LINE": conversation.get("turn2ContextReportCauseLine", ""),
    "CONVERSATION_TURN3_REPORT_CAUSE_LINE": conversation.get("turn3ContextReportCauseLine", ""),
    "CONVERSATION_TURN2_REPORT_DECISION_REASON": conversation.get("turn2ContextReportDecisionReason", ""),
    "CONVERSATION_TURN3_REPORT_DECISION_REASON": conversation.get("turn3ContextReportDecisionReason", ""),
    "CONVERSATION_TURN2_REPORT_USER_FACING_REPORT": conversation.get("turn2ContextReportUserFacingReport", ""),
    "CONVERSATION_TURN3_REPORT_USER_FACING_REPORT": conversation.get("turn3ContextReportUserFacingReport", ""),
    "CONVERSATION_VERIFIED_TOKEN": conversation.get("verifiedWhatsappToken", ""),
    "CONVERSATION_VERIFIED_MANAGER": conversation.get("verifiedManagerSessionId", ""),
    "RESUME_STATUS": resume.get("status", ""),
    "RESUME_TURN2_MODE": resume.get("turn2ContextMode", ""),
    "RESUME_TURN2_REPORT_STATUS": resume.get("turn2ContextReportStatus", ""),
    "RESUME_TURN2_REPORT_REASON_SUMMARY": resume.get("turn2ContextReportReasonSummary", ""),
    "RESUME_TURN2_REPORT_DECISION_SOURCE": resume.get("turn2ContextReportDecisionSource", ""),
    "RESUME_TURN2_REPORT_CAUSE_LINE": resume.get("turn2ContextReportCauseLine", ""),
    "RESUME_TURN2_REPORT_DECISION_REASON": resume.get("turn2ContextReportDecisionReason", ""),
    "RESUME_TURN2_REPORT_USER_FACING_REPORT": resume.get("turn2ContextReportUserFacingReport", ""),
    "RESUME_VERIFIED_TOKEN": resume.get("verifiedWhatsappToken", ""),
    "RESUME_VERIFIED_MANAGER": resume.get("verifiedManagerSessionId", ""),
}
for name, value in values.items():
    print(f"{name}={shlex.quote(str(value))}")
PY
)"

if [[ "$CONVERSATION_STATUS" != "passed" ]]; then
  echo "conversation fallback path did not pass: $CONVERSATION_STATUS" >&2
  exit 1
fi
if [[ "$CONVERSATION_TURN2_MODE" != "history" ]]; then
  echo "conversation turn 2 did not fall back to history: $CONVERSATION_TURN2_MODE" >&2
  exit 1
fi
if [[ "$CONVERSATION_TURN3_MODE" != "history" ]]; then
  echo "conversation turn 3 did not fall back to history: $CONVERSATION_TURN3_MODE" >&2
  exit 1
fi
if [[ "$CONVERSATION_TURN2_REPORT_STATUS" != "mismatch" ]]; then
  echo "conversation turn 2 consistency report did not record mismatch: $CONVERSATION_TURN2_REPORT_STATUS" >&2
  exit 1
fi
if [[ "$CONVERSATION_TURN3_REPORT_STATUS" != "mismatch" ]]; then
  echo "conversation turn 3 consistency report did not record mismatch: $CONVERSATION_TURN3_REPORT_STATUS" >&2
  exit 1
fi
if [[ "$CONVERSATION_TURN2_REPORT_DECISION_SOURCE" != "sessions_history" ]]; then
  echo "conversation turn 2 consistency report did not choose sessions_history: $CONVERSATION_TURN2_REPORT_DECISION_SOURCE" >&2
  exit 1
fi
if [[ "$CONVERSATION_TURN3_REPORT_DECISION_SOURCE" != "sessions_history" ]]; then
  echo "conversation turn 3 consistency report did not choose sessions_history: $CONVERSATION_TURN3_REPORT_DECISION_SOURCE" >&2
  exit 1
fi
if [[ "$CONVERSATION_TURN2_REPORT_REASON_SUMMARY" != *"whatsappToken mismatch"* ]]; then
  echo "conversation turn 2 consistency report did not explain whatsapp token mismatch" >&2
  exit 1
fi
if [[ "$CONVERSATION_TURN3_REPORT_REASON_SUMMARY" != *"managerSessionId mismatch"* ]]; then
  echo "conversation turn 3 consistency report did not explain manager session mismatch" >&2
  exit 1
fi
if [[ "$CONVERSATION_TURN2_REPORT_CAUSE_LINE" != *"erwartet="* || "$CONVERSATION_TURN2_REPORT_CAUSE_LINE" != *"tatsaechlich="* || "$CONVERSATION_TURN2_REPORT_CAUSE_LINE" != *"abweichung="* || "$CONVERSATION_TURN2_REPORT_CAUSE_LINE" != *"quelle=sessions_history"* ]]; then
  echo "conversation turn 2 consistency cause line is incomplete" >&2
  exit 1
fi
if [[ "$CONVERSATION_TURN3_REPORT_CAUSE_LINE" != *"erwartet="* || "$CONVERSATION_TURN3_REPORT_CAUSE_LINE" != *"tatsaechlich="* || "$CONVERSATION_TURN3_REPORT_CAUSE_LINE" != *"abweichung="* || "$CONVERSATION_TURN3_REPORT_CAUSE_LINE" != *"quelle=sessions_history"* ]]; then
  echo "conversation turn 3 consistency cause line is incomplete" >&2
  exit 1
fi
if [[ "$CONVERSATION_TURN2_REPORT_DECISION_REASON" != *"Ich nutze sessions_history, weil"* ]]; then
  echo "conversation turn 2 decision reason did not explain sessions_history fallback" >&2
  exit 1
fi
if [[ "$CONVERSATION_TURN3_REPORT_DECISION_REASON" != *"Ich nutze sessions_history, weil"* ]]; then
  echo "conversation turn 3 decision reason did not explain sessions_history fallback" >&2
  exit 1
fi
if [[ "$CONVERSATION_TURN2_REPORT_USER_FACING_REPORT" != *"erwartet="* || "$CONVERSATION_TURN2_REPORT_USER_FACING_REPORT" != *"tatsaechlich="* || "$CONVERSATION_TURN2_REPORT_USER_FACING_REPORT" != *"abweichung="* || "$CONVERSATION_TURN2_REPORT_USER_FACING_REPORT" != *"Ich nutze sessions_history, weil"* ]]; then
  echo "conversation turn 2 user-facing mismatch report is incomplete" >&2
  exit 1
fi
if [[ "$CONVERSATION_TURN3_REPORT_USER_FACING_REPORT" != *"erwartet="* || "$CONVERSATION_TURN3_REPORT_USER_FACING_REPORT" != *"tatsaechlich="* || "$CONVERSATION_TURN3_REPORT_USER_FACING_REPORT" != *"abweichung="* || "$CONVERSATION_TURN3_REPORT_USER_FACING_REPORT" != *"Ich nutze sessions_history, weil"* ]]; then
  echo "conversation turn 3 user-facing mismatch report is incomplete" >&2
  exit 1
fi
if [[ "$RESUME_STATUS" != "passed" ]]; then
  echo "resume fallback path did not pass: $RESUME_STATUS" >&2
  exit 1
fi
if [[ "$RESUME_TURN2_MODE" != "history" ]]; then
  echo "resume turn 2 did not fall back to history: $RESUME_TURN2_MODE" >&2
  exit 1
fi
if [[ "$RESUME_TURN2_REPORT_STATUS" != "mismatch" ]]; then
  echo "resume turn 2 consistency report did not record mismatch: $RESUME_TURN2_REPORT_STATUS" >&2
  exit 1
fi
if [[ "$RESUME_TURN2_REPORT_DECISION_SOURCE" != "sessions_history" ]]; then
  echo "resume turn 2 consistency report did not choose sessions_history: $RESUME_TURN2_REPORT_DECISION_SOURCE" >&2
  exit 1
fi
if [[ "$RESUME_TURN2_REPORT_REASON_SUMMARY" != *"whatsappToken mismatch"* ]]; then
  echo "resume turn 2 consistency report did not explain whatsapp token mismatch" >&2
  exit 1
fi
if [[ "$RESUME_TURN2_REPORT_CAUSE_LINE" != *"erwartet="* || "$RESUME_TURN2_REPORT_CAUSE_LINE" != *"tatsaechlich="* || "$RESUME_TURN2_REPORT_CAUSE_LINE" != *"abweichung="* || "$RESUME_TURN2_REPORT_CAUSE_LINE" != *"quelle=sessions_history"* ]]; then
  echo "resume turn 2 consistency cause line is incomplete" >&2
  exit 1
fi
if [[ "$RESUME_TURN2_REPORT_DECISION_REASON" != *"Ich nutze sessions_history, weil"* ]]; then
  echo "resume turn 2 decision reason did not explain sessions_history fallback" >&2
  exit 1
fi
if [[ "$RESUME_TURN2_REPORT_USER_FACING_REPORT" != *"erwartet="* || "$RESUME_TURN2_REPORT_USER_FACING_REPORT" != *"tatsaechlich="* || "$RESUME_TURN2_REPORT_USER_FACING_REPORT" != *"abweichung="* || "$RESUME_TURN2_REPORT_USER_FACING_REPORT" != *"Ich nutze sessions_history, weil"* ]]; then
  echo "resume turn 2 user-facing mismatch report is incomplete" >&2
  exit 1
fi
if [[ -z "$CONVERSATION_VERIFIED_TOKEN" || "$CONVERSATION_VERIFIED_TOKEN" != "$RESUME_VERIFIED_TOKEN" ]]; then
  echo "conversation/resume verified tokens do not match" >&2
  exit 1
fi
if [[ -z "$CONVERSATION_VERIFIED_MANAGER" || "$CONVERSATION_VERIFIED_MANAGER" != "$RESUME_VERIFIED_MANAGER" ]]; then
  echo "conversation/resume verified manager session ids do not match" >&2
  exit 1
fi

CONTEXT_FALLBACK_STATUS="passed"

echo "== context fallback smoke artifacts =="
printf 'conversation_summary=%s\n' "$CONVERSATION_SUMMARY_PATH"
printf 'resume_summary=%s\n' "$RESUME_SUMMARY_PATH"
printf 'context_fallback_summary=%s\n' "$CONTEXT_FALLBACK_SUMMARY_PATH"
printf 'verified_whatsapp_token=%s\n' "$CONVERSATION_VERIFIED_TOKEN"
printf 'verified_manager_session=%s\n' "$CONVERSATION_VERIFIED_MANAGER"
echo "== local human whatsapp context fallback smoke passed =="
