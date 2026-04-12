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
let beforeDispatchHandler = null;
plugin.register({
  on(hookName, handler) {
    if (hookName === "before_dispatch") {
      beforeDispatchHandler = handler;
    }
    if (hookName === "before_agent_reply") {
      beforeAgentReplyHandler = handler;
    }
  },
});

assert.equal(typeof beforeDispatchHandler, "function", "before_dispatch hook was not registered");
assert.equal(typeof beforeAgentReplyHandler, "function", "before_agent_reply hook was not registered");

const projectPrompt =
  "Ich bin der Nutzer. Schau jetzt aktiv auf meinen Mac und sage mir, welche Projekte hier gerade relevant sind.";
const projectDispatchResult = await beforeDispatchHandler(
  {
    content: projectPrompt,
    body: projectPrompt,
    channel: "whatsapp",
    sessionKey: "agent:main:whatsapp:direct:+4917623606147",
  },
  {
    channelId: "whatsapp",
    conversationId: "+4917623606147",
    sessionKey: "agent:main:whatsapp:direct:+4917623606147",
    senderId: "+4917623606147",
  },
);
const projectReplyResult = await beforeAgentReplyHandler(
  {
    cleanedBody: projectPrompt,
  },
  {
    agentId: "main",
    sessionKey: "agent:main:whatsapp:direct:+4917623606147",
  },
);

const workPrompt = "Was hast du gearbeitet heute an meine Projekte";
const workDispatchResult = await beforeDispatchHandler(
  {
    content: workPrompt,
    body: workPrompt,
    channel: "whatsapp",
    sessionKey: "agent:main:whatsapp:direct:+4917623606147",
  },
  {
    channelId: "whatsapp",
    conversationId: "+4917623606147",
    sessionKey: "agent:main:whatsapp:direct:+4917623606147",
    senderId: "+4917623606147",
  },
);
const workReplyResult = await beforeAgentReplyHandler(
  {
    cleanedBody: workPrompt,
  },
  {
    agentId: "main",
    sessionKey: "agent:main:whatsapp:direct:+4917623606147",
  },
);

const dispatchText = assertProjectReply("before_dispatch(project)", projectDispatchResult?.text);
const replyText = assertProjectReply("before_agent_reply(project)", projectReplyResult?.reply?.text);
assert.equal(replyText, dispatchText, "before_dispatch and before_agent_reply should agree for project prompts");

const workDispatchText = assertWorkReply("before_dispatch(work)", workDispatchResult?.text);
const workReplyText = assertWorkReply("before_agent_reply(work)", workReplyResult?.reply?.text);
assert.equal(workReplyText, workDispatchText, "before_dispatch and before_agent_reply should agree for work prompts");

console.log(
  JSON.stringify(
    {
      status: "passed",
      pluginPath,
      projectDispatchText: dispatchText,
      projectReplyText: replyText,
      workDispatchText,
      workReplyText,
    },
    null,
    2,
  ),
);

function assertProjectReply(label, rawText) {
  assert.equal(typeof rawText, "string", `${label} hook did not return a text reply`);
  const text = rawText.trim();
  const lines = text.split(/\r?\n/).filter(Boolean);
  assert.equal(lines.length, 4, `${label}: expected 4 bullet lines, got ${lines.length}`);
  assert(lines.every((line) => line.startsWith("- ")), `${label}: reply must use plain bullets: ${text}`);
  assert(
    lines.slice(0, 3).every((line) => !line.startsWith("- -")),
    `${label}: reply must not double-prefix bullets: ${text}`,
  );

  const expectedNames = collectExpectedNames([playgroundRoot, workspaceRoot]);
  const mentioned = expectedNames.filter((name) => text.toLowerCase().includes(name.toLowerCase()));
  assert(mentioned.length >= 2, `${label}: expected at least two real project names in reply: ${text}`);

  const blocked = ["ai_assistant", "cl_image_processing", "nlp_experiments"];
  assert(
    blocked.every((token) => !text.toLowerCase().includes(token)),
    `${label}: reply still hallucinates placeholder repos: ${text}`,
  );
  return text;
}

function assertWorkReply(label, rawText) {
  assert.equal(typeof rawText, "string", `${label} hook did not return a text reply`);
  const text = rawText.trim();
  const lines = text.split(/\r?\n/).filter(Boolean);
  assert.equal(lines.length, 4, `${label}: expected 4 bullet lines, got ${lines.length}`);
  assert(lines.every((line) => line.startsWith("- ")), `${label}: reply must use plain bullets: ${text}`);
  assert(
    /openclaw-local-agents/i.test(text),
    `${label}: expected openclaw-local-agents in work summary: ${text}`,
  );
  assert(
    /(projekt-scout|whatsapp|eval|fallback|reply-pfad|guardrail)/i.test(text),
    `${label}: expected concrete work markers in work summary: ${text}`,
  );
  return text;
}

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
