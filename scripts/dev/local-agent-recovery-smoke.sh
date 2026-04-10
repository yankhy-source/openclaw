#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
STATE_DIR="${OPENCLAW_STATE_DIR:-$HOME/.openclaw}"
NODE22_BIN="${OPENCLAW_SELFTEST_NODE_BIN:-$HOME/.node22/current/bin}"
RECOVERY_BASE="${OPENCLAW_RECOVERY_SMOKE_BASE:-$REPO_ROOT/.local-agent-recovery-smoke}"
RECOVERY_SUMMARY_PATH="${OPENCLAW_RECOVERY_SMOKE_SUMMARY_PATH:-$REPO_ROOT/.local-agent-last-recovery-smoke.json}"
HUMAN_WHATSAPP_EVAL_SCRIPT="$SCRIPT_DIR/local-human-whatsapp-eval.sh"
HUMAN_WHATSAPP_SUMMARY_PATH="${OPENCLAW_HUMAN_WHATSAPP_EVAL_SUMMARY_PATH:-$REPO_ROOT/.local-agent-last-human-whatsapp-eval.json}"
BOOTSTRAP_SCRIPT="$SCRIPT_DIR/bootstrap-local-coding-agents.mjs"
RECOVERY_ROOT=""
RECOVERY_STARTED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
GATEWAY_RESTARTED_AT=""
RECOVERY_STATUS="failed"
RECOVERY_FAILED_COMMAND=""
HUMAN_WHATSAPP_STATUS=""
HUMAN_WHATSAPP_STATUS_TEXT=""

if [[ -d "$NODE22_BIN" ]]; then
  PATH="$NODE22_BIN:$PATH"
  export PATH
fi

PATH="$REPO_ROOT/scripts/dev:$REPO_ROOT/../claw-code-parity/scripts:$PATH"
export PATH

mkdir -p "$RECOVERY_BASE"
RECOVERY_ROOT="$(mktemp -d "$RECOVERY_BASE/run.XXXXXX")"

source "$SCRIPT_DIR/lib/openclaw-smoke-common.sh"

on_error() {
  RECOVERY_FAILED_COMMAND="${BASH_COMMAND}"
}

write_recovery_summary() {
  local exit_code="$1"
  if [[ "$exit_code" -eq 0 ]]; then
    RECOVERY_STATUS="passed"
  fi
  python3 - <<'PY' \
    "$RECOVERY_SUMMARY_PATH" \
    "$RECOVERY_ROOT/summary.json" \
    "$RECOVERY_STATUS" \
    "$RECOVERY_STARTED_AT" \
    "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    "$REPO_ROOT" \
    "$RECOVERY_ROOT" \
    "$GATEWAY_RESTARTED_AT" \
    "$HUMAN_WHATSAPP_SUMMARY_PATH" \
    "$HUMAN_WHATSAPP_STATUS" \
    "$HUMAN_WHATSAPP_STATUS_TEXT" \
    "$RECOVERY_FAILED_COMMAND"
import json, pathlib, sys

summary_paths = [pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])]
payload = {
    "summaryVersion": 1,
    "status": sys.argv[3],
    "startedAt": sys.argv[4],
    "finishedAt": sys.argv[5],
    "repoRoot": sys.argv[6],
    "recoveryRoot": sys.argv[7],
    "gatewayRestartedAt": sys.argv[8] or None,
    "humanWhatsappEvalSummaryPath": sys.argv[9],
    "humanWhatsappStatus": sys.argv[10] or None,
    "humanWhatsappStatusText": sys.argv[11] or None,
    "failedCommand": sys.argv[12] or None,
}
for summary_path in summary_paths:
    summary_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY
}

on_exit() {
  local exit_code="$1"
  trap - EXIT ERR
  set +e
  write_recovery_summary "$exit_code"
  exit "$exit_code"
}

wait_for_gateway_ok() {
  local attempts="${1:-45}"
  local delay="${2:-1}"
  for _ in $(seq 1 "$attempts"); do
    if openclaw gateway health >/dev/null 2>&1; then
      return 0
    fi
    sleep "$delay"
  done
  echo "gateway did not become healthy after restart" >&2
  return 1
}

trap on_error ERR
trap 'on_exit $?' EXIT

echo "== bootstrap local coding agents =="
node "$BOOTSTRAP_SCRIPT" >/dev/null

echo "== restart gateway =="
openclaw_gateway_restart_with_retry
GATEWAY_RESTARTED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
wait_for_gateway_ok

echo "== post-restart human whatsapp eval =="
bash "$HUMAN_WHATSAPP_EVAL_SCRIPT" >/dev/null

if [[ ! -f "$HUMAN_WHATSAPP_SUMMARY_PATH" ]]; then
  echo "missing human whatsapp summary at $HUMAN_WHATSAPP_SUMMARY_PATH" >&2
  exit 1
fi

HUMAN_WHATSAPP_STATUS="$(
  python3 - <<'PY' "$HUMAN_WHATSAPP_SUMMARY_PATH"
import json, sys
payload = json.loads(open(sys.argv[1], "r", encoding="utf-8").read())
print(payload.get("status", ""))
PY
)"

HUMAN_WHATSAPP_STATUS_TEXT="$(
  python3 - <<'PY' "$HUMAN_WHATSAPP_SUMMARY_PATH"
import json, sys
payload = json.loads(open(sys.argv[1], "r", encoding="utf-8").read())
print(payload.get("statusText", ""))
PY
)"

if [[ "$HUMAN_WHATSAPP_STATUS" != "passed" ]]; then
  echo "human whatsapp eval did not recover cleanly: $HUMAN_WHATSAPP_STATUS" >&2
  exit 1
fi

openclaw_gateway_health_check >/dev/null

RECOVERY_STATUS="passed"

echo "== recovery smoke artifacts =="
printf 'human_whatsapp_eval_summary=%s\n' "$HUMAN_WHATSAPP_SUMMARY_PATH"
printf 'recovery_smoke_summary=%s\n' "$RECOVERY_SUMMARY_PATH"
echo "== local agent recovery smoke passed =="
