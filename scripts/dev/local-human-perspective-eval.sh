#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
STATE_DIR="${OPENCLAW_STATE_DIR:-$HOME/.openclaw}"
NODE22_BIN="${OPENCLAW_SELFTEST_NODE_BIN:-$HOME/.node22/current/bin}"
SUMMARY_PATH="${OPENCLAW_SELFTEST_SUMMARY_PATH:-$REPO_ROOT/.local-agent-last-selftest.json}"
HUMAN_EVAL_BASE="${OPENCLAW_HUMAN_EVAL_BASE:-$REPO_ROOT/.local-human-eval}"
HUMAN_EVAL_SUMMARY_PATH="${OPENCLAW_HUMAN_EVAL_SUMMARY_PATH:-$REPO_ROOT/.local-agent-last-human-eval.json}"
MAIN_AGENT_ID="${OPENCLAW_HUMAN_MAIN_AGENT_ID:-oc-human-main}"
BUILDER_AGENT_ID="${OPENCLAW_HUMAN_BUILDER_AGENT_ID:-oc-human-builder}"
EVAL_ROOT=""
EVAL_SUMMARY_SNAPSHOT=""
Q1_JSON="$EVAL_ROOT/human-status.json"
Q2_JSON="$EVAL_ROOT/human-plan.json"
Q3_JSON="$EVAL_ROOT/human-artifact.json"
ARTIFACT_PATH="$EVAL_ROOT/team-update.md"
BOOTSTRAP_SCRIPT="$SCRIPT_DIR/bootstrap-local-coding-agents.mjs"
ENSURE_SCRIPT="$SCRIPT_DIR/local-coding-agents-ensure.sh"
EVAL_STARTED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
EVAL_STATUS="failed"
EVAL_FAILED_COMMAND=""
EVAL_TASK1_TEXT=""
EVAL_TASK2_TEXT=""

if [[ -d "$NODE22_BIN" ]]; then
  PATH="$NODE22_BIN:$PATH"
  export PATH
fi

PATH="$REPO_ROOT/scripts/dev:$REPO_ROOT/../claw-code-parity/scripts:$PATH"
export PATH

mkdir -p "$HUMAN_EVAL_BASE"
EVAL_ROOT="$(mktemp -d "$HUMAN_EVAL_BASE/run.XXXXXX")"
EVAL_SUMMARY_SNAPSHOT="$EVAL_ROOT/selftest-summary.json"
Q1_JSON="$EVAL_ROOT/human-status.json"
Q2_JSON="$EVAL_ROOT/human-plan.json"
Q3_JSON="$EVAL_ROOT/human-artifact.json"
ARTIFACT_PATH="$EVAL_ROOT/team-update.md"

source "$SCRIPT_DIR/lib/openclaw-smoke-common.sh"

run_main_agent_json() {
  local output_path="$1"
  shift
  run_openclaw_agent_json "$output_path" --agent "$MAIN_AGENT_ID" --thinking medium "$@"
}

run_builder_agent_json() {
  local output_path="$1"
  shift
  run_openclaw_agent_json "$output_path" --agent "$BUILDER_AGENT_ID" --thinking medium "$@"
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
    "$EVAL_ROOT/summary.json" \
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
    "$MAIN_AGENT_ID" \
    "$BUILDER_AGENT_ID"
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
    "task1Path": sys.argv[9],
    "task2Path": sys.argv[10],
    "task3Path": sys.argv[11],
    "artifactPath": sys.argv[12],
    "failedCommand": sys.argv[13] or None,
    "task1Text": sys.argv[14] or None,
    "task2Text": sys.argv[15] or None,
    "artifactText": sys.argv[16] or None,
    "mainAgentId": sys.argv[17] or None,
    "builderAgentId": sys.argv[18] or None,
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
  exit "$exit_code"
}

trap on_error ERR
trap 'on_exit $?' EXIT

echo "== bootstrap local coding agents =="
node "$BOOTSTRAP_SCRIPT" >/dev/null

echo "== ensure fresh live selftest =="
bash "$ENSURE_SCRIPT" --live >/dev/null

if [[ ! -f "$SUMMARY_PATH" ]]; then
  echo "missing selftest summary at $SUMMARY_PATH" >&2
  exit 1
fi

cp "$SUMMARY_PATH" "$EVAL_SUMMARY_SNAPSHOT"

echo "== task 1: human status question =="
MAIN_SESSION="$(agent_main_session_jsonl "$MAIN_AGENT_ID")"
if [[ -z "$MAIN_SESSION" || ! -f "$MAIN_SESSION" ]]; then
  MAIN_BEFORE_LINES=0
else
  MAIN_BEFORE_LINES="$(session_line_count "$MAIN_SESSION")"
fi
run_main_agent_json "$Q1_JSON" \
  --message "Ich bin der Nutzer. Lies zuerst per read exakt $EVAL_SUMMARY_SNAPSHOT. Sag mir danach auf Deutsch in maximal 4 kurzen Sätzen: Läuft mein lokaler Agent gerade stabil, ist WhatsApp verbunden, und was ist der wichtigste nächste Schritt? Wenn der letzte Test fehlgeschlagen ist oder WhatsApp nicht belegt ist, sag das klar, aber normal. Sprich mit mir wie ein Operator, nicht wie ein Testreport. Verwende keine Labels wie DONE oder IN ARBEIT und nenne keine Dateinamen oder JSON-Feldnamen. Ohne echten read-Toolcall darfst du den Auftrag nicht abschließen."
if [[ -z "$MAIN_SESSION" || ! -f "$MAIN_SESSION" ]]; then
  MAIN_SESSION="$(wait_for_agent_main_session_jsonl "$MAIN_AGENT_ID" 40 1)"
fi

EVAL_TASK1_TEXT="$(python3 - <<'PY' "$Q1_JSON"
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
    raise SystemExit(f"task 1 missing JSON result payload in {sys.argv[1]}")
text = payload["payloads"][0]["text"]
if "whatsapp" not in text.lower():
    raise SystemExit(f"task 1 missing expected concepts in {text!r}")
if not any(token in text.lower() for token in ["lokal", "agent"]):
    raise SystemExit(f"task 1 missing agent/local stability wording in {text!r}")
if not any(token in text.lower() for token in ["schritt", "nächste", "nächstes"]):
    raise SystemExit(f"task 1 missing next-step wording in {text!r}")
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
wait_for_session_pattern_after_line "$MAIN_SESSION" "$MAIN_BEFORE_LINES" '"name":"read"'
wait_for_session_pattern_after_line "$MAIN_SESSION" "$MAIN_BEFORE_LINES" "$EVAL_SUMMARY_SNAPSHOT"

echo "== task 2: human next-action question =="
run_main_agent_json "$Q2_JSON" \
  --message "Ich will wissen, was ich als Nächstes tun sollte. Antworte auf Deutsch aus meiner Perspektive mit genau 3 knappen Bulletpoints. Jeder Bullet muss mit '- Ich ' beginnen. Nutze Tools nur wenn nötig und stütze dich auf den letzten Agent-Stand. Keine Testreport-Sprache."

EVAL_TASK2_TEXT="$(python3 - <<'PY' "$Q2_JSON"
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
    raise SystemExit(f"task 2 missing JSON result payload in {sys.argv[1]}")
text = payload["payloads"][0]["text"].strip()
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
BUILDER_SESSION="$(agent_main_session_jsonl "$BUILDER_AGENT_ID")"
if [[ -z "$BUILDER_SESSION" || ! -f "$BUILDER_SESSION" ]]; then
  BUILDER_BEFORE_LINES=0
else
  BUILDER_BEFORE_LINES="$(session_line_count "$BUILDER_SESSION")"
fi
run_builder_agent_json "$Q3_JSON" \
  --message "Lies zuerst per read exakt $EVAL_SUMMARY_SNAPSHOT. Erstelle oder überschreibe danach exakt die Datei $ARTIFACT_PATH. Inhalt: eine Markdown-Überschrift '# Team-Status', ein kurzer Abschnitt '## Live-Status' und ein kurzer Abschnitt '## Nächster Schritt'. Schreib nutzerfreundlich auf Deutsch, ohne interne Testlabels, ohne DONE/IN ARBEIT und ohne rohe JSON-Feldnamen. Wenn die JSON einen WhatsApp-Token enthält, nenne ihn als normalen Satz im Live-Status. Lies nach dem Schreiben die Datei $ARTIFACT_PATH noch einmal per read zur Verifikation. Antworte exakt mit ARTIFACT_DONE."
if [[ -z "$BUILDER_SESSION" || ! -f "$BUILDER_SESSION" ]]; then
  BUILDER_SESSION="$(wait_for_agent_main_session_jsonl "$BUILDER_AGENT_ID" 40 1)"
fi

run_json_assert "$Q3_JSON" "ARTIFACT_DONE" >/dev/null
wait_for_session_pattern_after_line "$BUILDER_SESSION" "$BUILDER_BEFORE_LINES" '"name":"read"'
wait_for_session_pattern_after_line "$BUILDER_SESSION" "$BUILDER_BEFORE_LINES" "$EVAL_SUMMARY_SNAPSHOT"
if session_pattern_line_after_line "$BUILDER_SESSION" "$BUILDER_BEFORE_LINES" '"name":"sessions_spawn"|"toolName":"sessions_spawn"' >/dev/null; then
  wait_for_session_pattern_after_line "$BUILDER_SESSION" "$BUILDER_BEFORE_LINES" '"name":"sessions_spawn"|"toolName":"sessions_spawn"'
  wait_for_session_pattern_after_line "$BUILDER_SESSION" "$BUILDER_BEFORE_LINES" "agent:${BUILDER_AGENT_ID}:subagent:"
  wait_for_session_pattern_after_line "$BUILDER_SESSION" "$BUILDER_BEFORE_LINES" "$ARTIFACT_PATH"
else
  wait_for_session_pattern_after_line "$BUILDER_SESSION" "$BUILDER_BEFORE_LINES" '"name":"apply_patch"|"name":"edit"|"name":"write"'
  wait_for_session_pattern_after_line "$BUILDER_SESSION" "$BUILDER_BEFORE_LINES" "$ARTIFACT_PATH"
fi

python3 - <<'PY' "$ARTIFACT_PATH" "$EVAL_SUMMARY_SNAPSHOT"
import json, sys
from pathlib import Path
artifact = Path(sys.argv[1]).read_text(encoding="utf-8")
summary = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
token = summary.get("whatsappToken")
required = ["# Team-Status", "Live-Status", "Nächster Schritt"]
if token:
    required.append(token)
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
printf 'main_agent_id=%s\n' "$MAIN_AGENT_ID"
printf 'builder_agent_id=%s\n' "$BUILDER_AGENT_ID"
echo "== local human perspective eval passed =="
