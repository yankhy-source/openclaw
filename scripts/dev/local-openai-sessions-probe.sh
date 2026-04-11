#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
NODE22_BIN="${OPENCLAW_SELFTEST_NODE_BIN:-$HOME/.node22/current/bin}"
PROBE_SUMMARY_PATH="${OPENCLAW_OPENAI_SESSIONS_PROBE_SUMMARY_PATH:-$REPO_ROOT/.local-agent-last-openai-sessions-probe.json}"
PROBE_ROOT="$(mktemp -d "$REPO_ROOT/.local-openai-sessions-probe.XXXXXX")"
OUTPUT_LOG="$PROBE_ROOT/output.log"
PROBE_STARTED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
PROBE_EXIT_CODE=0
PROBE_STATUS="failed"
PROBE_FAILED_COMMAND=""
ARTIFACT_ROOT=""
MAIN_JSON_PATH=""
PROBE_PROVIDER=""
PROBE_MODEL=""
PROBE_REASON=""

cleanup() {
  if [[ "$PROBE_EXIT_CODE" -eq 0 ]]; then
    rm -rf "$PROBE_ROOT"
  else
    echo "preserving openai sessions probe artifacts: $PROBE_ROOT" >&2
  fi
}

write_probe_summary() {
  python3 - <<'PY' \
    "$PROBE_SUMMARY_PATH" \
    "$PROBE_STATUS" \
    "$PROBE_STARTED_AT" \
    "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    "$REPO_ROOT" \
    "$PROBE_ROOT" \
    "$OUTPUT_LOG" \
    "$ARTIFACT_ROOT" \
    "$MAIN_JSON_PATH" \
    "$PROBE_PROVIDER" \
    "$PROBE_MODEL" \
    "$PROBE_REASON" \
    "$PROBE_FAILED_COMMAND"
import json
import pathlib
import sys

(
    summary_path,
    status,
    started_at,
    finished_at,
    repo_root,
    probe_root,
    output_log,
    artifact_root,
    main_json_path,
    provider,
    model,
    reason,
    failed_command,
) = sys.argv[1:14]

payload = {
    "summaryVersion": 1,
    "status": status,
    "startedAt": started_at,
    "finishedAt": finished_at,
    "repoRoot": repo_root,
    "probeRoot": probe_root,
    "outputLog": output_log,
    "artifactRoot": artifact_root or None,
    "mainJsonPath": main_json_path or None,
    "provider": provider or None,
    "model": model or None,
    "reason": reason or None,
    "failedCommand": failed_command or None,
}
path = pathlib.Path(summary_path)
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY
}

finalize_probe_metadata() {
  if [[ -z "$ARTIFACT_ROOT" && -f "$OUTPUT_LOG" ]]; then
    ARTIFACT_ROOT="$(python3 - <<'PY' "$OUTPUT_LOG"
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace")
matches = re.findall(r"preserving main orchestrator smoke artifacts: (.+)", text)
if matches:
    print(matches[-1].strip())
PY
)"
  fi

  if [[ -n "$ARTIFACT_ROOT" ]]; then
    MAIN_JSON_PATH="$ARTIFACT_ROOT/main.json"
  fi

  if [[ -n "$MAIN_JSON_PATH" && -f "$MAIN_JSON_PATH" ]]; then
    python3 - <<'PY' "$MAIN_JSON_PATH" >"$PROBE_ROOT/metadata.env" || true
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
raw = path.read_text(encoding="utf-8", errors="replace")
decoder = json.JSONDecoder()
payload = None
for index, char in enumerate(raw):
    if char != "{":
        continue
    try:
        candidate, _ = decoder.raw_decode(raw[index:])
    except json.JSONDecodeError:
        continue
    if isinstance(candidate, dict) and isinstance(candidate.get("result"), dict):
        payload = candidate

provider = ""
model = ""
reason = ""
if payload is not None:
    agent_meta = payload.get("result", {}).get("meta", {}).get("agentMeta", {})
    provider = agent_meta.get("provider") or ""
    model = agent_meta.get("model") or ""
    texts = [
        item.get("text", "")
        for item in payload.get("result", {}).get("payloads") or []
        if isinstance(item, dict)
    ]
    text = "\n".join(texts).lower()
    if "sessions_spawn" in text and ("nicht" in text or "kein" in text):
        reason = "sessions_spawn_unavailable"

def emit(name, value):
    print(f"{name}={value}")

emit("PROBE_PROVIDER", json.dumps(provider))
emit("PROBE_MODEL", json.dumps(model))
emit("PROBE_REASON", json.dumps(reason))
PY
    if [[ -f "$PROBE_ROOT/metadata.env" ]]; then
      # shellcheck disable=SC1090
      source "$PROBE_ROOT/metadata.env"
    fi
  fi

  if [[ -z "$PROBE_REASON" && -f "$OUTPUT_LOG" ]] && rg -q 'did not expose the sessions_spawn runtime tool' "$OUTPUT_LOG"; then
    PROBE_REASON="sessions_spawn_unavailable"
  fi
}

on_exit() {
  PROBE_EXIT_CODE="$1"
  trap - EXIT
  finalize_probe_metadata
  if [[ "$PROBE_EXIT_CODE" -eq 0 ]]; then
    PROBE_STATUS="passed"
  elif [[ "$PROBE_EXIT_CODE" -eq 2 ]]; then
    PROBE_STATUS="blocked"
  fi
  if [[ "$PROBE_EXIT_CODE" -ne 0 && -z "$PROBE_FAILED_COMMAND" ]]; then
    PROBE_FAILED_COMMAND="openai sessions probe exited with code $PROBE_EXIT_CODE"
  fi
  write_probe_summary
  cleanup
  exit "$PROBE_EXIT_CODE"
}

trap 'on_exit $?' EXIT

if [[ -d "$NODE22_BIN" ]]; then
  PATH="$NODE22_BIN:$PATH"
  export PATH
fi

set +e
OPENCLAW_SELFTEST_MANAGER_ID=oc-selftest-openai \
OPENCLAW_MAIN_ORCHESTRATOR_CHILD_AGENT_ID=oc-builder-openai \
OPENCLAW_MAIN_ORCHESTRATOR_EXPECT_CHILD_PROVIDER=openai \
OPENCLAW_MAIN_ORCHESTRATOR_EXPECT_CHILD_MODEL=gpt-4.1 \
bash "$SCRIPT_DIR/local-main-orchestrator-smoke.sh" 2>&1 | tee "$OUTPUT_LOG"
PROBE_EXIT_CODE="${PIPESTATUS[0]}"
set -e
if [[ "$PROBE_EXIT_CODE" -ne 0 ]]; then
  PROBE_FAILED_COMMAND="bash $SCRIPT_DIR/local-main-orchestrator-smoke.sh"
fi
exit "$PROBE_EXIT_CODE"
