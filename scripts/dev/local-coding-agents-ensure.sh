#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
STATUS_SCRIPT="$SCRIPT_DIR/local-coding-agents-status.sh"
SELFTEST_SCRIPT="$SCRIPT_DIR/local-coding-agents-selftest.sh"
REQUIRED_MODE="core"
MAX_AGE_SECONDS="${OPENCLAW_SELFTEST_MAX_AGE_SECONDS:-21600}"
OUTPUT_MODE="text"

usage() {
  cat <<'EOF'
Usage: local-coding-agents-ensure.sh [--core|--live] [--max-age-seconds N] [--json]

Checks the latest local coding-agent selftest summary and reruns the minimal
required selftest when the summary is missing, failed, stale, or too weak for
the requested mode.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --core)
      REQUIRED_MODE="core"
      shift
      ;;
    --live)
      REQUIRED_MODE="live"
      shift
      ;;
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

status_json() {
  bash "$STATUS_SCRIPT" --json --require-mode "$REQUIRED_MODE" --max-age-seconds "$MAX_AGE_SECONDS"
}

status_text() {
  bash "$STATUS_SCRIPT" --require-mode "$REQUIRED_MODE" --max-age-seconds "$MAX_AGE_SECONDS"
}

run_required_selftest() {
  if [[ "$REQUIRED_MODE" == "live" ]]; then
    bash "$SELFTEST_SCRIPT"
  else
    OPENCLAW_SELFTEST_SKIP_WHATSAPP=1 bash "$SELFTEST_SCRIPT"
  fi
}

if status_output="$(status_json 2>/dev/null)"; then
  if [[ "$OUTPUT_MODE" == "json" ]]; then
    printf '%s\n' "$status_output"
  else
    echo "ensure action=skip mode=$REQUIRED_MODE maxAgeSeconds=$MAX_AGE_SECONDS"
    status_text
  fi
  exit 0
fi

if [[ "$OUTPUT_MODE" == "json" ]]; then
  echo '{"action":"rerun"}'
else
  echo "ensure action=rerun mode=$REQUIRED_MODE maxAgeSeconds=$MAX_AGE_SECONDS"
fi

run_required_selftest

if [[ "$OUTPUT_MODE" == "json" ]]; then
  status_json
else
  status_text
fi
