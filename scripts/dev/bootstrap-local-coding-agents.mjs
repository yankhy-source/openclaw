#!/usr/bin/env node

import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(__dirname, "..", "..");
const homeDir = os.homedir();
const stateDir = resolveHomePath(process.env.OPENCLAW_STATE_DIR ?? path.join(homeDir, ".openclaw"));
const configPath = resolveHomePath(process.env.OPENCLAW_CONFIG_PATH ?? path.join(stateDir, "openclaw.json"));
const sharedSkillsRoot = path.join(stateDir, "skills");
const parityRoot = resolveHomePath(process.env.CLAW_CODE_PARITY_ROOT ?? path.join(repoRoot, "..", "claw-code-parity"));
const sharedSkillIds = ["claw-code-local", "main-tool-discipline", "main-human-operator"];
const mainPrimaryModel = "openai-codex/gpt-5.3-codex-spark";
const mainFallbackModels = [
  "heretic-local/qwen3-4b-instruct-2507",
  "groq/llama-3.3-70b-versatile",
  "groq/deepseek-r1-distill-llama-70b",
  "google-gemini/gemini-2.0-flash",
];
const specialistModel = {
  primary: mainPrimaryModel,
  fallbacks: [...mainFallbackModels],
};

const sharedPathPrepend = [
  path.join(repoRoot, "scripts", "dev"),
  path.join(parityRoot, "scripts"),
  path.join(homeDir, "bin"),
  path.join(homeDir, ".openclaw", ".venvs", "ai-tools", "bin"),
];

const agentIds = ["oc-builder", "oc-github", "claw-code"];
const humanEvalAgentIds = ["oc-human-main", "oc-human-builder"];

await ensureExists(path.dirname(configPath), "OpenClaw config directory");
await ensureExists(parityRoot, "claw-code parity repository");
await syncSharedSkills();
const { config, rawConfig } = await readConfig();
const backupPath = await backupConfig(rawConfig);
mutateConfig(config);
await fs.writeFile(configPath, JSON.stringify(config, null, 2) + "\n", "utf8");

const summary = {
  configPath,
  backupPath,
  sharedSkills: sharedSkillIds.map((id) => path.join(sharedSkillsRoot, id)),
  repoRoot,
  parityRoot,
  agentIds: [...agentIds, ...humanEvalAgentIds],
};
console.log(JSON.stringify(summary, null, 2));

function resolveHomePath(value) {
  if (!value.startsWith("~")) {
    return path.resolve(value);
  }
  if (value === "~") {
    return homeDir;
  }
  return path.join(homeDir, value.slice(2));
}

async function ensureExists(targetPath, label) {
  try {
    await fs.access(targetPath);
  } catch {
    throw new Error(`${label} not found: ${targetPath}`);
  }
}

async function syncSharedSkills() {
  for (const skillId of sharedSkillIds) {
    const sourceSkillDir = path.join(repoRoot, "skills", skillId);
    const targetSkillDir = path.join(sharedSkillsRoot, skillId);
    await ensureExists(sourceSkillDir, `Source ${skillId} skill`);
    await fs.mkdir(targetSkillDir, { recursive: true });
    await fs.copyFile(path.join(sourceSkillDir, "SKILL.md"), path.join(targetSkillDir, "SKILL.md"));
  }
}

async function readConfig() {
  const rawConfig = await fs.readFile(configPath, "utf8");
  let config;
  try {
    config = JSON.parse(rawConfig);
  } catch (error) {
    throw new Error(`OpenClaw config must be valid JSON at ${configPath}: ${String(error)}`);
  }
  if (!config || typeof config !== "object") {
    throw new Error(`Invalid OpenClaw config object at ${configPath}`);
  }
  return { config, rawConfig };
}

async function backupConfig(rawConfig) {
  const backupPath = `${configPath}.bak.local-coding-agents-${Date.now()}`;
  await fs.writeFile(backupPath, rawConfig, "utf8");
  return backupPath;
}

function mutateConfig(config) {
  config.agents ??= {};
  config.agents.defaults ??= {};
  config.agents.list = Array.isArray(config.agents.list) ? config.agents.list : [];
  config.tools ??= {};
  config.tools.agentToAgent ??= {};
  config.agents.defaults.subagents ??= {};
  config.agents.defaults.sandbox ??= {};
  config.agents.defaults.sandbox.mode = "off";
  config.agents.defaults.subagents.model = mainPrimaryModel;
  config.tools.deny = Array.isArray(config.tools.deny)
    ? config.tools.deny.filter(
        (entry) => !["group:fs", "group:runtime", "group:web"].includes(String(entry).trim()),
      )
    : config.tools.deny;

  const desiredAgents = [
    {
      id: "oc-selftest",
      name: "OpenClaw Selftest",
      workspace: repoRoot,
      model: {
        primary: specialistModel.primary,
        fallbacks: [...specialistModel.fallbacks],
      },
      skills: ["main-tool-discipline", "session-logs"],
      identity: {
        name: "OpenClaw Selftest",
        theme: "Isolated orchestration for local agent QA",
        emoji: "🧪",
      },
      subagents: {
        model: mainPrimaryModel,
        allowAgents: [...agentIds],
      },
      tools: {
        profile: "coding",
        fs: {
          workspaceOnly: true,
        },
        exec: {
          pathPrepend: sharedPathPrepend,
        },
      },
    },
    {
      id: "oc-builder",
      name: "OpenClaw Builder",
      workspace: repoRoot,
      model: {
        primary: specialistModel.primary,
        fallbacks: [...specialistModel.fallbacks],
      },
      skills: ["claw-code-local", "coding-agent", "github", "session-logs"],
      identity: {
        name: "OpenClaw Builder",
        theme: "Local code execution and patching",
        emoji: "🛠️",
      },
      tools: {
        profile: "coding",
        fs: {
          workspaceOnly: true,
        },
        exec: {
          pathPrepend: sharedPathPrepend,
        },
      },
    },
    {
      id: "oc-github",
      name: "OpenClaw GitHub",
      workspace: repoRoot,
      model: {
        primary: specialistModel.primary,
        fallbacks: [...specialistModel.fallbacks],
      },
      skills: ["github", "session-logs", "claw-code-local"],
      identity: {
        name: "OpenClaw GitHub",
        theme: "Repository and PR operations",
        emoji: "🐙",
      },
      tools: {
        profile: "coding",
        fs: {
          workspaceOnly: true,
        },
        exec: {
          pathPrepend: sharedPathPrepend,
        },
      },
    },
    {
      id: "claw-code",
      name: "claw-code",
      workspace: parityRoot,
      model: {
        primary: specialistModel.primary,
        fallbacks: [...specialistModel.fallbacks],
      },
      skills: ["claw-code-local", "session-logs"],
      identity: {
        name: "claw-code",
        theme: "Local claw-code parity operations",
        emoji: "🦞",
      },
      tools: {
        profile: "coding",
        fs: {
          workspaceOnly: true,
        },
        exec: {
          pathPrepend: sharedPathPrepend,
        },
      },
    },
    {
      id: "oc-human-main",
      name: "OpenClaw Human Main",
      workspace: repoRoot,
      model: {
        primary: specialistModel.primary,
        fallbacks: [...specialistModel.fallbacks],
      },
      skills: ["main-tool-discipline", "main-human-operator", "session-logs"],
      identity: {
        name: "OpenClaw Human Main",
        theme: "Fresh user-facing local operator answers",
        emoji: "🧭",
      },
      subagents: {
        model: mainPrimaryModel,
        allowAgents: ["oc-human-builder"],
      },
      tools: {
        profile: "coding",
        fs: {
          workspaceOnly: true,
        },
        exec: {
          pathPrepend: sharedPathPrepend,
        },
      },
    },
    {
      id: "oc-human-builder",
      name: "OpenClaw Human Builder",
      workspace: repoRoot,
      model: {
        primary: specialistModel.primary,
        fallbacks: [...specialistModel.fallbacks],
      },
      skills: ["claw-code-local", "coding-agent", "main-human-operator", "session-logs"],
      identity: {
        name: "OpenClaw Human Builder",
        theme: "Fresh user-facing artifact generation",
        emoji: "📝",
      },
      tools: {
        profile: "coding",
        fs: {
          workspaceOnly: true,
        },
        exec: {
          pathPrepend: sharedPathPrepend,
        },
      },
    },
  ];

  for (const agent of desiredAgents) {
    upsertAgent(config.agents.list, agent);
  }

  const allow = Array.isArray(config.tools.agentToAgent.allow) ? config.tools.agentToAgent.allow : [];
  config.tools.agentToAgent.allow = uniqueStrings([...allow, "oc-selftest", ...agentIds, ...humanEvalAgentIds]);

  const mainAgent = config.agents.list.find((entry) => entry && entry.id === "main");
  if (mainAgent) {
    const skills = Array.isArray(mainAgent.skills) ? mainAgent.skills : [];
    mainAgent.skills = uniqueStrings([...skills, "main-tool-discipline", "main-human-operator"]);
    mainAgent.model = {
      primary: mainPrimaryModel,
      fallbacks: uniqueStrings(mainFallbackModels),
    };
    mainAgent.subagents ??= {};
    mainAgent.subagents.model = mainPrimaryModel;
    const allowAgents = Array.isArray(mainAgent.subagents.allowAgents) ? mainAgent.subagents.allowAgents : [];
    mainAgent.subagents.allowAgents = uniqueStrings([...allowAgents, ...agentIds]);
    mainAgent.tools = mergeTools(mainAgent.tools, {
      profile: "coding",
      fs: {
        workspaceOnly: true,
      },
      exec: {
        pathPrepend: sharedPathPrepend,
      },
    });
  }
}

function upsertAgent(list, nextAgent) {
  const index = list.findIndex((entry) => entry && entry.id === nextAgent.id);
  if (index === -1) {
    list.push(nextAgent);
    return;
  }
  const merged = {
    ...list[index],
    ...nextAgent,
    identity: {
      ...(list[index].identity ?? {}),
      ...(nextAgent.identity ?? {}),
    },
    tools: mergeTools(list[index].tools, nextAgent.tools),
  };
  delete merged.thinkingDefault;
  delete merged.reasoningDefault;
  list[index] = merged;
}

function mergeTools(existing, incoming) {
  if (!existing) {
    return incoming;
  }
  if (!incoming) {
    return existing;
  }
  return {
    ...existing,
    ...incoming,
    profile: incoming.profile ?? existing.profile,
    fs: {
      ...(existing.fs ?? {}),
      ...(incoming.fs ?? {}),
    },
    exec: {
      ...(existing.exec ?? {}),
      ...(incoming.exec ?? {}),
      pathPrepend: uniqueStrings([...(existing.exec?.pathPrepend ?? []), ...(incoming.exec?.pathPrepend ?? [])]),
    },
  };
}

function uniqueStrings(values) {
  return [...new Set(values.filter((value) => typeof value === "string" && value.trim().length > 0))];
}
