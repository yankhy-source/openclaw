#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
STATE_DIR="${OPENCLAW_STATE_DIR:-$HOME/.openclaw}"
NODE22_BIN="${OPENCLAW_SELFTEST_NODE_BIN:-$HOME/.node22/current/bin}"
SUMMARY_PATH="${OPENCLAW_SELFTEST_SUMMARY_PATH:-$REPO_ROOT/.local-agent-last-selftest.json}"
EVAL_BASE="${OPENCLAW_HUMAN_WHATSAPP_CONVERSATION_EVAL_BASE:-$REPO_ROOT/.local-human-whatsapp-conversation-eval}"
EVAL_SUMMARY_PATH="${OPENCLAW_HUMAN_WHATSAPP_CONVERSATION_EVAL_SUMMARY_PATH:-$REPO_ROOT/.local-agent-last-human-whatsapp-conversation-eval.json}"
MAX_AGE_SECONDS="${OPENCLAW_SELFTEST_MAX_AGE_SECONDS:-21600}"
BOOTSTRAP_SCRIPT="$SCRIPT_DIR/bootstrap-local-coding-agents.mjs"
ENSURE_SCRIPT="$SCRIPT_DIR/local-coding-agents-ensure.sh"
WHATSAPP_AGENT_ID="${OPENCLAW_HUMAN_WHATSAPP_CONVERSATION_AGENT_ID:-main}"
BUILDER_AGENT_ID="${OPENCLAW_HUMAN_WHATSAPP_CONVERSATION_BUILDER_AGENT_ID:-oc-builder}"
SUMMARY_SNAPSHOT_OVERRIDE="${OPENCLAW_HUMAN_WHATSAPP_CONVERSATION_SUMMARY_SNAPSHOT_PATH:-}"
SUMMARY_SNAPSHOT_PATH=""
MAIN_SUMMARY_WORKSPACE_PATH=""
TURN1_SOURCE_PATH=""
EVAL_ROOT=""
TURN1_JSON=""
TURN2_JSON=""
TURN3_JSON=""
ARTIFACT_PATH=""
SELF_E164=""
TURN1_TEXT=""
TURN2_TEXT=""
TURN3_TEXT=""
ARTIFACT_TEXT=""
BUILDER_SESSION=""
ARTIFACT_ROUTE="unknown"
CONVERSATION_MARKER="nebelstern-$(python3 - <<'PY'
import uuid
print(uuid.uuid4().hex[:10])
PY
)"
EVAL_STARTED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
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
TURN2_JSON="$EVAL_ROOT/turn2-plan.json"
TURN3_JSON="$EVAL_ROOT/turn3-artifact.json"
ARTIFACT_PATH="$EVAL_ROOT/team-update.md"

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

cleanup() {
  if [[ -n "$MAIN_SUMMARY_WORKSPACE_PATH" && -f "$MAIN_SUMMARY_WORKSPACE_PATH" ]]; then
    rm -f "$MAIN_SUMMARY_WORKSPACE_PATH"
  fi
}

session_pattern_after_line_with_retry() {
  local session_file="$1"
  local start_line="$2"
  local pattern="$3"
  local attempts="${4:-40}"
  local delay="${5:-1}"

  for _ in $(seq 1 "$attempts"); do
    if [[ -n "$session_file" && -f "$session_file" ]] && session_pattern_line_after_line "$session_file" "$start_line" "$pattern" >/dev/null; then
      return 0
    fi
    sleep "$delay"
  done
  return 1
}

resolve_child_session_after_line() {
  local main_session="$1"
  local start_line="$2"
  local agent_id="$3"
  local target_path="$4"
  local attempts="${5:-40}"
  local delay="${6:-1}"
  local child_session=""

  for _ in $(seq 1 "$attempts"); do
    child_session="$(child_session_file_from_main_after_line "$main_session" "$start_line" "$agent_id" "$target_path")"
    if [[ -n "$child_session" && -f "$child_session" ]]; then
      printf '%s\n' "$child_session"
      return 0
    fi
    sleep "$delay"
  done
  return 1
}

wait_for_valid_artifact() {
  local artifact_path="$1"
  local marker="$2"
  local attempts="${3:-180}"
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
required = ["# Team-Update", "## Stand", "## Nächste Schritte"]
missing = [item for item in required if item not in text]
if missing:
    raise SystemExit(1)
if text.count(marker) != 1:
    raise SystemExit(1)
blocked = [
    ".local-agent-last-selftest.json",
    ".local-agent-last-human-whatsapp-eval.json",
    ".local-agent-last-human-whatsapp-conversation-eval.json",
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
required = ["# Team-Update", "## Stand", "## Nächste Schritte"]
missing = [item for item in required if item not in text]
if missing:
    raise SystemExit(f"artifact missing headings {missing!r}: {text!r}")
if text.count(marker) != 1:
    raise SystemExit(f"artifact must contain marker exactly once: {marker!r} in {text!r}")
blocked = [
    ".local-agent-last-selftest.json",
    ".local-agent-last-human-whatsapp-eval.json",
    ".local-agent-last-human-whatsapp-conversation-eval.json",
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
    "$TURN3_JSON" \
    "$ARTIFACT_PATH" \
    "$CONVERSATION_MARKER" \
    "$EVAL_FAILED_COMMAND" \
    "$TURN1_TEXT" \
    "$TURN2_TEXT" \
    "$TURN3_TEXT" \
    "$ARTIFACT_TEXT" \
    "$ARTIFACT_ROUTE" \
    "$SELF_E164" \
    "$WHATSAPP_AGENT_ID" \
    "$BUILDER_AGENT_ID" \
    "$BUILDER_SESSION"
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
    "turn3Path": sys.argv[11],
    "artifactPath": sys.argv[12],
    "conversationMarker": sys.argv[13],
    "failedCommand": sys.argv[14] or None,
    "turn1Text": sys.argv[15] or None,
    "turn2Text": sys.argv[16] or None,
    "turn3Text": sys.argv[17] or None,
    "artifactText": sys.argv[18] or None,
    "artifactRoute": sys.argv[19] or None,
    "selfE164": sys.argv[20] or None,
    "mainAgentId": sys.argv[21] or None,
    "builderAgentId": sys.argv[22] or None,
    "builderSessionPath": sys.argv[23] or None,
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
bash "$ENSURE_SCRIPT" --live --max-age-seconds "$MAX_AGE_SECONDS" >/dev/null

if [[ ! -f "$SUMMARY_PATH" ]]; then
  echo "missing selftest summary at $SUMMARY_PATH" >&2
  exit 1
fi

cp "$SUMMARY_PATH" "$SUMMARY_SNAPSHOT_PATH"
printf 'before\n' >"$ARTIFACT_PATH"
TURN1_SOURCE_PATH="$SUMMARY_SNAPSHOT_PATH"
if [[ "$WHATSAPP_AGENT_ID" == "main" ]]; then
  MAIN_SUMMARY_WORKSPACE_PATH="$(workspace_mirror_file "$SUMMARY_SNAPSHOT_PATH" "human-whatsapp-conversation-summary" "selftest-summary.json")"
  TURN1_SOURCE_PATH="$MAIN_SUMMARY_WORKSPACE_PATH"
fi

echo "== gateway health =="
openclaw_ensure_gateway_healthy >/dev/null

SELF_E164="$(openclaw_whatsapp_self_e164)"

echo "== whatsapp conversation turn 1 =="
MAIN_SESSION="$(agent_main_session_jsonl "$WHATSAPP_AGENT_ID")"
if [[ -z "$MAIN_SESSION" || ! -f "$MAIN_SESSION" ]]; then
  MAIN_BEFORE_LINES=0
else
  MAIN_BEFORE_LINES="$(session_line_count "$MAIN_SESSION")"
fi
run_main_whatsapp_json "$TURN1_JSON" \
  --message "Ich bin der Nutzer. Lies zuerst per read exakt $TURN1_SOURCE_PATH. Antworte danach auf Deutsch in genau 3 kurzen Sätzen: Läuft mein lokaler Agent stabil, ist WhatsApp verbunden, und was ist der wichtigste nächste Schritt? Baue das Merkwort $CONVERSATION_MARKER genau einmal als normales Wort ein. Keine Testreport-Sprache, keine Dateinamen, keine JSON-Feldnamen, keine Labels wie DONE oder IN ARBEIT. Ohne echten read-Toolcall darfst du den Auftrag nicht abschließen."
if [[ -z "$MAIN_SESSION" || ! -f "$MAIN_SESSION" ]]; then
  MAIN_SESSION="$(wait_for_agent_main_session_jsonl "$WHATSAPP_AGENT_ID" 40 1)"
fi
TURN1_TEXT="$(python3 - <<'PY' "$TURN1_JSON" "$CONVERSATION_MARKER"
import json, sys
from pathlib import Path

raw = Path(sys.argv[1]).read_text(encoding="utf-8")
marker = sys.argv[2]
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
    raise SystemExit(f"turn 1 missing JSON result payload in {sys.argv[1]}")
texts = [item.get("text", "") for item in payload["payloads"] if item.get("text")]
text = texts[-1]
if "✅ Subagent " in text:
    text = text.split("✅ Subagent ", 1)[0]
text = text.strip()
if not all(term in text.lower() for term in ["whatsapp", "lokal"]):
    raise SystemExit(f"turn 1 missing core concepts in {text!r}")
if not any(term in text.lower() for term in ["schritt", "nächste", "nächstes"]):
    raise SystemExit(f"turn 1 missing next-step wording in {text!r}")
if text.count(marker) != 1:
    raise SystemExit(f"turn 1 must contain marker exactly once: {marker!r} in {text!r}")
blocked = [
    "DONE:",
    "IN ARBEIT:",
    ".local-agent-last-selftest.json",
    "failedStep",
    "stepsCompleted",
]
found = [item for item in blocked if item.lower() in text.lower()]
if found:
    raise SystemExit(f"turn 1 contains internal wording {found!r}: {text!r}")
sentence_count = sum(text.count(mark) for mark in ".!?")
if sentence_count != 3:
    raise SystemExit(f"turn 1 expected exactly 3 sentences, got {sentence_count} in {text!r}")
print(text)
PY
)"
printf '%s\n' "$TURN1_TEXT"
wait_for_session_pattern_after_line "$MAIN_SESSION" "$MAIN_BEFORE_LINES" '"name":"read"|"toolName":"read"'
wait_for_session_pattern_after_line "$MAIN_SESSION" "$MAIN_BEFORE_LINES" "$TURN1_SOURCE_PATH"

echo "== whatsapp conversation turn 2 =="
TURN2_BEFORE_LINES="$(session_line_count "$MAIN_SESSION")"
run_main_whatsapp_json "$TURN2_JSON" \
  --message "Behalte den bisherigen Gesprächskontext. Antworte jetzt auf Deutsch mit genau 3 knappen Bulletpoints aus meiner Perspektive. Jede Zeile muss mit '- Ich ' beginnen. Verwende das Merkwort von eben genau einmal wieder, ohne dass ich es erneut nenne. Keine Testreport-Sprache, keine Dateinamen, keine JSON-Feldnamen, keine Labels wie DONE oder IN ARBEIT."
TURN2_TEXT="$(python3 - <<'PY' "$TURN2_JSON" "$CONVERSATION_MARKER"
import json, sys
from pathlib import Path

raw = Path(sys.argv[1]).read_text(encoding="utf-8")
marker = sys.argv[2]
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
    raise SystemExit(f"turn 2 missing JSON result payload in {sys.argv[1]}")
texts = [item.get("text", "") for item in payload["payloads"] if item.get("text")]
text = texts[-1]
if "✅ Subagent " in text:
    text = text.split("✅ Subagent ", 1)[0]
text = text.strip()
lines = [line.strip() for line in text.splitlines() if line.strip()]
bullets = [line for line in lines if line.startswith("- ")]
if len(bullets) != 3:
    raise SystemExit(f"turn 2 expected exactly 3 bullets, got {len(bullets)} in {text!r}")
bad = [line for line in bullets if not line.startswith("- Ich ")]
if bad:
    raise SystemExit(f"turn 2 must stay in first person, got {bad!r}")
if text.count(marker) != 1:
    raise SystemExit(f"turn 2 must reuse marker exactly once: {marker!r} in {text!r}")
blocked = ["DONE:", "IN ARBEIT:", ".local-agent-last-selftest.json", "failedStep", "stepsCompleted"]
found = [item for item in blocked if item.lower() in text.lower()]
if found:
    raise SystemExit(f"turn 2 contains internal wording {found!r}: {text!r}")
print(text)
PY
)"
printf '%s\n' "$TURN2_TEXT"

echo "== whatsapp conversation turn 3 =="
TURN3_BEFORE_LINES="$(session_line_count "$MAIN_SESSION")"
run_main_whatsapp_json "$TURN3_JSON" \
  --message "Erstell mir jetzt einen kurzen Team-Update-Entwurf als Datei. Nutze dafür zwingend per sessions_spawn einen $BUILDER_AGENT_ID-Subagenten. Nur der $BUILDER_AGENT_ID-Subagent darf die Datei ändern; du selbst darfst $ARTIFACT_PATH nicht direkt schreiben oder überschreiben. Der Child-Task muss zuerst per read exakt $SUMMARY_SNAPSHOT_PATH lesen und danach exakt die bereits existierende Datei $ARTIFACT_PATH überschreiben. Inhalt: Markdown mit '# Team-Update', '## Stand' und '## Nächste Schritte'. Schreib kurz, freundlich und auf Deutsch. Nutze das Merkwort aus dem bisherigen Gespräch genau einmal im Dateiinhalt, ohne dass ich es neu nenne. Keine Testreport-Sprache, keine Dateinamen, keine JSON-Feldnamen, keine Labels wie DONE oder IN ARBEIT. Lies die geschriebene Datei danach noch einmal per read zur Verifikation. Antworte mir danach auf Deutsch in genau 1 kurzen Satz, dass der Entwurf jetzt erstellt wird und gleich bereit ist. Nenne keine Dateipfade und verwende das Merkwort in der Chat-Antwort nicht erneut."
TURN3_TEXT="$(python3 - <<'PY' "$TURN3_JSON" "$CONVERSATION_MARKER" "$ARTIFACT_PATH"
import json, sys
from pathlib import Path

raw = Path(sys.argv[1]).read_text(encoding="utf-8")
marker = sys.argv[2]
artifact_path = sys.argv[3]
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
    raise SystemExit(f"turn 3 missing JSON result payload in {sys.argv[1]}")
texts = [item.get("text", "") for item in payload["payloads"] if item.get("text")]
text = texts[-1]
if "✅ Subagent " in text:
    text = text.split("✅ Subagent ", 1)[0]
text = text.strip()
if text.count(marker) != 0:
    raise SystemExit(f"turn 3 chat reply must not repeat marker {marker!r}: {text!r}")
if artifact_path in text:
    raise SystemExit(f"turn 3 chat reply leaked artifact path {artifact_path!r}: {text!r}")
if not any(term in text.lower() for term in ["entwurf", "update"]):
    raise SystemExit(f"turn 3 chat reply must mention the artifact in normal language: {text!r}")
if not any(term in text.lower() for term in ["erstellt", "gleich", "bereit"]):
    raise SystemExit(f"turn 3 chat reply must confirm the delegated creation path: {text!r}")
blocked = ["DONE:", "IN ARBEIT:", ".local-agent-last-selftest.json", "failedStep", "stepsCompleted"]
found = [item for item in blocked if item.lower() in text.lower()]
if found:
    raise SystemExit(f"turn 3 contains internal wording {found!r}: {text!r}")
sentence_count = sum(text.count(mark) for mark in ".!?")
if sentence_count != 1:
    raise SystemExit(f"turn 3 expected exactly 1 sentence, got {sentence_count} in {text!r}")
print(text)
PY
)"
printf '%s\n' "$TURN3_TEXT"

if session_pattern_after_line_with_retry "$MAIN_SESSION" "$TURN3_BEFORE_LINES" '"name":"sessions_spawn"|"toolName":"sessions_spawn"' 120 1; then
  if BUILDER_SESSION="$(resolve_child_session_after_line "$MAIN_SESSION" "$TURN3_BEFORE_LINES" "$BUILDER_AGENT_ID" "$ARTIFACT_PATH" 120 1)"; then
    ARTIFACT_ROUTE="builder"
  fi
fi

if [[ "$ARTIFACT_ROUTE" == "unknown" ]]; then
  session_pattern_after_line_with_retry "$MAIN_SESSION" "$TURN3_BEFORE_LINES" "$ARTIFACT_PATH" 120 1 || {
    echo "turn 3 did not reference artifact path in main session" >&2
    exit 1
  }
  session_pattern_after_line_with_retry "$MAIN_SESSION" "$TURN3_BEFORE_LINES" '"name":"apply_patch"|"name":"edit"|"name":"write"|"name":"exec"|"toolName":"apply_patch"|"toolName":"edit"|"toolName":"write"|"toolName":"exec"' 120 1 || {
    echo "turn 3 did not produce any main-session write path" >&2
    exit 1
  }
  ARTIFACT_ROUTE="main_direct"
fi

wait_for_valid_artifact "$ARTIFACT_PATH" "$CONVERSATION_MARKER" 180 1
ARTIFACT_TEXT="$(cat "$ARTIFACT_PATH")"

if [[ "$ARTIFACT_ROUTE" == "builder" ]]; then
  wait_for_session_pattern_after_line "$BUILDER_SESSION" 0 '"provider":"openai-codex"' 120 1
  wait_for_session_pattern_after_line "$BUILDER_SESSION" 0 '"model":"gpt-5.3-codex-spark"' 120 1
  wait_for_session_pattern_after_line "$BUILDER_SESSION" 0 "$SUMMARY_SNAPSHOT_PATH" 120 1
  wait_for_session_pattern_after_line "$BUILDER_SESSION" 0 '"name":"apply_patch"|"name":"edit"|"name":"write"|"name":"exec"|"toolName":"apply_patch"|"toolName":"edit"|"toolName":"write"|"toolName":"exec"' 120 1
  wait_for_session_pattern_after_line "$BUILDER_SESSION" 0 "$ARTIFACT_PATH" 120 1
  wait_for_session_pattern_after_line "$BUILDER_SESSION" 0 '"name":"read"|"name":"exec"|"toolName":"read"|"toolName":"exec"' 120 1
else
  wait_for_session_pattern_after_line "$MAIN_SESSION" "$TURN3_BEFORE_LINES" "$ARTIFACT_PATH" 120 1
  wait_for_session_pattern_after_line "$MAIN_SESSION" "$TURN3_BEFORE_LINES" '"name":"apply_patch"|"name":"edit"|"name":"write"|"name":"exec"|"toolName":"apply_patch"|"toolName":"edit"|"toolName":"write"|"toolName":"exec"' 120 1
fi

EVAL_STATUS="passed"

echo "== human whatsapp conversation eval artifacts =="
printf 'turn1_answer=%s\n' "$TURN1_JSON"
printf 'turn2_answer=%s\n' "$TURN2_JSON"
printf 'turn3_answer=%s\n' "$TURN3_JSON"
printf 'artifact_path=%s\n' "$ARTIFACT_PATH"
printf 'conversation_summary=%s\n' "$EVAL_SUMMARY_PATH"
printf 'conversation_marker=%s\n' "$CONVERSATION_MARKER"
printf 'artifact_route=%s\n' "$ARTIFACT_ROUTE"
echo "== local human whatsapp conversation eval passed =="

cleanup
