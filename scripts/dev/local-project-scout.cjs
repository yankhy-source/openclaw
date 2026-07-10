"use strict";

const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { execFileSync } = require("node:child_process");

const HOME_DIR = os.homedir();
const PLAYGROUND_ROOT = process.env.OPENCLAW_PROJECT_SCOUT_ROOT_A || path.join(HOME_DIR, "Documents", "Playground");
const WORKSPACE_ROOT = process.env.OPENCLAW_PROJECT_SCOUT_ROOT_B || path.join(HOME_DIR, ".openclaw", "workspace");
const MEMORY_ROOT = path.join(PLAYGROUND_ROOT, "memory");
const OPENCLAW_LOCAL_AGENTS_ROOT = path.join(PLAYGROUND_ROOT, "openclaw-local-agents");
const LAST_SELFTEST_SUMMARY_PATH = path.join(OPENCLAW_LOCAL_AGENTS_ROOT, ".local-agent-last-selftest.json");
const LAST_TRANSPORT_SUMMARY_PATH = path.join(
  OPENCLAW_LOCAL_AGENTS_ROOT,
  ".local-agent-last-whatsapp-transport-smoke.json",
);
const LAST_PROJECT_SCOUT_SUMMARY_PATH = path.join(
  OPENCLAW_LOCAL_AGENTS_ROOT,
  ".local-agent-last-human-project-scout-eval.json",
);
const LAST_OPENAI_PROBE_SUMMARY_PATH = path.join(
  OPENCLAW_LOCAL_AGENTS_ROOT,
  ".local-agent-last-openai-sessions-probe.json",
);
const LAST_QWEN_PROBE_SUMMARY_PATH = path.join(
  OPENCLAW_LOCAL_AGENTS_ROOT,
  ".local-agent-last-qwen-sessions-probe.json",
);

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
    api.on("before_dispatch", async (event, ctx) => {
      const text = buildProjectScoutReply({
        texts: [event && event.body, event && event.content],
        sessionKey: (ctx && ctx.sessionKey) || (event && event.sessionKey),
      });
      if (!text) {
        return;
      }
      return {
        handled: true,
        text,
      };
    });

    api.on("before_agent_reply", async (event, ctx) => {
      const text = buildProjectScoutReply({
        texts: [event && event.cleanedBody],
        agentId: ctx && ctx.agentId,
        sessionKey: ctx && ctx.sessionKey,
      });
      if (!text) {
        return;
      }
      return {
        handled: true,
        reason: "local-project-scout",
        reply: {
          text,
        },
      };
    });
  },
};

function buildProjectScoutReply(params) {
  const targetMainHumanAgent = shouldTargetMainHumanAgent(params);
  const cleanedBody = normalizeText(selectRelevantScoutText(params && params.texts));
  if (!targetMainHumanAgent) {
    return "";
  }
  if (!cleanedBody) {
    return "";
  }

  if (matchesWorkSummaryIntent(cleanedBody)) {
    return buildWorkSummaryReply();
  }
  if (matchesCurrentStatusIntent(cleanedBody)) {
    return buildCurrentStatusReply();
  }
  if (!matchesProjectScoutIntent(cleanedBody)) {
    return "";
  }

  const projectCards = collectProjectCards();
  if (projectCards.length < 2) {
    return "";
  }

  const selected = projectCards.slice(0, 3);
  const questionTargets = selected.slice(0, 3).map((card) => card.name).join(", ");
  const lines = selected.map((card) => `- ${card.name} - ${card.hint}`);
  lines.push(`- Womit soll ich als Naechstes weitermachen: ${questionTargets}?`);
  return lines.join("\n");
}

function shouldTargetMainHumanAgent(params) {
  const agentId = params && typeof params.agentId === "string" ? params.agentId.trim() : "";
  const sessionKey =
    params && typeof params.sessionKey === "string" ? params.sessionKey.trim().toLowerCase() : "";
  if (agentId) {
    const normalizedAgentId = agentId.toLowerCase();
    if (["main", "oc-human-main"].includes(normalizedAgentId)) {
      return true;
    }
    if (!sessionKey) {
      return false;
    }
    return sessionKey.startsWith("agent:main:") || sessionKey.startsWith("agent:oc-human-main:");
  }
  if (!sessionKey) {
    return true;
  }
  return sessionKey.startsWith("agent:main:") || sessionKey.startsWith("agent:oc-human-main:");
}

function selectRelevantScoutText(values) {
  const candidates = Array.isArray(values) ? values : [];
  let best = "";
  for (const value of candidates) {
    const current = normalizeText(value);
    if (!current) {
      continue;
    }
    if (matchesProjectScoutIntent(current)) {
      return current;
    }
    if (current.length > best.length) {
      best = current;
    }
  }
  return best;
}

function matchesProjectScoutIntent(cleanedBody) {
  if (!cleanedBody) {
    return false;
  }
  if (
    /(meine projekte|auf meinen mac|auf meinem mac|was ist hier relevant|was geht hier ab|was haben wir alles dran gearbeitet|was hast du gearbeitet heute an meine projekte)/.test(
      cleanedBody,
    )
  ) {
    return true;
  }
  return (
    /(welche|was|woran|guck|schau|zeig|analys|status|relevant|gearbeitet|abgeht|dran gearbeitet)/.test(
      cleanedBody,
    ) &&
    /(projekt|projekte|repo|repos|mac|workspace|lokal|local|playground|code)/.test(cleanedBody)
  );
}

function matchesWorkSummaryIntent(cleanedBody) {
  if (!cleanedBody) {
    return false;
  }
  return (
    /(was hast du gearbeitet|was haben wir alles dran gearbeitet|woran haben wir gearbeitet|was haben wir heute gemacht|was hast du heute gemacht|heute gearbeitet)/.test(
      cleanedBody,
    ) &&
    /(projekt|projekte|heute|dran gearbeitet|gearbeitet)/.test(cleanedBody)
  );
}

function matchesCurrentStatusIntent(cleanedBody) {
  if (!cleanedBody) {
    return false;
  }
  return (
    /(was machen wir|was machen wir grade|was machen wir gerade|was geht ab|was eht ab|status|woran sind wir|wo stehen wir|was laeuft gerade|was passiert gerade|was ist der stand)/.test(
      cleanedBody,
    ) &&
    !/(welche projekte|meine projekte|auf meinen mac|auf meinem mac)/.test(cleanedBody)
  );
}

function buildWorkSummaryReply() {
  const cards = collectRecentWorkCards();
  if (cards.length < 2) {
    return "";
  }
  const selected = cards.slice(0, 3);
  const lines = selected.map((card) => `- ${card.area} - ${card.summary}`);
  lines.push("- Soll ich als Naechstes die echte WhatsApp-Antwort, Memory-Nutzung oder den naechsten Tool-Fix schaerfen?");
  return lines.join("\n");
}

function collectRecentWorkCards() {
  const seen = new Set();
  const cards = [];

  for (const card of collectTodayCommitCards()) {
    const key = `${card.area}::${card.summary}`;
    if (seen.has(key)) {
      continue;
    }
    cards.push(card);
    seen.add(key);
  }

  const memoryCard = collectMemoryStatusCard();
  if (memoryCard) {
    const key = `${memoryCard.area}::${memoryCard.summary}`;
    if (!seen.has(key)) {
      cards.push(memoryCard);
      seen.add(key);
    }
  }

  return cards;
}

function buildCurrentStatusReply() {
  const lines = [];

  const selftest = readJsonFile(LAST_SELFTEST_SUMMARY_PATH);
  if (selftest && selftest.status === "passed") {
    lines.push(
      `- Agent-Stand - letzter Live-Selftest ist ${String(selftest.status)}; der lokale Agent-Pfad steht auf ${String(selftest.mode || "live")} und die Kernschritte liefen durch.`,
    );
  }

  const transport = readJsonFile(LAST_TRANSPORT_SUMMARY_PATH);
  const projectScoutEval = readJsonFile(LAST_PROJECT_SCOUT_SUMMARY_PATH);
  if (transport && transport.status === "passed" && projectScoutEval && projectScoutEval.status === "passed") {
    lines.push(
      "- WhatsApp-Pfad - Transport-Smoke und Project-Scout-Eval sind gruen; die deterministischen Antworten fuer Projekte und Arbeitsstand sind lokal geladen.",
    );
  } else if (transport && transport.status === "passed") {
    lines.push("- WhatsApp-Pfad - Transport-Smoke ist gruen; der Kanal ist lokal erreichbar und antwortet.");
  }

  const blockers = collectCurrentBlockers();
  if (blockers.length > 0) {
    lines.push(`- Aktueller Blocker - ${blockers.join("; ")}.`);
  }

  const recentWork = collectRecentWorkCards()[0];
  if (lines.length < 3 && recentWork) {
    lines.push(`- Letzter harter Fix - ${recentWork.summary}`);
  }

  while (lines.length < 3) {
    lines.push("- Status - lokaler Agent wird gerade weiter auf deterministic replies und stabilere WhatsApp-Antworten gehoben.");
  }

  lines.push("- Soll ich als Naechstes den Live-WhatsApp-Stand, den naechsten Blocker oder die Antwortqualitaet weiter schaerfen?");
  return lines.slice(0, 4).join("\n");
}

function collectTodayCommitCards() {
  if (!isDirectory(OPENCLAW_LOCAL_AGENTS_ROOT)) {
    return [];
  }

  const messages = readGitCommitMessages(OPENCLAW_LOCAL_AGENTS_ROOT);
  return messages
    .map((message) => mapCommitMessageToCard(message))
    .filter(Boolean);
}

function readGitCommitMessages(repoPath) {
  const dayStart = new Date();
  dayStart.setHours(0, 0, 0, 0);
  const isoDay = `${dayStart.getFullYear()}-${String(dayStart.getMonth() + 1).padStart(2, "0")}-${String(dayStart.getDate()).padStart(2, "0")}`;

  const attempts = [
    ["-C", repoPath, "log", "--since", `${isoDay} 00:00:00`, "--no-merges", "--pretty=%s", "-5"],
    ["-C", repoPath, "log", "--no-merges", "--pretty=%s", "-5"],
  ];

  for (const args of attempts) {
    try {
      const output = execFileSync("git", args, {
        encoding: "utf8",
        stdio: ["ignore", "pipe", "ignore"],
        timeout: 4000,
      })
        .split(/\r?\n/)
        .map((line) => line.trim())
        .filter(Boolean);
      if (output.length > 0) {
        return output;
      }
    } catch {
      continue;
    }
  }
  return [];
}

function mapCommitMessageToCard(message) {
  const normalized = normalizeText(message);
  if (!normalized) {
    return null;
  }

  const mappedSummary =
    COMMIT_SUMMARY_MAP.find((entry) => normalized.includes(entry.match))?.summary ||
    summarizeCommitMessage(message);

  return {
    area: "openclaw-local-agents",
    summary: mappedSummary,
  };
}

const COMMIT_SUMMARY_MAP = [
  {
    match: "intercept project scout earlier in reply pipeline",
    summary:
      "Projekt-Scout frueher im echten WhatsApp-Reply-Pfad abgefangen, damit Projektfragen nicht mehr an der 4B-Fallback-Antwort vorbeilaufen.",
  },
  {
    match: "add local project scout guardrail for human agent",
    summary:
      "Deterministischen Projekt-Scout fuer den Human-Agent eingebaut, damit lokale Repo-Namen statt Halluzinationen zurueckkommen.",
  },
  {
    match: "harden human eval and conversation fallbacks",
    summary:
      "Human-Evals und Gespraechs-Fallbacks gehaertet, damit WhatsApp-Antworten stabiler und konsistenter werden.",
  },
  {
    match: "harden context audits and recovery blockers",
    summary:
      "Kontext-Audits und Recovery-Blocker gehaertet, damit Fehlerfaelle sauberer erkannt und gefixt werden.",
  },
  {
    match: "standardize whatsapp context reports",
    summary:
      "WhatsApp-Kontextberichte vereinheitlicht, damit Status- und Team-Updates konsistent aus dem echten Lauf kommen.",
  },
];

function summarizeCommitMessage(message) {
  const trimmed = String(message || "").trim();
  if (!trimmed) {
    return "";
  }
  const compact = trimmed.replace(/\s+/g, " ");
  if (compact.length <= 120) {
    return compact;
  }
  return `${compact.slice(0, 117).trimEnd()}...`;
}

function collectMemoryStatusCard() {
  const memoryPath = path.join(MEMORY_ROOT, currentDayFileName());
  if (!fs.existsSync(memoryPath)) {
    return null;
  }
  try {
    const content = fs.readFileSync(memoryPath, "utf8");
    if (/project-scout-eval.*passed|hookcount=2|hookCount=2/i.test(content)) {
      return {
        area: "WhatsApp-Localtests",
        summary:
          "Projekt-Scout-Eval lokal gruen, Plugin geladen und der Guardrail aktuell mit zwei Hook-Punkten aktiv.",
      };
    }
    if (/intelligence-loop.*passed|ops-status.*ok|trend.*ok/i.test(content)) {
      return {
        area: "WhatsApp-Localtests",
        summary:
          "Intelligence-Loop, Ops-Status und Trend lagen zuletzt auf gruen oder ok, der Live-Pfad ist also lokal wieder stabiler.",
      };
    }
  } catch {
    return null;
  }
  return null;
}

function currentDayFileName() {
  const now = new Date();
  return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}-${String(now.getDate()).padStart(2, "0")}.md`;
}

function collectCurrentBlockers() {
  const blockers = [];
  const openaiProbe = readJsonFile(LAST_OPENAI_PROBE_SUMMARY_PATH);
  const qwenProbe = readJsonFile(LAST_QWEN_PROBE_SUMMARY_PATH);

  if (openaiProbe && openaiProbe.status === "blocked") {
    blockers.push(
      `OpenAI-Probe blockiert auf ${String(openaiProbe.reason || "unbekannt")}`,
    );
  }
  if (qwenProbe && qwenProbe.status === "blocked") {
    blockers.push(
      `Qwen-Probe blockiert auf ${String(qwenProbe.reason || "unbekannt")}`,
    );
  }
  return blockers.slice(0, 2);
}

function readJsonFile(filePath) {
  try {
    return JSON.parse(fs.readFileSync(filePath, "utf8"));
  } catch {
    return null;
  }
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
