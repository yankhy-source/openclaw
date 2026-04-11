#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONTEXT_REPORT_AUDIT_BASE="${OPENCLAW_CONTEXT_REPORT_AUDIT_BASE:-$REPO_ROOT/.local-agent-context-report-audit}"
CONTEXT_REPORT_AUDIT_SUMMARY_PATH="${OPENCLAW_CONTEXT_REPORT_AUDIT_SUMMARY_PATH:-$REPO_ROOT/.local-agent-last-context-report-audit.json}"
HUMAN_WHATSAPP_EVAL_SUMMARY_PATH="${OPENCLAW_HUMAN_WHATSAPP_EVAL_SUMMARY_PATH:-$REPO_ROOT/.local-agent-last-human-whatsapp-eval.json}"
HUMAN_WHATSAPP_CONVERSATION_EVAL_SUMMARY_PATH="${OPENCLAW_HUMAN_WHATSAPP_CONVERSATION_EVAL_SUMMARY_PATH:-$REPO_ROOT/.local-agent-last-human-whatsapp-conversation-eval.json}"
HUMAN_WHATSAPP_RESUME_EVAL_SUMMARY_PATH="${OPENCLAW_HUMAN_WHATSAPP_RESUME_EVAL_SUMMARY_PATH:-$REPO_ROOT/.local-agent-last-human-whatsapp-resume-eval.json}"
HUMAN_WHATSAPP_RESUME_FAILURE_EVAL_SUMMARY_PATH="${OPENCLAW_HUMAN_WHATSAPP_RESUME_FAILURE_EVAL_SUMMARY_PATH:-$REPO_ROOT/.local-agent-last-human-whatsapp-resume-failure-eval.json}"
CONTEXT_FALLBACK_SMOKE_SUMMARY_PATH="${OPENCLAW_CONTEXT_FALLBACK_SMOKE_SUMMARY_PATH:-$REPO_ROOT/.local-agent-last-context-fallback-smoke.json}"

mkdir -p "$CONTEXT_REPORT_AUDIT_BASE"
CONTEXT_REPORT_AUDIT_ROOT="$(mktemp -d "$CONTEXT_REPORT_AUDIT_BASE/run.XXXXXX")"
CONTEXT_REPORT_AUDIT_MARKDOWN_PATH="$CONTEXT_REPORT_AUDIT_ROOT/context-report-audit.md"

python3 - <<'PY' \
  "$CONTEXT_REPORT_AUDIT_SUMMARY_PATH" \
  "$CONTEXT_REPORT_AUDIT_ROOT/summary.json" \
  "$CONTEXT_REPORT_AUDIT_ROOT" \
  "$CONTEXT_REPORT_AUDIT_MARKDOWN_PATH" \
  "$REPO_ROOT" \
  "$HUMAN_WHATSAPP_EVAL_SUMMARY_PATH" \
  "$HUMAN_WHATSAPP_CONVERSATION_EVAL_SUMMARY_PATH" \
  "$HUMAN_WHATSAPP_RESUME_EVAL_SUMMARY_PATH" \
  "$HUMAN_WHATSAPP_RESUME_FAILURE_EVAL_SUMMARY_PATH" \
  "$CONTEXT_FALLBACK_SMOKE_SUMMARY_PATH"
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

summary_paths = [Path(sys.argv[1]), Path(sys.argv[2])]
audit_root = Path(sys.argv[3])
audit_path = Path(sys.argv[4])
repo_root = sys.argv[5]
started_at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
sys.path.insert(0, str(Path(repo_root) / "scripts" / "dev" / "lib"))
from local_agent_run_history import load_run_summaries  # type: ignore

inputs = {
    "human_whatsapp": {
        "last": Path(sys.argv[6]),
        "base": Path(repo_root) / ".local-human-whatsapp-eval",
        "kind": "human_whatsapp",
        "requiredPrefixes": ["statusContextReport"],
    },
    "conversation": {
        "last": Path(sys.argv[7]),
        "base": Path(repo_root) / ".local-human-whatsapp-conversation-eval",
        "kind": "human_whatsapp_conversation",
        "requiredPrefixes": ["turn2ContextReport", "turn3ContextReport"],
    },
    "resume": {
        "last": Path(sys.argv[8]),
        "base": Path(repo_root) / ".local-human-whatsapp-resume-eval",
        "kind": "human_whatsapp_resume",
        "requiredPrefixes": ["turn2ContextReport"],
    },
    "resume_failure": {
        "last": Path(sys.argv[9]),
        "base": Path(repo_root) / ".local-human-whatsapp-resume-failure-eval",
        "kind": "human_whatsapp_resume_failure",
        "requiredPrefixes": ["recoveryContextReport"],
    },
    "context_fallback": {
        "last": Path(sys.argv[10]),
        "base": Path(repo_root) / ".local-agent-context-fallback-smoke",
        "kind": "context_fallback",
        "requiredPrefixes": [
            "conversationTurn2ContextReport",
            "conversationTurn3ContextReport",
            "resumeTurn2ContextReport",
        ],
    },
}

def has_required_reports(payload, prefixes):
    if payload.get("status") != "passed":
        return False
    for prefix in prefixes:
        report = payload.get(f"{prefix}UserFacingReport")
        if not isinstance(report, str) or not report.strip():
            return False
    return True

resolved_inputs = {}
payloads = {}

for name, meta in inputs.items():
    selected_path = None
    selected_payload = None
    last_path = meta["last"]
    required_prefixes = meta["requiredPrefixes"]

    if last_path.is_file():
        candidate = json.loads(last_path.read_text(encoding="utf-8"))
        if has_required_reports(candidate, required_prefixes):
            selected_path = last_path
            selected_payload = candidate

    if selected_payload is None:
        history, _ = load_run_summaries(meta["base"], meta["kind"])
        for candidate in history:
            if has_required_reports(candidate, required_prefixes):
                selected_path = Path(candidate["_summaryPath"])
                selected_payload = candidate
                break

    if selected_payload is None or selected_path is None:
        raise SystemExit(f"missing passed input summary with required reports for {name}: {last_path}")

    resolved_inputs[name] = selected_path
    payloads[name] = selected_payload

def extract(report_label, lane, payload_name, prefix, expected_source=None):
    payload = payloads[payload_name]
    report = payload.get(f"{prefix}UserFacingReport")
    if not isinstance(report, str) or not report.strip():
        raise SystemExit(f"{report_label} missing user-facing report in {resolved_inputs[payload_name]}")
    required_fragments = ("Kontext-Report:", "erwartet=", "tatsaechlich=", "abweichung=", "quelle=")
    missing = [fragment for fragment in required_fragments if fragment not in report]
    if missing:
        raise SystemExit(f"{report_label} report missing fragments {missing!r}: {report!r}")
    decision_source = payload.get(f"{prefix}DecisionSource")
    if expected_source and decision_source != expected_source:
        raise SystemExit(
            f"{report_label} expected decision source {expected_source!r}, got {decision_source!r}"
        )
    if lane == "green" and "abweichung=keine" not in report:
        raise SystemExit(f"{report_label} green-path report must say abweichung=keine: {report!r}")
    if lane == "mismatch" and "abweichung=keine" in report:
        raise SystemExit(f"{report_label} mismatch report unexpectedly says abweichung=keine: {report!r}")
    return {
        "label": report_label,
        "lane": lane,
        "summaryPath": str(resolved_inputs[payload_name]),
        "report": report,
        "decisionSource": decision_source,
        "reportStatus": payload.get(f"{prefix}Status"),
        "expectedSummary": payload.get(f"{prefix}ExpectedSummary"),
        "actualSummary": payload.get(f"{prefix}ActualSummary"),
        "deviationSummary": payload.get(f"{prefix}DeviationSummary"),
    }

reports = [
    extract("status", "green", "human_whatsapp", "statusContextReport", "validated_snapshot"),
    extract("conversation turn 2", "green", "conversation", "turn2ContextReport", "validated_context"),
    extract("conversation turn 3", "green", "conversation", "turn3ContextReport", "validated_context"),
    extract("resume turn 2", "green", "resume", "turn2ContextReport", "validated_context"),
    extract("resume-failure recovery", "green", "resume_failure", "recoveryContextReport", "validated_recovery_context"),
    extract("fallback conversation turn 2", "mismatch", "context_fallback", "conversationTurn2ContextReport", "sessions_history"),
    extract("fallback conversation turn 3", "mismatch", "context_fallback", "conversationTurn3ContextReport", "sessions_history"),
    extract("fallback resume turn 2", "mismatch", "context_fallback", "resumeTurn2ContextReport", "sessions_history"),
]

green_reports = [report for report in reports if report["lane"] == "green"]
mismatch_reports = [report for report in reports if report["lane"] == "mismatch"]

markdown_lines = [
    "# Kontext-Report-Audit",
    "",
    "## Gruener Pfad",
]
for report in green_reports:
    markdown_lines.append(f"- {report['label']}: {report['report']}")
markdown_lines.extend(["", "## Mismatch-Pfad"])
for report in mismatch_reports:
    markdown_lines.append(f"- {report['label']}: {report['report']}")
markdown_lines.append("")

audit_path.write_text("\n".join(markdown_lines), encoding="utf-8")

finished_at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
summary_payload = {
    "summaryVersion": 1,
    "status": "passed",
    "startedAt": started_at,
    "finishedAt": finished_at,
    "repoRoot": repo_root,
    "auditRoot": str(audit_root),
    "auditPath": str(audit_path),
    "greenReportCount": len(green_reports),
    "mismatchReportCount": len(mismatch_reports),
    "reportCount": len(reports),
    "reports": reports,
}
for summary_path in summary_paths:
    summary_path.write_text(json.dumps(summary_payload, indent=2) + "\n", encoding="utf-8")
PY

printf 'context_report_audit_summary=%s\n' "$CONTEXT_REPORT_AUDIT_SUMMARY_PATH"
printf 'context_report_audit_markdown=%s\n' "$CONTEXT_REPORT_AUDIT_MARKDOWN_PATH"
echo "== local whatsapp context report audit passed =="
