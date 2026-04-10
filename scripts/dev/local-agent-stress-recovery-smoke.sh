#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
NODE22_BIN="${OPENCLAW_SELFTEST_NODE_BIN:-$HOME/.node22/current/bin}"
STRESS_BASE="${OPENCLAW_STRESS_RECOVERY_SMOKE_BASE:-$REPO_ROOT/.local-agent-stress-recovery-smoke}"
STRESS_SUMMARY_PATH="${OPENCLAW_STRESS_RECOVERY_SMOKE_SUMMARY_PATH:-$REPO_ROOT/.local-agent-last-stress-recovery-smoke.json}"
SELFTEST_SUMMARY_PATH="${OPENCLAW_SELFTEST_SUMMARY_PATH:-$REPO_ROOT/.local-agent-last-selftest.json}"
HUMAN_WHATSAPP_EVAL_SCRIPT="$SCRIPT_DIR/local-human-whatsapp-eval.sh"
RECOVERY_SCRIPT="$SCRIPT_DIR/local-agent-recovery-smoke.sh"
BOOTSTRAP_SCRIPT="$SCRIPT_DIR/bootstrap-local-coding-agents.mjs"
ITERATIONS="${OPENCLAW_STRESS_RECOVERY_ITERATIONS:-3}"
SNAPSHOT_DIR="${OPENCLAW_STRESS_RECOVERY_SNAPSHOT_DIR:-$REPO_ROOT/.tmp/local_agent_human_whatsapp}"
STRESS_ROOT=""
STRESS_STARTED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
STRESS_STATUS="failed"
STRESS_FAILED_COMMAND=""
RECOVERY_STATUS=""
SELFTEST_STATUS=""
SELFTEST_MODE=""
WHATSAPP_TOKEN=""

if [[ ! "$ITERATIONS" =~ ^[0-9]+$ ]] || [[ "$ITERATIONS" -lt 1 ]]; then
  echo "OPENCLAW_STRESS_RECOVERY_ITERATIONS must be a positive integer" >&2
  exit 2
fi

if [[ -d "$NODE22_BIN" ]]; then
  PATH="$NODE22_BIN:$PATH"
  export PATH
fi

PATH="$REPO_ROOT/scripts/dev:$REPO_ROOT/../claw-code-parity/scripts:$PATH"
export PATH

mkdir -p "$STRESS_BASE"
STRESS_ROOT="$(mktemp -d "$STRESS_BASE/run.XXXXXX")"
mkdir -p "$SNAPSHOT_DIR"

make_snapshot_path() {
  python3 - <<'PY' "$SNAPSHOT_DIR"
import os, sys, tempfile
fd, path = tempfile.mkstemp(prefix="current.", suffix=".json", dir=sys.argv[1])
os.close(fd)
print(path)
PY
}

on_error() {
  STRESS_FAILED_COMMAND="${BASH_COMMAND}"
}

write_stress_summary() {
  local exit_code="$1"
  if [[ "$exit_code" -eq 0 ]]; then
    STRESS_STATUS="passed"
  fi
  python3 - <<'PY' \
    "$STRESS_SUMMARY_PATH" \
    "$STRESS_ROOT/summary.json" \
    "$STRESS_STATUS" \
    "$STRESS_STARTED_AT" \
    "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    "$REPO_ROOT" \
    "$STRESS_ROOT" \
    "$ITERATIONS" \
    "$RECOVERY_STATUS" \
    "$SELFTEST_SUMMARY_PATH" \
    "$SELFTEST_STATUS" \
    "$SELFTEST_MODE" \
    "$WHATSAPP_TOKEN" \
    "$STRESS_FAILED_COMMAND"
import json, pathlib, sys

stress_root = pathlib.Path(sys.argv[7])
iteration_summaries = [str(path) for path in sorted(stress_root.glob("human-whatsapp-*.summary.json"))]
iteration_statuses = []
for path in iteration_summaries:
    try:
        payload = json.loads(pathlib.Path(path).read_text(encoding="utf-8"))
    except Exception:
        payload = {}
    iteration_statuses.append(payload.get("status"))

payload = {
    "summaryVersion": 1,
    "status": sys.argv[3],
    "startedAt": sys.argv[4],
    "finishedAt": sys.argv[5],
    "repoRoot": sys.argv[6],
    "stressRoot": sys.argv[7],
    "iterationsRequested": int(sys.argv[8]),
    "iterationsPassed": sum(1 for status in iteration_statuses if status == "passed"),
    "iterationSummaryPaths": iteration_summaries,
    "iterationStatuses": iteration_statuses,
    "recoveryStatus": sys.argv[9] or None,
    "recoverySummaryPath": str(stress_root / "recovery-summary.json"),
    "selftestSummaryPath": sys.argv[10],
    "selftestStatus": sys.argv[11] or None,
    "selftestMode": sys.argv[12] or None,
    "whatsappToken": sys.argv[13] or None,
    "failedCommand": sys.argv[14] or None,
}
for target in (pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])):
    target.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY
}

on_exit() {
  local exit_code="$1"
  trap - EXIT ERR
  set +e
  write_stress_summary "$exit_code"
  exit "$exit_code"
}

trap on_error ERR
trap 'on_exit $?' EXIT

echo "== bootstrap local coding agents =="
node "$BOOTSTRAP_SCRIPT" >/dev/null

for iteration in $(seq 1 "$ITERATIONS"); do
  local_summary="$STRESS_ROOT/human-whatsapp-$iteration.summary.json"
  local_base="$STRESS_ROOT/human-whatsapp-runs-$iteration"
  local_snapshot="$(make_snapshot_path)"
  echo "== stress whatsapp iteration $iteration/$ITERATIONS =="
  OPENCLAW_HUMAN_WHATSAPP_EVAL_BASE="$local_base" \
    OPENCLAW_HUMAN_WHATSAPP_EVAL_SUMMARY_PATH="$local_summary" \
    OPENCLAW_HUMAN_WHATSAPP_SUMMARY_SNAPSHOT_PATH="$local_snapshot" \
    bash "$HUMAN_WHATSAPP_EVAL_SCRIPT" >/dev/null

  iteration_status="$(
    python3 - <<'PY' "$local_summary"
import json, sys
payload = json.loads(open(sys.argv[1], "r", encoding="utf-8").read())
print(payload.get("status", ""))
PY
  )"
  if [[ "$iteration_status" != "passed" ]]; then
    echo "stress whatsapp iteration $iteration failed: $iteration_status" >&2
    exit 1
  fi
done

echo "== stress recovery phase =="
RECOVERY_SNAPSHOT_PATH="$(make_snapshot_path)"
OPENCLAW_HUMAN_WHATSAPP_SUMMARY_SNAPSHOT_PATH="$RECOVERY_SNAPSHOT_PATH" \
  bash "$RECOVERY_SCRIPT" >/dev/null
cp "$REPO_ROOT/.local-agent-last-recovery-smoke.json" "$STRESS_ROOT/recovery-summary.json"
RECOVERY_STATUS="$(
  python3 - <<'PY' "$STRESS_ROOT/recovery-summary.json"
import json, sys
payload = json.loads(open(sys.argv[1], "r", encoding="utf-8").read())
print(payload.get("status", ""))
PY
)"
if [[ "$RECOVERY_STATUS" != "passed" ]]; then
  echo "stress recovery phase failed: $RECOVERY_STATUS" >&2
  exit 1
fi

if [[ -f "$SELFTEST_SUMMARY_PATH" ]]; then
  SELFTEST_STATUS="$(
    python3 - <<'PY' "$SELFTEST_SUMMARY_PATH"
import json, sys
payload = json.loads(open(sys.argv[1], "r", encoding="utf-8").read())
print(payload.get("status", ""))
PY
  )"
  SELFTEST_MODE="$(
    python3 - <<'PY' "$SELFTEST_SUMMARY_PATH"
import json, sys
payload = json.loads(open(sys.argv[1], "r", encoding="utf-8").read())
print(payload.get("mode", ""))
PY
  )"
  WHATSAPP_TOKEN="$(
    python3 - <<'PY' "$SELFTEST_SUMMARY_PATH"
import json, sys
payload = json.loads(open(sys.argv[1], "r", encoding="utf-8").read())
print(payload.get("whatsappToken", ""))
PY
  )"
fi

STRESS_STATUS="passed"

echo "== stress recovery artifacts =="
printf 'stress_summary=%s\n' "$STRESS_SUMMARY_PATH"
printf 'stress_root=%s\n' "$STRESS_ROOT"
echo "== local agent stress recovery smoke passed =="
