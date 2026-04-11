#!/usr/bin/env node

import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const repoRoot = path.resolve(path.dirname(new URL(import.meta.url).pathname), "..", "..");
const pluginPath = path.join(repoRoot, "scripts", "dev", "local-project-scout.cjs");
const playgroundRoot = process.env.OPENCLAW_PROJECT_SCOUT_ROOT_A ?? path.join(os.homedir(), "Documents", "Playground");
const workspaceRoot = process.env.OPENCLAW_PROJECT_SCOUT_ROOT_B ?? path.join(os.homedir(), ".openclaw", "workspace");
const plugin = require(pluginPath);

let beforeAgentReplyHandler = null;
plugin.register({
  on(hookName, handler) {
    if (hookName === "before_agent_reply") {
      beforeAgentReplyHandler = handler;
    }
  },
});

assert.equal(typeof beforeAgentReplyHandler, "function", "before_agent_reply hook was not registered");

const result = await beforeAgentReplyHandler(
  {
    cleanedBody:
      "Ich bin der Nutzer. Schau jetzt aktiv auf meinen Mac und sage mir, welche Projekte hier gerade relevant sind.",
  },
  {
    agentId: "main",
  },
);

assert.equal(result?.handled, true, "hook did not claim the project scout prompt");
assert.equal(typeof result?.reply?.text, "string", "hook did not return a text reply");

const text = result.reply.text.trim();
const lines = text.split(/\r?\n/).filter(Boolean);
assert.equal(lines.length, 4, `expected 4 bullet lines, got ${lines.length}`);
assert(lines.every((line) => line.startsWith("- ")), `reply must use plain bullets: ${text}`);
assert(lines.slice(0, 3).every((line) => !line.startsWith("- -")), `reply must not double-prefix bullets: ${text}`);

const expectedNames = collectExpectedNames([playgroundRoot, workspaceRoot]);
const mentioned = expectedNames.filter((name) => text.toLowerCase().includes(name.toLowerCase()));
assert(mentioned.length >= 2, `expected at least two real project names in reply: ${text}`);

const blocked = ["ai_assistant", "cl_image_processing", "nlp_experiments"];
assert(blocked.every((token) => !text.toLowerCase().includes(token)), `reply still hallucinates placeholder repos: ${text}`);

console.log(
  JSON.stringify(
    {
      status: "passed",
      pluginPath,
      mentioned,
      text,
    },
    null,
    2,
  ),
);

function collectExpectedNames(roots) {
  const names = [];
  for (const rootPath of roots) {
    if (!fs.existsSync(rootPath) || !fs.statSync(rootPath).isDirectory()) {
      continue;
    }
    for (const entry of fs.readdirSync(rootPath, { withFileTypes: true })) {
      if (!entry.isDirectory() || entry.name.startsWith(".")) {
        continue;
      }
      const lower = entry.name.toLowerCase();
      if (lower.includes("openclaw") || lower.includes("claw-code")) {
        names.push(entry.name);
      }
    }
  }
  return names;
}
