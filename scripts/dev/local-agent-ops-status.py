#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR / "lib"))

from local_agent_run_history import age_seconds, latest_problem, load_json, load_run_summaries, selftest_provider_blocker


def latest_or_none(items: list[dict]) -> dict | None:
    return items[0] if items else None


def build_result(repo_root: Path, window: int) -> dict:
    intelligence_base = Path(os.environ.get("OPENCLAW_INTELLIGENCE_LOOP_BASE", repo_root / ".local-agent-intelligence-loop"))
    recovery_base = Path(os.environ.get("OPENCLAW_RECOVERY_SMOKE_BASE", repo_root / ".local-agent-recovery-smoke"))
    context_fallback_base = Path(
        os.environ.get("OPENCLAW_CONTEXT_FALLBACK_SMOKE_BASE", repo_root / ".local-agent-context-fallback-smoke")
    )
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
    stress_recovery_summary_path = Path(
        os.environ.get("OPENCLAW_STRESS_RECOVERY_SMOKE_SUMMARY_PATH", repo_root / ".local-agent-last-stress-recovery-smoke.json")
    )

    intelligence_runs, intelligence_skipped = load_run_summaries(intelligence_base, "intelligence")
    recovery_runs, recovery_skipped = load_run_summaries(recovery_base, "recovery")
    context_fallback_runs, context_fallback_skipped = load_run_summaries(context_fallback_base, "context_fallback")
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
    stress_recovery = load_json(stress_recovery_summary_path) if stress_recovery_summary_path.exists() else None

    intelligence_latest = latest_or_none(intelligence_runs)
    recovery_latest = latest_or_none(recovery_runs)
    context_fallback_latest = latest_or_none(context_fallback_runs)
    human_whatsapp_latest = latest_or_none(human_whatsapp_runs)
    human_whatsapp_conversation_latest = latest_or_none(human_whatsapp_conversation_runs)
    human_whatsapp_resume_latest = latest_or_none(human_whatsapp_resume_runs)
    human_whatsapp_resume_failure_latest = latest_or_none(human_whatsapp_resume_failure_runs)

    problems: list[str] = []
    warnings: list[str] = []

    if not selftest:
        problems.append("missing selftest summary")
    elif selftest.get("status") == "blocked":
        problems.append("latest selftest blocked")
    elif selftest.get("status") != "passed" or selftest.get("mode") != "live":
        problems.append("latest selftest is not passed/live")

    if not whatsapp_transport:
        problems.append("missing whatsapp-transport summary")
    elif whatsapp_transport.get("status") != "passed":
        problems.append(latest_problem("whatsapp transport smoke", whatsapp_transport))

    if not intelligence_latest:
        problems.append("missing intelligence-loop summary")
    elif intelligence_latest.get("status") != "passed":
        problems.append(latest_problem("intelligence loop", intelligence_latest))

    if not recovery_latest:
        problems.append("missing recovery-smoke summary")
    elif recovery_latest.get("status") != "passed":
        problems.append(latest_problem("recovery smoke", recovery_latest))
    if not context_fallback_latest:
        problems.append("missing context-fallback summary")
    elif context_fallback_latest.get("status") != "passed":
        problems.append(latest_problem("context fallback smoke", context_fallback_latest))

    if not human_whatsapp_latest:
        problems.append("missing human-whatsapp summary")
    elif human_whatsapp_latest.get("status") != "passed":
        problems.append(latest_problem("human whatsapp eval", human_whatsapp_latest))
    if not human_whatsapp_conversation_latest:
        problems.append("missing human-whatsapp-conversation summary")
    elif human_whatsapp_conversation_latest.get("status") != "passed":
        problems.append(latest_problem("human whatsapp conversation eval", human_whatsapp_conversation_latest))
    if not human_whatsapp_resume_latest:
        problems.append("missing human-whatsapp-resume summary")
    elif human_whatsapp_resume_latest.get("status") != "passed":
        problems.append(latest_problem("human whatsapp resume eval", human_whatsapp_resume_latest))
    if not human_whatsapp_resume_failure_latest:
        problems.append("missing human-whatsapp-resume-failure summary")
    elif human_whatsapp_resume_failure_latest.get("status") != "passed":
        problems.append(latest_problem("human whatsapp resume-failure eval", human_whatsapp_resume_failure_latest))
    if stress_recovery and stress_recovery.get("status") != "passed":
        problems.append(latest_problem("stress-recovery smoke", stress_recovery))

    recent_intelligence_failures = sum(1 for item in intelligence_runs[:window] if item.get("status") != "passed")
    recent_recovery_failures = sum(1 for item in recovery_runs[:window] if item.get("status") != "passed")
    recent_context_fallback_failures = sum(1 for item in context_fallback_runs[:window] if item.get("status") != "passed")
    recent_human_whatsapp_failures = sum(1 for item in human_whatsapp_runs[:window] if item.get("status") != "passed")
    recent_human_whatsapp_conversation_failures = sum(
        1 for item in human_whatsapp_conversation_runs[:window] if item.get("status") != "passed"
    )
    recent_human_whatsapp_resume_failures = sum(
        1 for item in human_whatsapp_resume_runs[:window] if item.get("status") != "passed"
    )
    recent_human_whatsapp_resume_failure_failures = sum(
        1 for item in human_whatsapp_resume_failure_runs[:window] if item.get("status") != "passed"
    )
    if recent_intelligence_failures:
        warnings.append("recent intelligence-loop history contains non-passed runs")
    if recent_recovery_failures:
        warnings.append("recent recovery-smoke history contains non-passed runs")
    if recent_context_fallback_failures:
        warnings.append("recent context-fallback history contains non-passed runs")
    if recent_human_whatsapp_failures:
        warnings.append("recent human-whatsapp history contains non-passed runs")
    if recent_human_whatsapp_conversation_failures:
        warnings.append("recent human-whatsapp-conversation history contains non-passed runs")
    if recent_human_whatsapp_resume_failures:
        warnings.append("recent human-whatsapp-resume history contains non-passed runs")
    if recent_human_whatsapp_resume_failure_failures:
        warnings.append("recent human-whatsapp-resume-failure history contains non-passed runs")

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
        "contextFallback": {
            "status": context_fallback_latest.get("status") if context_fallback_latest else None,
            "finishedAt": context_fallback_latest.get("finishedAt") if context_fallback_latest else None,
            "ageSeconds": age_seconds(context_fallback_latest.get("finishedAt")) if context_fallback_latest else None,
            "conversationTurn2ContextMode": context_fallback_latest.get("conversationTurn2ContextMode")
            if context_fallback_latest
            else None,
            "conversationTurn3ContextMode": context_fallback_latest.get("conversationTurn3ContextMode")
            if context_fallback_latest
            else None,
            "resumeTurn2ContextMode": context_fallback_latest.get("resumeTurn2ContextMode")
            if context_fallback_latest
            else None,
            "recentFailCount": recent_context_fallback_failures,
            "skippedCount": context_fallback_skipped,
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
        "humanWhatsappResume": {
            "status": human_whatsapp_resume_latest.get("status") if human_whatsapp_resume_latest else None,
            "finishedAt": human_whatsapp_resume_latest.get("finishedAt") if human_whatsapp_resume_latest else None,
            "ageSeconds": age_seconds(human_whatsapp_resume_latest.get("finishedAt"))
            if human_whatsapp_resume_latest
            else None,
            "recentFailCount": recent_human_whatsapp_resume_failures,
            "skippedCount": human_whatsapp_resume_skipped,
        },
        "humanWhatsappResumeFailure": {
            "status": human_whatsapp_resume_failure_latest.get("status") if human_whatsapp_resume_failure_latest else None,
            "finishedAt": human_whatsapp_resume_failure_latest.get("finishedAt")
            if human_whatsapp_resume_failure_latest
            else None,
            "ageSeconds": age_seconds(human_whatsapp_resume_failure_latest.get("finishedAt"))
            if human_whatsapp_resume_failure_latest
            else None,
            "recentFailCount": recent_human_whatsapp_resume_failure_failures,
            "skippedCount": human_whatsapp_resume_failure_skipped,
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
            "whatsappTransport={whatsapp_transport_status} recovery={recovery_status} contextFallback={context_fallback_status} "
            "humanWhatsapp={human_status} humanConversation={human_conversation_status} "
            "humanResume={human_resume_status} humanResumeFailure={human_resume_failure_status} stressRecovery={stress_status}".format(
                status=result["status"],
                selftest_status=result["selftest"]["status"],
                selftest_mode=result["selftest"]["mode"],
                intelligence_status=result["intelligence"]["status"],
                whatsapp_transport_status=result["whatsappTransport"]["status"],
                recovery_status=result["recovery"]["status"],
                context_fallback_status=result["contextFallback"]["status"],
                human_status=result["humanWhatsapp"]["status"],
                human_conversation_status=result["humanWhatsappConversation"]["status"],
                human_resume_status=result["humanWhatsappResume"]["status"],
                human_resume_failure_status=result["humanWhatsappResumeFailure"]["status"],
                stress_status=result["stressRecovery"]["status"] or "missing",
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
        if result["whatsappTransport"]["token"]:
            print(
                "whatsappTransportToken={token} provider={provider} model={model}".format(
                    token=result["whatsappTransport"]["token"],
                    provider=result["whatsappTransport"]["provider"],
                    model=result["whatsappTransport"]["model"],
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
        if result["contextFallback"]["status"]:
            print(
                "contextFallback conversationTurn2={conversation_turn2} conversationTurn3={conversation_turn3} resumeTurn2={resume_turn2}".format(
                    conversation_turn2=result["contextFallback"]["conversationTurn2ContextMode"],
                    conversation_turn3=result["contextFallback"]["conversationTurn3ContextMode"],
                    resume_turn2=result["contextFallback"]["resumeTurn2ContextMode"],
                )
            )
        print(
            "ages selftest={selftest_age} intelligence={intelligence_age} recovery={recovery_age} contextFallback={context_fallback_age} "
            "whatsappTransport={whatsapp_transport_age} qwenSessionsProbe={qwen_probe_age} humanWhatsapp={human_age} "
            "humanConversation={human_conversation_age} humanResume={human_resume_age} "
            "humanResumeFailure={human_resume_failure_age} stressRecovery={stress_age}".format(
                selftest_age=result["selftest"]["ageSeconds"],
                intelligence_age=result["intelligence"]["ageSeconds"],
                whatsapp_transport_age=result["whatsappTransport"]["ageSeconds"],
                qwen_probe_age=result["qwenSessionsProbe"]["ageSeconds"],
                recovery_age=result["recovery"]["ageSeconds"],
                context_fallback_age=result["contextFallback"]["ageSeconds"],
                human_age=result["humanWhatsapp"]["ageSeconds"],
                human_conversation_age=result["humanWhatsappConversation"]["ageSeconds"],
                human_resume_age=result["humanWhatsappResume"]["ageSeconds"],
                human_resume_failure_age=result["humanWhatsappResumeFailure"]["ageSeconds"],
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
