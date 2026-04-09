#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SUMMARY_PATH="${OPENCLAW_SELFTEST_SUMMARY_PATH:-$REPO_ROOT/.local-agent-last-selftest.json}"
MAX_AGE_SECONDS="${OPENCLAW_SELFTEST_MAX_AGE_SECONDS:-}"
OUTPUT_MODE="text"
REQUIRED_MODE=""

usage() {
  cat <<'EOF'
Usage: local-coding-agents-status.sh [--json] [--max-age-seconds N] [--require-mode core|live]

Reads the latest local coding-agent selftest summary and exits non-zero when:
- the summary file is missing
- the last run status is not "passed"
- the summary is older than --max-age-seconds / OPENCLAW_SELFTEST_MAX_AGE_SECONDS
- the last run mode does not satisfy --require-mode
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json)
      OUTPUT_MODE="json"
      shift
      ;;
    --max-age-seconds)
      if [[ $# -lt 2 ]]; then
        echo "--max-age-seconds requires a value" >&2
        exit 2
      fi
      MAX_AGE_SECONDS="$2"
      shift 2
      ;;
    --require-mode)
      if [[ $# -lt 2 ]]; then
        echo "--require-mode requires a value" >&2
        exit 2
      fi
      REQUIRED_MODE="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -n "$REQUIRED_MODE" && "$REQUIRED_MODE" != "core" && "$REQUIRED_MODE" != "live" ]]; then
  echo "unsupported required mode: $REQUIRED_MODE" >&2
  exit 2
fi

if [[ ! -f "$SUMMARY_PATH" ]]; then
  echo "missing selftest summary: $SUMMARY_PATH" >&2
  exit 1
fi

python3 - <<'PY' "$SUMMARY_PATH" "$OUTPUT_MODE" "${MAX_AGE_SECONDS:-}" "${REQUIRED_MODE:-}"
import json
import sys
from datetime import datetime, timezone

summary_path, output_mode, max_age_raw, required_mode = sys.argv[1:5]
with open(summary_path, "r", encoding="utf-8") as handle:
    summary = json.load(handle)

finished_at_raw = summary.get("finishedAt")
if not finished_at_raw:
    raise SystemExit(f"summary missing finishedAt: {summary_path}")

finished_at = datetime.strptime(finished_at_raw, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
now = datetime.now(timezone.utc)
age_seconds = int((now - finished_at).total_seconds())

status = summary.get("status")
mode = summary.get("mode")
current_step = summary.get("currentStep")
failed_step = summary.get("failedStep")
failed_command = summary.get("failedCommand")
whatsapp_token = summary.get("whatsappToken")

result = {
    **summary,
    "ageSeconds": age_seconds,
    "fresh": True,
    "requiredMode": required_mode or None,
    "modeSatisfiesRequirement": True,
}

if max_age_raw:
    max_age_seconds = int(max_age_raw)
    result["maxAgeSeconds"] = max_age_seconds
    result["fresh"] = age_seconds <= max_age_seconds

mode_rank = {"core": 1, "live": 2}
if required_mode:
    actual_rank = mode_rank.get(mode, 0)
    required_rank = mode_rank.get(required_mode, 99)
    result["modeSatisfiesRequirement"] = actual_rank >= required_rank

ok = status == "passed" and result["fresh"] and result["modeSatisfiesRequirement"]

if output_mode == "json":
    print(json.dumps(result, indent=2))
else:
    line = f"selftest status={status} mode={mode} ageSeconds={age_seconds} currentStep={current_step}"
    if whatsapp_token:
        line += f" whatsappToken={whatsapp_token}"
    print(line)
    if failed_step:
        print(f"failedStep={failed_step}")
    if failed_command:
        print(f"failedCommand={failed_command}")
    if "maxAgeSeconds" in result:
        print(f"fresh={str(result['fresh']).lower()} maxAgeSeconds={result['maxAgeSeconds']}")
    if required_mode:
        print(f"requiredMode={required_mode} modeOk={str(result['modeSatisfiesRequirement']).lower()}")

raise SystemExit(0 if ok else 1)
PY
