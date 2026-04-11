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
SOURCE_AGENT_ID="${OPENCLAW_HUMAN_WHATSAPP_RESUME_FAILURE_SOURCE_AGENT_ID:-oc-human-source}"
RECOVERY_AGENT_ID="${OPENCLAW_HUMAN_WHATSAPP_RESUME_FAILURE_RECOVERY_AGENT_ID:-oc-human-recovery}"
SUMMARY_SNAPSHOT_OVERRIDE="${OPENCLAW_HUMAN_WHATSAPP_RESUME_FAILURE_SUMMARY_SNAPSHOT_PATH:-}"
SUMMARY_SNAPSHOT_PATH=""
SOURCE_SUMMARY_WORKSPACE_PATH=""
SOURCE_TURN_PATH=""
EVAL_ROOT=""
TURN1_JSON=""
TURN2_JSON=""
TOOL_MODEL_PRECHECK_JSON=""
TOOL_MODEL_PRECHECK_PATH=""
TOOL_MODEL_PRECHECK_REL=""
ARTIFACT_PATH=""
ARTIFACT_REL=""
RECOVERY_CONTEXT_PATH=""
RECOVERY_CONTEXT_REPORT_PATH=""
CONFLICT_NOTE_PATH=""
CONFLICT_NOTE_REL=""
CONFLICT_NOTE_TEXT=""
TOOL_MODEL_PRECHECK_TEXT=""
TOOL_MODEL_PRECHECK_PROVIDER=""
TOOL_MODEL_PRECHECK_MODEL=""
TOOL_MODEL_BLOCKED_REASON=""
SELF_E164=""
TURN1_TEXT=""
TURN2_TEXT=""
ARTIFACT_TEXT=""
RECOVERY_CONTEXT_MODE="history_only"
VERIFIED_WHATSAPP_TOKEN=""
VERIFIED_MANAGER_SESSION_ID=""
VERIFIED_SELFTEST_ARTIFACT_ROOT=""
RECOVERY_CONTEXT_REPORT_STATUS=""
RECOVERY_CONTEXT_REPORT_REASON_CODES=""
RECOVERY_CONTEXT_REPORT_REASON_SUMMARY=""
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
CONFLICT_MARKER="nebelstern-falsch-$(python3 - <<'PY'
import uuid
print(uuid.uuid4().hex[:8])
PY
)"
CONFLICT_TAG="resume-failure-falsch-$(python3 - <<'PY'
import uuid
print(uuid.uuid4().hex[:8])
PY
)"
TOOL_MODEL_PRECHECK_TOKEN="toolmodell-$(python3 - <<'PY'
import uuid
print(uuid.uuid4().hex[:10])
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
TOOL_MODEL_PRECHECK_JSON="$EVAL_ROOT/tool-model-preflight.json"
TOOL_MODEL_PRECHECK_PATH="$EVAL_ROOT/tool-model-preflight.txt"
TOOL_MODEL_PRECHECK_REL="${TOOL_MODEL_PRECHECK_PATH#"$REPO_ROOT/"}"
ARTIFACT_PATH="$EVAL_ROOT/recovery-note.md"
ARTIFACT_REL="${ARTIFACT_PATH#"$REPO_ROOT/"}"
RECOVERY_CONTEXT_PATH="$EVAL_ROOT/recovery-context.json"
RECOVERY_CONTEXT_REPORT_PATH="$EVAL_ROOT/recovery-consistency.json"
CONFLICT_NOTE_PATH="$EVAL_ROOT/conflicting-note.md"
CONFLICT_NOTE_REL="${CONFLICT_NOTE_PATH#"$REPO_ROOT/"}"

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

extract_agent_meta_field() {
  local json_path="$1"
  local field="$2"
  python3 - <<'PY' "$json_path" "$field"
import json, sys
from pathlib import Path

json_path = Path(sys.argv[1])
field = sys.argv[2]
raw = json_path.read_text(encoding="utf-8")
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
    raise SystemExit(1)
meta = payload.get("meta", {}).get("agentMeta", {})
value = meta.get(field)
if value is None:
    raise SystemExit(1)
print(value)
PY
}

block_tool_model_precheck() {
  TOOL_MODEL_BLOCKED_REASON="$1"
  EVAL_STATUS="blocked"
  EVAL_FAILED_COMMAND="$1"
  printf 'tool model preflight blocked: %s\n' "$1" >&2
  exit 2
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
  local source_tag="$3"
  local conflict_marker="$4"
  local conflict_tag="$5"
  python3 - <<'PY' "$artifact_path" "$marker" "$source_tag" "$conflict_marker" "$conflict_tag"
from pathlib import Path
import sys

artifact_path = Path(sys.argv[1])
marker = sys.argv[2]
source_tag = sys.argv[3]
conflict_marker = sys.argv[4]
conflict_tag = sys.argv[5]
if not artifact_path.is_file():
    raise SystemExit(f"artifact was not created: {artifact_path}")
text = artifact_path.read_text(encoding="utf-8")
required = ["# Recovery Note", "## Rekonstruktion", "## Konsistenzprüfung", "## Nächster Schritt"]
missing = [item for item in required if item not in text]
if missing:
    raise SystemExit(f"artifact missing headings {missing!r}: {text!r}")
if text.count(marker) != 1:
    raise SystemExit(f"artifact must contain marker exactly once: {marker!r} in {text!r}")
if text.count(source_tag) != 1:
    raise SystemExit(f"artifact must contain source tag exactly once: {source_tag!r} in {text!r}")
if conflict_marker in text or conflict_tag in text:
    raise SystemExit(f"artifact leaked rejected conflict values: {text!r}")
if not any(term in text.lower() for term in ["widerspruch", "verworfen", "history", "historie"]):
    raise SystemExit(f"artifact must explain the conflict rejection: {text!r}")
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

archive_agent_sessions_for_eval() {
  local agent_id="$1"
  local label="$2"
  local session_dir="$STATE_DIR/agents/$agent_id/sessions"
  local archive_dir="$EVAL_ROOT/archived-$label-sessions"
  if [[ ! -d "$session_dir" ]]; then
    mkdir -p "$session_dir"
    return 0
  fi

  shopt -s nullglob
  local files=("$session_dir"/*)
  shopt -u nullglob
  if ((${#files[@]} == 0)); then
    return 0
  fi

  mkdir -p "$archive_dir"
  mv "${files[@]}" "$archive_dir"/
  mkdir -p "$session_dir"
}

session_tool_result_line_after_line() {
  local session_file="$1"
  local start_line="$2"
  local tool_name="$3"
  local content_substring="$4"
  python3 - <<'PY' "$session_file" "$start_line" "$tool_name" "$content_substring"
import json
import sys
from pathlib import Path

session_file = Path(sys.argv[1])
start_line = int(sys.argv[2])
tool_name = sys.argv[3]
content_substring = sys.argv[4]
if not session_file.is_file():
    raise SystemExit(1)
with session_file.open("r", encoding="utf-8") as handle:
    for line_number, raw_line in enumerate(handle, start=1):
        if line_number <= start_line:
            continue
        try:
            entry = json.loads(raw_line)
        except json.JSONDecodeError:
            continue
        message = entry.get("message") or {}
        if message.get("role") != "toolResult" or message.get("toolName") != tool_name:
            continue
        content = "".join(
            part.get("text", "")
            for part in message.get("content") or []
            if isinstance(part, dict) and part.get("type") == "text"
        )
        if content_substring in content:
            print(line_number)
            raise SystemExit(0)
raise SystemExit(1)
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
    "$TOOL_MODEL_PRECHECK_JSON" \
    "$TOOL_MODEL_PRECHECK_PATH" \
    "$TOOL_MODEL_PRECHECK_REL" \
    "$TOOL_MODEL_PRECHECK_TOKEN" \
    "$TOOL_MODEL_PRECHECK_TEXT" \
    "$TOOL_MODEL_PRECHECK_PROVIDER" \
    "$TOOL_MODEL_PRECHECK_MODEL" \
    "$TOOL_MODEL_BLOCKED_REASON" \
    "$CONFLICT_NOTE_PATH" \
    "$CONFLICT_NOTE_REL" \
    "$CONFLICT_NOTE_TEXT" \
    "$CONFLICT_MARKER" \
    "$CONFLICT_TAG" \
    "$SELF_E164" \
    "$SOURCE_AGENT_ID" \
    "$RECOVERY_AGENT_ID" \
    "$VERIFIED_WHATSAPP_TOKEN" \
    "$VERIFIED_MANAGER_SESSION_ID" \
    "$RECOVERY_CONTEXT_MODE" \
    "$RECOVERY_CONTEXT_REPORT_PATH" \
    "$RECOVERY_CONTEXT_REPORT_STATUS" \
    "$RECOVERY_CONTEXT_REPORT_REASON_CODES" \
    "$RECOVERY_CONTEXT_REPORT_REASON_SUMMARY"
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
    "toolModelPrecheckPath": sys.argv[23] or None,
    "toolModelPrecheckProbePath": sys.argv[24] or None,
    "toolModelPrecheckProbeRelativePath": sys.argv[25] or None,
    "toolModelPrecheckToken": sys.argv[26] or None,
    "toolModelPrecheckText": sys.argv[27] or None,
    "toolModelPrecheckProvider": sys.argv[28] or None,
    "toolModelPrecheckModel": sys.argv[29] or None,
    "toolModelBlockedReason": sys.argv[30] or None,
    "conflictNotePath": sys.argv[31] or None,
    "conflictNoteRelativePath": sys.argv[32] or None,
    "conflictNoteText": sys.argv[33] or None,
    "conflictMarker": sys.argv[34] or None,
    "conflictTag": sys.argv[35] or None,
    "selfE164": sys.argv[36] or None,
    "sourceAgentId": sys.argv[37] or None,
    "recoveryAgentId": sys.argv[38] or None,
    "verifiedWhatsappToken": sys.argv[39] or None,
    "verifiedManagerSessionId": sys.argv[40] or None,
    "recoveryContextMode": sys.argv[41] or None,
    "recoveryContextReportPath": sys.argv[42] or None,
    "recoveryContextReportStatus": sys.argv[43] or None,
    "recoveryContextReportReasonCodes": sys.argv[44] or None,
    "recoveryContextReportReasonSummary": sys.argv[45] or None,
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

archive_agent_sessions_for_eval "$SOURCE_AGENT_ID" "source"
archive_agent_sessions_for_eval "$RECOVERY_AGENT_ID" "recovery"

echo "== ensure fresh live selftest =="
set +e
bash "$ENSURE_SCRIPT" --live --max-age-seconds "$MAX_AGE_SECONDS" >/dev/null
ENSURE_EXIT_CODE="$?"
set -e
if [[ "$ENSURE_EXIT_CODE" -ne 0 ]]; then
  SELFTEST_STATUS="$(python3 - <<'PY' "$SUMMARY_PATH" || true
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
if not path.is_file():
    raise SystemExit(1)
payload = json.loads(path.read_text(encoding="utf-8"))
print(payload.get("status") or "")
PY
)"
  if [[ "$ENSURE_EXIT_CODE" -eq 2 || "$SELFTEST_STATUS" == "blocked" ]]; then
    EVAL_STATUS="blocked"
    EVAL_FAILED_COMMAND="fresh live selftest prerequisite blocked (${SELFTEST_STATUS:-unknown})"
    exit 2
  fi
  EVAL_FAILED_COMMAND="fresh live selftest prerequisite failed (${SELFTEST_STATUS:-unknown})"
  exit "$ENSURE_EXIT_CODE"
fi

if [[ ! -f "$SUMMARY_PATH" ]]; then
  echo "missing selftest summary at $SUMMARY_PATH" >&2
  exit 1
fi

cp "$SUMMARY_PATH" "$SUMMARY_SNAPSHOT_PATH"
eval "$(verify_live_selftest_summary_snapshot "$SUMMARY_SNAPSHOT_PATH")"
SOURCE_TURN_PATH="$SUMMARY_SNAPSHOT_PATH"
if [[ "$SOURCE_AGENT_ID" == "main" ]]; then
  SOURCE_SUMMARY_WORKSPACE_PATH="$(workspace_mirror_file "$SUMMARY_SNAPSHOT_PATH" "human-whatsapp-resume-failure-summary" "selftest-summary.json")"
  SOURCE_TURN_PATH="$SOURCE_SUMMARY_WORKSPACE_PATH"
fi

mkdir -p "$(dirname "$ARTIFACT_PATH")"
printf 'before\n' >"$ARTIFACT_PATH"
CONFLICT_NOTE_TEXT="$(python3 - <<'PY' "$CONFLICT_NOTE_PATH" "$CONFLICT_MARKER" "$CONFLICT_TAG"
from pathlib import Path
import sys

path = Path(sys.argv[1])
marker = sys.argv[2]
tag = sys.argv[3]
text = (
    "# Konflikt-Notiz\n\n"
    "Diese absichtlich falsche Notiz behauptet einen anderen Lauf.\n\n"
    f"Kennung: {tag}\n"
    f"Merkwort: {marker}\n\n"
    "Diese Werte sind nur eine negative Gegenprobe und dürfen nicht in die Antwort übernommen werden.\n"
)
path.write_text(text, encoding="utf-8")
print(text)
PY
)"

echo "== gateway health =="
openclaw_ensure_gateway_healthy >/dev/null
SELF_E164="$(openclaw_whatsapp_self_e164)"

echo "== tool model preflight =="
printf '%s\n' "$TOOL_MODEL_PRECHECK_TOKEN" >"$TOOL_MODEL_PRECHECK_PATH"
RECOVERY_PREFLIGHT_SESSION="$(agent_main_session_jsonl "$RECOVERY_AGENT_ID")"
if [[ -z "$RECOVERY_PREFLIGHT_SESSION" || ! -f "$RECOVERY_PREFLIGHT_SESSION" ]]; then
  RECOVERY_PREFLIGHT_BEFORE_LINES=0
else
  RECOVERY_PREFLIGHT_BEFORE_LINES="$(session_line_count "$RECOVERY_PREFLIGHT_SESSION")"
fi
if ! run_openclaw_agent_json "$TOOL_MODEL_PRECHECK_JSON" \
  --agent "$RECOVERY_AGENT_ID" \
  --thinking medium \
  --message "Preflight für einen toolkritischen Recovery-Test. Rufe sessions_history für sessionKey $SOURCE_SESSION_KEY mit includeTools=true und limit 1 auf. Lies danach exakt die Datei $TOOL_MODEL_PRECHECK_REL per read. Antworte exakt mit dem Dateiinhalt, eine Zeile, kein Zusatztext. Ohne beide Toolcalls darfst du nicht abschließen."; then
  if [[ -f "$TOOL_MODEL_PRECHECK_JSON" ]]; then
    TOOL_MODEL_PRECHECK_PROVIDER="$(extract_agent_meta_field "$TOOL_MODEL_PRECHECK_JSON" provider || true)"
    TOOL_MODEL_PRECHECK_MODEL="$(extract_agent_meta_field "$TOOL_MODEL_PRECHECK_JSON" model || true)"
  fi
  block_tool_model_precheck "no text result from a tool-capable recovery model; current providers are unavailable or fell back to a non-tool runtime"
fi
if [[ -z "$RECOVERY_PREFLIGHT_SESSION" || ! -f "$RECOVERY_PREFLIGHT_SESSION" ]]; then
  RECOVERY_PREFLIGHT_SESSION="$(wait_for_agent_main_session_jsonl "$RECOVERY_AGENT_ID" 40 1)"
fi
TOOL_MODEL_PRECHECK_TEXT="$(extract_result_text "$TOOL_MODEL_PRECHECK_JSON")"
TOOL_MODEL_PRECHECK_PROVIDER="$(extract_agent_meta_field "$TOOL_MODEL_PRECHECK_JSON" provider || true)"
TOOL_MODEL_PRECHECK_MODEL="$(extract_agent_meta_field "$TOOL_MODEL_PRECHECK_JSON" model || true)"
if [[ "$TOOL_MODEL_PRECHECK_TEXT" != "$TOOL_MODEL_PRECHECK_TOKEN" ]]; then
  block_tool_model_precheck "preflight returned unexpected text from ${TOOL_MODEL_PRECHECK_PROVIDER:-unknown}/${TOOL_MODEL_PRECHECK_MODEL:-unknown}"
fi
if ! session_pattern_line_after_line "$RECOVERY_PREFLIGHT_SESSION" "$RECOVERY_PREFLIGHT_BEFORE_LINES" '"name":"sessions_history"|"toolName":"sessions_history"' >/dev/null; then
  block_tool_model_precheck "preflight completed without a sessions_history toolcall from ${TOOL_MODEL_PRECHECK_PROVIDER:-unknown}/${TOOL_MODEL_PRECHECK_MODEL:-unknown}"
fi
if ! session_pattern_line_after_line "$RECOVERY_PREFLIGHT_SESSION" "$RECOVERY_PREFLIGHT_BEFORE_LINES" '"name":"read"|"toolName":"read"' >/dev/null; then
  block_tool_model_precheck "preflight completed without a read toolcall from ${TOOL_MODEL_PRECHECK_PROVIDER:-unknown}/${TOOL_MODEL_PRECHECK_MODEL:-unknown}"
fi
if [[ "$TOOL_MODEL_PRECHECK_PROVIDER" == "heretic-local" ]]; then
  block_tool_model_precheck "preflight reached heretic-local; this eval requires a tool-reliable remote coding model"
fi
archive_agent_sessions_for_eval "$RECOVERY_AGENT_ID" "recovery-after-preflight"
printf 'tool_model_provider=%s/%s\n' "$TOOL_MODEL_PRECHECK_PROVIDER" "$TOOL_MODEL_PRECHECK_MODEL"

echo "== resume-failure source turn =="
SOURCE_SESSION="$(agent_main_session_jsonl "$SOURCE_AGENT_ID")"
if [[ -z "$SOURCE_SESSION" || ! -f "$SOURCE_SESSION" ]]; then
  SOURCE_BEFORE_LINES=0
else
  SOURCE_BEFORE_LINES="$(session_line_count "$SOURCE_SESSION")"
fi
run_source_whatsapp_json "$TURN1_JSON" \
  --message "Ich bin der Nutzer. Das ist die Resume-Failure-Quelle mit Kennung $SOURCE_TAG. Antworte auf Deutsch in 2-3 kurzen Sätzen: bestätige, dass wir diesen Recovery-Kontext fortsetzen, und sag, welches Merkwort wir jetzt nutzen. Verwende das Merkwort $RESUME_FAILURE_MARKER genau einmal. Keine Testreport-Sprache, keine Dateinamen, keine JSON-Feldnamen, keine Labels wie DONE oder IN ARBEIT."
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
if not any(term in text.lower() for term in ["recovery", "kontext", "fortsetzen", "weiter"]):
    raise SystemExit(f"turn 1 missing recovery/context wording in {text!r}")
if text.count(marker) != 1:
    raise SystemExit(f"turn 1 must contain marker exactly once: {marker!r} in {text!r}")
blocked = ["DONE:", "IN ARBEIT:", ".local-agent-last-selftest.json", "failedStep", "stepsCompleted"]
found = [item for item in blocked if item.lower() in text.lower()]
if found:
    raise SystemExit(f"turn 1 contains internal wording {found!r}: {text!r}")
sentence_count = sum(text.count(mark) for mark in ".!?")
if sentence_count not in (2, 3):
    raise SystemExit(f"turn 1 expected 2-3 short sentences, got {sentence_count} in {text!r}")
PY
printf '%s\n' "$TURN1_TEXT"
wait_for_session_pattern_after_line "$SOURCE_SESSION" "$SOURCE_BEFORE_LINES" "$SOURCE_TAG"
python3 - <<'PY' \
  "$RECOVERY_CONTEXT_PATH" \
  "$SUMMARY_SNAPSHOT_PATH" \
  "$TURN1_JSON" \
  "$ARTIFACT_PATH" \
  "$CONFLICT_NOTE_PATH" \
  "$SOURCE_SESSION_KEY" \
  "$SOURCE_TAG" \
  "$RESUME_FAILURE_MARKER" \
  "$SELF_E164" \
  "$VERIFIED_WHATSAPP_TOKEN" \
  "$VERIFIED_MANAGER_SESSION_ID" \
  "$TOOL_MODEL_PRECHECK_TOKEN"
import json
import pathlib
import sys

(
    context_path,
    summary_snapshot_path,
    turn1_path,
    artifact_path,
    conflict_note_path,
    source_session_key,
    source_tag,
    resume_marker,
    self_e164,
    whatsapp_token,
    manager_session_id,
    tool_model_precheck_token,
) = sys.argv[1:13]

payload = {
    "kind": "resume-failure-recovery",
    "summarySnapshotPath": summary_snapshot_path,
    "turn1Path": turn1_path,
    "artifactPath": artifact_path,
    "conflictNotePath": conflict_note_path,
    "sourceSessionKey": source_session_key,
    "sourceTag": source_tag,
    "resumeMarker": resume_marker,
    "selfE164": self_e164,
    "whatsappToken": whatsapp_token,
    "managerSessionId": manager_session_id,
    "toolModelPrecheckToken": tool_model_precheck_token,
}
path = pathlib.Path(context_path)
path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY
eval "$(inspect_whatsapp_run_context_json "$RECOVERY_CONTEXT_PATH" "$RECOVERY_CONTEXT_REPORT_PATH")"
RECOVERY_CONTEXT_REPORT_STATUS="$WHATSAPP_CONTEXT_STATUS"
RECOVERY_CONTEXT_REPORT_REASON_CODES="$WHATSAPP_CONTEXT_REASON_CODES"
RECOVERY_CONTEXT_REPORT_REASON_SUMMARY="$WHATSAPP_CONTEXT_REASON_SUMMARY"
if [[ "$WHATSAPP_CONTEXT_OK" != "1" ]]; then
  RECOVERY_CONTEXT_MODE="history_only_unverified"
fi

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
  --message "Ich komme in einer frischen Agent-Session nach einer Unterbrechung zurück. Dein eigener Chatkontext enthält das Merkwort nicht. Rufe als allerersten Toolschritt genau sessions_history für sessionKey $SOURCE_SESSION_KEY mit includeTools=true und limit 40 auf. Benutze nicht sessions_list. Rekonstruiere daraus ausschließlich die neueste User-Nachricht, die exakt die Kennung $SOURCE_TAG enthält, plus die unmittelbar folgende Assistant-Antwort. Verwende kein Merkwort aus älteren Kennungen oder älteren Läufen derselben Session. Bestimme daraus das genaue Merkwort plus den nächsten Schritt. Lies danach exakt die Konfliktdatei $CONFLICT_NOTE_REL. Diese Konfliktdatei ist absichtlich widersprüchlich und darf nur als negative Gegenprobe dienen. Wenn Konfliktdatei und History widersprechen, gewinnt immer sessions_history; verwerfe die Konfliktwerte vollständig. Du brauchst dafür keine alten Dateien erneut zu öffnen. Wenn in der History ein Pfad außerhalb deines Workspace auftaucht, ignoriere ihn. Benutze kein process und keine langen Suchläufe über ~/.openclaw. Falls du exec nutzt, dann nur kurz und lokal im aktuellen Workspace. Überschreibe danach exakt die bereits existierende Datei $ARTIFACT_REL mit Markdown: '# Recovery Note', '## Rekonstruktion', '## Konsistenzprüfung', '## Nächster Schritt'. Nutze das rekonstruierte Merkwort genau einmal im Dateiinhalt und die rekonstruierte Kennung $SOURCE_TAG genau einmal im Dateiinhalt. Erkläre in der Konsistenzprüfung kurz, dass die widersprüchliche Notiz verworfen wurde, ohne deren falsche Werte zu wiederholen. Lies die geschriebene Datei danach per read zur Verifikation. Antworte mir danach auf Deutsch in genau 2 kurzen Sätzen: welches Merkwort wir benutzt haben und was ich als Nächstes tun sollte. Verwende das Merkwort genau einmal. Wiederhole keine Konfliktwerte. Keine Dateipfade, keine Testreport-Sprache, keine JSON-Feldnamen, keine Labels wie DONE oder IN ARBEIT. Ohne sessions_history darfst du nicht abschließen."
if [[ -z "$RECOVERY_SESSION" || ! -f "$RECOVERY_SESSION" ]]; then
  RECOVERY_SESSION="$(wait_for_agent_main_session_jsonl "$RECOVERY_AGENT_ID" 40 1)"
fi
TURN2_TEXT="$(extract_result_text "$TURN2_JSON")"
python3 - <<'PY' "$TURN2_TEXT" "$RESUME_FAILURE_MARKER" "$CONFLICT_MARKER" "$CONFLICT_TAG"
import sys

text = sys.argv[1]
marker = sys.argv[2]
if text.count(marker) != 1:
    raise SystemExit(f"turn 2 must repeat marker exactly once: {marker!r} in {text!r}")
if sys.argv[3] in text or sys.argv[4] in text:
    raise SystemExit(f"turn 2 leaked rejected conflict values in {text!r}")
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
assert_session_read_result "$RECOVERY_SESSION" "$CONFLICT_NOTE_REL" "$CONFLICT_NOTE_TEXT" >/dev/null
assert_session_pattern_after_line "$RECOVERY_SESSION" "$RECOVERY_BEFORE_LINES" "\"name\":\"apply_patch\"|\"name\":\"edit\"|\"name\":\"write\"|\"name\":\"exec\"|\"toolName\":\"apply_patch\"|\"toolName\":\"edit\"|\"toolName\":\"write\"|\"toolName\":\"exec\""
assert_session_pattern_after_line "$RECOVERY_SESSION" "$RECOVERY_BEFORE_LINES" "$ARTIFACT_REL"
assert_session_pattern_after_line "$RECOVERY_SESSION" "$RECOVERY_BEFORE_LINES" '"name":"read"|"toolName":"read"'

HISTORY_LINE="$(session_pattern_line_after_line "$RECOVERY_SESSION" "$RECOVERY_BEFORE_LINES" '"name":"sessions_history"|"toolName":"sessions_history"')"
CONFLICT_LINE="$(session_tool_result_line_after_line "$RECOVERY_SESSION" "$RECOVERY_BEFORE_LINES" "read" "$CONFLICT_MARKER")"
WRITE_LINE="$(session_pattern_line_after_line "$RECOVERY_SESSION" "$RECOVERY_BEFORE_LINES" '"name":"apply_patch"|"name":"edit"|"name":"write"|"name":"exec"|"toolName":"apply_patch"|"toolName":"edit"|"toolName":"write"|"toolName":"exec"')"
if [[ -z "$HISTORY_LINE" || -z "$CONFLICT_LINE" || -z "$WRITE_LINE" || "$HISTORY_LINE" -gt "$CONFLICT_LINE" || "$CONFLICT_LINE" -gt "$WRITE_LINE" ]]; then
  echo "recovery run did not reconstruct via sessions_history, read the conflict note, then write artifact in order" >&2
  exit 1
fi

assert_valid_artifact "$ARTIFACT_PATH" "$RESUME_FAILURE_MARKER" "$SOURCE_TAG" "$CONFLICT_MARKER" "$CONFLICT_TAG"
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
printf 'conflict_note=%s\n' "$CONFLICT_NOTE_PATH"
echo "== local human whatsapp resume-failure eval passed =="
