#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
STATE_DIR="${OPENCLAW_STATE_DIR:-$HOME/.openclaw}"
NODE22_BIN="${OPENCLAW_SELFTEST_NODE_BIN:-$HOME/.node22/current/bin}"
SMOKE_ROOT="$(mktemp -d "$REPO_ROOT/.local-main-routing-smoke.XXXXXX")"
GITHUB_JSON="$SMOKE_ROOT/main-github.json"
CLAW_JSON="$SMOKE_ROOT/main-claw.json"
GITHUB_PROOF="$(mktemp /tmp/main-route-github.XXXXXX)"
CLAW_PROOF="$(mktemp /tmp/main-route-claw.XXXXXX)"

cleanup() {
  rm -rf "$SMOKE_ROOT"
  rm -f "$GITHUB_PROOF" "$CLAW_PROOF"
}
trap cleanup EXIT

if [[ -d "$NODE22_BIN" ]]; then
  PATH="$NODE22_BIN:$PATH"
  export PATH
fi

PATH="$REPO_ROOT/scripts/dev:$REPO_ROOT/../claw-code-parity/scripts:$PATH"
export PATH

source "$SCRIPT_DIR/lib/openclaw-smoke-common.sh"

echo "== bootstrap local coding agents =="
node "$REPO_ROOT/scripts/dev/bootstrap-local-coding-agents.mjs" >/dev/null

echo "== main -> oc-github routing smoke =="
openclaw agent --agent main --message "Nutze sessions_spawn und starte einen oc-github-Subagenten. Child-Task: führe per exec 'gh repo view yankhy-source/claw-code-parity --json nameWithOwner --jq .nameWithOwner' aus und überschreibe danach per exec exakt die bereits existierende Datei $GITHUB_PROOF mit ROUTE_GITHUB_OK:yankhy-source/claw-code-parity. Verwende genau diesen Pfad, keine neue Temp-Datei. Antworte exakt mit MAIN_ROUTE_GITHUB_OK, sobald der Child-Run akzeptiert wurde." --json >"$GITHUB_JSON"
run_json_assert "$GITHUB_JSON" "MAIN_ROUTE_GITHUB_OK" >/dev/null

MAIN_SESSION="$(latest_session_jsonl "main")"
assert_session_pattern "$MAIN_SESSION" '"name":"sessions_spawn"'
assert_session_pattern "$MAIN_SESSION" "$GITHUB_PROOF"

GITHUB_SESSION=""
for _ in $(seq 1 40); do
  GITHUB_SESSION="$(child_session_file_from_main "$MAIN_SESSION" "oc-github" "$GITHUB_PROOF")"
  if [[ -n "$GITHUB_SESSION" && -f "$GITHUB_SESSION" ]]; then
    break
  fi
  sleep 1
done

if [[ -z "$GITHUB_SESSION" || ! -f "$GITHUB_SESSION" ]]; then
  echo "could not find oc-github subagent session for $GITHUB_PROOF" >&2
  exit 1
fi

wait_for_file_contents "$GITHUB_PROOF" "ROUTE_GITHUB_OK:yankhy-source/claw-code-parity"

assert_session_pattern "$GITHUB_SESSION" '"provider":"openai-codex"'
assert_session_pattern "$GITHUB_SESSION" '"model":"gpt-5.3-codex-spark"'
assert_session_pattern "$GITHUB_SESSION" '"name":"exec"'
assert_session_pattern "$GITHUB_SESSION" 'gh repo view yankhy-source/claw-code-parity'
assert_session_pattern "$GITHUB_SESSION" "$GITHUB_PROOF"

echo "== main -> claw-code routing smoke =="
openclaw agent --agent main --message "Nutze sessions_spawn und starte einen claw-code-Subagenten. Child-Task: führe per exec 'claw-code-local status' aus und überschreibe danach per exec exakt die bereits existierende Datei $CLAW_PROOF mit ROUTE_CLAW_OK. Verwende genau diesen Pfad, keine neue Temp-Datei. Antworte exakt mit MAIN_ROUTE_CLAW_OK, sobald der Child-Run akzeptiert wurde." --json >"$CLAW_JSON"
run_json_assert "$CLAW_JSON" "MAIN_ROUTE_CLAW_OK" >/dev/null

MAIN_SESSION="$(latest_session_jsonl "main")"
assert_session_pattern "$MAIN_SESSION" '"name":"sessions_spawn"'
assert_session_pattern "$MAIN_SESSION" "$CLAW_PROOF"

CLAW_SESSION=""
for _ in $(seq 1 40); do
  CLAW_SESSION="$(child_session_file_from_main "$MAIN_SESSION" "claw-code" "$CLAW_PROOF")"
  if [[ -n "$CLAW_SESSION" && -f "$CLAW_SESSION" ]]; then
    break
  fi
  sleep 1
done

if [[ -z "$CLAW_SESSION" || ! -f "$CLAW_SESSION" ]]; then
  echo "could not find claw-code subagent session for $CLAW_PROOF" >&2
  exit 1
fi

wait_for_file_contents "$CLAW_PROOF" "ROUTE_CLAW_OK"

assert_session_pattern "$CLAW_SESSION" '"provider":"openai-codex"'
assert_session_pattern "$CLAW_SESSION" '"model":"gpt-5.3-codex-spark"'
assert_session_pattern "$CLAW_SESSION" '"name":"exec"'
assert_session_pattern "$CLAW_SESSION" 'claw-code-local status'
assert_session_pattern "$CLAW_SESSION" "$CLAW_PROOF"

echo "== local main routing smoke passed =="
