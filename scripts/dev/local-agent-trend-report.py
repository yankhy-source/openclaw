#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR / "lib"))

from local_agent_run_history import (
    age_seconds,
    latest_problem,
    load_json,
    load_run_summaries,
    selftest_provider_blocker,
    summarize_window,
)


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
    human_whatsapp_resume_base = Path(
        os.environ.get(
            "OPENCLAW_HUMAN_WHATSAPP_RESUME_EVAL_BASE",
            repo_root / ".local-human-whatsapp-resume-eval",
        )
    )
    human_whatsapp_resume_failure_base = Path(
        os.environ.get(
            "OPENCLAW_HUMAN_WHATSAPP_RESUME_FAILURE_EVAL_BASE",
            repo_root / ".local-human-whatsapp-resume-failure-eval",
        )
    )
    selftest_summary_path = Path(os.environ.get("OPENCLAW_SELFTEST_SUMMARY_PATH", repo_root / ".local-agent-last-selftest.json"))
    whatsapp_transport_summary_path = Path(
        os.environ.get(
            "OPENCLAW_WHATSAPP_TRANSPORT_SMOKE_SUMMARY_PATH",
            repo_root / ".local-agent-last-whatsapp-transport-smoke.json",
        )
    )
    qwen_sessions_probe_summary_path = Path(
        os.environ.get(
            "OPENCLAW_QWEN_SESSIONS_PROBE_SUMMARY_PATH",
            repo_root / ".local-agent-last-qwen-sessions-probe.json",
        )
    )

    intelligence_runs, intelligence_skipped = load_run_summaries(intelligence_base, "intelligence")
    recovery_runs, recovery_skipped = load_run_summaries(recovery_base, "recovery")
    human_whatsapp_runs, human_whatsapp_skipped = load_run_summaries(human_whatsapp_base, "human_whatsapp")
    human_whatsapp_conversation_runs, human_whatsapp_conversation_skipped = load_run_summaries(
        human_whatsapp_conversation_base,
        "human_whatsapp_conversation",
    )
    human_whatsapp_resume_runs, human_whatsapp_resume_skipped = load_run_summaries(
        human_whatsapp_resume_base,
        "human_whatsapp_resume",
    )
    human_whatsapp_resume_failure_runs, human_whatsapp_resume_failure_skipped = load_run_summaries(
        human_whatsapp_resume_failure_base,
        "human_whatsapp_resume_failure",
    )
    selftest = load_json(selftest_summary_path) if selftest_summary_path.exists() else None
    selftest_blocker = selftest_provider_blocker(selftest)
    whatsapp_transport = load_json(whatsapp_transport_summary_path) if whatsapp_transport_summary_path.exists() else None
    qwen_sessions_probe = load_json(qwen_sessions_probe_summary_path) if qwen_sessions_probe_summary_path.exists() else None

    intelligence = summarize_window(intelligence_runs, window, intelligence_skipped)
    recovery = summarize_window(recovery_runs, window, recovery_skipped)
    human_whatsapp = summarize_window(human_whatsapp_runs, window, human_whatsapp_skipped)
    human_whatsapp_conversation = summarize_window(
        human_whatsapp_conversation_runs,
        window,
        human_whatsapp_conversation_skipped,
    )
    human_whatsapp_resume = summarize_window(
        human_whatsapp_resume_runs,
        window,
        human_whatsapp_resume_skipped,
    )
    human_whatsapp_resume_failure = summarize_window(
        human_whatsapp_resume_failure_runs,
        window,
        human_whatsapp_resume_failure_skipped,
    )

    problems: list[str] = []
    warnings: list[str] = []
    if not selftest:
        problems.append("latest selftest is not passed/live")
    elif selftest.get("status") == "blocked":
        problems.append("latest selftest blocked")
    elif selftest.get("status") != "passed" or selftest.get("mode") != "live":
        problems.append("latest selftest is not passed/live")
    if not whatsapp_transport:
        problems.append("latest whatsapp transport smoke missing")
    elif whatsapp_transport.get("status") != "passed":
        problems.append(latest_problem("whatsapp transport smoke", whatsapp_transport))
    if intelligence["latest"] is None:
        problems.append("no intelligence-loop history")
    elif intelligence["latest"].get("status") != "passed":
        problems.append(latest_problem("intelligence loop", intelligence["latest"]))
    if recovery["latest"] is None:
        problems.append("no recovery-smoke history")
    elif recovery["latest"].get("status") != "passed":
        problems.append(latest_problem("recovery smoke", recovery["latest"]))
    if human_whatsapp["latest"] is None:
        problems.append("no human-whatsapp history")
    elif human_whatsapp["latest"].get("status") != "passed":
        problems.append(latest_problem("human whatsapp eval", human_whatsapp["latest"]))
    if human_whatsapp_conversation["latest"] is None:
        problems.append("no human-whatsapp-conversation history")
    elif human_whatsapp_conversation["latest"].get("status") != "passed":
        problems.append(latest_problem("human whatsapp conversation eval", human_whatsapp_conversation["latest"]))
    if human_whatsapp_resume["latest"] is None:
        problems.append("no human-whatsapp-resume history")
    elif human_whatsapp_resume["latest"].get("status") != "passed":
        problems.append(latest_problem("human whatsapp resume eval", human_whatsapp_resume["latest"]))
    if human_whatsapp_resume_failure["latest"] is None:
        problems.append("no human-whatsapp-resume-failure history")
    elif human_whatsapp_resume_failure["latest"].get("status") != "passed":
        problems.append(latest_problem("human whatsapp resume-failure eval", human_whatsapp_resume_failure["latest"]))
    if intelligence["failCount"] > 0:
        warnings.append("recent intelligence-loop history contains non-passed runs")
    if recovery["failCount"] > 0:
        warnings.append("recent recovery-smoke history contains non-passed runs")
    if human_whatsapp["failCount"] > 0:
        warnings.append("recent human-whatsapp history contains non-passed runs")
    if human_whatsapp_conversation["failCount"] > 0:
        warnings.append("recent human-whatsapp-conversation history contains non-passed runs")
    if human_whatsapp_resume["failCount"] > 0:
        warnings.append("recent human-whatsapp-resume history contains non-passed runs")
    if human_whatsapp_resume_failure["failCount"] > 0:
        warnings.append("recent human-whatsapp-resume-failure history contains non-passed runs")

    return {
        "summaryVersion": 1,
        "repoRoot": str(repo_root),
        "window": window,
        "status": "ok" if not problems else "regression",
        "problems": problems,
        "warnings": warnings,
        "selftest": {
            "status": selftest.get("status") if selftest else None,
            "mode": selftest.get("mode") if selftest else None,
            "finishedAt": selftest.get("finishedAt") if selftest else None,
            "ageSeconds": age_seconds(selftest.get("finishedAt")) if selftest else None,
            "whatsappToken": selftest.get("whatsappToken") if selftest else None,
            "blocker": selftest_blocker,
        },
        "whatsappTransport": {
            "status": whatsapp_transport.get("status") if whatsapp_transport else None,
            "finishedAt": whatsapp_transport.get("finishedAt") if whatsapp_transport else None,
            "ageSeconds": age_seconds(whatsapp_transport.get("finishedAt")) if whatsapp_transport else None,
            "token": whatsapp_transport.get("token") if whatsapp_transport else None,
            "provider": whatsapp_transport.get("provider") if whatsapp_transport else None,
            "model": whatsapp_transport.get("model") if whatsapp_transport else None,
        },
        "qwenSessionsProbe": {
            "status": qwen_sessions_probe.get("status") if qwen_sessions_probe else None,
            "finishedAt": qwen_sessions_probe.get("finishedAt") if qwen_sessions_probe else None,
            "ageSeconds": age_seconds(qwen_sessions_probe.get("finishedAt")) if qwen_sessions_probe else None,
            "provider": qwen_sessions_probe.get("provider") if qwen_sessions_probe else None,
            "model": qwen_sessions_probe.get("model") if qwen_sessions_probe else None,
            "reason": qwen_sessions_probe.get("reason") if qwen_sessions_probe else None,
        },
        "intelligence": intelligence,
        "recovery": recovery,
        "humanWhatsapp": human_whatsapp,
        "humanWhatsappConversation": human_whatsapp_conversation,
        "humanWhatsappResume": human_whatsapp_resume,
        "humanWhatsappResumeFailure": human_whatsapp_resume_failure,
    }


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Report recent local intelligence/recovery/human-WhatsApp trend state.",
    )
    parser.add_argument("--json", action="store_true", help="Emit JSON instead of text.")
    parser.add_argument(
        "--window",
        type=int,
        default=int(os.environ.get("OPENCLAW_TREND_WINDOW", "5")),
        help="Number of recent runs per flow to inspect.",
    )
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parents[2]
    result = build_result(repo_root, args.window)

    if args.json:
        print(json.dumps(result, indent=2))
    else:
        intelligence = result["intelligence"]
        recovery = result["recovery"]
        human_whatsapp = result["humanWhatsapp"]
        human_whatsapp_conversation = result["humanWhatsappConversation"]
        human_whatsapp_resume = result["humanWhatsappResume"]
        human_whatsapp_resume_failure = result["humanWhatsappResumeFailure"]
        print(
            "trend status={status} window={window} selftest={selftest_status}/{selftest_mode} "
            "whatsappTransport={whatsapp_transport_status} intelligenceLatest={intelligence_latest} recoveryLatest={recovery_latest} "
            "humanWhatsappLatest={human_latest} humanConversationLatest={human_conversation_latest} "
            "humanResumeLatest={human_resume_latest} humanResumeFailureLatest={human_resume_failure_latest}".format(
                status=result["status"],
                window=result["window"],
                selftest_status=result["selftest"]["status"],
                selftest_mode=result["selftest"]["mode"],
                whatsapp_transport_status=result["whatsappTransport"]["status"],
                intelligence_latest=(intelligence["latest"] or {}).get("status"),
                recovery_latest=(recovery["latest"] or {}).get("status"),
                human_latest=(human_whatsapp["latest"] or {}).get("status"),
                human_conversation_latest=(human_whatsapp_conversation["latest"] or {}).get("status"),
                human_resume_latest=(human_whatsapp_resume["latest"] or {}).get("status"),
                human_resume_failure_latest=(human_whatsapp_resume_failure["latest"] or {}).get("status"),
            )
        )
        if result["selftest"]["whatsappToken"]:
            print(f"whatsappToken={result['selftest']['whatsappToken']}")
        if result["selftest"]["blocker"]:
            blocker = result["selftest"]["blocker"]
            print(f"selftestBlocker={blocker['summary']}")
            for cooldown in blocker.get("cooldowns") or []:
                remaining_ms = cooldown.get("remainingMs")
                if remaining_ms is not None:
                    remaining_seconds = (int(remaining_ms) + 999) // 1000
                    print(
                        "selftestCooldown provider={provider} profile={profile} remainingSeconds={seconds}".format(
                            provider=cooldown.get("provider"),
                            profile=cooldown.get("profileId"),
                            seconds=remaining_seconds,
                        )
                    )
        if result["qwenSessionsProbe"]["status"]:
            print(
                "qwenSessionsProbe={status} provider={provider} model={model} reason={reason}".format(
                    status=result["qwenSessionsProbe"]["status"],
                    provider=result["qwenSessionsProbe"]["provider"],
                    model=result["qwenSessionsProbe"]["model"],
                    reason=result["qwenSessionsProbe"]["reason"],
                )
            )
        print(
            f"intelligence passCount={intelligence['passCount']} failCount={intelligence['failCount']} total={intelligence['count']} skipped={intelligence['skippedCount']}"
        )
        print(
            f"recovery passCount={recovery['passCount']} failCount={recovery['failCount']} total={recovery['count']} skipped={recovery['skippedCount']}"
        )
        print(
            f"humanWhatsapp passCount={human_whatsapp['passCount']} failCount={human_whatsapp['failCount']} total={human_whatsapp['count']} skipped={human_whatsapp['skippedCount']}"
        )
        print(
            "humanConversation passCount={pass_count} failCount={fail_count} total={total} skipped={skipped}".format(
                pass_count=human_whatsapp_conversation["passCount"],
                fail_count=human_whatsapp_conversation["failCount"],
                total=human_whatsapp_conversation["count"],
                skipped=human_whatsapp_conversation["skippedCount"],
            )
        )
        print(
            "humanResume passCount={pass_count} failCount={fail_count} total={total} skipped={skipped}".format(
                pass_count=human_whatsapp_resume["passCount"],
                fail_count=human_whatsapp_resume["failCount"],
                total=human_whatsapp_resume["count"],
                skipped=human_whatsapp_resume["skippedCount"],
            )
        )
        print(
            "humanResumeFailure passCount={pass_count} failCount={fail_count} total={total} skipped={skipped}".format(
                pass_count=human_whatsapp_resume_failure["passCount"],
                fail_count=human_whatsapp_resume_failure["failCount"],
                total=human_whatsapp_resume_failure["count"],
                skipped=human_whatsapp_resume_failure["skippedCount"],
            )
        )
        latest_intelligence = intelligence["latest"] or {}
        if latest_intelligence.get("nextUpgrade"):
            print(f"nextUpgrade={latest_intelligence['nextUpgrade']}")
        for warning in result["warnings"]:
            print(f"warning={warning}")
        for problem in result["problems"]:
            print(f"problem={problem}")

    return 0 if result["status"] == "ok" else 1


if __name__ == "__main__":
    raise SystemExit(main())
