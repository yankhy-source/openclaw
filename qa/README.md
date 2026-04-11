# QA Scenarios

Seed QA assets for the private `qa-lab` extension.

Files:

- `QA_KICKOFF_TASK.md` - operator prompt for the QA agent.
- `frontier-harness-plan.md` - big-model bakeoff and tuning loop for harness work.
- `local-coding-agents.md` - local OpenClaw coding-agent bootstrap and selftest workflow.
- `seed-scenarios.json` - repo-backed baseline QA scenarios.

Key workflow:

- `qa suite` is the executable frontier subset / regression loop.
- `qa manual` is the scoped personality and style probe after the executable subset is green.
- `pnpm qa:local-agents:bootstrap` syncs the local coding profiles and shared skills into `~/.openclaw`.
- `pnpm qa:local-agents:doctor` audits the local coding-agent config plus latest selftest summary and exits non-zero on drift.
- `pnpm qa:local-agents:ensure` checks the last selftest summary and reruns the minimal required selftest when the state is missing, stale, failed, or below the requested mode.
- `pnpm qa:local-agents:status` reads the latest selftest summary and exits non-zero if the last run failed or is stale.
- `pnpm qa:local-agents:ops-status` prints the current operating state across selftest, intelligence loop, recovery, human WhatsApp, the deeper human WhatsApp conversation path, and the interruption/resume path, with warning-only recent-history counters.
- `pnpm qa:local-agents:trend` reads recent per-run summaries for intelligence, recovery, human WhatsApp, the deeper human WhatsApp conversation path, and the interruption/resume path and exits non-zero on visible regressions in the inspected window.
- `pnpm qa:local-agents:core-selftest` runs the local coding-agent proofs without the live WhatsApp delivery step.
- `pnpm qa:local-agents:selftest` runs the local end-to-end coding stack check, including `main` exact-read discipline, `main` subagent orchestration, specialist routing, delegated patch work, and WhatsApp reply delivery.
- `pnpm qa:local-agents:whatsapp-transport-smoke` runs a minimal live WhatsApp transport proof without requiring the full Codex-backed subagent selftest to be green first.
- `pnpm qa:local-agents:whatsapp-smoke` runs the focused live WhatsApp client proof on top of `doctor/ensure`.
- `pnpm qa:local-agents:human-eval` runs user-perspective questions through fresh dedicated eval agents plus a user-facing artifact task, and keeps the outputs under `.local-human-eval/` plus `.local-agent-last-human-eval.json`.
- `pnpm qa:local-agents:human-whatsapp-eval` runs user-perspective questions over the live WhatsApp delivery path through `oc-human-main`, ensures there is a fresh enough live baseline first, and keeps the outputs under `.local-human-whatsapp-eval/` plus `.local-agent-last-human-whatsapp-eval.json`.
- `pnpm qa:local-agents:human-whatsapp-conversation-eval` runs a deeper multi-turn live WhatsApp conversation with a memory marker plus a delegated builder artifact, and keeps the outputs under `.local-human-whatsapp-conversation-eval/` plus `.local-agent-last-human-whatsapp-conversation-eval.json`.
- `pnpm qa:local-agents:human-whatsapp-resume-eval` runs a live WhatsApp interruption/resume check by restarting the gateway between turns and verifying that the agent resumes with the earlier marker and next-step context, storing outputs under `.local-human-whatsapp-resume-eval/` plus `.local-agent-last-human-whatsapp-resume-eval.json`.
- `pnpm qa:local-agents:human-whatsapp-resume-failure-eval` runs a harder lost-context recovery path: `main` creates a unique source marker, then `oc-human-main` reconstructs that marker from `agent:main:main` via `sessions_history`, rewrites a recovery artifact, and answers over live WhatsApp. Outputs live under `.local-human-whatsapp-resume-failure-eval/` plus `.local-agent-last-human-whatsapp-resume-failure-eval.json`.
- `pnpm qa:local-agents:context-fallback-smoke` injects controlled mismatches into the conversation/resume context snapshots and only passes if those runs automatically fall back to `sessions_history` while still completing successfully. Outputs live under `.local-agent-context-fallback-smoke/` plus `.local-agent-last-context-fallback-smoke.json`.
- the WhatsApp human, conversation, resume, and resume-failure evals now also persist step-level consistency reports that record whether token/session/marker checks passed cleanly or why a fallback path was required, including `decisionSource`, `decisionReason`, `expectedSummary`, `actualSummary`, `deviationSummary`, a compact `causeLine`, and a fixed user-facing report template for every run: `erwartet=...; tatsaechlich=...; abweichung=...; quelle=...`.
- `pnpm qa:local-agents:intelligence-loop` runs the full human loop: human eval, WhatsApp human eval, the deeper WhatsApp conversation eval, the interruption/resume eval, the lost-context resume-failure eval, the forced context-fallback smoke, and a separate evaluator review with a next upgrade recommendation stored under `.local-agent-intelligence-loop/` plus `.local-agent-last-intelligence-loop.json`.
- `pnpm qa:local-agents:recovery-smoke` intentionally restarts the gateway and then proves the live WhatsApp human path recovers cleanly, storing the result under `.local-agent-recovery-smoke/` plus `.local-agent-last-recovery-smoke.json`.
- `pnpm qa:local-agents:stress-recovery-smoke` runs several back-to-back live human WhatsApp evals and then a full recovery smoke, storing the aggregate result under `.local-agent-stress-recovery-smoke/` plus `.local-agent-last-stress-recovery-smoke.json`.
- both selftest modes refresh `.local-agent-last-selftest.json` in the repo root as a machine-readable status artifact for agents and automation.
- `pnpm qa:local-agents:main-smoke` runs `main` as an orchestrator and verifies that it spawns a Codex-backed `oc-builder` child run.
- `pnpm qa:local-agents:qwen-sessions-probe` runs the same orchestrator proof through dedicated Qwen-only probe agents to check whether `qwen-portal/coder-model` actually exposes the `sessions_spawn` runtime tool in this local setup, and writes `.local-agent-last-qwen-sessions-probe.json`.
- `pnpm qa:local-agents:gemini-sessions-probe` runs the same orchestrator proof through dedicated Gemini-only probe agents to detect provider/runtime mismatches on `google-gemini`, and writes `.local-agent-last-gemini-sessions-probe.json`.
- `pnpm qa:local-agents:heretic-sessions-probe` runs the same orchestrator proof through dedicated `heretic-local` probe agents to catch fake-success or missing-tool behavior before it can pollute the main quality lane, and writes `.local-agent-last-heretic-sessions-probe.json`.
- `pnpm qa:local-agents:openai-sessions-probe` runs the same orchestrator proof through dedicated `openai` probe agents to diagnose direct OpenAI API-backed session behavior independently of the Codex OAuth lane, and writes `.local-agent-last-openai-sessions-probe.json`.
- `pnpm qa:local-agents:routing-smoke` verifies that `main` routes GitHub work to `oc-github` and `claw-code` work to `claw-code`.
- `pnpm qa:local-agents:main-task-smoke` verifies that `main` delegates a small real repo patch task to `oc-builder`.
- `pnpm qa:local-agents:task-smoke` runs one small real repo task through `oc-builder` and verifies the tool usage in session logs.

Working rule behind these flows:

- keep `main` as the user-facing manager when one answer must combine multiple verified inputs
- use specialists for bounded tasks
- preserve handoff state in short files and summaries
- grade user-facing quality with a separate evaluator instead of trusting the generator alone

Keep this folder in git. Add new scenarios here before wiring them into automation.
