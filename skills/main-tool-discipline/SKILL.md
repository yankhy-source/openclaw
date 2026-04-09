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
- When the user asks for exact output, answer only from the verified tool result.
- Do not infer missing fields from memory or earlier turns when a fresh tool read is requested.

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
