#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SUMMARY_PATH="${OPENCLAW_SELFTEST_SUMMARY_PATH:-$REPO_ROOT/.local-agent-last-selftest.json}"
STATE_DIR="${OPENCLAW_STATE_DIR:-$HOME/.openclaw}"
CONFIG_PATH="${OPENCLAW_CONFIG_PATH:-$STATE_DIR/openclaw.json}"
PARITY_ROOT="${CLAW_CODE_PARITY_ROOT:-$REPO_ROOT/../claw-code-parity}"
MAX_AGE_SECONDS="${OPENCLAW_SELFTEST_MAX_AGE_SECONDS:-}"
REQUIRED_MODE=""
OUTPUT_MODE="text"

usage() {
  cat <<'EOF'
Usage: local-coding-agents-doctor.sh [--json] [--max-age-seconds N] [--require-mode core|live]

Audits the local coding-agent configuration and latest selftest summary.
Exits non-zero when configuration drift or selftest problems are detected.
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

python3 - <<'PY' \
  "$REPO_ROOT" \
  "$SUMMARY_PATH" \
  "$CONFIG_PATH" \
  "$PARITY_ROOT" \
  "$OUTPUT_MODE" \
  "${MAX_AGE_SECONDS:-}" \
  "${REQUIRED_MODE:-}"
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

repo_root = Path(sys.argv[1]).resolve()
summary_path = Path(sys.argv[2]).resolve()
config_path = Path(sys.argv[3]).resolve()
parity_root = Path(sys.argv[4]).resolve()
output_mode = sys.argv[5]
max_age_raw = sys.argv[6]
required_mode = sys.argv[7]

if required_mode and required_mode not in {"core", "live"}:
    raise SystemExit(f"unsupported required mode: {required_mode}")

main_primary_model = "openai-codex/gpt-5.3-codex-spark"
main_fallbacks = [
    "heretic-local/qwen3-4b-instruct-2507",
    "groq/llama-3.3-70b-versatile",
    "groq/deepseek-r1-distill-llama-70b",
    "google-gemini/gemini-2.0-flash",
]
shared_skill_ids = ["claw-code-local", "main-tool-discipline", "main-human-operator"]
agent_ids = ["oc-builder", "oc-github", "claw-code"]
human_eval_agent_ids = ["oc-human-main", "oc-human-builder"]
home_dir = Path.home()
shared_path_prepend = [
    str(repo_root / "scripts" / "dev"),
    str(parity_root / "scripts"),
    str(home_dir / "bin"),
    str(home_dir / ".openclaw" / ".venvs" / "ai-tools" / "bin"),
]

findings = []

def add(level: str, code: str, message: str) -> None:
    findings.append({"level": level, "code": code, "message": message})

def find_agent(agent_list, agent_id):
    for entry in agent_list:
        if isinstance(entry, dict) and entry.get("id") == agent_id:
            return entry
    return None

def require(condition: bool, code: str, message: str) -> None:
    if not condition:
        add("error", code, message)

def model_primary(value):
    if isinstance(value, str):
        return value
    if isinstance(value, dict):
        primary = value.get("primary")
        if isinstance(primary, str):
            return primary
    return None

def model_fallbacks(value):
    if isinstance(value, dict) and isinstance(value.get("fallbacks"), list):
        return [item for item in value.get("fallbacks") if isinstance(item, str)]
    return []

report = {
    "doctorVersion": 1,
    "repoRoot": str(repo_root),
    "configPath": str(config_path),
    "summaryPath": str(summary_path),
    "parityRoot": str(parity_root),
    "requiredMode": required_mode or None,
    "checks": {},
    "summary": None,
    "findings": findings,
}

require(config_path.is_file(), "config_missing", f"OpenClaw config not found: {config_path}")
require(parity_root.is_dir(), "parity_missing", f"claw-code parity repo not found: {parity_root}")
require((repo_root / "scripts" / "dev" / "claw-code-local").is_file(), "wrapper_missing", "Missing repo-local claw-code wrapper")

state_skills = Path(os.environ.get("OPENCLAW_STATE_DIR", str(home_dir / ".openclaw"))) / "skills"
for skill_id in shared_skill_ids:
    require((state_skills / skill_id / "SKILL.md").is_file(), f"skill_missing_{skill_id}", f"Missing synced shared skill: {skill_id}")

config = {}
if config_path.is_file():
    try:
        config = json.loads(config_path.read_text(encoding="utf-8"))
    except Exception as exc:
        add("error", "config_invalid_json", f"Invalid JSON in {config_path}: {exc}")

if isinstance(config, dict):
    agents = config.get("agents") or {}
    agent_list = agents.get("list") if isinstance(agents.get("list"), list) else []
    defaults = agents.get("defaults") if isinstance(agents.get("defaults"), dict) else {}
    tools = config.get("tools") if isinstance(config.get("tools"), dict) else {}

    main_agent = find_agent(agent_list, "main")
    require(main_agent is not None, "main_missing", "Missing main agent profile")
    if main_agent:
        report["checks"]["main"] = {
            "workspace": main_agent.get("workspace"),
            "model": main_agent.get("model"),
            "subagents": main_agent.get("subagents"),
            "skills": main_agent.get("skills"),
        }
        main_skills = main_agent.get("skills") or []
        require("main-tool-discipline" in main_skills, "main_skill_missing", "main is missing main-tool-discipline")
        require("main-human-operator" in main_skills, "main_human_skill_missing", "main is missing main-human-operator")
        model = main_agent.get("model") if isinstance(main_agent.get("model"), dict) else {}
        require(model.get("primary") == main_primary_model, "main_primary_mismatch", f"main.model.primary must be {main_primary_model}")
        fallbacks = model.get("fallbacks") if isinstance(model.get("fallbacks"), list) else []
        for fallback in main_fallbacks:
            require(fallback in fallbacks, "main_fallback_missing", f"main.model.fallbacks missing {fallback}")
        subagents = main_agent.get("subagents") if isinstance(main_agent.get("subagents"), dict) else {}
        require(subagents.get("model") == main_primary_model, "main_subagent_model_mismatch", f"main.subagents.model must be {main_primary_model}")
        allow_agents = subagents.get("allowAgents") if isinstance(subagents.get("allowAgents"), list) else []
        for agent_id in agent_ids:
            require(agent_id in allow_agents, "main_allow_agent_missing", f"main.subagents.allowAgents missing {agent_id}")
        exec_cfg = ((main_agent.get("tools") or {}).get("exec") or {})
        path_prepend = exec_cfg.get("pathPrepend") if isinstance(exec_cfg.get("pathPrepend"), list) else []
        for expected in shared_path_prepend:
            require(expected in path_prepend, "main_path_prepend_missing", f"main.tools.exec.pathPrepend missing {expected}")

    defaults_subagents = defaults.get("subagents") if isinstance(defaults.get("subagents"), dict) else {}
    report["checks"]["defaultsSubagentsModel"] = defaults_subagents.get("model")
    require(defaults_subagents.get("model") == main_primary_model, "defaults_subagents_model_mismatch", f"agents.defaults.subagents.model must be {main_primary_model}")
    defaults_sandbox = defaults.get("sandbox") if isinstance(defaults.get("sandbox"), dict) else {}
    report["checks"]["defaultsSandboxMode"] = defaults_sandbox.get("mode")
    require(defaults_sandbox.get("mode") == "off", "defaults_sandbox_mode_mismatch", 'agents.defaults.sandbox.mode must be "off"')

    agent_to_agent = tools.get("agentToAgent") if isinstance(tools.get("agentToAgent"), dict) else {}
    allow = agent_to_agent.get("allow") if isinstance(agent_to_agent.get("allow"), list) else []
    report["checks"]["agentToAgentAllow"] = allow
    for agent_id in ["oc-selftest", *agent_ids, *human_eval_agent_ids]:
        require(agent_id in allow, "agent_to_agent_allow_missing", f"tools.agentToAgent.allow missing {agent_id}")

    expected_agents = {
        "oc-selftest": {"workspace": str(repo_root), "model": main_primary_model, "fallbacks": main_fallbacks, "subagents_model": main_primary_model, "allow_agents": agent_ids},
        "oc-builder": {"workspace": str(repo_root), "model": main_primary_model, "fallbacks": main_fallbacks},
        "oc-github": {"workspace": str(repo_root), "model": main_primary_model, "fallbacks": main_fallbacks},
        "claw-code": {"workspace": str(parity_root), "model": main_primary_model, "fallbacks": main_fallbacks},
        "oc-human-main": {"workspace": str(repo_root), "model": main_primary_model, "fallbacks": main_fallbacks, "subagents_model": main_primary_model, "allow_agents": ["oc-human-builder"]},
        "oc-human-builder": {"workspace": str(repo_root), "model": main_primary_model, "fallbacks": main_fallbacks},
    }
    report["checks"]["agents"] = {}
    for agent_id, expected in expected_agents.items():
        agent = find_agent(agent_list, agent_id)
        require(agent is not None, f"{agent_id}_missing", f"Missing {agent_id} agent profile")
        if not agent:
            continue
        report["checks"]["agents"][agent_id] = {
            "workspace": agent.get("workspace"),
            "model": agent.get("model"),
            "skills": agent.get("skills"),
        }
        require(agent.get("workspace") == expected["workspace"], f"{agent_id}_workspace_mismatch", f"{agent_id}.workspace must be {expected['workspace']}")
        require(model_primary(agent.get("model")) == expected["model"], f"{agent_id}_model_mismatch", f"{agent_id}.model.primary must be {expected['model']}")
        fallbacks = model_fallbacks(agent.get("model"))
        for fallback in expected["fallbacks"]:
            require(fallback in fallbacks, f"{agent_id}_fallback_missing", f"{agent_id}.model.fallbacks missing {fallback}")
        if "subagents_model" in expected:
            subagents = agent.get("subagents") if isinstance(agent.get("subagents"), dict) else {}
            require(subagents.get("model") == expected["subagents_model"], f"{agent_id}_subagents_model_mismatch", f"{agent_id}.subagents.model must be {expected['subagents_model']}")
            allow_agents = subagents.get("allowAgents") if isinstance(subagents.get("allowAgents"), list) else []
            for allowed_agent in expected.get("allow_agents", []):
                require(allowed_agent in allow_agents, f"{agent_id}_allow_agent_missing", f"{agent_id}.subagents.allowAgents missing {allowed_agent}")
        exec_cfg = ((agent.get("tools") or {}).get("exec") or {})
        path_prepend = exec_cfg.get("pathPrepend") if isinstance(exec_cfg.get("pathPrepend"), list) else []
        for expected_path in shared_path_prepend:
            require(expected_path in path_prepend, f"{agent_id}_path_prepend_missing", f"{agent_id}.tools.exec.pathPrepend missing {expected_path}")

summary = None
if summary_path.is_file():
    try:
        summary = json.loads(summary_path.read_text(encoding="utf-8"))
    except Exception as exc:
        add("error", "summary_invalid_json", f"Invalid JSON in {summary_path}: {exc}")
else:
    add("error", "summary_missing", f"Selftest summary not found: {summary_path}")

if isinstance(summary, dict):
    finished_at_raw = summary.get("finishedAt")
    age_seconds = None
    if finished_at_raw:
        try:
            finished_at = datetime.strptime(finished_at_raw, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
            age_seconds = int((datetime.now(timezone.utc) - finished_at).total_seconds())
        except ValueError as exc:
            add("error", "summary_finished_at_invalid", f"Invalid summary finishedAt: {exc}")
    else:
        add("error", "summary_finished_at_missing", "Summary is missing finishedAt")

    mode = summary.get("mode")
    status = summary.get("status")
    report["summary"] = {
        **summary,
        "ageSeconds": age_seconds,
    }
    require(status == "passed", "summary_not_passed", f"Last selftest status is {status!r}, expected 'passed'")
    if max_age_raw:
        max_age_seconds = int(max_age_raw)
        require(age_seconds is not None and age_seconds <= max_age_seconds, "summary_stale", f"Last selftest age {age_seconds}s exceeds max {max_age_seconds}s")
        report["summary"]["maxAgeSeconds"] = max_age_seconds
    if required_mode:
        mode_rank = {"core": 1, "live": 2}
        actual_rank = mode_rank.get(mode, 0)
        required_rank = mode_rank.get(required_mode, 99)
        require(actual_rank >= required_rank, "summary_mode_too_weak", f"Last selftest mode {mode!r} does not satisfy required mode {required_mode!r}")

ok = not any(item["level"] == "error" for item in findings)
report["status"] = "ok" if ok else "fail"

if output_mode == "json":
    print(json.dumps(report, indent=2))
else:
    summary_status = report["summary"]["status"] if isinstance(report.get("summary"), dict) else "missing"
    summary_mode = report["summary"]["mode"] if isinstance(report.get("summary"), dict) else "missing"
    summary_age = report["summary"].get("ageSeconds") if isinstance(report.get("summary"), dict) else None
    line = f"doctor status={report['status']} findings={len(findings)} summaryStatus={summary_status} summaryMode={summary_mode}"
    if summary_age is not None:
        line += f" summaryAgeSeconds={summary_age}"
    print(line)
    for finding in findings:
        print(f"{finding['level']} {finding['code']}: {finding['message']}")

raise SystemExit(0 if ok else 1)
PY
