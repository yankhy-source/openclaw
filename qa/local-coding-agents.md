# Local Coding Agents

This repo carries a local OpenClaw coding setup for the shared Playground machine.

It is intentionally local-first:

- it wires `claw-code` through the sibling `claw-code-parity` checkout
- it creates fixed agent profiles in `~/.openclaw/openclaw.json`
- it provides a reproducible selftest for the main local coding paths
- it hardens the local `main` agent for exact tool-backed answers

## Files

- `scripts/dev/bootstrap-local-coding-agents.mjs`
  - syncs the `claw-code-local` skill into `~/.openclaw/skills`
  - syncs the `main-tool-discipline` skill into `~/.openclaw/skills`
  - syncs the `main-human-operator` skill into `~/.openclaw/skills`
  - upserts the local coding agent profiles
  - updates `tools.agentToAgent.allow`
  - extends `main.subagents.allowAgents`
  - adds `main-tool-discipline` to `main.skills`
  - adds `main-human-operator` to `main.skills`
  - extends `main.tools.exec.pathPrepend`
  - writes a timestamped backup of `~/.openclaw/openclaw.json`
- `scripts/dev/local-coding-agents-selftest.sh`
  - validates `claw-code`, `exec`, `read`, `patch`, GitHub, and WhatsApp reply delivery
- `scripts/dev/lib/openclaw-smoke-common.sh`
  - shared helper functions for JSON assertions, session resolution, and file waits across the smoke scripts
- `scripts/dev/claw-code-local`
  - stable repo-local launcher for the sibling `claw-code-parity` checkout
- `skills/claw-code-local/SKILL.md`
  - local skill that teaches the agent how to invoke the wrapper correctly

## Agent Profiles

The bootstrap adds these profiles:

- `oc-builder`
  - workspace: this repo
  - purpose: local code execution, repo reads, patching
- `oc-github`
  - workspace: this repo
  - purpose: `gh`-based repo and PR work
- `claw-code`
  - workspace: `../claw-code-parity`
  - purpose: local `claw-code` execution

All three use `openai-codex/gpt-5.3-codex-spark` in the current local setup.

The local `main` agent is also hardened for exact tool-backed work:

- primary model: `openai-codex/gpt-5.3-codex-spark`
- fallback chain starts with `heretic-local/qwen3-4b-instruct-2507`
- spawned subagents from `main` default to `openai-codex/gpt-5.3-codex-spark`
- `main-tool-discipline` is synced into `~/.openclaw/skills` and attached to `main`
- `main-human-operator` is synced into `~/.openclaw/skills` and attached to `main`

## Commands

Bootstrap the profiles and skill sync:

```bash
pnpm qa:local-agents:bootstrap
```

Read the last selftest result without running a new test:

```bash
pnpm qa:local-agents:status
```

Read the recent trend state across intelligence, recovery, and human WhatsApp runs:

```bash
pnpm qa:local-agents:trend
```

Read just the current operating state without the fuller history report:

```bash
pnpm qa:local-agents:ops-status
```

Use `ops-status` for fast health checks and automation gates. Use `trend` when
you want the wider recent-history window and regression warnings.

Audit the local coding-agent config and latest selftest together:

```bash
pnpm qa:local-agents:doctor
```

Require a fresh enough live result during the audit:

```bash
OPENCLAW_SELFTEST_MAX_AGE_SECONDS=21600 \
bash scripts/dev/local-coding-agents-doctor.sh --require-mode live
```

Require freshness for automation or agent gating:

```bash
OPENCLAW_SELFTEST_MAX_AGE_SECONDS=21600 pnpm qa:local-agents:status
```

Ensure a fresh enough green selftest exists and rerun only if needed:

```bash
pnpm qa:local-agents:ensure
```

Require a fresh live run instead of accepting a fresh core-only result:

```bash
OPENCLAW_SELFTEST_MAX_AGE_SECONDS=21600 \
bash scripts/dev/local-coding-agents-ensure.sh --live
```

Run the focused WhatsApp client smoke on top of the latest live summary:

```bash
PATH="${OPENCLAW_SELFTEST_NODE_BIN:-$HOME/.node22/current/bin}:$PATH" \
pnpm qa:local-agents:whatsapp-smoke
```

Run a user-perspective intelligence eval against `main`:

```bash
PATH="${OPENCLAW_SELFTEST_NODE_BIN:-$HOME/.node22/current/bin}:$PATH" \
pnpm qa:local-agents:human-eval
```

That eval now keeps its artifacts on disk under `.local-human-eval/` and refreshes
`.local-agent-last-human-eval.json` in the repo root, so the created answers and
artifact file remain inspectable after the run. It uses fresh dedicated eval
agents instead of the long-lived `main` and `oc-builder` sessions.

Run the same user-perspective style check over the live WhatsApp delivery path:

```bash
PATH="${OPENCLAW_SELFTEST_NODE_BIN:-$HOME/.node22/current/bin}:$PATH" \
pnpm qa:local-agents:human-whatsapp-eval
```

That live eval keeps its outputs under `.local-human-whatsapp-eval/` and refreshes
`.local-agent-last-human-whatsapp-eval.json` in the repo root. It exercises the
real live WhatsApp path through the fresh dedicated `oc-human-main` profile and
first ensures there is a fresh enough live selftest summary available.

Run the harder multi-turn live WhatsApp conversation eval:

```bash
PATH="${OPENCLAW_SELFTEST_NODE_BIN:-$HOME/.node22/current/bin}:$PATH" \
pnpm qa:local-agents:human-whatsapp-conversation-eval
```

That eval keeps its outputs under `.local-human-whatsapp-conversation-eval/`
and refreshes `.local-agent-last-human-whatsapp-conversation-eval.json` in the
repo root. It tests a real three-turn WhatsApp conversation, reuses a marker
from an earlier answer without restating it in the prompt, and proves that the
agent can hand off an artifact-writing task to `oc-human-builder`.

Run the interruption/resume WhatsApp eval:

```bash
PATH="${OPENCLAW_SELFTEST_NODE_BIN:-$HOME/.node22/current/bin}:$PATH" \
pnpm qa:local-agents:human-whatsapp-resume-eval
```

That eval keeps its outputs under `.local-human-whatsapp-resume-eval/` and
refreshes `.local-agent-last-human-whatsapp-resume-eval.json` in the repo root.
It restarts the gateway between turns and then verifies that the agent can
resume the live WhatsApp conversation by recalling the earlier marker and the
next-step context without restating the marker in the prompt.

Run the full research-backed intelligence loop:

```bash
PATH="${OPENCLAW_SELFTEST_NODE_BIN:-$HOME/.node22/current/bin}:$PATH" \
pnpm qa:local-agents:intelligence-loop
```

That loop chains three roles:

- generator-style human eval over the local agent stack
- generator-style human eval over the live WhatsApp path
- deeper multi-turn WhatsApp conversation eval with memory plus a delegated artifact
- interruption/resume eval that forces a gateway restart between turns
- separate evaluator review via `oc-selftest` that reads all summaries and writes one focused next upgrade step

It persists run artifacts under `.local-agent-intelligence-loop/` and refreshes
`.local-agent-last-intelligence-loop.json` in the repo root. Each run also keeps
its own `summary.json` inside the run directory so later trend analysis can read
real history instead of only the latest result.

Run the recovery smoke after an intentional gateway restart:

```bash
PATH="${OPENCLAW_SELFTEST_NODE_BIN:-$HOME/.node22/current/bin}:$PATH" \
pnpm qa:local-agents:recovery-smoke
```

Run a harder burst-and-recover check that chains multiple live WhatsApp evals
before the recovery path:

```bash
pnpm qa:local-agents:stress-recovery-smoke
```

This is the stronger operational proof after the basic green path. It catches
cases where one single live run is green but short burst traffic or an immediate
post-burst restart still exposes instability.

That smoke restarts the gateway, waits for health to return, then proves the
live human WhatsApp path still responds cleanly. It persists artifacts under
`.local-agent-recovery-smoke/` and refreshes
`.local-agent-last-recovery-smoke.json`. Each run also keeps a `summary.json`
inside its run directory.

Run the full end-to-end selftest:

```bash
PATH="${OPENCLAW_SELFTEST_NODE_BIN:-$HOME/.node22/current/bin}:$PATH" \
pnpm qa:local-agents:selftest
```

That full selftest now also includes the `main` orchestrator smoke, the
specialist routing smoke, and the delegated task smoke, so one green run covers
direct tool proofs, delegated subagent proofs, delegated patch work, and
WhatsApp reply delivery.

Run the fast core selftest without the live WhatsApp delivery step:

```bash
PATH="${OPENCLAW_SELFTEST_NODE_BIN:-$HOME/.node22/current/bin}:$PATH" \
pnpm qa:local-agents:core-selftest
```

Use the core variant for frequent local regressions. Keep the full selftest for
end-to-end confidence on the live reply path.

Run a minimal live WhatsApp transport proof without requiring the full
Codex-backed subagent gate to be green:

```bash
PATH="${OPENCLAW_SELFTEST_NODE_BIN:-$HOME/.node22/current/bin}:$PATH" \
pnpm qa:local-agents:whatsapp-transport-smoke
```

This only proves the WhatsApp client can deliver an exact reply through the
configured `main` agent. It does not prove subagent orchestration or delegated
coding intelligence.

Both selftest modes also refresh a stable machine-readable report at
`.local-agent-last-selftest.json` in the repo root. Override the target path
with `OPENCLAW_SELFTEST_SUMMARY_PATH` if another consumer needs a different
location. Use `pnpm qa:local-agents:status --json` only via the underlying
script invocation if a caller needs the enriched JSON form. The `ensure` script
builds on that summary and only reruns the minimum required mode. The `doctor`
script combines summary health with bootstrap/config drift checks.

Run the builder against one small real repo task:

```bash
PATH="${OPENCLAW_SELFTEST_NODE_BIN:-$HOME/.node22/current/bin}:$PATH" \
pnpm qa:local-agents:task-smoke
```

Run the `main` agent as an orchestrator that spawns `oc-builder`:

```bash
PATH="${OPENCLAW_SELFTEST_NODE_BIN:-$HOME/.node22/current/bin}:$PATH" \
pnpm qa:local-agents:main-smoke
```

Run the `main` agent through specialist routing (`oc-github`, `claw-code`):

```bash
PATH="${OPENCLAW_SELFTEST_NODE_BIN:-$HOME/.node22/current/bin}:$PATH" \
pnpm qa:local-agents:routing-smoke
```

Run a small real patch task through `main -> oc-builder`:

```bash
PATH="${OPENCLAW_SELFTEST_NODE_BIN:-$HOME/.node22/current/bin}:$PATH" \
pnpm qa:local-agents:main-task-smoke
```

The selftest script already checks `OPENCLAW_SELFTEST_NODE_BIN` and otherwise
falls back to `$HOME/.node22/current/bin`. Keep that override only when your
login shell resolves `openclaw` through an older Node runtime.

For non-interactive `claw-code` health checks, use `claw-code-local --version`
or `claw-code-local status`. The current Rust CLI treats `summary` as a slash
command, so `claw-code-local summary` is not a stable probe.

## What the Selftest Verifies

- `claw-code` wrapper invocation through the `claw-code` agent
- `exec` through `oc-builder`
- repo file reads through `oc-builder`
- exact JSON read + formatting through `main`
- repo patching through `oc-builder`
- GitHub CLI access through `oc-github`
- `main` subagent orchestration through `oc-builder`
- `main` specialist routing to `oc-github` and `claw-code`
- `main` delegated patch work through `oc-builder`
- live WhatsApp self-delivery through `main`
- stable JSON summary output for the latest run

## What the WhatsApp Client Smoke Verifies

- `doctor`/`ensure` produce or confirm a fresh enough live summary
- `main` can read the latest summary file over the live WhatsApp delivery path
- the live WhatsApp reply matches the exact derived summary string
- the main session log contains the expected `read` tool call on the summary file
- by default it tolerates older but still healthy live summaries for up to 6 hours before forcing a full live refresh

## What the Human Perspective Eval Verifies

- `oc-human-main` answers a human-style status question in concise German
- `oc-human-main` produces a short next-step answer from the user's perspective
- `oc-human-builder` creates a user-facing artifact file from the latest selftest summary
- the eval runs on fresh dedicated QA agents instead of long-lived main sessions
- the status and artifact proofs use run-specific copied summary files, so a fresh `read` is still required even when sessions already know older state
- the answer avoids internal test labels and raw JSON field names
- the created artifact remains on disk for inspection after the eval

## What the Human WhatsApp Eval Verifies

- `oc-human-main` answers a human-style status question over the live WhatsApp delivery path
- the live answer stays out of harness/test-report language
- `oc-human-main` answers a human next-step question in first-person bullets over WhatsApp
- the run keeps persistent artifacts and a machine-readable summary
- the run first confirms or refreshes a fresh enough live selftest baseline
- the status proof uses a run-specific copied summary file, so the live check cannot pass purely from remembered prior state
- the run writes a consistency report for the status context, so the summary records whether token/session binding passed cleanly before the user-facing answer was sent
- that consistency report now also carries `decisionSource`, `decisionReason`, `expectedSummary`, `actualSummary`, `deviationSummary`, a compact `causeLine`, and a fixed user-facing report template for every run (`erwartet=...; tatsaechlich=...; abweichung=...; quelle=...`), so fallback reasons are visible without opening raw snapshots

## What the Intelligence Loop Verifies

- the local human eval, live WhatsApp human eval, deeper WhatsApp conversation eval, interruption/resume eval, lost-context resume-failure eval, and forced context-fallback smoke all pass in the same cycle
- a separate evaluator agent reads all six summaries plus the live selftest summary
- the evaluator writes a concise intelligence review and one focused next upgrade step
- the review avoids leaking internal paths, JSON field names, or harness labels
- the loop leaves behind a stable machine-readable summary for the latest full cycle

## What the Human WhatsApp Resume Failure Eval Verifies

- `main` creates a fresh source marker over the real WhatsApp path
- `oc-human-main` recovers after a gateway restart without sharing `main`'s live chat context
- the recovery agent reconstructs the marker from `agent:main:main` via `sessions_history`
- the recovery agent rewrites a recovery artifact file from reconstructed state instead of an intact happy-path chat memory
- the recovery agent verifies the written artifact with a fresh `read`
- the live reply stays concise, user-facing, and free of harness labels

## What the Context Fallback Smoke Verifies

- the conversation eval still passes when turn 2 receives a deliberately mismatched context token
- the conversation eval still passes when turn 3 receives a deliberately mismatched manager/session binding
- both affected conversation turns switch from memory to `sessions_history` instead of trusting the bad context snapshot
- the resume eval still passes when its turn-2 context snapshot is deliberately mismatched
- the resume turn switches to `sessions_history` instead of trusting the broken resume snapshot
- the conversation and resume fallback paths still share one verified live WhatsApp token and manager session id from the same baseline
- the mismatch reason is written into step-level consistency reports, not only implied by the fallback mode
- those reports now expose the chosen source (`decisionSource`), a short source explanation (`decisionReason`), one compact `causeLine`, and a user-facing report with the same fixed fields in every path: expected value, actual value, detected deviation, and source

## What the Recovery Smoke Verifies

- the gateway can be restarted intentionally without leaving the local stack unhealthy
- the live human WhatsApp eval still passes after the restart
- the recovery result is written to a stable machine-readable summary

## What the Trend Report Verifies

- recent intelligence-loop runs stay green across the inspected history window
- recent recovery-smoke runs stay green across the inspected history window
- the latest human WhatsApp eval is green
- the latest human WhatsApp conversation eval is green
- the latest human WhatsApp resume eval is green
- the latest human WhatsApp resume-failure eval is green
- the latest context-fallback smoke is green
- the latest selftest is still a passed live run
- the most recent next-upgrade recommendation from the intelligence loop stays visible to automation and operators

## Research-Backed Design Rules

These rules are the load-bearing ones in the current local setup:

- keep `main` as a manager when one final answer must combine verified outputs from several specialist paths
- use specialists for bounded tasks such as GitHub inspection, patching, or `claw-code` execution
- keep handoff context in short structured artifacts instead of dragging long transcripts across turns
- run a separate evaluator for user-facing quality instead of trusting the generator to grade itself
- simplify the harness only after proving which parts are actually load-bearing

Primary references behind those choices:

- OpenAI Agents SDK orchestration guide: `agents as tools` vs `handoffs`, eval loops, and specialized agents
- OpenAI Agents SDK handoff prompt guidance for hiding transfer mechanics from the user
- Anthropic harness-design writeup on planner/generator/evaluator roles, structured artifact handoffs, and skepticism in the evaluator

## What the Task Smoke Verifies

- `oc-builder` can read real repo files with `read`
- `oc-builder` can modify a repo-local temp file with `apply_patch` or `edit`
- the session log contains the expected repo-read and repo-write tool calls

## What the Main Orchestrator Smoke Verifies

- `main` uses `sessions_spawn` to start an `oc-builder` child run
- the spawned `oc-builder` child session runs on `openai-codex/gpt-5.3-codex-spark`
- the spawned child uses `exec`
- the spawned child writes the expected proof file

## What the Qwen Sessions Probe Verifies

- `oc-selftest-qwen` runs as a Qwen-only manager with no Codex fallback
- `oc-selftest-qwen` either performs a real `sessions_spawn` call to `oc-builder-qwen` or fails/blocks explicitly
- if the spawn succeeds, the `oc-builder-qwen` child runs on `qwen-portal/coder-model` and writes the proof file via `exec`
- this probe is diagnostic only; it does not by itself prove that the full Codex-backed intelligence stack is green
- the latest machine-readable result is written to `.local-agent-last-qwen-sessions-probe.json`

## What the Alternative Provider Sessions Probes Verify

- `pnpm qa:local-agents:gemini-sessions-probe` drives the same proof through `oc-selftest-gemini` and `oc-builder-gemini`, with no Codex or Qwen fallback
- `pnpm qa:local-agents:heretic-sessions-probe` drives the same proof through `oc-selftest-heretic` and `oc-builder-heretic`, but still rejects fake-success runs that do not produce a real `sessions_spawn` trail
- `pnpm qa:local-agents:openai-sessions-probe` drives the same proof through `oc-selftest-openai` and `oc-builder-openai`, isolating direct OpenAI API behavior from the Codex OAuth lane
- all three probes are diagnostic only; they help classify provider/runtime blockers without changing the main green path
- the latest machine-readable results are written to `.local-agent-last-gemini-sessions-probe.json`, `.local-agent-last-heretic-sessions-probe.json`, and `.local-agent-last-openai-sessions-probe.json`

## What the Main Routing Smoke Verifies

- `main` routes GitHub work to `oc-github`
- `main` routes `claw-code` work to `claw-code`
- the spawned specialist child sessions run on `openai-codex/gpt-5.3-codex-spark`
- both specialist child sessions use `exec`

## What the Main Delegated Task Smoke Verifies

- `main` uses `sessions_spawn` to hand a small repo task to `oc-builder`
- the `oc-builder` child reads the exact repo `package.json` plus a repo-local proof token file
- the `oc-builder` child patches a concrete report file
- the task stays pinned to the intended repo instead of silently reading from `~/.openclaw/workspace`
- the child session stays on `openai-codex/gpt-5.3-codex-spark`

## Real Task Examples

Read repo data through the builder agent:

```bash
PATH="${OPENCLAW_SELFTEST_NODE_BIN:-$HOME/.node22/current/bin}:$PATH" \
openclaw agent --agent oc-builder \
  --message "Nutze read, lies package.json und antworte mit dem lokalen Agent-Selftest-Scriptnamen." \
  --json
```

Run GitHub repo inspection:

```bash
PATH="${OPENCLAW_SELFTEST_NODE_BIN:-$HOME/.node22/current/bin}:$PATH" \
openclaw agent --agent oc-github \
  --message "Nutze exec und führe 'gh repo view yankhy-source/claw-code-parity --json nameWithOwner,isFork,url' aus." \
  --json
```

Run local `claw-code`:

```bash
PATH="${OPENCLAW_SELFTEST_NODE_BIN:-$HOME/.node22/current/bin}:$PATH" \
openclaw agent --agent claw-code \
  --message "Nutze exec und führe 'claw-code-local --version' aus." \
  --json
```

## Expected Local Side Effects

Bootstrap writes only to local OpenClaw state:

- `~/.openclaw/openclaw.json`
- `~/.openclaw/openclaw.json.bak.local-coding-agents-*`
- `~/.openclaw/skills/claw-code-local/SKILL.md`

It does not push, publish, or touch upstream repositories.
