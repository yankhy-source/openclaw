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
  - upserts the local coding agent profiles
  - updates `tools.agentToAgent.allow`
  - extends `main.subagents.allowAgents`
  - adds `main-tool-discipline` to `main.skills`
  - extends `main.tools.exec.pathPrepend`
  - writes a timestamped backup of `~/.openclaw/openclaw.json`
- `scripts/dev/local-coding-agents-selftest.sh`
  - validates `claw-code`, `exec`, `read`, `patch`, GitHub, and WhatsApp reply delivery
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
- `main-tool-discipline` is synced into `~/.openclaw/skills` and attached to `main`

## Commands

Bootstrap the profiles and skill sync:

```bash
pnpm qa:local-agents:bootstrap
```

Run the full end-to-end selftest:

```bash
PATH="${OPENCLAW_SELFTEST_NODE_BIN:-$HOME/.node22/current/bin}:$PATH" \
pnpm qa:local-agents:selftest
```

Run the builder against one small real repo task:

```bash
PATH="${OPENCLAW_SELFTEST_NODE_BIN:-$HOME/.node22/current/bin}:$PATH" \
pnpm qa:local-agents:task-smoke
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
- live WhatsApp self-delivery through `main`

## What the Task Smoke Verifies

- `oc-builder` can read real repo files with `read`
- `oc-builder` can modify a repo-local temp file with `apply_patch` or `edit`
- the session log contains the expected repo-read and repo-write tool calls

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
