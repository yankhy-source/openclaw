import { describe, expect, it } from "vitest";
import {
  buildProjectScoutFallbackReply,
  rewriteHeartbeatOnlyPayloads,
} from "./heartbeat-fallback.js";

describe("heartbeat fallback", () => {
  it("returns a generic local fallback when no command body is available", () => {
    expect(buildProjectScoutFallbackReply(undefined)).toContain(
      "Ich laufe lokal auf deinem Mac",
    );
  });

  it("replaces heartbeat-only payloads with project fallback text", () => {
    const result = rewriteHeartbeatOnlyPayloads({
      payloads: [{ text: "HEARTBEAT_OK" }],
      commandBody: "Was machen wir gerade hier, was ist der Stand?",
    });

    expect(result.didStrip).toBe(true);
    expect(result.payloads).toEqual([
      {
        text: expect.stringContaining("Agent-Stand"),
      },
    ]);
  });
});
