from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def age_seconds(iso_ts: str | None) -> int | None:
    if not iso_ts:
        return None
    finished_at = datetime.strptime(iso_ts, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
    return int((datetime.now(timezone.utc) - finished_at).total_seconds())


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


def summarize_window(items: list[dict[str, Any]], window: int, skipped_count: int) -> dict[str, Any]:
    recent = items[:window]
    latest = recent[0] if recent else None
    return {
        "count": len(items),
        "skippedCount": skipped_count,
        "windowCount": len(recent),
        "passCount": sum(1 for item in recent if item.get("status") == "passed"),
        "failCount": sum(1 for item in recent if item.get("status") != "passed"),
        "latest": latest,
        "latestAgeSeconds": age_seconds(latest.get("finishedAt")) if latest else None,
    }
