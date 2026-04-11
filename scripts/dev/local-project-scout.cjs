"use strict";

const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { execFileSync } = require("node:child_process");

const HOME_DIR = os.homedir();
const PLAYGROUND_ROOT = process.env.OPENCLAW_PROJECT_SCOUT_ROOT_A || path.join(HOME_DIR, "Documents", "Playground");
const WORKSPACE_ROOT = process.env.OPENCLAW_PROJECT_SCOUT_ROOT_B || path.join(HOME_DIR, ".openclaw", "workspace");

const KNOWN_PROJECTS = [
  "openclaw-local-agents",
  "claw-code-parity",
  "openclaw-local-upstream",
  "openclaw-src",
  "openclaw-git",
  "openclaw-ci-fix",
  "openclaw-agents-ci-fix",
  "qwen-code-upstream",
];

const PROJECT_HINTS = {
  "openclaw-local-agents": "aktueller Repo fuer Agenten, Skills und WhatsApp-Tests",
  "claw-code-parity": "lokale Paritaetskopie von ultraworkers/claw-code",
  "openclaw-local-upstream": "Upstream-Referenz fuer Vergleiche und Rueckports",
  "openclaw-src": "tieferer Source-Checkout fuer OpenClaw-Code",
  "openclaw-git": "Git-Worktree fuer Branches und Hotfixes",
  "openclaw-ci-fix": "separater CI-Fix-Worktree",
  "openclaw-agents-ci-fix": "Agents-spezifischer CI-Fix-Worktree",
  "qwen-code-upstream": "Qwen-Upstream fuer Referenzvergleiche",
};

module.exports = {
  id: "local-project-scout",
  name: "Local Project Scout",
  description: "Short-circuit project and Mac discovery questions with a deterministic local scan.",
  register(api) {
    api.on("before_agent_reply", async (event, ctx) => {
      if (!shouldHandleProjectScout(event, ctx)) {
        return;
      }

      const projectCards = collectProjectCards();
      if (projectCards.length < 2) {
        return;
      }

      const selected = projectCards.slice(0, 3);
      const questionTargets = selected.slice(0, 3).map((card) => card.name).join(", ");
      const lines = selected.map((card) => `- ${card.name} - ${card.hint}`);
      lines.push(`- Womit soll ich als Naechstes weitermachen: ${questionTargets}?`);

      return {
        handled: true,
        reason: "local-project-scout",
        reply: {
          text: lines.join("\n"),
        },
      };
    });
  },
};

function shouldHandleProjectScout(event, ctx) {
  if (ctx && typeof ctx.agentId === "string" && !["main", "oc-human-main"].includes(ctx.agentId)) {
    return false;
  }
  const cleanedBody = normalizeText(event && event.cleanedBody);
  if (!cleanedBody) {
    return false;
  }
  return (
    /(welche|was|guck|schau|zeig|analys)/.test(cleanedBody) &&
    /(projekt|projekte|repo|repos|mac|workspace|lokal|local|playground|code)/.test(cleanedBody)
  ) || /(meine projekte|auf meinen mac|auf meinem mac|was ist hier relevant|was geht hier ab)/.test(cleanedBody);
}

function collectProjectCards() {
  const seen = new Set();
  const cards = [];
  for (const name of KNOWN_PROJECTS) {
    const fullPath = resolveProjectPath(name);
    if (!fullPath || seen.has(name)) {
      continue;
    }
    cards.push({
      name,
      path: fullPath,
      hint: buildProjectHint(name, fullPath),
      score: projectScore(name, fullPath),
    });
    seen.add(name);
  }
  for (const root of [PLAYGROUND_ROOT, WORKSPACE_ROOT]) {
    for (const entry of readVisibleDirectories(root)) {
      if (seen.has(entry.name)) {
        continue;
      }
      if (!looksRelevant(entry.name)) {
        continue;
      }
      cards.push({
        name: entry.name,
        path: entry.fullPath,
        hint: buildProjectHint(entry.name, entry.fullPath),
        score: projectScore(entry.name, entry.fullPath),
      });
      seen.add(entry.name);
    }
  }
  return cards.sort((left, right) => right.score - left.score || left.name.localeCompare(right.name));
}

function resolveProjectPath(name) {
  const candidates = [path.join(PLAYGROUND_ROOT, name), path.join(WORKSPACE_ROOT, name)];
  for (const candidate of candidates) {
    if (isDirectory(candidate)) {
      return candidate;
    }
  }
  return null;
}

function buildProjectHint(name, fullPath) {
  const baseHint = PROJECT_HINTS[name] || "lokaler Arbeitsordner";
  const gitHint = readGitHint(fullPath);
  return gitHint ? `${baseHint}; ${gitHint}` : baseHint;
}

function readGitHint(fullPath) {
  if (!isDirectory(path.join(fullPath, ".git"))) {
    return "";
  }
  try {
    const output = execFileSync("git", ["-C", fullPath, "status", "--short", "--branch"], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
      timeout: 4000,
    }).trim();
    if (!output) {
      return "sauber";
    }
    const lines = output.split(/\r?\n/).filter(Boolean);
    const branchLine = lines[0] && lines[0].startsWith("## ") ? lines[0].slice(3).trim() : "";
    const dirtyCount = Math.max(lines.length - (branchLine ? 1 : 0), 0);
    if (branchLine && dirtyCount > 0) {
      return `${branchLine}, ${dirtyCount} offene Aenderungen`;
    }
    if (branchLine) {
      return branchLine;
    }
    if (dirtyCount > 0) {
      return `${dirtyCount} offene Aenderungen`;
    }
  } catch {
    return "Git-Repo";
  }
  return "";
}

function projectScore(name, fullPath) {
  const lower = String(name).toLowerCase();
  let score = 0;
  if (KNOWN_PROJECTS.indexOf(name) !== -1) {
    score += 100 - KNOWN_PROJECTS.indexOf(name);
  }
  if (lower.includes("openclaw")) {
    score += 30;
  }
  if (lower.includes("claw-code")) {
    score += 25;
  }
  if (lower.includes("qwen")) {
    score += 15;
  }
  if (String(fullPath).startsWith(PLAYGROUND_ROOT)) {
    score += 10;
  }
  return score;
}

function looksRelevant(name) {
  const lower = String(name).toLowerCase();
  return lower.includes("openclaw") || lower.includes("claw-code") || lower.includes("qwen");
}

function readVisibleDirectories(rootPath) {
  if (!isDirectory(rootPath)) {
    return [];
  }
  try {
    return fs
      .readdirSync(rootPath, { withFileTypes: true })
      .filter((entry) => entry.isDirectory() && !entry.name.startsWith("."))
      .map((entry) => ({
        name: entry.name,
        fullPath: path.join(rootPath, entry.name),
      }));
  } catch {
    return [];
  }
}

function isDirectory(targetPath) {
  try {
    return fs.statSync(targetPath).isDirectory();
  } catch {
    return false;
  }
}

function normalizeText(value) {
  return String(value || "")
    .toLowerCase()
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}
