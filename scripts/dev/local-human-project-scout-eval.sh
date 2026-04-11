#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
NODE22_BIN="${OPENCLAW_SELFTEST_NODE_BIN:-$HOME/.node22/current/bin}"
EVAL_BASE="${OPENCLAW_HUMAN_PROJECT_SCOUT_EVAL_BASE:-$REPO_ROOT/.local-human-project-scout-eval}"
EVAL_SUMMARY_PATH="${OPENCLAW_HUMAN_PROJECT_SCOUT_EVAL_SUMMARY_PATH:-$REPO_ROOT/.local-agent-last-human-project-scout-eval.json}"
BOOTSTRAP_SCRIPT="$SCRIPT_DIR/bootstrap-local-coding-agents.mjs"
HOOK_SMOKE_SCRIPT="$SCRIPT_DIR/local-project-scout-hook-smoke.mjs"
PLUGINS_JSON=""
HOOK_SMOKE_JSON=""
EVAL_ROOT=""
EVAL_STARTED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
EVAL_STATUS="failed"
EVAL_FAILED_COMMAND=""

if [[ -d "$NODE22_BIN" ]]; then
  PATH="$NODE22_BIN:$PATH"
  export PATH
fi

mkdir -p "$EVAL_BASE"
EVAL_ROOT="$(mktemp -d "$EVAL_BASE/run.XXXXXX")"
PLUGINS_JSON="$EVAL_ROOT/plugins.json"
HOOK_SMOKE_JSON="$EVAL_ROOT/project-scout-hook-smoke.json"

source "$SCRIPT_DIR/lib/openclaw-smoke-common.sh"

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
    "$PLUGINS_JSON" \
    "$HOOK_SMOKE_JSON" \
    "$EVAL_FAILED_COMMAND"
import json, pathlib, sys

summary_paths = [pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])]
payload = {
    "summaryVersion": 2,
    "status": sys.argv[3],
    "startedAt": sys.argv[4],
    "finishedAt": sys.argv[5],
    "repoRoot": sys.argv[6],
    "evalRoot": sys.argv[7],
    "pluginsPath": sys.argv[8],
    "hookSmokePath": sys.argv[9],
    "failedCommand": sys.argv[10] or None,
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

echo "== restart gateway for plugin/config reload =="
openclaw_gateway_restart_with_retry >/dev/null

echo "== ensure gateway healthy =="
openclaw_ensure_gateway_healthy >/dev/null

echo "== verify project scout plugin loaded =="
openclaw plugins list --json >"$PLUGINS_JSON"
python3 - <<'PY' "$PLUGINS_JSON"
import json
import sys
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
    if isinstance(candidate, dict) and "plugins" in candidate:
        payload = candidate
        break
if payload is None:
    raise SystemExit(f"missing JSON payload in {sys.argv[1]}")
plugins = payload.get("plugins") or []
match = next((item for item in plugins if item.get("id") == "local-project-scout"), None)
if not match:
    raise SystemExit("local-project-scout plugin not listed")
if match.get("status") != "loaded":
    raise SystemExit(f"local-project-scout plugin status={match.get('status')!r}")
if match.get("hookCount", 0) < 1:
    raise SystemExit(f"local-project-scout plugin hookCount={match.get('hookCount')!r}")
print(json.dumps({"plugin": match.get("id"), "status": match.get("status"), "hookCount": match.get("hookCount")}))
PY

echo "== run project scout hook smoke =="
node "$HOOK_SMOKE_SCRIPT" >"$HOOK_SMOKE_JSON"
cat "$HOOK_SMOKE_JSON"

EVAL_STATUS="passed"

echo "== human project scout eval artifacts =="
printf 'plugins_json=%s\n' "$PLUGINS_JSON"
printf 'hook_smoke_json=%s\n' "$HOOK_SMOKE_JSON"
printf 'human_project_scout_eval_summary=%s\n' "$EVAL_SUMMARY_PATH"
echo "== local human project scout eval passed =="
