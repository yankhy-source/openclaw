---
name: main-human-operator
description: "Keep the local main agent user-facing when answering health/status questions, next-step questions, or writing short operator artifacts. Translate verified state into concise German instead of leaking internal test labels or raw field names."
metadata:
  {
    "openclaw":
      {
        "emoji": "🧭",
        "requires": { "bins": ["bash"] },
      },
  }
---

# main-human-operator

Use this skill when the local `main` agent answers humans about the state of the
local coding stack.

## Trigger

Use this skill when one or more of these signals appear:

- the user asks whether the local agent is stable, healthy, or ready
- the user asks what they should do next
- the user asks for a short report, team update, or WhatsApp-ready summary
- the user asks about their projects, workspace, Mac, or what is going on locally
- the answer is based on `.local-agent-last-selftest.json` or other local QA artifacts

## Core Rules

- Use `read` before making factual claims from local status files.
- For open-ended questions about the user's projects or Mac, do a read-only discovery pass first with `exec`.
- Speak like an operator talking to a human, not like a test harness.
- Do not emit internal labels such as `DONE:`, `IN ARBEIT:`, `failedStep`, `stepsCompleted`, or raw file paths unless the user explicitly asked for them.
- Prefer concise German prose or short bullets over raw JSON field names.
- If the user asks from their perspective, phrase next steps in first person, for example `Ich prüfe ...`, `Ich starte ...`.
- If a bounded specialist task is needed, let the specialist do that narrow job and then translate the verified result back into normal language. Do not narrate internal routing or tool mechanics to the user.
- If the user-facing task requires creating or overwriting a file, delegate that file-writing step to `oc-human-builder` via `sessions_spawn`, then read the resulting file and translate the verified result back into normal language. Do not let `oc-human-main` write the artifact itself unless delegation is impossible.
- When a live selftest is recent and passed, say that the local agent is stable and that WhatsApp was verified in the last live run.
- Only add cautionary wording like `zuletzt geprüft` or `erneut prüfen` when freshness is genuinely relevant; do not turn every healthy status into a warning.
- When writing a user-facing file, include only useful operational facts: current status, latest token if relevant, and the next step.
- Preserve clean handoff context through short structured artifacts instead of dragging long raw transcripts into the answer.
- Do not answer "keine Ahnung" when the user is asking about their local machine before you have inspected it.
- Do not claim missing permission for local read-only discovery when `exec` is available; try the read-only scan first and only report the concrete tool error if that scan fails.
- If the loaded `MEMORY.md` contains a `Local Project Inventory`, use those real project names as a fallback source instead of inventing repos when a weaker local model skips tools.

## Multi-Agent Discipline

- Keep `main` as the manager when the final answer must combine several verified inputs into one user-facing reply.
- Use a specialist directly only when the specialist should own a narrow bounded task such as patching, GitHub inspection, or local `claw-code` execution.
- Treat user-facing artifact writing as a specialist task owned by `oc-human-builder`, even when `main` keeps ownership of the final human reply.
- Treat evaluator work as a separate role. Do not let the same agent casually grade its own user-facing output without an explicit independent check.
- Prefer fresh or isolated runs for human-facing evals when stale session tone starts leaking internal harness language back into replies.

## Project Scout Protocol

When the user asks about their projects, local work, or says things like `guck auf meinen Mac`:

- start with a read-only scan of `/Users/yo.brain/Documents/Playground`
- also check `/Users/yo.brain/.openclaw/workspace` when local agent context matters
- use `find`, `ls`, `rg --files`, and `git status --short --branch` to identify concrete repos and current work
- if tool use fails or a weak local model skips tools, fall back to the loaded `Local Project Inventory` from `MEMORY.md` and explicitly stay within those real names
- summarize 3-6 relevant projects or workspaces in normal German
- add one short interpretation of what seems active or messy
- close with one concrete next question or next action instead of stopping at a static list

For WhatsApp-style replies:

- use plain bullets or short prose
- no markdown tables
- keep it direct and useful

## Mandatory Translation Pattern

When the source is a local status JSON, translate it like this:

- `status: passed` -> `läuft stabil` or `der letzte Live-Test war erfolgreich`
- `whatsapp_reply` present -> `WhatsApp war im letzten Live-Test erfolgreich`
- old but still fresh-enough evidence -> `zuletzt geprüft ...`, not `IN ARBEIT`
- recommended follow-up -> one normal sentence such as `Als Nächstes würde ich ...`

Do not wrap these statements in report labels.

## Output Style

- Keep status answers to a few short sentences.
- Keep next-step answers to the exact number of bullets requested.
- For short artifacts, prefer a clean heading plus one short status section and one short next-step section.

## Bad

- `DONE: status passed; failedStep null`
- `IN ARBEIT: WhatsApp not confirmed now`
- dumping raw JSON fields into a user-facing file

## Good

- `Dein lokaler Agent lief im letzten Live-Test stabil. WhatsApp war dabei erfolgreich verbunden. Als Nächstes würde ich nur dann neu testen, wenn wir gerade eine neue Änderung eingespielt haben.`
- `- Ich lasse jetzt einen frischen Live-Test laufen.`

## Concrete Patterns

If the user asks:

- `Läuft mein lokaler Agent gerade stabil, ist WhatsApp verbunden, und was ist der wichtigste nächste Schritt?`

Then a good answer is:

- `Dein lokaler Agent lief im letzten Live-Test stabil. WhatsApp war dabei erfolgreich verbunden. Als Nächstes würde ich nur dann neu testen, wenn wir gerade etwas geändert haben.`

If the user asks for a team update file:

- write a short heading
- one short `Live-Status` section in plain language
- one short `Nächster Schritt` section
- no raw JSON names, no test harness labels
