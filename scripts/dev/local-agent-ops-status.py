#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR / "lib"))

from local_agent_run_history import age_seconds, load_json, load_run_summaries


def latest_or_none(items: list[dict]) -> dict | None:
    return items[0] if items else None


def build_result(repo_root: Path, window: int) -> dict:
    intelligence_base = Path(os.environ.get("OPENCLAW_INTELLIGENCE_LOOP_BASE", repo_root / ".local-agent-intelligence-loop"))
    recovery_base = Path(os.environ.get("OPENCLAW_RECOVERY_SMOKE_BASE", repo_root / ".local-agent-recovery-smoke"))
    human_whatsapp_base = Path(os.environ.get("OPENCLAW_HUMAN_WHATSAPP_EVAL_BASE", repo_root / ".local-human-whatsapp-eval"))
    human_whatsapp_conversation_base = Path(
        os.environ.get(
            "OPENCLAW_HUMAN_WHATSAPP_CONVERSATION_EVAL_BASE",
            repo_root / ".local-human-whatsapp-conversation-eval",
        )
    )
    selftest_summary_path = Path(os.environ.get("OPENCLAW_SELFTEST_SUMMARY_PATH", repo_root / ".local-agent-last-selftest.json"))
    stress_recovery_summary_path = Path(
        os.environ.get("OPENCLAW_STRESS_RECOVERY_SMOKE_SUMMARY_PATH", repo_root / ".local-agent-last-stress-recovery-smoke.json")
    )

    intelligence_runs, intelligence_skipped = load_run_summaries(intelligence_base, "intelligence")
    recovery_runs, recovery_skipped = load_run_summaries(recovery_base, "recovery")
    human_whatsapp_runs, human_whatsapp_skipped = load_run_summaries(human_whatsapp_base, "human_whatsapp")
    human_whatsapp_conversation_runs, human_whatsapp_conversation_skipped = load_run_summaries(
        human_whatsapp_conversation_base,
        "human_whatsapp_conversation",
    )
    selftest = load_json(selftest_summary_path) if selftest_summary_path.exists() else None
    stress_recovery = load_json(stress_recovery_summary_path) if stress_recovery_summary_path.exists() else None

    intelligence_latest = latest_or_none(intelligence_runs)
    recovery_latest = latest_or_none(recovery_runs)
    human_whatsapp_latest = latest_or_none(human_whatsapp_runs)
    human_whatsapp_conversation_latest = latest_or_none(human_whatsapp_conversation_runs)

    problems: list[str] = []
    warnings: list[str] = []

    if not selftest:
        problems.append("missing selftest summary")
    elif selftest.get("status") != "passed" or selftest.get("mode") != "live":
        problems.append("latest selftest is not passed/live")

    if not intelligence_latest:
        problems.append("missing intelligence-loop summary")
    elif intelligence_latest.get("status") != "passed":
        problems.append("latest intelligence loop failed")

    if not recovery_latest:
        problems.append("missing recovery-smoke summary")
    elif recovery_latest.get("status") != "passed":
        problems.append("latest recovery smoke failed")

    if not human_whatsapp_latest:
        problems.append("missing human-whatsapp summary")
    elif human_whatsapp_latest.get("status") != "passed":
        problems.append("latest human whatsapp eval failed")
    if not human_whatsapp_conversation_latest:
        problems.append("missing human-whatsapp-conversation summary")
    elif human_whatsapp_conversation_latest.get("status") != "passed":
        problems.append("latest human whatsapp conversation eval failed")
    if stress_recovery and stress_recovery.get("status") != "passed":
        problems.append("latest stress-recovery smoke failed")

    recent_intelligence_failures = sum(1 for item in intelligence_runs[:window] if item.get("status") != "passed")
    recent_recovery_failures = sum(1 for item in recovery_runs[:window] if item.get("status") != "passed")
    recent_human_whatsapp_failures = sum(1 for item in human_whatsapp_runs[:window] if item.get("status") != "passed")
    recent_human_whatsapp_conversation_failures = sum(
        1 for item in human_whatsapp_conversation_runs[:window] if item.get("status") != "passed"
    )
    if recent_intelligence_failures:
        warnings.append("recent intelligence-loop history contains failures")
    if recent_recovery_failures:
        warnings.append("recent recovery-smoke history contains failures")
    if recent_human_whatsapp_failures:
        warnings.append("recent human-whatsapp history contains failures")
    if recent_human_whatsapp_conversation_failures:
        warnings.append("recent human-whatsapp-conversation history contains failures")

    next_upgrade = intelligence_latest.get("nextUpgrade") if intelligence_latest else None
    if stress_recovery and stress_recovery.get("status") == "passed":
        next_upgrade = None

    return {
        "summaryVersion": 1,
        "repoRoot": str(repo_root),
        "window": window,
        "status": "ok" if not problems else "fail",
        "problems": problems,
        "warnings": warnings,
        "selftest": {
            "status": selftest.get("status") if selftest else None,
            "mode": selftest.get("mode") if selftest else None,
            "finishedAt": selftest.get("finishedAt") if selftest else None,
            "ageSeconds": age_seconds(selftest.get("finishedAt")) if selftest else None,
            "whatsappToken": selftest.get("whatsappToken") if selftest else None,
        },
        "intelligence": {
            "status": intelligence_latest.get("status") if intelligence_latest else None,
            "finishedAt": intelligence_latest.get("finishedAt") if intelligence_latest else None,
            "ageSeconds": age_seconds(intelligence_latest.get("finishedAt")) if intelligence_latest else None,
            "nextUpgrade": next_upgrade,
            "recentFailCount": recent_intelligence_failures,
            "skippedCount": intelligence_skipped,
        },
        "recovery": {
            "status": recovery_latest.get("status") if recovery_latest else None,
            "finishedAt": recovery_latest.get("finishedAt") if recovery_latest else None,
            "ageSeconds": age_seconds(recovery_latest.get("finishedAt")) if recovery_latest else None,
            "recentFailCount": recent_recovery_failures,
            "skippedCount": recovery_skipped,
        },
        "humanWhatsapp": {
            "status": human_whatsapp_latest.get("status") if human_whatsapp_latest else None,
            "finishedAt": human_whatsapp_latest.get("finishedAt") if human_whatsapp_latest else None,
            "ageSeconds": age_seconds(human_whatsapp_latest.get("finishedAt")) if human_whatsapp_latest else None,
            "recentFailCount": recent_human_whatsapp_failures,
            "skippedCount": human_whatsapp_skipped,
        },
        "humanWhatsappConversation": {
            "status": human_whatsapp_conversation_latest.get("status") if human_whatsapp_conversation_latest else None,
            "finishedAt": human_whatsapp_conversation_latest.get("finishedAt") if human_whatsapp_conversation_latest else None,
            "ageSeconds": age_seconds(human_whatsapp_conversation_latest.get("finishedAt"))
            if human_whatsapp_conversation_latest
            else None,
            "recentFailCount": recent_human_whatsapp_conversation_failures,
            "skippedCount": human_whatsapp_conversation_skipped,
        },
        "stressRecovery": {
            "status": stress_recovery.get("status") if stress_recovery else None,
            "finishedAt": stress_recovery.get("finishedAt") if stress_recovery else None,
            "ageSeconds": age_seconds(stress_recovery.get("finishedAt")) if stress_recovery else None,
            "iterationsRequested": stress_recovery.get("iterationsRequested") if stress_recovery else None,
            "iterationsPassed": stress_recovery.get("iterationsPassed") if stress_recovery else None,
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Emit the current local coding-agent ops state without a full historical report.",
    )
    parser.add_argument("--json", action="store_true", help="Emit JSON instead of text.")
    parser.add_argument(
        "--window",
        type=int,
        default=int(os.environ.get("OPENCLAW_TREND_WINDOW", "5")),
        help="Recent-history window used only for warning counts.",
    )
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parents[2]
    result = build_result(repo_root, args.window)

    if args.json:
        print(json.dumps(result, indent=2))
    else:
        print(
            "ops status={status} selftest={selftest_status}/{selftest_mode} intelligence={intelligence_status} "
            "recovery={recovery_status} humanWhatsapp={human_status} humanConversation={human_conversation_status} stressRecovery={stress_status}".format(
                status=result["status"],
                selftest_status=result["selftest"]["status"],
                selftest_mode=result["selftest"]["mode"],
                intelligence_status=result["intelligence"]["status"],
                recovery_status=result["recovery"]["status"],
                human_status=result["humanWhatsapp"]["status"],
                human_conversation_status=result["humanWhatsappConversation"]["status"],
                stress_status=result["stressRecovery"]["status"] or "missing",
            )
        )
        if result["selftest"]["whatsappToken"]:
            print(f"whatsappToken={result['selftest']['whatsappToken']}")
        print(
            "ages selftest={selftest_age} intelligence={intelligence_age} recovery={recovery_age} "
            "humanWhatsapp={human_age} humanConversation={human_conversation_age} stressRecovery={stress_age}".format(
                selftest_age=result["selftest"]["ageSeconds"],
                intelligence_age=result["intelligence"]["ageSeconds"],
                recovery_age=result["recovery"]["ageSeconds"],
                human_age=result["humanWhatsapp"]["ageSeconds"],
                human_conversation_age=result["humanWhatsappConversation"]["ageSeconds"],
                stress_age=result["stressRecovery"]["ageSeconds"],
            )
        )
        if result["stressRecovery"]["status"]:
            print(
                f"stressRecoveryIterations={result['stressRecovery']['iterationsPassed']}/{result['stressRecovery']['iterationsRequested']}"
            )
        if result["intelligence"]["nextUpgrade"]:
            print(f"nextUpgrade={result['intelligence']['nextUpgrade']}")
        for warning in result["warnings"]:
            print(f"warning={warning}")
        for problem in result["problems"]:
            print(f"problem={problem}")

    return 0 if result["status"] == "ok" else 1


if __name__ == "__main__":
    raise SystemExit(main())
