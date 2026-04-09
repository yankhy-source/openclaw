#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SUMMARY_PATH="${OPENCLAW_SELFTEST_SUMMARY_PATH:-$REPO_ROOT/.local-agent-last-selftest.json}"
MAX_AGE_SECONDS="${OPENCLAW_SELFTEST_MAX_AGE_SECONDS:-}"
OUTPUT_MODE="text"

usage() {
  cat <<'EOF'
Usage: local-coding-agents-status.sh [--json] [--max-age-seconds N]

Reads the latest local coding-agent selftest summary and exits non-zero when:
- the summary file is missing
- the last run status is not "passed"
- the summary is older than --max-age-seconds / OPENCLAW_SELFTEST_MAX_AGE_SECONDS
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

if [[ ! -f "$SUMMARY_PATH" ]]; then
  echo "missing selftest summary: $SUMMARY_PATH" >&2
  exit 1
fi

python3 - <<'PY' "$SUMMARY_PATH" "$OUTPUT_MODE" "${MAX_AGE_SECONDS:-}"
import json
import sys
from datetime import datetime, timezone

summary_path, output_mode, max_age_raw = sys.argv[1:4]
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
}

if max_age_raw:
    max_age_seconds = int(max_age_raw)
    result["maxAgeSeconds"] = max_age_seconds
    result["fresh"] = age_seconds <= max_age_seconds

ok = status == "passed" and result["fresh"]

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

raise SystemExit(0 if ok else 1)
PY
