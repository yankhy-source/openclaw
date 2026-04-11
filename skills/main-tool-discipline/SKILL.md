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
- questions like "welche Projekte habe ich", "guck auf meinen Mac", or other local discovery requests
- requests that depend on repository state instead of general knowledge

## Core Rules

- If the answer depends on a file, use `read` first.
- If the answer depends on a command result, use `exec` first.
- If the user asks about projects on this Mac or wants local discovery, start with `exec` and a read-only scan.
- For local discovery, prefer read-only commands such as `pwd`, `ls`, `find`, `rg --files`, `git status --short --branch`, `cat`, and `sed -n`.
- If the relevant path is outside the workspace and a direct `read` would be blocked, use `exec` with read-only shell commands instead of claiming missing permission.
- Do not say "keine Berechtigung", "kein Zugriff", or "ich kann das nicht sehen" before a real `exec`/`read` attempt fails.
- When the user asks broadly about their local projects, inspect `/Users/yo.brain/Documents/Playground` first and also check `/Users/yo.brain/.openclaw/workspace` unless the user named a different root.
- If a weaker fallback model skips tools, prefer the loaded `MEMORY.md` `Local Project Inventory` over guessing; never invent placeholder project names.
- If the task is GitHub or `gh` heavy, delegate to `oc-github`.
- If the task is multi-step repo work or patching, delegate to `oc-builder`.
- If the task is about `claw-code` or the parity repo, delegate to `claw-code`.
- If the request explicitly says `sessions_spawn`, "starte einen Subagenten", or otherwise asks for a fresh child run, use `sessions_spawn` directly.
- If the tool list contains `sessions_spawn`, never claim that the tool is unavailable; call it or report the concrete tool error after the call fails.
- Do not replace a required fresh child run with `sessions_send`, `sessions_list`, or `sessions_history`.
- Do not perform a child task yourself when the user requested `sessions_spawn`; direct `read`, `exec`, `write`, or `edit` in the parent session is a failed delegation.
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

## Local Discovery Rule

When the user asks what exists on their Mac, what projects are active, or what is going on locally:

- inspect first, summarize second
- mention concrete project or folder names you actually found
- if the answer is using `MEMORY.md` inventory fallback, stay anchored to those exact names and say nothing beyond that inventory unless a tool verified it
- give one short status hint per project when available
- end with one concrete next question or suggestion instead of saying you have no idea

## Example

Bad:

- User asks for `DEFAULT=<model>;FALLBACK=<model>` from a config file
- You answer from memory

Good:

- `read /path/to/config.json`
- extract the exact values from the file
- answer only in the requested format
