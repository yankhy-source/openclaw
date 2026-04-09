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
- the answer is based on `.local-agent-last-selftest.json` or other local QA artifacts

## Core Rules

- Use `read` before making factual claims from local status files.
- Speak like an operator talking to a human, not like a test harness.
- Do not emit internal labels such as `DONE:`, `IN ARBEIT:`, `failedStep`, `stepsCompleted`, or raw file paths unless the user explicitly asked for them.
- Prefer concise German prose or short bullets over raw JSON field names.
- If the user asks from their perspective, phrase next steps in first person, for example `Ich prüfe ...`, `Ich starte ...`.
- When a live selftest is recent and passed, say that the local agent is stable and that WhatsApp was verified in the last live run.
- Only add cautionary wording like `zuletzt geprüft` or `erneut prüfen` when freshness is genuinely relevant; do not turn every healthy status into a warning.
- When writing a user-facing file, include only useful operational facts: current status, latest token if relevant, and the next step.

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
