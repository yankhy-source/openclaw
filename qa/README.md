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
- `pnpm qa:local-agents:core-selftest` runs the local coding-agent proofs without the live WhatsApp delivery step.
- `pnpm qa:local-agents:selftest` runs the local end-to-end coding stack check, including `main` exact-read discipline, `main` subagent orchestration, specialist routing, delegated patch work, and WhatsApp reply delivery.
- both selftest modes refresh `.local-agent-last-selftest.json` in the repo root as a machine-readable status artifact for agents and automation.
- `pnpm qa:local-agents:main-smoke` runs `main` as an orchestrator and verifies that it spawns a Codex-backed `oc-builder` child run.
- `pnpm qa:local-agents:routing-smoke` verifies that `main` routes GitHub work to `oc-github` and `claw-code` work to `claw-code`.
- `pnpm qa:local-agents:main-task-smoke` verifies that `main` delegates a small real repo patch task to `oc-builder`.
- `pnpm qa:local-agents:task-smoke` runs one small real repo task through `oc-builder` and verifies the tool usage in session logs.

Keep this folder in git. Add new scenarios here before wiring them into automation.
