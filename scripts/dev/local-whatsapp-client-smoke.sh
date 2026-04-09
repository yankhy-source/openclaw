#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
STATE_DIR="${OPENCLAW_STATE_DIR:-$HOME/.openclaw}"
NODE22_BIN="${OPENCLAW_SELFTEST_NODE_BIN:-$HOME/.node22/current/bin}"
SUMMARY_PATH="${OPENCLAW_SELFTEST_SUMMARY_PATH:-$REPO_ROOT/.local-agent-last-selftest.json}"
MAX_AGE_SECONDS="${OPENCLAW_SELFTEST_MAX_AGE_SECONDS:-900}"
SMOKE_JSON="${OPENCLAW_WHATSAPP_SMOKE_JSON:-${TMPDIR:-/tmp}/openclaw-whatsapp-client-smoke.json}"
DOCTOR_SCRIPT="$SCRIPT_DIR/local-coding-agents-doctor.sh"
ENSURE_SCRIPT="$SCRIPT_DIR/local-coding-agents-ensure.sh"

if [[ -d "$NODE22_BIN" ]]; then
  PATH="$NODE22_BIN:$PATH"
  export PATH
fi

PATH="$REPO_ROOT/scripts/dev:$REPO_ROOT/../claw-code-parity/scripts:$PATH"
export PATH

source "$SCRIPT_DIR/lib/openclaw-smoke-common.sh"

echo "== local coding agent doctor =="
bash "$DOCTOR_SCRIPT" --require-mode live --max-age-seconds "$MAX_AGE_SECONDS" >/dev/null 2>&1 || \
  bash "$ENSURE_SCRIPT" --live --max-age-seconds "$MAX_AGE_SECONDS" >/dev/null

echo "== whatsapp client read proof =="
SELF_E164="$(
  openclaw channels status --json | python3 -c 'import json,sys; raw=sys.stdin.read(); start=raw.find("{"); assert start >= 0, raw; print(json.loads(raw[start:])["channels"]["whatsapp"]["self"]["e164"])'
)"

EXPECTED="$(
  python3 - <<'PY' "$SUMMARY_PATH"
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as handle:
    summary = json.load(handle)
print(f"LIVE_CHECK=mode={summary['mode']};status={summary['status']};token={summary['whatsappToken']}")
PY
)"

run_openclaw_agent_json "$SMOKE_JSON" \
  --agent main \
  --channel whatsapp \
  --to "$SELF_E164" \
  --deliver \
  --message "Nutze read, lies $SUMMARY_PATH und antworte exakt mit $EXPECTED"

run_json_assert "$SMOKE_JSON" "$EXPECTED" >/dev/null
assert_latest_session_pattern "main" '"name":"read"'
assert_latest_session_pattern "main" "$SUMMARY_PATH"
assert_latest_session_pattern "main" "$EXPECTED"

echo "== local whatsapp client smoke passed =="
