from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def load_last_json_object(path: Path) -> dict[str, Any]:
    raw = path.read_text(encoding="utf-8")
    try:
        payload = json.loads(raw)
        if isinstance(payload, dict):
            return payload
    except json.JSONDecodeError:
        pass

    decoder = json.JSONDecoder()
    payload: dict[str, Any] | None = None
    for index, char in enumerate(raw):
        if char != "{":
            continue
        try:
            candidate, _ = decoder.raw_decode(raw[index:])
        except json.JSONDecodeError:
            continue
        if isinstance(candidate, dict):
            payload = candidate
    if payload is None:
        raise ValueError(f"missing JSON object in {path}")
    return payload


def age_seconds(iso_ts: str | None) -> int | None:
    if not iso_ts:
        return None
    finished_at = datetime.strptime(iso_ts, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
    return int((datetime.now(timezone.utc) - finished_at).total_seconds())


def remaining_milliseconds(until_ms: int | float | None) -> int | None:
    if until_ms is None:
        return None
    now_ms = int(datetime.now(timezone.utc).timestamp() * 1000)
    return max(0, int(until_ms) - now_ms)


def selftest_provider_blocker(selftest: dict[str, Any] | None) -> dict[str, Any] | None:
    if not selftest or selftest.get("failedStep") != "tool_provider_preflight":
        return None

    artifact_root = selftest.get("artifactRoot")
    preflight_path = Path(artifact_root) / "tool-provider-preflight.json" if artifact_root else None
    result: dict[str, Any] = {
        "failedStep": selftest.get("failedStep"),
        "failedCommand": selftest.get("failedCommand"),
        "artifactRoot": artifact_root,
        "preflightPath": str(preflight_path) if preflight_path else None,
        "providerResults": [],
        "cooldowns": [],
        "summary": selftest.get("failedCommand") or "tool provider preflight blocked",
    }
    if not preflight_path or not preflight_path.exists():
        return result

    try:
        payload = load_last_json_object(preflight_path)
    except Exception as exc:
        result["summary"] = f"tool provider preflight artifact unreadable: {exc}"
        return result

    provider_results: list[dict[str, Any]] = []
    for item in payload.get("auth", {}).get("probes", {}).get("results") or []:
        if not isinstance(item, dict):
            continue
        provider_results.append(
            {
                "provider": item.get("provider"),
                "model": item.get("model"),
                "profileId": item.get("profileId"),
                "status": item.get("status"),
                "error": item.get("error") or item.get("reasonCode"),
                "latencyMs": item.get("latencyMs"),
            }
        )
    result["providerResults"] = provider_results

    cooldowns: list[dict[str, Any]] = []
    for item in payload.get("auth", {}).get("unusableProfiles") or []:
        if not isinstance(item, dict) or item.get("kind") != "cooldown":
            continue
        until = item.get("until")
        cooldowns.append(
            {
                "provider": item.get("provider"),
                "profileId": item.get("profileId"),
                "until": until,
                "remainingMs": remaining_milliseconds(until),
            }
        )
    result["cooldowns"] = cooldowns

    if provider_results:
        summary_items = []
        for item in provider_results:
            provider = item.get("provider")
            model = item.get("model")
            if provider and model and str(model).startswith(f"{provider}/"):
                label = str(model)
            else:
                label = "/".join(part for part in [provider, model] if part)
            status = item.get("status") or "unknown"
            error = item.get("error")
            summary_items.append(f"{label}={status}{':' + error if error else ''}")
        result["summary"] = "; ".join(summary_items)
    return result


def is_incomplete_run(kind: str, payload: dict[str, Any]) -> bool:
    if payload.get("status") != "failed":
        return False
    if payload.get("failedCommand"):
        return False
    if kind == "human_whatsapp":
        return not payload.get("statusText") and not payload.get("planText")
    if kind == "human_whatsapp_conversation":
        return (
            not payload.get("turn1Text")
            and not payload.get("turn2Text")
            and not payload.get("turn3Text")
            and not payload.get("artifactText")
        )
    if kind == "human_whatsapp_resume":
        return not payload.get("turn1Text") and not payload.get("turn2Text")
    if kind == "human_whatsapp_resume_failure":
        return (
            not payload.get("turn1Text")
            and not payload.get("turn2Text")
            and not payload.get("artifactText")
        )
    if kind == "recovery":
        return payload.get("humanWhatsappStatus") is None and not payload.get("humanWhatsappStatusText")
    if kind == "intelligence":
        return (
            payload.get("selftestStatus") == "passed"
            and payload.get("selftestMode") == "live"
            and payload.get("humanEvalStatus") == "passed"
            and payload.get("humanWhatsappEvalStatus") == "passed"
            and payload.get("humanWhatsappConversationStatus") in (None, "passed")
            and payload.get("humanWhatsappResumeStatus") in (None, "passed")
            and payload.get("humanWhatsappResumeFailureStatus") in (None, "passed")
            and not payload.get("reviewText")
            and not payload.get("nextUpgrade")
        )
    return False


def load_run_summaries(base: Path, kind: str) -> tuple[list[dict[str, Any]], int]:
    if not base.exists():
        return [], 0
    items: list[dict[str, Any]] = []
    skipped = 0
    for summary_path in sorted(base.glob("run.*/summary.json"), reverse=True):
        try:
            payload = load_json(summary_path)
        except Exception:
            continue
        if is_incomplete_run(kind, payload):
            skipped += 1
            continue
        payload["_summaryPath"] = str(summary_path)
        items.append(payload)
    items.sort(key=lambda item: item.get("finishedAt", ""), reverse=True)
    return items, skipped


def latest_problem(label: str, payload: dict[str, Any]) -> str:
    status = payload.get("status")
    if status == "blocked":
        return f"latest {label} blocked"
    return f"latest {label} failed"


def summarize_window(items: list[dict[str, Any]], window: int, skipped_count: int) -> dict[str, Any]:
    recent = items[:window]
    latest = recent[0] if recent else None
    return {
        "count": len(items),
        "skippedCount": skipped_count,
        "windowCount": len(recent),
        "passCount": sum(1 for item in recent if item.get("status") == "passed"),
        "failCount": sum(1 for item in recent if item.get("status") != "passed"),
        "blockedCount": sum(1 for item in recent if item.get("status") == "blocked"),
        "latest": latest,
        "latestAgeSeconds": age_seconds(latest.get("finishedAt")) if latest else None,
    }
