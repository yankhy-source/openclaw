---
name: claw-code-local
description: "Use the local claw-code installation that is wired to the sibling claw-code-parity checkout. Use when: (1) you need claw-code version or summary output, (2) you need to inspect or operate on the local claw-code-parity workspace, (3) you need a stable local command path for claw-code from OpenClaw. NOT for: generic GitHub tasks (use github), generic coding delegation (use coding-agent), or questions that can be answered by reading files directly."
metadata:
  {
    "openclaw":
      {
        "emoji": "🦞",
        "requires": { "bins": ["bash"] },
      },
  }
---

# claw-code-local

Use the local `claw-code` integration that lives beside this OpenClaw checkout.

## Trigger

Use this skill when the task explicitly involves:

- the sibling `claw-code-parity` repository
- the `claw-code` binary or wrapper
- validating that local OpenClaw can invoke `claw-code`

## Local Paths

- OpenClaw wrapper command: `claw-code-local`
- OpenClaw wrapper path: `scripts/dev/claw-code-local`
- Parity repo root: `../claw-code-parity`
- Parity repo wrapper: `../claw-code-parity/scripts/claw-code`
- Rust binary (preferred when present): `../claw-code-parity/rust/target/release/claw`

## Fast Checks

```bash
claw-code-local --version
claw-code-local summary
```

## Behavior

- Prefer `claw-code-local` over guessing where the parity repo lives.
- The wrapper automatically prefers the Rust binary when it exists.
- If the Rust binary is missing, it falls back to the parity repo launcher.
- If you need more context, read files in `../claw-code-parity` directly.

## Typical Uses

### Check the installed local version

```bash
claw-code-local --version
```

### Summarize the local parity workspace

```bash
claw-code-local summary
```

### Work against the parity repository explicitly

```bash
cd ../claw-code-parity
git status --short
```

## Notes

- This is a local integration, not an upstream OpenClaw core feature.
- If `claw-code-local` fails, inspect `scripts/dev/claw-code-local` first, then verify that `../claw-code-parity` still exists.
