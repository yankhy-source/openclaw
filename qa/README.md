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
- `pnpm qa:local-agents:selftest` runs the local end-to-end coding stack check, including `main` exact-read discipline, `main` subagent orchestration, specialist routing, and WhatsApp reply delivery.
- `pnpm qa:local-agents:main-smoke` runs `main` as an orchestrator and verifies that it spawns a Codex-backed `oc-builder` child run.
- `pnpm qa:local-agents:routing-smoke` verifies that `main` routes GitHub work to `oc-github` and `claw-code` work to `claw-code`.
- `pnpm qa:local-agents:task-smoke` runs one small real repo task through `oc-builder` and verifies the tool usage in session logs.

Keep this folder in git. Add new scenarios here before wiring them into automation.
