#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
STATE_DIR="${OPENCLAW_STATE_DIR:-$HOME/.openclaw}"
NODE22_BIN="${OPENCLAW_SELFTEST_NODE_BIN:-$HOME/.node22/current/bin}"
SUMMARY_PATH="${OPENCLAW_SELFTEST_SUMMARY_PATH:-$REPO_ROOT/.local-agent-last-selftest.json}"
HUMAN_EVAL_BASE="${OPENCLAW_HUMAN_EVAL_BASE:-$REPO_ROOT/.local-human-eval}"
HUMAN_EVAL_SUMMARY_PATH="${OPENCLAW_HUMAN_EVAL_SUMMARY_PATH:-$REPO_ROOT/.local-agent-last-human-eval.json}"
EVAL_ROOT=""
Q1_JSON="$EVAL_ROOT/human-status.json"
Q2_JSON="$EVAL_ROOT/human-plan.json"
Q3_JSON="$EVAL_ROOT/human-artifact.json"
ARTIFACT_PATH="$EVAL_ROOT/team-update.md"
BOOTSTRAP_SCRIPT="$SCRIPT_DIR/bootstrap-local-coding-agents.mjs"
DOCTOR_SCRIPT="$SCRIPT_DIR/local-coding-agents-doctor.sh"
ENSURE_SCRIPT="$SCRIPT_DIR/local-coding-agents-ensure.sh"
EVAL_STARTED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
EVAL_STATUS="failed"
EVAL_FAILED_COMMAND=""
EVAL_TASK1_TEXT=""
EVAL_TASK2_TEXT=""
MAIN_SESSION_ID="local-human-eval-$(date +%s)-$$"

if [[ -d "$NODE22_BIN" ]]; then
  PATH="$NODE22_BIN:$PATH"
  export PATH
fi

PATH="$REPO_ROOT/scripts/dev:$REPO_ROOT/../claw-code-parity/scripts:$PATH"
export PATH

mkdir -p "$HUMAN_EVAL_BASE"
EVAL_ROOT="$(mktemp -d "$HUMAN_EVAL_BASE/run.XXXXXX")"
Q1_JSON="$EVAL_ROOT/human-status.json"
Q2_JSON="$EVAL_ROOT/human-plan.json"
Q3_JSON="$EVAL_ROOT/human-artifact.json"
ARTIFACT_PATH="$EVAL_ROOT/team-update.md"

source "$SCRIPT_DIR/lib/openclaw-smoke-common.sh"

run_main_agent_json() {
  local output_path="$1"
  shift
  run_openclaw_agent_json "$output_path" --agent main --session-id "$MAIN_SESSION_ID" --thinking medium "$@"
}

on_error() {
  EVAL_FAILED_COMMAND="${BASH_COMMAND}"
}

write_eval_summary() {
  local exit_code="$1"
  local artifact_text=""
  if [[ "$exit_code" -eq 0 ]]; then
    EVAL_STATUS="passed"
  fi
  if [[ -f "$ARTIFACT_PATH" ]]; then
    artifact_text="$(cat "$ARTIFACT_PATH")"
  fi
  python3 - <<'PY' \
    "$HUMAN_EVAL_SUMMARY_PATH" \
    "$EVAL_STATUS" \
    "$EVAL_STARTED_AT" \
    "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    "$REPO_ROOT" \
    "$EVAL_ROOT" \
    "$SUMMARY_PATH" \
    "$Q1_JSON" \
    "$Q2_JSON" \
    "$Q3_JSON" \
    "$ARTIFACT_PATH" \
    "$EVAL_FAILED_COMMAND" \
    "$EVAL_TASK1_TEXT" \
    "$EVAL_TASK2_TEXT" \
    "$artifact_text" \
    "$MAIN_SESSION_ID"
import json, pathlib, sys

summary_path = pathlib.Path(sys.argv[1])
payload = {
    "summaryVersion": 1,
    "status": sys.argv[2],
    "startedAt": sys.argv[3],
    "finishedAt": sys.argv[4],
    "repoRoot": sys.argv[5],
    "evalRoot": sys.argv[6],
    "selftestSummaryPath": sys.argv[7],
    "task1Path": sys.argv[8],
    "task2Path": sys.argv[9],
    "task3Path": sys.argv[10],
    "artifactPath": sys.argv[11],
    "failedCommand": sys.argv[12] or None,
    "task1Text": sys.argv[13] or None,
    "task2Text": sys.argv[14] or None,
    "artifactText": sys.argv[15] or None,
    "mainSessionId": sys.argv[16] or None,
}
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

echo "== bootstrap local coding agents =="
node "$BOOTSTRAP_SCRIPT" >/dev/null

echo "== ensure fresh live baseline =="
bash "$DOCTOR_SCRIPT" --require-mode live --max-age-seconds 1800 >/dev/null 2>&1 || \
  bash "$ENSURE_SCRIPT" --live --max-age-seconds 1800 >/dev/null

echo "== task 1: human status question =="
run_main_agent_json "$Q1_JSON" \
  --message "Ich bin der Nutzer. Sag mir auf Deutsch in maximal 4 kurzen Sätzen: Läuft mein lokaler Agent gerade stabil, ist WhatsApp verbunden, und was ist der wichtigste nächste Schritt? Nutze read auf $SUMMARY_PATH, wenn du konkrete Aussagen machst. Sprich normal mit mir, nicht wie ein Testreport. Verwende keine Labels wie DONE, IN ARBEIT oder NÄCHSTER SCHRITT und nenne keine Dateinamen oder JSON-Feldnamen."

EVAL_TASK1_TEXT="$(python3 - <<'PY' "$Q1_JSON"
import json, sys
from pathlib import Path
raw = Path(sys.argv[1]).read_text(encoding="utf-8")
start = raw.find("{")
payload = json.loads(raw[start:])
text = payload["result"]["payloads"][0]["text"]
checks = ["WhatsApp", "lokal", "nächste"]
missing = [item for item in checks if item.lower() not in text.lower()]
if missing:
    raise SystemExit(f"task 1 missing expected concepts: {missing} in {text!r}")
blocked = ["DONE:", "IN ARBEIT:", "failedStep", "stepsCompleted", ".local-agent-last-selftest.json"]
found_blocked = [item for item in blocked if item.lower() in text.lower()]
if found_blocked:
    raise SystemExit(f"task 1 contains internal wording: {found_blocked} in {text!r}")
sentence_count = sum(text.count(mark) for mark in ".!?")
if sentence_count == 0 or sentence_count > 4:
    raise SystemExit(f"task 1 expected 1-4 short sentences, got {sentence_count} in {text!r}")
print(text)
PY
)"
printf '%s\n' "$EVAL_TASK1_TEXT"
assert_latest_session_pattern "main" '"name":"read"'
assert_latest_session_pattern "main" "$SUMMARY_PATH"

echo "== task 2: human next-action question =="
run_main_agent_json "$Q2_JSON" \
  --message "Ich will wissen, was ich als Nächstes tun sollte. Antworte auf Deutsch aus meiner Perspektive mit genau 3 knappen Bulletpoints. Jeder Bullet muss mit '- Ich ' beginnen. Nutze Tools nur wenn nötig und stütze dich auf den letzten Agent-Stand. Keine Testreport-Sprache."

EVAL_TASK2_TEXT="$(python3 - <<'PY' "$Q2_JSON"
import json, sys
from pathlib import Path
raw = Path(sys.argv[1]).read_text(encoding="utf-8")
start = raw.find("{")
payload = json.loads(raw[start:])
text = payload["result"]["payloads"][0]["text"].strip()
lines = [line.strip() for line in text.splitlines() if line.strip()]
bullets = [line for line in lines if line.startswith("- ")]
if len(bullets) != 3:
    raise SystemExit(f"task 2 expected exactly 3 bullets, got {len(bullets)} from {text!r}")
bad = [line for line in bullets if not line.startswith("- Ich ")]
if bad:
    raise SystemExit(f"task 2 must stay in first-person perspective, got {bad!r}")
print(text)
PY
)"
printf '%s\n' "$EVAL_TASK2_TEXT"

echo "== task 3: create user-facing artifact =="
run_main_agent_json "$Q3_JSON" \
  --message "Erstelle für mich eine kurze Team-Statusdatei unter $ARTIFACT_PATH. Inhalt: Überschrift, ein kurzer Abschnitt 'Live-Status', der aktuelle WhatsApp-Token und ein Abschnitt 'Nächster Schritt'. Schreib nutzerfreundlich auf Deutsch, ohne interne Testlabels, ohne DONE/IN ARBEIT und ohne rohe JSON-Feldnamen. Nutze sessions_spawn, wenn ein Spezialagent sinnvoll ist. Antworte exakt mit ARTIFACT_DONE."

run_json_assert "$Q3_JSON" "ARTIFACT_DONE" >/dev/null

python3 - <<'PY' "$ARTIFACT_PATH" "$SUMMARY_PATH"
import json, sys
from pathlib import Path
artifact = Path(sys.argv[1]).read_text(encoding="utf-8")
summary = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
token = summary["whatsappToken"]
required = ["# ", "Live-Status", token, "Nächster Schritt"]
missing = [item for item in required if item not in artifact]
if missing:
    raise SystemExit(f"task 3 artifact missing {missing!r}")
blocked = ["failedStep", "stepsCompleted", ".local-agent-last-selftest.json", "DONE:", "IN ARBEIT:"]
found_blocked = [item for item in blocked if item.lower() in artifact.lower()]
if found_blocked:
    raise SystemExit(f"task 3 artifact contains internal wording: {found_blocked!r}")
print(artifact)
PY

EVAL_STATUS="passed"

echo "== human perspective eval artifacts =="
printf 'status_answer=%s\n' "$Q1_JSON"
printf 'next_steps_answer=%s\n' "$Q2_JSON"
printf 'team_artifact=%s\n' "$ARTIFACT_PATH"
printf 'human_eval_summary=%s\n' "$HUMAN_EVAL_SUMMARY_PATH"
printf 'main_session_id=%s\n' "$MAIN_SESSION_ID"
echo "== local human perspective eval passed =="
