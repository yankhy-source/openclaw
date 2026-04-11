#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
STATE_DIR="${OPENCLAW_STATE_DIR:-$HOME/.openclaw}"
NODE22_BIN="${OPENCLAW_SELFTEST_NODE_BIN:-$HOME/.node22/current/bin}"
SMOKE_SUMMARY_PATH="${OPENCLAW_WHATSAPP_TRANSPORT_SMOKE_SUMMARY_PATH:-$REPO_ROOT/.local-agent-last-whatsapp-transport-smoke.json}"
SMOKE_ROOT="$(mktemp -d "$REPO_ROOT/.local-whatsapp-transport-smoke.XXXXXX")"
SMOKE_JSON="$SMOKE_ROOT/whatsapp-transport.json"
SMOKE_STARTED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
SMOKE_EXIT_CODE=0
SMOKE_FAILED_COMMAND=""
TOKEN=""
SMOKE_PROVIDER=""
SMOKE_MODEL=""
SMOKE_SELF_E164=""

write_smoke_summary() {
  local exit_code="$1"
  local status="failed"
  if [[ "$exit_code" -eq 0 ]]; then
    status="passed"
  fi
  python3 - <<'PY' \
    "$SMOKE_SUMMARY_PATH" \
    "$status" \
    "$SMOKE_STARTED_AT" \
    "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    "$REPO_ROOT" \
    "$SMOKE_ROOT" \
    "$SMOKE_JSON" \
    "$TOKEN" \
    "$SMOKE_PROVIDER" \
    "$SMOKE_MODEL" \
    "$SMOKE_SELF_E164" \
    "$SMOKE_FAILED_COMMAND"
import json
import pathlib
import sys

(
    summary_path,
    status,
    started_at,
    finished_at,
    repo_root,
    artifact_root,
    json_path,
    token,
    provider,
    model,
    self_e164,
    failed_command,
) = sys.argv[1:13]

payload = {
    "summaryVersion": 1,
    "status": status,
    "startedAt": started_at,
    "finishedAt": finished_at,
    "repoRoot": repo_root,
    "artifactRoot": artifact_root,
    "jsonPath": json_path,
    "token": token or None,
    "provider": provider or None,
    "model": model or None,
    "selfE164": self_e164 or None,
    "failedCommand": failed_command or None,
}
path = pathlib.Path(summary_path)
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY
}

cleanup() {
  if [[ "$SMOKE_EXIT_CODE" -eq 0 ]]; then
    rm -rf "$SMOKE_ROOT"
  else
    echo "preserving whatsapp transport smoke artifacts: $SMOKE_ROOT" >&2
  fi
}

on_exit() {
  SMOKE_EXIT_CODE="$1"
  if [[ "$SMOKE_EXIT_CODE" -ne 0 && -z "$SMOKE_FAILED_COMMAND" ]]; then
    SMOKE_FAILED_COMMAND="whatsapp transport smoke exited with code $SMOKE_EXIT_CODE"
  fi
  trap - EXIT ERR
  set +e
  write_smoke_summary "$SMOKE_EXIT_CODE"
  cleanup
  exit "$SMOKE_EXIT_CODE"
}

on_error() {
  SMOKE_FAILED_COMMAND="$BASH_COMMAND"
}

trap on_error ERR
trap 'on_exit $?' EXIT

if [[ -d "$NODE22_BIN" ]]; then
  PATH="$NODE22_BIN:$PATH"
  export PATH
fi

PATH="$REPO_ROOT/scripts/dev:$REPO_ROOT/../claw-code-parity/scripts:$PATH"
export PATH

source "$SCRIPT_DIR/lib/openclaw-smoke-common.sh"

echo "== gateway health =="
openclaw_ensure_gateway_healthy >/dev/null

echo "== whatsapp transport proof =="
SMOKE_SELF_E164="${OPENCLAW_WHATSAPP_TRANSPORT_TO:-$(openclaw_whatsapp_self_e164)}"
GATEWAY_LOG="$STATE_DIR/logs/gateway.log"
TOKEN="DIRECT_WA_$(date +%s)"

if [[ ! -f "$GATEWAY_LOG" ]]; then
  echo "missing gateway log at $GATEWAY_LOG" >&2
  exit 1
fi
LOG_OFFSET="$(wc -c <"$GATEWAY_LOG")"

run_openclaw_agent_json "$SMOKE_JSON" \
  --agent main \
  --channel whatsapp \
  --to "$SMOKE_SELF_E164" \
  --deliver \
  --message "Antworte exakt: $TOKEN"

run_json_assert "$SMOKE_JSON" "$TOKEN" >/dev/null
SMOKE_PROVIDER="$(agent_json_meta_field "$SMOKE_JSON" provider || true)"
SMOKE_MODEL="$(agent_json_meta_field "$SMOKE_JSON" model || true)"

python3 - <<'PY' "$GATEWAY_LOG" "$LOG_OFFSET" "$TOKEN" "$SMOKE_JSON"
import json
import sys
from pathlib import Path

log_path, offset_raw, token, json_path = sys.argv[1:5]
offset = int(offset_raw)
with open(log_path, "rb") as handle:
    handle.seek(offset)
    tail = handle.read().decode("utf-8", errors="replace")
if token not in tail or "Sent message" not in tail:
    raise SystemExit(f"whatsapp delivery proof missing token or sent marker for {token!r}")

raw = Path(json_path).read_text(encoding="utf-8", errors="replace")
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
    raise SystemExit(f"{json_path}: missing JSON result payload")
meta = payload.get("meta", {}).get("agentMeta", {})
provider = meta.get("provider") or "unknown"
model = meta.get("model") or "unknown"
print(f"whatsapp_transport=passed provider={provider} model={model} token={token}")
PY

echo "== local whatsapp transport smoke passed =="
