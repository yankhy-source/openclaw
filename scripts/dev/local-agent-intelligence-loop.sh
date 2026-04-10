#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
STATE_DIR="${OPENCLAW_STATE_DIR:-$HOME/.openclaw}"
NODE22_BIN="${OPENCLAW_SELFTEST_NODE_BIN:-$HOME/.node22/current/bin}"
SELFTEST_SUMMARY_PATH="${OPENCLAW_SELFTEST_SUMMARY_PATH:-$REPO_ROOT/.local-agent-last-selftest.json}"
HUMAN_EVAL_SUMMARY_PATH="${OPENCLAW_HUMAN_EVAL_SUMMARY_PATH:-$REPO_ROOT/.local-agent-last-human-eval.json}"
HUMAN_WHATSAPP_EVAL_SUMMARY_PATH="${OPENCLAW_HUMAN_WHATSAPP_EVAL_SUMMARY_PATH:-$REPO_ROOT/.local-agent-last-human-whatsapp-eval.json}"
HUMAN_WHATSAPP_CONVERSATION_EVAL_SUMMARY_PATH="${OPENCLAW_HUMAN_WHATSAPP_CONVERSATION_EVAL_SUMMARY_PATH:-$REPO_ROOT/.local-agent-last-human-whatsapp-conversation-eval.json}"
HUMAN_WHATSAPP_RESUME_EVAL_SUMMARY_PATH="${OPENCLAW_HUMAN_WHATSAPP_RESUME_EVAL_SUMMARY_PATH:-$REPO_ROOT/.local-agent-last-human-whatsapp-resume-eval.json}"
HUMAN_WHATSAPP_RESUME_FAILURE_EVAL_SUMMARY_PATH="${OPENCLAW_HUMAN_WHATSAPP_RESUME_FAILURE_EVAL_SUMMARY_PATH:-$REPO_ROOT/.local-agent-last-human-whatsapp-resume-failure-eval.json}"
INTELLIGENCE_LOOP_BASE="${OPENCLAW_INTELLIGENCE_LOOP_BASE:-$REPO_ROOT/.local-agent-intelligence-loop}"
INTELLIGENCE_LOOP_SUMMARY_PATH="${OPENCLAW_INTELLIGENCE_LOOP_SUMMARY_PATH:-$REPO_ROOT/.local-agent-last-intelligence-loop.json}"
BOOTSTRAP_SCRIPT="$SCRIPT_DIR/bootstrap-local-coding-agents.mjs"
HUMAN_EVAL_SCRIPT="$SCRIPT_DIR/local-human-perspective-eval.sh"
HUMAN_WHATSAPP_EVAL_SCRIPT="$SCRIPT_DIR/local-human-whatsapp-eval.sh"
HUMAN_WHATSAPP_CONVERSATION_EVAL_SCRIPT="$SCRIPT_DIR/local-human-whatsapp-conversation-eval.sh"
HUMAN_WHATSAPP_RESUME_EVAL_SCRIPT="$SCRIPT_DIR/local-human-whatsapp-resume-eval.sh"
HUMAN_WHATSAPP_RESUME_FAILURE_EVAL_SCRIPT="$SCRIPT_DIR/local-human-whatsapp-resume-failure-eval.sh"
EVALUATOR_AGENT_ID="${OPENCLAW_INTELLIGENCE_EVALUATOR_AGENT_ID:-oc-selftest}"
LOOP_ROOT=""
REVIEW_JSON=""
REVIEW_PATH=""
SELFTEST_SNAPSHOT_PATH=""
HUMAN_EVAL_SNAPSHOT_PATH=""
HUMAN_WHATSAPP_SNAPSHOT_PATH=""
HUMAN_WHATSAPP_CONVERSATION_SNAPSHOT_PATH=""
HUMAN_WHATSAPP_RESUME_SNAPSHOT_PATH=""
HUMAN_WHATSAPP_RESUME_FAILURE_SNAPSHOT_PATH=""
LOOP_STARTED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
LOOP_STATUS="failed"
LOOP_FAILED_COMMAND=""
REVIEW_TEXT=""
NEXT_UPGRADE_TEXT=""
SELFTEST_STATUS=""
SELFTEST_MODE=""
HUMAN_EVAL_STATUS=""
HUMAN_WHATSAPP_EVAL_STATUS=""
HUMAN_WHATSAPP_CONVERSATION_EVAL_STATUS=""
HUMAN_WHATSAPP_RESUME_EVAL_STATUS=""
HUMAN_WHATSAPP_RESUME_FAILURE_EVAL_STATUS=""

if [[ -d "$NODE22_BIN" ]]; then
  PATH="$NODE22_BIN:$PATH"
  export PATH
fi

PATH="$REPO_ROOT/scripts/dev:$REPO_ROOT/../claw-code-parity/scripts:$PATH"
export PATH

mkdir -p "$INTELLIGENCE_LOOP_BASE"
LOOP_ROOT="$(mktemp -d "$INTELLIGENCE_LOOP_BASE/run.XXXXXX")"
REVIEW_JSON="$LOOP_ROOT/intelligence-review.json"
REVIEW_PATH="$LOOP_ROOT/intelligence-review.md"
SELFTEST_SNAPSHOT_PATH="$LOOP_ROOT/selftest-summary.json"
HUMAN_EVAL_SNAPSHOT_PATH="$LOOP_ROOT/human-eval-summary.json"
HUMAN_WHATSAPP_SNAPSHOT_PATH="$LOOP_ROOT/human-whatsapp-eval-summary.json"
HUMAN_WHATSAPP_CONVERSATION_SNAPSHOT_PATH="$LOOP_ROOT/human-whatsapp-conversation-summary.json"
HUMAN_WHATSAPP_RESUME_SNAPSHOT_PATH="$LOOP_ROOT/human-whatsapp-resume-summary.json"
HUMAN_WHATSAPP_RESUME_FAILURE_SNAPSHOT_PATH="$LOOP_ROOT/human-whatsapp-resume-failure-summary.json"

source "$SCRIPT_DIR/lib/openclaw-smoke-common.sh"

run_evaluator_agent_json() {
  local output_path="$1"
  shift
  run_openclaw_agent_json "$output_path" --agent "$EVALUATOR_AGENT_ID" --thinking medium "$@"
}

on_error() {
  LOOP_FAILED_COMMAND="${BASH_COMMAND}"
}

write_loop_summary() {
  local exit_code="$1"
  if [[ "$exit_code" -eq 0 ]]; then
    LOOP_STATUS="passed"
  fi
  python3 - <<'PY' \
    "$INTELLIGENCE_LOOP_SUMMARY_PATH" \
    "$LOOP_ROOT/summary.json" \
    "$LOOP_STATUS" \
    "$LOOP_STARTED_AT" \
    "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    "$REPO_ROOT" \
    "$LOOP_ROOT" \
    "$SELFTEST_SUMMARY_PATH" \
    "$HUMAN_EVAL_SUMMARY_PATH" \
    "$HUMAN_WHATSAPP_EVAL_SUMMARY_PATH" \
    "$HUMAN_WHATSAPP_CONVERSATION_EVAL_SUMMARY_PATH" \
    "$HUMAN_WHATSAPP_RESUME_EVAL_SUMMARY_PATH" \
    "$HUMAN_WHATSAPP_RESUME_FAILURE_EVAL_SUMMARY_PATH" \
    "$REVIEW_PATH" \
    "$REVIEW_JSON" \
    "$EVALUATOR_AGENT_ID" \
    "$LOOP_FAILED_COMMAND" \
    "$SELFTEST_STATUS" \
    "$SELFTEST_MODE" \
    "$HUMAN_EVAL_STATUS" \
    "$HUMAN_WHATSAPP_EVAL_STATUS" \
    "$HUMAN_WHATSAPP_CONVERSATION_EVAL_STATUS" \
    "$HUMAN_WHATSAPP_RESUME_EVAL_STATUS" \
    "$HUMAN_WHATSAPP_RESUME_FAILURE_EVAL_STATUS" \
    "$NEXT_UPGRADE_TEXT" \
    "$REVIEW_TEXT"
import json, pathlib, sys

summary_paths = [pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])]
payload = {
    "summaryVersion": 1,
    "status": sys.argv[3],
    "startedAt": sys.argv[4],
    "finishedAt": sys.argv[5],
    "repoRoot": sys.argv[6],
    "loopRoot": sys.argv[7],
    "selftestSummaryPath": sys.argv[8],
    "humanEvalSummaryPath": sys.argv[9],
    "humanWhatsappEvalSummaryPath": sys.argv[10],
    "humanWhatsappConversationEvalSummaryPath": sys.argv[11],
    "humanWhatsappResumeEvalSummaryPath": sys.argv[12],
    "humanWhatsappResumeFailureEvalSummaryPath": sys.argv[13],
    "reviewPath": sys.argv[14],
    "reviewJsonPath": sys.argv[15],
    "evaluatorAgentId": sys.argv[16] or None,
    "failedCommand": sys.argv[17] or None,
    "selftestStatus": sys.argv[18] or None,
    "selftestMode": sys.argv[19] or None,
    "humanEvalStatus": sys.argv[20] or None,
    "humanWhatsappEvalStatus": sys.argv[21] or None,
    "humanWhatsappConversationStatus": sys.argv[22] or None,
    "humanWhatsappResumeStatus": sys.argv[23] or None,
    "humanWhatsappResumeFailureStatus": sys.argv[24] or None,
    "nextUpgrade": sys.argv[25] or None,
    "reviewText": sys.argv[26] or None,
}
for summary_path in summary_paths:
    summary_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY
}

on_exit() {
  local exit_code="$1"
  trap - EXIT ERR
  set +e
  write_loop_summary "$exit_code"
  exit "$exit_code"
}

trap on_error ERR
trap 'on_exit $?' EXIT

echo "== bootstrap local coding agents =="
node "$BOOTSTRAP_SCRIPT" >/dev/null

echo "== human perspective eval =="
bash "$HUMAN_EVAL_SCRIPT" >/dev/null

echo "== human whatsapp eval =="
bash "$HUMAN_WHATSAPP_EVAL_SCRIPT" >/dev/null

echo "== human whatsapp conversation eval =="
bash "$HUMAN_WHATSAPP_CONVERSATION_EVAL_SCRIPT" >/dev/null

echo "== human whatsapp resume eval =="
bash "$HUMAN_WHATSAPP_RESUME_EVAL_SCRIPT" >/dev/null

echo "== human whatsapp resume-failure eval =="
bash "$HUMAN_WHATSAPP_RESUME_FAILURE_EVAL_SCRIPT" >/dev/null

if [[ ! -f "$SELFTEST_SUMMARY_PATH" ]]; then
  echo "missing selftest summary at $SELFTEST_SUMMARY_PATH" >&2
  exit 1
fi
if [[ ! -f "$HUMAN_EVAL_SUMMARY_PATH" ]]; then
  echo "missing human eval summary at $HUMAN_EVAL_SUMMARY_PATH" >&2
  exit 1
fi
if [[ ! -f "$HUMAN_WHATSAPP_EVAL_SUMMARY_PATH" ]]; then
  echo "missing human whatsapp eval summary at $HUMAN_WHATSAPP_EVAL_SUMMARY_PATH" >&2
  exit 1
fi
if [[ ! -f "$HUMAN_WHATSAPP_CONVERSATION_EVAL_SUMMARY_PATH" ]]; then
  echo "missing human whatsapp conversation eval summary at $HUMAN_WHATSAPP_CONVERSATION_EVAL_SUMMARY_PATH" >&2
  exit 1
fi
if [[ ! -f "$HUMAN_WHATSAPP_RESUME_EVAL_SUMMARY_PATH" ]]; then
  echo "missing human whatsapp resume eval summary at $HUMAN_WHATSAPP_RESUME_EVAL_SUMMARY_PATH" >&2
  exit 1
fi
if [[ ! -f "$HUMAN_WHATSAPP_RESUME_FAILURE_EVAL_SUMMARY_PATH" ]]; then
  echo "missing human whatsapp resume-failure eval summary at $HUMAN_WHATSAPP_RESUME_FAILURE_EVAL_SUMMARY_PATH" >&2
  exit 1
fi

cp "$SELFTEST_SUMMARY_PATH" "$SELFTEST_SNAPSHOT_PATH"
cp "$HUMAN_EVAL_SUMMARY_PATH" "$HUMAN_EVAL_SNAPSHOT_PATH"
cp "$HUMAN_WHATSAPP_EVAL_SUMMARY_PATH" "$HUMAN_WHATSAPP_SNAPSHOT_PATH"
cp "$HUMAN_WHATSAPP_CONVERSATION_EVAL_SUMMARY_PATH" "$HUMAN_WHATSAPP_CONVERSATION_SNAPSHOT_PATH"
cp "$HUMAN_WHATSAPP_RESUME_EVAL_SUMMARY_PATH" "$HUMAN_WHATSAPP_RESUME_SNAPSHOT_PATH"
cp "$HUMAN_WHATSAPP_RESUME_FAILURE_EVAL_SUMMARY_PATH" "$HUMAN_WHATSAPP_RESUME_FAILURE_SNAPSHOT_PATH"

eval "$(python3 - <<'PY' "$SELFTEST_SUMMARY_PATH" "$HUMAN_EVAL_SUMMARY_PATH" "$HUMAN_WHATSAPP_EVAL_SUMMARY_PATH" "$HUMAN_WHATSAPP_CONVERSATION_EVAL_SUMMARY_PATH" "$HUMAN_WHATSAPP_RESUME_EVAL_SUMMARY_PATH" "$HUMAN_WHATSAPP_RESUME_FAILURE_EVAL_SUMMARY_PATH"
import json, shlex, sys
paths = sys.argv[1:7]
labels = [
    ("SELFTEST_STATUS", "status"),
    ("SELFTEST_MODE", "mode"),
    ("HUMAN_EVAL_STATUS", "status"),
    ("HUMAN_WHATSAPP_EVAL_STATUS", "status"),
    ("HUMAN_WHATSAPP_CONVERSATION_EVAL_STATUS", "status"),
    ("HUMAN_WHATSAPP_RESUME_EVAL_STATUS", "status"),
    ("HUMAN_WHATSAPP_RESUME_FAILURE_EVAL_STATUS", "status"),
]
selftest = json.loads(open(paths[0], "r", encoding="utf-8").read())
human = json.loads(open(paths[1], "r", encoding="utf-8").read())
whatsapp = json.loads(open(paths[2], "r", encoding="utf-8").read())
conversation = json.loads(open(paths[3], "r", encoding="utf-8").read())
resume = json.loads(open(paths[4], "r", encoding="utf-8").read())
resume_failure = json.loads(open(paths[5], "r", encoding="utf-8").read())
values = {
    "SELFTEST_STATUS": selftest.get("status", ""),
    "SELFTEST_MODE": selftest.get("mode", ""),
    "HUMAN_EVAL_STATUS": human.get("status", ""),
    "HUMAN_WHATSAPP_EVAL_STATUS": whatsapp.get("status", ""),
    "HUMAN_WHATSAPP_CONVERSATION_EVAL_STATUS": conversation.get("status", ""),
    "HUMAN_WHATSAPP_RESUME_EVAL_STATUS": resume.get("status", ""),
    "HUMAN_WHATSAPP_RESUME_FAILURE_EVAL_STATUS": resume_failure.get("status", ""),
}
for name, _ in labels:
    print(f"{name}={shlex.quote(str(values[name]))}")
PY
)"

if [[ "$SELFTEST_STATUS" != "passed" || "$SELFTEST_MODE" != "live" ]]; then
  echo "intelligence loop requires a passed live selftest, got status=$SELFTEST_STATUS mode=$SELFTEST_MODE" >&2
  exit 1
fi
if [[ "$HUMAN_EVAL_STATUS" != "passed" ]]; then
  echo "human eval did not pass: $HUMAN_EVAL_STATUS" >&2
  exit 1
fi
if [[ "$HUMAN_WHATSAPP_EVAL_STATUS" != "passed" ]]; then
  echo "human whatsapp eval did not pass: $HUMAN_WHATSAPP_EVAL_STATUS" >&2
  exit 1
fi
if [[ "$HUMAN_WHATSAPP_CONVERSATION_EVAL_STATUS" != "passed" ]]; then
  echo "human whatsapp conversation eval did not pass: $HUMAN_WHATSAPP_CONVERSATION_EVAL_STATUS" >&2
  exit 1
fi
if [[ "$HUMAN_WHATSAPP_RESUME_EVAL_STATUS" != "passed" ]]; then
  echo "human whatsapp resume eval did not pass: $HUMAN_WHATSAPP_RESUME_EVAL_STATUS" >&2
  exit 1
fi
if [[ "$HUMAN_WHATSAPP_RESUME_FAILURE_EVAL_STATUS" != "passed" ]]; then
  echo "human whatsapp resume-failure eval did not pass: $HUMAN_WHATSAPP_RESUME_FAILURE_EVAL_STATUS" >&2
  exit 1
fi

echo "== evaluator review =="
EVALUATOR_SESSION="$(agent_main_session_jsonl "$EVALUATOR_AGENT_ID")"
if [[ -z "$EVALUATOR_SESSION" || ! -f "$EVALUATOR_SESSION" ]]; then
  EVALUATOR_BEFORE_LINES=0
else
  EVALUATOR_BEFORE_LINES="$(session_line_count "$EVALUATOR_SESSION")"
fi

run_evaluator_agent_json "$REVIEW_JSON" \
  --message "Du bist der skeptische Evaluator in einer lokalen Agent-Upgrade-Schleife. Lies zuerst per read exakt $SELFTEST_SNAPSHOT_PATH, $HUMAN_EVAL_SNAPSHOT_PATH, $HUMAN_WHATSAPP_SNAPSHOT_PATH, $HUMAN_WHATSAPP_CONVERSATION_SNAPSHOT_PATH, $HUMAN_WHATSAPP_RESUME_SNAPSHOT_PATH und $HUMAN_WHATSAPP_RESUME_FAILURE_SNAPSHOT_PATH. Erstelle oder überschreibe danach exakt die Datei $REVIEW_PATH. Inhalt: Markdown mit '# Intelligenz-Review', '## Stärken', '## Schwächen' und '## Nächster Upgrade-Schritt'. Bewerte nur das beobachtete Verhalten dieser Läufe. Berücksichtige ausdrücklich auch Gesprächsgedächtnis, Nutzersprache und Artefaktqualität im WhatsApp-Mehrturn-Lauf, die Wiederaufnahme nach Unterbrechung im Resume-Lauf und den harten Kontextbruch mit Rekonstruktion aus sessions_history im Resume-Failure-Lauf. Schreibe auf Deutsch, konkret und knapp. Keine Dateipfade, keine JSON-Feldnamen, keine Labels wie DONE oder IN ARBEIT. Unter 'Stärken' und 'Schwächen' nur kurze Bullets. Unter 'Nächster Upgrade-Schritt' genau ein fokussierter nächster Verbesserungsschritt als normaler kurzer Absatz. Lies die geschriebene Datei danach noch einmal per read zur Verifikation. Antworte exakt INTELLIGENCE_LOOP_DONE."

if [[ -z "$EVALUATOR_SESSION" || ! -f "$EVALUATOR_SESSION" ]]; then
  EVALUATOR_SESSION="$(wait_for_agent_main_session_jsonl "$EVALUATOR_AGENT_ID" 40 1)"
fi

run_json_assert "$REVIEW_JSON" "INTELLIGENCE_LOOP_DONE" >/dev/null
wait_for_session_pattern_after_line "$EVALUATOR_SESSION" "$EVALUATOR_BEFORE_LINES" '"name":"read"|"toolName":"read"' 80 1
wait_for_session_pattern_after_line "$EVALUATOR_SESSION" "$EVALUATOR_BEFORE_LINES" "$SELFTEST_SNAPSHOT_PATH" 80 1
wait_for_session_pattern_after_line "$EVALUATOR_SESSION" "$EVALUATOR_BEFORE_LINES" "$HUMAN_EVAL_SNAPSHOT_PATH" 80 1
wait_for_session_pattern_after_line "$EVALUATOR_SESSION" "$EVALUATOR_BEFORE_LINES" "$HUMAN_WHATSAPP_SNAPSHOT_PATH" 80 1
wait_for_session_pattern_after_line "$EVALUATOR_SESSION" "$EVALUATOR_BEFORE_LINES" "$HUMAN_WHATSAPP_CONVERSATION_SNAPSHOT_PATH" 80 1
wait_for_session_pattern_after_line "$EVALUATOR_SESSION" "$EVALUATOR_BEFORE_LINES" "$HUMAN_WHATSAPP_RESUME_SNAPSHOT_PATH" 80 1
wait_for_session_pattern_after_line "$EVALUATOR_SESSION" "$EVALUATOR_BEFORE_LINES" "$HUMAN_WHATSAPP_RESUME_FAILURE_SNAPSHOT_PATH" 80 1
wait_for_session_pattern_after_line "$EVALUATOR_SESSION" "$EVALUATOR_BEFORE_LINES" '"name":"apply_patch"|"name":"edit"|"name":"write"' 80 1
wait_for_session_pattern_after_line "$EVALUATOR_SESSION" "$EVALUATOR_BEFORE_LINES" "$REVIEW_PATH" 80 1

eval "$(python3 - <<'PY' "$REVIEW_PATH"
import shlex, sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")
required = ["# Intelligenz-Review", "## Stärken", "## Schwächen", "## Nächster Upgrade-Schritt"]
missing = [item for item in required if item not in text]
if missing:
    raise SystemExit(f"review missing headings: {missing!r}")
blocked = [
    ".local-agent-last-selftest.json",
    ".local-agent-last-human-eval.json",
    ".local-agent-last-human-whatsapp-eval.json",
    "failedStep",
    "stepsCompleted",
    "DONE:",
    "IN ARBEIT:",
]
found = [item for item in blocked if item.lower() in text.lower()]
if found:
    raise SystemExit(f"review contains internal wording: {found!r}")
next_step = ""
capture = False
for line in text.splitlines():
    stripped = line.strip()
    if stripped == "## Nächster Upgrade-Schritt":
        capture = True
        continue
    if capture:
        if stripped.startswith("## "):
            break
        if stripped:
            next_step = stripped
            break
if not next_step:
    raise SystemExit("review missing next upgrade text")
print(f"REVIEW_TEXT={shlex.quote(text)}")
print(f"NEXT_UPGRADE_TEXT={shlex.quote(next_step)}")
PY
)"

printf '%s\n' "$REVIEW_TEXT"
printf 'next_upgrade=%s\n' "$NEXT_UPGRADE_TEXT"

LOOP_STATUS="passed"

echo "== intelligence loop artifacts =="
printf 'human_eval_summary=%s\n' "$HUMAN_EVAL_SUMMARY_PATH"
printf 'human_whatsapp_eval_summary=%s\n' "$HUMAN_WHATSAPP_EVAL_SUMMARY_PATH"
printf 'human_whatsapp_conversation_eval_summary=%s\n' "$HUMAN_WHATSAPP_CONVERSATION_EVAL_SUMMARY_PATH"
printf 'human_whatsapp_resume_eval_summary=%s\n' "$HUMAN_WHATSAPP_RESUME_EVAL_SUMMARY_PATH"
printf 'review_path=%s\n' "$REVIEW_PATH"
printf 'intelligence_loop_summary=%s\n' "$INTELLIGENCE_LOOP_SUMMARY_PATH"
printf 'evaluator_agent_id=%s\n' "$EVALUATOR_AGENT_ID"
echo "== local agent intelligence loop passed =="
