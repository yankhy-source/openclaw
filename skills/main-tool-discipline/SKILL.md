---
name: main-tool-discipline
description: "Harden the local main agent for exact tool-backed answers. Use when the user asks for exact output, exact formatting, file contents, config values, command output, or explicitly says to use read/exec. Never guess when a tool or a delegated coding agent is required."
metadata:
  {
    "openclaw":
      {
        "emoji": "🎯",
        "requires": { "bins": ["bash"] },
      },
  }
---

# main-tool-discipline

Use this skill to keep the local `main` agent honest on tool-backed tasks.

## Trigger

Use this skill when the request includes one or more of these signals:

- "exakt", "genau", "nur dieses Format"
- "nutze read", "nutze exec"
- file contents, config values, JSON fields, command output
- requests that depend on repository state instead of general knowledge

## Core Rules

- If the answer depends on a file, use `read` first.
- If the answer depends on a command result, use `exec` first.
- If the task is GitHub or `gh` heavy, delegate to `oc-github`.
- If the task is multi-step repo work or patching, delegate to `oc-builder`.
- If the task is about `claw-code` or the parity repo, delegate to `claw-code`.
- If the request explicitly says `sessions_spawn`, "starte einen Subagenten", or otherwise asks for a fresh child run, use `sessions_spawn` directly.
- Do not replace a required fresh child run with `sessions_send`, `sessions_list`, or `sessions_history`.
- For local QA/selftests, prefer a new child session over reusing an older agent session.
- When the user asks for exact output, answer only from the verified tool result.
- Do not infer missing fields from memory or earlier turns when a fresh tool read is requested.

## Exact Output Rule

When the user asks for exact output, exact formatting, or one specific line:

- return only the requested output
- do not add explanations, self-corrections, confidence language, or preambles
- do not restate the question
- if one line was requested, output one line only
- if exact bullets were requested, output only those bullets

Bad:

- `DEFAULT=... Actually check: yes as before`
- `Here is the line you asked for: DEFAULT=...`

Good:

- `DEFAULT=heretic-local/qwen3-4b-instruct-2507;FALLBACK=openai-codex/gpt-5.3-codex-spark`

## Refusal Rule

If the user explicitly requested a tool-backed answer and you do not have a matching tool result yet, do not guess. Use the tool first. If the tool is unavailable or fails, say so plainly.

## Example

Bad:

- User asks for `DEFAULT=<model>;FALLBACK=<model>` from a config file
- You answer from memory

Good:

- `read /path/to/config.json`
- extract the exact values from the file
- answer only in the requested format
