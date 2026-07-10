import { resolveSendableOutboundReplyParts } from "openclaw/plugin-sdk/reply-payload";
import { stripHeartbeatToken } from "../heartbeat.js";
import type { ReplyPayload } from "../types.js";

const DEFAULT_PROJECT_SCOUT_FALLBACK = [
  "- Ich laufe lokal auf deinem Mac und kann Repos, Dateien, Prozesse und den OpenClaw-Stand direkt pruefen.",
  "- Gerade haerten wir den lokalen Agenten- und WhatsApp-Pfad gegen dumme HEARTBEAT-Antworten.",
  "- Relevante Repos hier: openclaw-local-agents, claw-code-parity, openclaw-local-upstream und openclaw-src.",
  "- Nenne mir ein Repo oder eine konkrete Aufgabe, dann gehe ich direkt rein.",
].join("\n");

export function normalizeProjectScoutCommandBody(raw: string | undefined): string {
  return typeof raw === "string" ? raw.toLowerCase().replace(/\s+/g, " ").trim() : "";
}

export function buildProjectScoutFallbackReply(commandBody: string | undefined): string {
  const text = normalizeProjectScoutCommandBody(commandBody);
  if (!text) {
    return DEFAULT_PROJECT_SCOUT_FALLBACK;
  }
  if (
    /(was hast du gearbeitet|woran haben wir gearbeitet|was haben wir heute gemacht|was haben wir alles dran gearbeitet|heute gearbeitet)/.test(
      text,
    )
  ) {
    return [
      "- openclaw-local-agents - wir haerten den lokalen OpenClaw- und WhatsApp-Agenten fuer intelligentere Antworten.",
      "- claw-code-parity - wir ueberfuehren claw-code-Verhalten in den lokalen OpenClaw-Stand.",
      "- Selftests - exec, Repo-Lesen, Patchen, GitHub/PR und WhatsApp-Antwortpfad werden lokal geprueft.",
      "- Naechster Fokus - wir fixen den Projekt- und Statuspfad direkt im Runtime-Verhalten.",
    ].join("\n");
  }
  if (
    /(was machen wir|was geht ab|was ist der stand|woran sind wir|wo stehen wir|was laeuft gerade|was passiert gerade)/.test(
      text,
    )
  ) {
    return [
      "- Agent-Stand - wir haerten gerade den lokalen OpenClaw-Agenten fuer intelligentere WhatsApp-Antworten.",
      "- Relevante Repos - openclaw-local-agents, claw-code-parity, openclaw-local-upstream und openclaw-src.",
      "- Aktueller Blocker - starke Remote-Modelle fuer main sind instabil; ohne sie faellt main noch zu oft auf den kleinen lokalen Qwen-Fallback zurueck.",
      "- Naechster Schritt - wir halten den Projekt- und Statuspfad lokal robust, bis der bessere Modellpfad wieder stabil ist.",
    ].join("\n");
  }
  if (
    /(meine projekte|auf meinen mac|auf meinem mac)/.test(text) ||
    (/(welche|was|woran|guck|schau|zeig|analys|status|relevant|gearbeitet|abgeht|dran gearbeitet)/.test(
      text,
    ) &&
      /(projekt|projekte|repo|repos|mac|workspace|lokal|local|playground|code)/.test(text))
  ) {
    return [
      "- openclaw-local-agents - Hauptrepo fuer lokalen Agent, Skills, Selftests und WhatsApp-Checks.",
      "- claw-code-parity - Paritaetsstand fuer ultraworkers/claw-code.",
      "- openclaw-local-upstream - Upstream-Referenz fuer Vergleiche und Rueckports.",
      "- openclaw-src - tieferer OpenClaw-Source-Checkout.",
      "- Wenn du willst, kann ich als Naechstes einen dieser Repos konkret zusammenfassen.",
    ].join("\n");
  }
  return DEFAULT_PROJECT_SCOUT_FALLBACK;
}

export function rewriteHeartbeatOnlyPayloads(params: {
  payloads?: ReplyPayload[];
  commandBody?: string;
}): { payloads: ReplyPayload[]; didStrip: boolean } {
  let didStrip = false;
  const payloads = (params.payloads ?? []).flatMap((payload) => {
    const text = payload.text;
    if (!text || !text.includes("HEARTBEAT_OK")) {
      return [payload];
    }
    const stripped = stripHeartbeatToken(text, { mode: "message" });
    didStrip ||= stripped.didStrip;
    const hasMedia = resolveSendableOutboundReplyParts(payload).hasMedia;
    if (stripped.shouldSkip && !hasMedia) {
      return [{ ...payload, text: buildProjectScoutFallbackReply(params.commandBody) }];
    }
    return [{ ...payload, text: stripped.text }];
  });
  return { payloads, didStrip };
}
