: "${STATE_DIR:=${OPENCLAW_STATE_DIR:-$HOME/.openclaw}}"

openclaw_transient_gateway_error() {
  local output_path="$1"
  rg -q 'gateway closed \(1012\): service restart|Gateway agent failed; falling back to embedded|service restart|gateway closed \(1006 abnormal closure \(no close frame\)\): no close reason|1006 abnormal closure|no close reason|Gateway target: ws://127\.0\.0\.1:' "$output_path"
}

run_json_assert() {
  local json_path="$1"
  local expected="$2"
  python3 - <<'PY' "$json_path" "$expected"
import json, sys
path, expected = sys.argv[1], sys.argv[2]
decoder = json.JSONDecoder()
best = None

def result_payload(candidate):
    if not isinstance(candidate, dict):
        return None
    if isinstance(candidate.get("result"), dict):
        return candidate["result"]
    if isinstance(candidate.get("payloads"), list):
        return candidate
    return None

with open(path, "r", encoding="utf-8") as handle:
    raw = handle.read()
for index, char in enumerate(raw):
    if char != "{":
        continue
    try:
        candidate, _ = decoder.raw_decode(raw[index:])
    except json.JSONDecodeError:
        continue
    payload = result_payload(candidate)
    if payload is not None:
        best = payload
if best is None:
    raise SystemExit(f"{path}: missing JSON payload")
payload = best
texts = [
    item.get("text", "")
    for item in payload.get("payloads") or []
    if isinstance(item, dict) and item.get("text", "").strip()
]
if not texts:
    raise SystemExit(f"{path}: missing non-empty text payload")
text = texts[-1]
first_line = text.splitlines()[0] if text else ""
if text != expected and first_line != expected:
    raise SystemExit(f"{path}: unexpected final text {text!r} != {expected!r}")
print(first_line if first_line == expected else text)
PY
}

json_payload_has_text_result() {
  local json_path="$1"
  python3 - <<'PY' "$json_path"
import json, sys
path = sys.argv[1]
decoder = json.JSONDecoder()

def result_payload(candidate):
    if not isinstance(candidate, dict):
        return None
    if isinstance(candidate.get("result"), dict):
        return candidate["result"]
    if isinstance(candidate.get("payloads"), list):
        return candidate
    return None

with open(path, "r", encoding="utf-8") as handle:
    raw = handle.read()
for index, char in enumerate(raw):
    if char != "{":
        continue
    try:
        candidate, _ = decoder.raw_decode(raw[index:])
    except json.JSONDecodeError:
        continue
    payload = result_payload(candidate)
    if payload is not None:
        payloads = payload.get("payloads") or []
        texts = [item.get("text", "") for item in payloads if isinstance(item, dict)]
        if any(text.strip() for text in texts):
            raise SystemExit(0)
raise SystemExit(1)
PY
}

json_payload_empty_text_summary() {
  local json_path="$1"
  python3 - <<'PY' "$json_path"
import json, sys
from pathlib import Path

path = Path(sys.argv[1])
raw = path.read_text(encoding="utf-8")
decoder = json.JSONDecoder()
payload = None
run_id = "unknown"

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
        if isinstance(candidate, dict):
            run_id = candidate.get("runId") or run_id
if payload is None:
    raise SystemExit(1)
result = payload
payloads = result.get("payloads") or []
texts = [item.get("text", "") for item in payloads if isinstance(item, dict)]
if any(text.strip() for text in texts):
    raise SystemExit(1)
agent_meta = result.get("meta", {}).get("agentMeta", {})
provider = agent_meta.get("provider") or "unknown"
model = agent_meta.get("model") or "unknown"
print(
    f"openclaw agent produced no text payload: runId={run_id} "
    f"provider={provider} model={model} payloads={len(payloads)}"
)
raise SystemExit(0)
PY
}

agent_json_meta_field() {
  local json_path="$1"
  local field="$2"
  python3 - <<'PY' "$json_path" "$field"
import json, sys
from pathlib import Path

path = Path(sys.argv[1])
field = sys.argv[2]
raw = path.read_text(encoding="utf-8")
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
value = payload.get("meta", {}).get("agentMeta", {}).get(field)
if value is None:
    raise SystemExit(1)
print(value)
PY
}

verify_live_selftest_summary_snapshot() {
  local summary_path="$1"
  python3 - <<'PY' "$summary_path"
import json
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
if not path.is_file():
    raise SystemExit(f"missing live selftest summary: {path}")

payload = json.loads(path.read_text(encoding="utf-8"))
errors = []

if payload.get("status") != "passed":
    errors.append(f"status={payload.get('status')!r}")
if payload.get("mode") != "live":
    errors.append(f"mode={payload.get('mode')!r}")
if payload.get("currentStep") != "done":
    errors.append(f"currentStep={payload.get('currentStep')!r}")

steps = payload.get("stepsCompleted") or []
if "whatsapp_reply" not in steps:
    errors.append("stepsCompleted missing whatsapp_reply")

whatsapp_token = payload.get("whatsappToken") or ""
if not re.fullmatch(r"WA_SELFTEST_\d+", whatsapp_token):
    errors.append(f"whatsappToken={whatsapp_token!r}")

manager_session_id = payload.get("managerSessionId") or ""
if not manager_session_id:
    errors.append("managerSessionId missing")

artifact_root = payload.get("artifactRoot") or ""
if not artifact_root or not Path(artifact_root).is_absolute():
    errors.append(f"artifactRoot={artifact_root!r}")

if errors:
    raise SystemExit(
        "invalid live selftest summary snapshot "
        f"{path}: {', '.join(errors)}"
    )

print(f'VERIFIED_WHATSAPP_TOKEN={json.dumps(whatsapp_token)}')
print(f'VERIFIED_MANAGER_SESSION_ID={json.dumps(manager_session_id)}')
print(f'VERIFIED_SELFTEST_ARTIFACT_ROOT={json.dumps(artifact_root)}')
PY
}

verify_whatsapp_run_context_json() {
  local context_path="$1"
  python3 - <<'PY' "$context_path"
import json
import re
import sys
from pathlib import Path

context_path = Path(sys.argv[1])
if not context_path.is_file():
    raise SystemExit(f"missing WhatsApp context file: {context_path}")

context = json.loads(context_path.read_text(encoding="utf-8"))
kind = context.get("kind")
valid_kinds = {
    "whatsapp-status",
    "conversation-turn2",
    "conversation-turn3",
    "resume-turn2",
    "resume-failure-recovery",
}
if kind not in valid_kinds:
    raise SystemExit(f"unsupported WhatsApp context kind {kind!r} in {context_path}")

errors = []

def require_abs_path(key, must_exist=True, allow_parent=False):
    value = context.get(key)
    if not value:
        errors.append(f"{key} missing")
        return None
    path = Path(value)
    if not path.is_absolute():
        errors.append(f"{key} not absolute: {value!r}")
        return None
    if must_exist and not path.exists():
        errors.append(f"{key} missing on disk: {value!r}")
    if allow_parent and not path.parent.exists():
        errors.append(f"{key} parent missing: {str(path.parent)!r}")
    return path

def require_regex(key, pattern):
    value = context.get(key) or ""
    if not re.fullmatch(pattern, value):
        errors.append(f"{key} invalid: {value!r}")
    return value

def require_nonempty(key):
    value = context.get(key)
    if not isinstance(value, str) or not value.strip():
        errors.append(f"{key} missing")
        return ""
    return value.strip()

session_key = context.get("sessionKey")
if session_key is not None:
    require_regex("sessionKey", r"agent:[A-Za-z0-9._-]+:main")
source_session_key = context.get("sourceSessionKey")
if source_session_key is not None:
    require_regex("sourceSessionKey", r"agent:[A-Za-z0-9._-]+:main")

self_e164 = context.get("selfE164")
if self_e164 is not None:
    require_regex("selfE164", r"\+[1-9]\d{7,14}")

summary_snapshot_path = require_abs_path("summarySnapshotPath")
whatsapp_token = require_regex("whatsappToken", r"WA_SELFTEST_\d+")
manager_session_id = require_nonempty("managerSessionId")

if summary_snapshot_path and summary_snapshot_path.is_file():
    summary_payload = json.loads(summary_snapshot_path.read_text(encoding="utf-8"))
    if summary_payload.get("status") != "passed":
        errors.append(f"summarySnapshotPath status={summary_payload.get('status')!r}")
    if summary_payload.get("mode") != "live":
        errors.append(f"summarySnapshotPath mode={summary_payload.get('mode')!r}")
    if summary_payload.get("whatsappToken") != whatsapp_token:
        errors.append(
            "summarySnapshotPath whatsappToken mismatch: "
            f"{summary_payload.get('whatsappToken')!r} != {whatsapp_token!r}"
        )
    if summary_payload.get("managerSessionId") != manager_session_id:
        errors.append(
            "summarySnapshotPath managerSessionId mismatch: "
            f"{summary_payload.get('managerSessionId')!r} != {manager_session_id!r}"
        )

if kind == "whatsapp-status":
    require_abs_path("statusPath", must_exist=False, allow_parent=True)
    require_abs_path("planPath", must_exist=False, allow_parent=True)

if kind == "conversation-turn2":
    require_regex("marker", r"nebelstern-[a-f0-9]{10}")
    require_abs_path("turn1Path")
    require_abs_path("turn1SourcePath")

if kind == "conversation-turn3":
    require_regex("marker", r"nebelstern-[a-f0-9]{10}")
    require_abs_path("turn1Path")
    require_abs_path("turn2Path")
    require_abs_path("artifactPath", must_exist=False, allow_parent=True)
    require_nonempty("builderAgentId")

if kind == "resume-turn2":
    require_regex("marker", r"nebelstern-[a-f0-9]{10}")
    require_abs_path("turn1Path")
    require_abs_path("turn1SourcePath")

if kind == "resume-failure-recovery":
    require_regex("resumeMarker", r"nebelstern-[a-f0-9]{10}")
    require_regex("sourceTag", r"resume-failure-quelle-[a-f0-9]{8}")
    require_regex("toolModelPrecheckToken", r"toolmodell-[a-f0-9]{10}")
    require_abs_path("turn1Path")
    require_abs_path("artifactPath", must_exist=False, allow_parent=True)
    require_abs_path("conflictNotePath")

if errors:
    raise SystemExit(
        "invalid WhatsApp run context "
        f"{context_path}: {', '.join(errors)}"
    )
PY
}

agent_json_indicates_missing_tool() {
  local json_path="$1"
  local tool_name="$2"
  python3 - <<'PY' "$json_path" "$tool_name"
import json
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
tool_name = sys.argv[2]
raw = path.read_text(encoding="utf-8")
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

texts = [
    item.get("text", "")
    for item in payload.get("payloads") or []
    if isinstance(item, dict)
]
text = "\n".join(texts).lower()
tool = tool_name.lower()
missing_patterns = [
    rf"{re.escape(tool)}[^.\n]{{0,120}}not (among|available|in|found)",
    rf"no [`']?{re.escape(tool)}[`']? tool",
    rf"kein [`']?{re.escape(tool)}[`']?-tool",
    rf"kein [`']?{re.escape(tool)}[`']?",
    rf"{re.escape(tool)}[^.\n]{{0,160}}nicht[^.\n]{{0,80}}(verf[üu]gbar|zur verf[üu]gung)",
    rf"{re.escape(tool)}[^.\n]{{0,160}}steht[^.\n]{{0,80}}nicht[^.\n]{{0,80}}zur verf[üu]gung",
    rf"do not have (a |the )?[`']?{re.escape(tool)}[`']?",
    rf"cannot (use|call|make).*{re.escape(tool)}",
    rf"{re.escape(tool)}[^.\n]{{0,120}}does(n't| not) exist",
]
if tool in text and any(re.search(pattern, text) for pattern in missing_patterns):
    raise SystemExit(0)
raise SystemExit(1)
PY
}

assert_agent_json_not_heretic_fallback() {
  local json_path="$1"
  local context="$2"
  local provider
  local model
  provider="$(agent_json_meta_field "$json_path" provider || true)"
  model="$(agent_json_meta_field "$json_path" model || true)"
  if [[ "$provider" == "heretic-local" ]]; then
    echo "$context reached heretic-local/$model; tool-critical selftests require a tool-reliable model before continuing" >&2
    exit 2
  fi
}

openclaw_tool_provider_preflight() {
  local output_path="$1"
  local agent_id="${2:-}"
  local allowed_providers="${OPENCLAW_TOOL_PROVIDER_PREFLIGHT_PROVIDERS:-openai,openai-codex,qwen-portal,claude-bridge,groq,google-gemini}"
  local timeout_ms="${OPENCLAW_TOOL_PROVIDER_PREFLIGHT_TIMEOUT_MS:-15000}"
  local concurrency="${OPENCLAW_TOOL_PROVIDER_PREFLIGHT_CONCURRENCY:-2}"
  local max_tokens="${OPENCLAW_TOOL_PROVIDER_PREFLIGHT_MAX_TOKENS:-4}"
  local args=(
    models
    status
    --json
    --probe
    --probe-timeout "$timeout_ms"
    --probe-concurrency "$concurrency"
    --probe-max-tokens "$max_tokens"
  )
  local tmp_output
  local status

  if [[ -n "$agent_id" ]]; then
    args+=(--agent "$agent_id")
  fi
  if [[ "$allowed_providers" != *,* ]]; then
    args+=(--probe-provider "$allowed_providers")
  fi

  tmp_output="$(mktemp "${TMPDIR:-/tmp}/openclaw-tool-provider-preflight.XXXXXX")"
  if openclaw "${args[@]}" >"$tmp_output" 2>&1; then
    status=0
  else
    status=$?
  fi

  if [[ "$status" -ne 0 ]]; then
    cat "$tmp_output" >&2
    mv "$tmp_output" "$output_path"
    return "$status"
  fi

  if python3 - <<'PY' "$tmp_output" "$output_path"
import json
import shutil
import sys
from pathlib import Path

raw_path = Path(sys.argv[1])
output_path = Path(sys.argv[2])
raw = raw_path.read_text(encoding="utf-8")
decoder = json.JSONDecoder()
payload = None
for index, char in enumerate(raw):
    if char != "{":
        continue
    try:
        candidate, _ = decoder.raw_decode(raw[index:])
    except json.JSONDecodeError:
        continue
    if isinstance(candidate, dict) and candidate.get("auth", {}).get("probes"):
        payload = candidate
if payload is None:
    shutil.move(str(raw_path), str(output_path))
    raise SystemExit(1)
output_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
raw_path.unlink()
PY
  then
    :
  else
    echo "tool provider preflight warning: kept raw mixed output at $output_path" >&2
  fi

  python3 - <<'PY' "$output_path" "$allowed_providers"
import json
import sys
from collections import defaultdict

path, allowed_raw = sys.argv[1], sys.argv[2]
allowed = {item.strip() for item in allowed_raw.split(",") if item.strip()}
decoder = json.JSONDecoder()
payload = None
with open(path, "r", encoding="utf-8") as handle:
    raw = handle.read()
for index, char in enumerate(raw):
    if char != "{":
        continue
    try:
        candidate, _ = decoder.raw_decode(raw[index:])
    except json.JSONDecodeError:
        continue
    if isinstance(candidate, dict) and candidate.get("auth", {}).get("probes"):
        payload = candidate

if payload is None:
    print("tool provider preflight blocked: models status probe did not produce JSON", file=sys.stderr)
    raise SystemExit(2)

results = payload.get("auth", {}).get("probes", {}).get("results") or []
candidate_results = [item for item in results if item.get("provider") in allowed]
ok_results = [item for item in candidate_results if item.get("status") == "ok"]

if ok_results:
    first = ok_results[0]
    label = first.get("profileId") or first.get("label") or first.get("source") or "default"
    print(
        "tool provider preflight ok: "
        f"{first.get('provider')}/{first.get('model')} via {label}"
    )
    raise SystemExit(0)

by_provider: dict[str, list[str]] = defaultdict(list)
for item in candidate_results:
    provider = item.get("provider") or "unknown"
    status = item.get("status") or "unknown"
    detail = item.get("error") or item.get("reasonCode") or item.get("label") or ""
    detail = " ".join(str(detail).split())
    if len(detail) > 150:
        detail = detail[:147] + "..."
    by_provider[provider].append(f"{status}{': ' + detail if detail else ''}")

if by_provider:
    summary = "; ".join(
        f"{provider}={', '.join(entries[:2])}" for provider, entries in sorted(by_provider.items())
    )
else:
    summary = "no probe targets for configured tool providers"

print(
    "tool provider preflight blocked: no allowed tool provider probe passed "
    f"({summary})",
    file=sys.stderr,
)
raise SystemExit(2)
PY
}

run_openclaw_agent_capture() {
  local output_path="$1"
  local timeout_seconds="$2"
  local has_timeout="$3"
  shift 3
  local early_accept_seconds="${OPENCLAW_SELFTEST_AGENT_EARLY_ACCEPT_SECONDS:-3}"
  local watchdog_seconds="${OPENCLAW_SELFTEST_AGENT_WATCHDOG_SECONDS:-$((timeout_seconds + 30))}"
  local pid
  local started_at="$SECONDS"
  local valid_seen_at=0
  local status

  if (( has_timeout )); then
    openclaw agent "$@" --json >"$output_path" 2>&1 &
  else
    openclaw agent "$@" --timeout "$timeout_seconds" --json >"$output_path" 2>&1 &
  fi
  pid=$!

  while kill -0 "$pid" 2>/dev/null; do
    if json_payload_has_text_result "$output_path"; then
      if [[ "$valid_seen_at" -eq 0 ]]; then
        valid_seen_at="$SECONDS"
      elif (( SECONDS - valid_seen_at >= early_accept_seconds )); then
        {
          echo
          echo "[openclaw-smoke] accepted completed JSON payload and stopped still-running agent process pid=$pid"
        } >>"$output_path"
        kill "$pid" 2>/dev/null || true
        sleep 1
        kill -9 "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
        return 0
      fi
    else
      valid_seen_at=0
    fi

    if (( SECONDS - started_at >= watchdog_seconds )); then
      {
        echo
        echo "[openclaw-smoke] watchdog timeout after ${watchdog_seconds}s; stopping agent process pid=$pid"
      } >>"$output_path"
      kill "$pid" 2>/dev/null || true
      sleep 1
      kill -9 "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      return 124
    fi

    sleep 1
  done

  wait "$pid"
  status=$?
  return "$status"
}

run_openclaw_agent_json() {
  local output_path="$1"
  shift
  local attempts="${OPENCLAW_SELFTEST_AGENT_RETRIES:-3}"
  local delay="${OPENCLAW_SELFTEST_AGENT_RETRY_DELAY:-2}"
  local timeout_seconds="${OPENCLAW_SELFTEST_AGENT_TIMEOUT_SECONDS:-240}"
  local attempt
  local tmp_output
  local status
  local args=("$@")
  local has_timeout=0

  for ((attempt = 0; attempt < ${#args[@]}; attempt++)); do
    if [[ "${args[$attempt]}" == "--timeout" ]]; then
      has_timeout=1
      break
    fi
  done

  for attempt in $(seq 1 "$attempts"); do
    tmp_output="$(mktemp "${TMPDIR:-/tmp}/openclaw-agent-json.XXXXXX")"
    if run_openclaw_agent_capture "$tmp_output" "$timeout_seconds" "$has_timeout" "${args[@]}"; then
      status=0
    else
      status=$?
    fi

    if json_payload_has_text_result "$tmp_output"; then
      mv "$tmp_output" "$output_path"
      return 0
    fi

    if [[ "$attempt" -lt "$attempts" ]] && openclaw_transient_gateway_error "$tmp_output"; then
      rm -f "$tmp_output"
      sleep "$delay"
      continue
    fi

    if json_payload_empty_text_summary "$tmp_output" >&2; then
      mv "$tmp_output" "$output_path"
    else
      mv "$tmp_output" "$output_path"
      cat "$output_path" >&2
    fi
    if [[ "${status:-1}" -eq 0 ]]; then
      return 1
    fi
    return "${status:-1}"
  done

  echo "openclaw agent did not produce a valid JSON result after $attempts attempts" >&2
  return 1
}

openclaw_gateway_health_check() {
  local attempts="${OPENCLAW_SELFTEST_GATEWAY_RETRIES:-4}"
  local delay="${OPENCLAW_SELFTEST_GATEWAY_RETRY_DELAY:-2}"
  local attempt
  local tmp_output

  for attempt in $(seq 1 "$attempts"); do
    tmp_output="$(mktemp "${TMPDIR:-/tmp}/openclaw-gateway-health.XXXXXX")"
    if openclaw gateway health >"$tmp_output" 2>&1; then
      cat "$tmp_output"
      rm -f "$tmp_output"
      return 0
    fi

    if [[ "$attempt" -lt "$attempts" ]] && openclaw_transient_gateway_error "$tmp_output"; then
      rm -f "$tmp_output"
      sleep "$delay"
      continue
    fi

    cat "$tmp_output" >&2
    rm -f "$tmp_output"
    return 1
  done

  echo "openclaw gateway health failed after $attempts attempts" >&2
  return 1
}

openclaw_gateway_restart_with_retry() {
  local attempts="${OPENCLAW_GATEWAY_RESTART_ATTEMPTS:-5}"
  local delay="${OPENCLAW_GATEWAY_RESTART_DELAY:-5}"
  local attempt
  local tmp_output

  for attempt in $(seq 1 "$attempts"); do
    tmp_output="$(mktemp "${TMPDIR:-/tmp}/openclaw-gateway-restart.XXXXXX")"
    if openclaw gateway restart >"$tmp_output" 2>&1; then
      cat "$tmp_output"
      rm -f "$tmp_output"
      return 0
    fi

    if rg -q 'Gateway service not loaded\.|Start with: openclaw gateway install|Service not installed\. Run: openclaw gateway install|Could not find service "ai\.openclaw\.gateway"' "$tmp_output"; then
      rm -f "$tmp_output"
      if openclaw_gateway_install_and_start; then
        return 0
      fi
      return 1
    fi

    if [[ "$attempt" -lt "$attempts" ]] && rg -q 'launchctl bootstrap failed: spawn launchctl EAGAIN|spawn launchctl EAGAIN|Resource temporarily unavailable' "$tmp_output"; then
      rm -f "$tmp_output"
      sleep "$delay"
      continue
    fi

    cat "$tmp_output" >&2
    rm -f "$tmp_output"
    return 1
  done

  echo "gateway restart failed after $attempts attempts" >&2
  return 1
}

openclaw_gateway_install_and_start() {
  local tmp_output

  tmp_output="$(mktemp "${TMPDIR:-/tmp}/openclaw-gateway-install.XXXXXX")"
  if ! openclaw gateway install --force >"$tmp_output" 2>&1; then
    cat "$tmp_output" >&2
    rm -f "$tmp_output"
    return 1
  fi
  rm -f "$tmp_output"

  tmp_output="$(mktemp "${TMPDIR:-/tmp}/openclaw-gateway-start.XXXXXX")"
  if openclaw gateway start >"$tmp_output" 2>&1; then
    rm -f "$tmp_output"
  else
    if ! rg -q 'Gateway service not loaded\.|Start with: openclaw gateway install' "$tmp_output"; then
      cat "$tmp_output" >&2
      rm -f "$tmp_output"
      return 1
    fi
    rm -f "$tmp_output"
  fi

  if [[ "${OSTYPE:-}" == darwin* ]] && command -v launchctl >/dev/null 2>&1; then
    launchctl kickstart -k "gui/$UID/ai.openclaw.gateway" >/dev/null 2>&1 || true
  fi

  return 0
}

openclaw_ensure_gateway_healthy() {
  if openclaw_gateway_health_check >/dev/null 2>&1; then
    return 0
  fi

  openclaw_gateway_restart_with_retry >/dev/null
  openclaw_gateway_health_check >/dev/null
}

openclaw_whatsapp_self_e164() {
  local attempts="${OPENCLAW_SELFTEST_CHANNEL_RETRIES:-4}"
  local delay="${OPENCLAW_SELFTEST_CHANNEL_RETRY_DELAY:-2}"
  local attempt
  local tmp_output

  for attempt in $(seq 1 "$attempts"); do
    tmp_output="$(mktemp "${TMPDIR:-/tmp}/openclaw-channels-status.XXXXXX")"
    if openclaw channels status --json >"$tmp_output" 2>&1; then
      if python3 - <<'PY' "$tmp_output"
import json, sys
raw = open(sys.argv[1], "r", encoding="utf-8").read()
decoder = json.JSONDecoder()
payload = None
for index, char in enumerate(raw):
    if char != "{":
        continue
    try:
        candidate, _ = decoder.raw_decode(raw[index:])
    except json.JSONDecodeError:
        continue
    if isinstance(candidate, dict) and "channels" in candidate:
        payload = candidate
if payload is None:
    raise SystemExit(1)
print(payload["channels"]["whatsapp"]["self"]["e164"])
PY
      then
        rm -f "$tmp_output"
        return 0
      fi
    fi

    if [[ "$attempt" -lt "$attempts" ]] && openclaw_transient_gateway_error "$tmp_output"; then
      rm -f "$tmp_output"
      sleep "$delay"
      continue
    fi

    cat "$tmp_output" >&2
    rm -f "$tmp_output"
    return 1
  done

  echo "openclaw channels status failed after $attempts attempts" >&2
  return 1
}

latest_session_jsonl() {
  local agent_id="$1"
  python3 - <<'PY' "$STATE_DIR" "$agent_id"
import pathlib, sys
state_dir, agent_id = sys.argv[1], sys.argv[2]
session_dir = pathlib.Path(state_dir) / "agents" / agent_id / "sessions"
files = sorted(session_dir.glob("*.jsonl"), key=lambda item: item.stat().st_mtime, reverse=True)
print(files[0] if files else "")
PY
}

agent_main_session_jsonl() {
  local agent_id="${1:-main}"
  session_jsonl_for_key "$agent_id" "agent:${agent_id}:main"
}

main_session_jsonl() {
  agent_main_session_jsonl "main"
}

wait_for_agent_main_session_jsonl() {
  local agent_id="$1"
  local attempts="${2:-40}"
  local delay="${3:-1}"
  local session_file=""

  for _ in $(seq 1 "$attempts"); do
    session_file="$(agent_main_session_jsonl "$agent_id")"
    if [[ -n "$session_file" && -f "$session_file" ]]; then
      printf '%s\n' "$session_file"
      return 0
    fi
    sleep "$delay"
  done

  echo "could not resolve main session file for $agent_id" >&2
  return 1
}

session_jsonl_for_key() {
  local agent_id="$1"
  local session_key="$2"
  python3 - <<'PY' "$STATE_DIR" "$agent_id" "$session_key"
import json, pathlib, sys

state_dir, agent_id, session_key = sys.argv[1:4]
session_dir = pathlib.Path(state_dir) / "agents" / agent_id / "sessions"
sessions_index = session_dir / "sessions.json"

if sessions_index.is_file():
    with open(sessions_index, "r", encoding="utf-8") as handle:
        data = json.load(handle)
    entry = data.get(session_key) or {}
    session_file = entry.get("sessionFile")
    if session_file:
        print(session_file)
        raise SystemExit(0)

print("")
PY
}

session_jsonl_for_id() {
  local agent_id="$1"
  local session_id="$2"
  python3 - <<'PY' "$STATE_DIR" "$agent_id" "$session_id"
import json, pathlib, sys

state_dir, agent_id, session_id = sys.argv[1:4]
session_dir = pathlib.Path(state_dir) / "agents" / agent_id / "sessions"
sessions_index = session_dir / "sessions.json"

if sessions_index.is_file():
    with open(sessions_index, "r", encoding="utf-8") as handle:
        data = json.load(handle)
    entry = data.get(session_id) or {}
    session_file = entry.get("sessionFile")
    if session_file:
        print(session_file)
        raise SystemExit(0)

for candidate in sorted(session_dir.glob("*.jsonl"), key=lambda item: item.stat().st_mtime, reverse=True):
    try:
        with open(candidate, "r", encoding="utf-8") as handle:
            first_line = handle.readline().strip()
        if not first_line:
            continue
        entry = json.loads(first_line)
        if entry.get("id") == session_id or (entry.get("message") or {}).get("id") == session_id:
            print(candidate)
            raise SystemExit(0)
    except (OSError, json.JSONDecodeError):
        continue

print("")
PY
}

wait_for_session_jsonl_for_id() {
  local agent_id="$1"
  local session_id="$2"
  local attempts="${3:-40}"
  local delay="${4:-1}"
  local session_file=""

  for _ in $(seq 1 "$attempts"); do
    session_file="$(session_jsonl_for_id "$agent_id" "$session_id")"
    if [[ -n "$session_file" && -f "$session_file" ]]; then
      printf '%s\n' "$session_file"
      return 0
    fi
    sleep "$delay"
  done

  echo "could not resolve session file for $agent_id/$session_id" >&2
  return 1
}

wait_for_child_session_from_main_after_line() {
  local main_session="$1"
  local start_line="$2"
  local agent_id="$3"
  local target_path="$4"
  local attempts="${5:-40}"
  local delay="${6:-1}"
  local child_session=""

  for _ in $(seq 1 "$attempts"); do
    child_session="$(child_session_file_from_main_after_line "$main_session" "$start_line" "$agent_id" "$target_path")"
    if [[ -n "$child_session" && -f "$child_session" ]]; then
      printf '%s\n' "$child_session"
      return 0
    fi
    sleep "$delay"
  done

  echo "could not find $agent_id subagent session for $target_path" >&2
  return 1
}

workspace_mirror_file() {
  local source_path="$1"
  local prefix="${2:-mirror}"
  local suffix="${3:-$(basename "$source_path")}"
  local mirror_dir="${STATE_DIR}/workspace/.local-agent-mirrors"
  local target_path=""

  mkdir -p "$mirror_dir"
  target_path="$(python3 - <<'PY' "$mirror_dir" "$prefix" "$suffix"
import os
import sys
import tempfile

mirror_dir, prefix, suffix = sys.argv[1:4]
if suffix and "." in suffix:
    extension = "." + suffix.rsplit(".", 1)[1]
else:
    extension = ""
fd, path = tempfile.mkstemp(prefix=f"{prefix}.", suffix=extension, dir=mirror_dir)
os.close(fd)
print(path)
PY
)"
  cp "$source_path" "$target_path"
  printf '%s\n' "$target_path"
}

session_line_count() {
  local session_file="$1"
  if [[ ! -f "$session_file" ]]; then
    echo 0
    return 0
  fi
  wc -l < "$session_file" | tr -d ' '
}

session_pattern_line_after_line() {
  local session_file="$1"
  local start_line="$2"
  local pattern="$3"
  python3 - <<'PY' "$session_file" "$start_line" "$pattern"
import re
import sys
from pathlib import Path

session_file = Path(sys.argv[1])
start_line = int(sys.argv[2])
pattern = re.compile(sys.argv[3])
if not session_file.is_file():
    raise SystemExit(1)
with session_file.open("r", encoding="utf-8") as handle:
    for line_number, raw_line in enumerate(handle, start=1):
        if line_number <= start_line:
            continue
        if pattern.search(raw_line):
            print(line_number)
            raise SystemExit(0)
raise SystemExit(1)
PY
}

assert_latest_session_pattern() {
  local agent_id="$1"
  local pattern="$2"
  local session_file
  session_file="$(latest_session_jsonl "$agent_id")"
  if [[ -z "$session_file" || ! -f "$session_file" ]]; then
    echo "missing session log for $agent_id" >&2
    exit 1
  fi
  assert_session_pattern "$session_file" "$pattern"
}

assert_session_pattern() {
  local session_file="$1"
  local pattern="$2"
  if [[ -z "$session_file" || ! -f "$session_file" ]]; then
    echo "missing session log $session_file" >&2
    exit 1
  fi
  if ! rg -q "$pattern" "$session_file"; then
    echo "expected pattern $pattern in $session_file" >&2
    exit 1
  fi
}

assert_session_pattern_after_line() {
  local session_file="$1"
  local start_line="$2"
  local pattern="$3"
  if [[ -z "$session_file" || ! -f "$session_file" ]]; then
    echo "missing session log $session_file" >&2
    exit 1
  fi
  if ! session_pattern_line_after_line "$session_file" "$start_line" "$pattern" >/dev/null; then
    echo "expected pattern $pattern after line $start_line in $session_file" >&2
    exit 1
  fi
}

wait_for_session_pattern_after_line() {
  local session_file="$1"
  local start_line="$2"
  local pattern="$3"
  local attempts="${4:-40}"
  local delay="${5:-1}"
  for _ in $(seq 1 "$attempts"); do
    if [[ -n "$session_file" && -f "$session_file" ]] && session_pattern_line_after_line "$session_file" "$start_line" "$pattern" >/dev/null; then
      return 0
    fi
    sleep "$delay"
  done
  echo "expected pattern $pattern after line $start_line in $session_file" >&2
  exit 1
}

child_session_file_from_main() {
  local main_session="$1"
  local agent_id="$2"
  local target_path="$3"
  python3 - <<'PY' "$STATE_DIR" "$main_session" "$agent_id" "$target_path"
import json, pathlib, sys

state_dir, main_session, agent_id, target_path = sys.argv[1:5]
tool_calls = {}
child_session_key = None

def resolve_session_file(state_dir: str, requested_agent_id: str, child_session_key: str) -> str:
    state_path = pathlib.Path(state_dir)
    candidates = []
    parts = child_session_key.split(":")
    if len(parts) >= 2 and parts[0] == "agent":
        candidates.append(parts[1])
    candidates.append(requested_agent_id)
    for agent in candidates:
        if not agent:
            continue
        sessions_index = state_path / "agents" / agent / "sessions" / "sessions.json"
        if not sessions_index.is_file():
            continue
        with open(sessions_index, "r", encoding="utf-8") as handle:
            data = json.load(handle)
        entry = data.get(child_session_key) or {}
        session_file = entry.get("sessionFile")
        if session_file:
            return session_file
    for sessions_index in state_path.glob("agents/*/sessions/sessions.json"):
        with open(sessions_index, "r", encoding="utf-8") as handle:
            data = json.load(handle)
        entry = data.get(child_session_key) or {}
        session_file = entry.get("sessionFile")
        if session_file:
            return session_file
    return ""

with open(main_session, "r", encoding="utf-8") as handle:
    for raw_line in handle:
        raw_line = raw_line.strip()
        if not raw_line:
            continue
        entry = json.loads(raw_line)
        message = entry.get("message") or {}
        role = message.get("role")
        if role == "assistant":
            for item in message.get("content") or []:
                if item.get("type") != "toolCall" or item.get("name") != "sessions_spawn":
                    continue
                arguments = item.get("arguments") or {}
                task = arguments.get("task") or ""
                agent_matches = arguments.get("agentId") == agent_id
                if target_path in task and (agent_matches or not arguments.get("agentId")):
                    tool_calls[item.get("id")] = True
        elif role == "toolResult" and message.get("toolName") == "sessions_spawn":
            tool_call_id = message.get("toolCallId")
            if tool_call_id in tool_calls:
                details = message.get("details") or {}
                child_session_key = details.get("childSessionKey")

if not child_session_key:
    print("")
    raise SystemExit(0)

print(resolve_session_file(state_dir, agent_id, child_session_key))
PY
}

child_session_file_from_main_after_line() {
  local main_session="$1"
  local start_line="$2"
  local agent_id="$3"
  local target_path="$4"
  python3 - <<'PY' "$STATE_DIR" "$main_session" "$start_line" "$agent_id" "$target_path"
import json, pathlib, sys

state_dir, main_session, start_line_raw, agent_id, target_path = sys.argv[1:6]
start_line = int(start_line_raw)
tool_calls = {}
child_session_key = None

def resolve_session_file(state_dir: str, requested_agent_id: str, child_session_key: str) -> str:
    state_path = pathlib.Path(state_dir)
    candidates = []
    parts = child_session_key.split(":")
    if len(parts) >= 2 and parts[0] == "agent":
        candidates.append(parts[1])
    candidates.append(requested_agent_id)
    for agent in candidates:
        if not agent:
            continue
        sessions_index = state_path / "agents" / agent / "sessions" / "sessions.json"
        if not sessions_index.is_file():
            continue
        with open(sessions_index, "r", encoding="utf-8") as handle:
            data = json.load(handle)
        entry = data.get(child_session_key) or {}
        session_file = entry.get("sessionFile")
        if session_file:
            return session_file
    for sessions_index in state_path.glob("agents/*/sessions/sessions.json"):
        with open(sessions_index, "r", encoding="utf-8") as handle:
            data = json.load(handle)
        entry = data.get(child_session_key) or {}
        session_file = entry.get("sessionFile")
        if session_file:
            return session_file
    return ""

with open(main_session, "r", encoding="utf-8") as handle:
    for index, raw_line in enumerate(handle, start=1):
        if index <= start_line:
            continue
        raw_line = raw_line.strip()
        if not raw_line:
            continue
        entry = json.loads(raw_line)
        message = entry.get("message") or {}
        role = message.get("role")
        if role == "assistant":
            for item in message.get("content") or []:
                if item.get("type") != "toolCall" or item.get("name") != "sessions_spawn":
                    continue
                arguments = item.get("arguments") or {}
                task = arguments.get("task") or ""
                agent_matches = arguments.get("agentId") == agent_id
                if target_path in task and (agent_matches or not arguments.get("agentId")):
                    tool_calls[item.get("id")] = True
        elif role == "toolResult" and message.get("toolName") == "sessions_spawn":
            tool_call_id = message.get("toolCallId")
            if tool_call_id in tool_calls:
                details = message.get("details") or {}
                child_session_key = details.get("childSessionKey")

if not child_session_key:
    print("")
    raise SystemExit(0)

print(resolve_session_file(state_dir, agent_id, child_session_key))
PY
}

wait_for_file_contents() {
  local target="$1"
  local expected="$2"
  local attempts="${3:-40}"
  local delay="${4:-1}"
  for _ in $(seq 1 "$attempts"); do
    if [[ -f "$target" ]]; then
      local content
      content="$(cat "$target")"
      if [[ "$content" == "$expected" ]]; then
        return 0
      fi
    fi
    sleep "$delay"
  done
  echo "timed out waiting for expected contents in $target" >&2
  if [[ -f "$target" ]]; then
    printf 'actual contents:\n%s\n' "$(cat "$target")" >&2
  fi
  exit 1
}

assert_session_exec_result() {
  local session_file="$1"
  local command_substring="$2"
  local expected_output="$3"
  if [[ -z "$session_file" || ! -f "$session_file" ]]; then
    echo "missing session log $session_file" >&2
    exit 1
  fi
  python3 - <<'PY' "$session_file" "$command_substring" "$expected_output"
import json, sys

session_file, command_substring, expected_output = sys.argv[1], sys.argv[2], sys.argv[3]
tool_calls = {}

with open(session_file, "r", encoding="utf-8") as handle:
    for raw_line in handle:
        raw_line = raw_line.strip()
        if not raw_line:
            continue
        entry = json.loads(raw_line)
        message = entry.get("message") or {}
        role = message.get("role")
        if role == "assistant":
            for item in message.get("content") or []:
                if item.get("type") == "toolCall" and item.get("name") == "exec":
                    tool_calls[item.get("id")] = (item.get("arguments") or {}).get("command", "")
        elif role == "toolResult" and message.get("toolName") == "exec":
            tool_call_id = message.get("toolCallId")
            command = tool_calls.get(tool_call_id, "")
            details = message.get("details") or {}
            aggregated = (details.get("aggregated") or "").strip()
            exit_code = details.get("exitCode")
            if command_substring in command and exit_code == 0 and aggregated == expected_output:
                print(expected_output)
                raise SystemExit(0)

raise SystemExit(
    f"missing exec result for command containing {command_substring!r} with output {expected_output!r} in {session_file}"
)
PY
}

assert_session_read_result() {
  local session_file="$1"
  local path_substring="$2"
  local expected_output="$3"
  if [[ -z "$session_file" || ! -f "$session_file" ]]; then
    echo "missing session log $session_file" >&2
    exit 1
  fi
  python3 - <<'PY' "$session_file" "$path_substring" "$expected_output"
import json, sys

session_file, path_substring, expected_output = sys.argv[1], sys.argv[2], sys.argv[3]
tool_calls = {}

with open(session_file, "r", encoding="utf-8") as handle:
    for raw_line in handle:
        raw_line = raw_line.strip()
        if not raw_line:
            continue
        entry = json.loads(raw_line)
        message = entry.get("message") or {}
        role = message.get("role")
        if role == "assistant":
            for item in message.get("content") or []:
                if item.get("type") == "toolCall" and item.get("name") == "read":
                    arguments = item.get("arguments") or {}
                    tool_calls[item.get("id")] = (
                        arguments.get("path")
                        or arguments.get("file_path")
                        or arguments.get("filepath")
                        or ""
                    )
        elif role == "toolResult" and message.get("toolName") == "read":
            tool_call_id = message.get("toolCallId")
            read_path = tool_calls.get(tool_call_id, "")
            content = "".join(
                part.get("text", "")
                for part in message.get("content") or []
                if isinstance(part, dict) and part.get("type") == "text"
            )
            if path_substring in read_path and content.rstrip("\n") == expected_output:
                print(expected_output)
                raise SystemExit(0)

raise SystemExit(
    f"missing read result for path containing {path_substring!r} with output {expected_output!r} in {session_file}"
)
PY
}
