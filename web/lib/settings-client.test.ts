import { describe, expect, it } from "vitest";

import {
  parseConnectionsPayload,
  parsePreferencesPayload,
  parseSourceHealthPayload,
  preferencePatchFromFormData,
} from "./settings-client";

describe("settings client contract helpers", () => {
  it("parses the six-source health response and connection response", () => {
    const sourceHealth = parseSourceHealthPayload([
      {
        group: "YouTube",
        state: "Connected",
        lastActivity: null,
        evidence: "Collection completed.",
        repairAction: "Review",
        dataTruth: "Live",
      },
    ]);
    const connections = parseConnectionsPayload([
      {
        provider: "ai-provider",
        state: "Cached",
        lastActivity: null,
        evidence: "Encrypted credential exists.",
        repairAction: "Validate again",
        retryAt: null,
      },
    ]);

    expect(sourceHealth[0]?.group).toBe("YouTube");
    expect(connections[0]?.provider).toBe("ai-provider");
  });

  it("builds a validated preference patch without accepting a credential field", () => {
    const formData = new FormData();
    formData.set("refreshMinutes", "30");
    formData.set("notificationsEnabled", "on");
    formData.set("digestHour", "18");
    formData.set("quietHoursEnabled", "on");
    formData.set("quietHoursStart", "22:00");
    formData.set("quietHoursEnd", "08:00");
    formData.set("locale", "ar-EG");
    formData.set("timeZone", "Africa/Cairo");
    formData.set("credential", "must-not-be-used");

    const patch = preferencePatchFromFormData(formData);
    expect(patch).toEqual({
      refreshMinutes: 30,
      notificationsEnabled: true,
      digestHour: 18,
      quietHours: { enabled: true, start: "22:00", end: "08:00" },
      locale: "ar-EG",
      timeZone: "Africa/Cairo",
    });
    expect(JSON.stringify(patch)).not.toContain("must-not-be-used");
  });

  it("requires an ETag for preferences responses", () => {
    expect(() => parsePreferencesPayload({
      refreshMinutes: 15,
      notificationsEnabled: false,
      digestHour: 18,
      quietHours: { enabled: false, start: "22:00", end: "08:00" },
      locale: "en",
      timeZone: "UTC",
      updatedAt: "2026-07-28T10:00:00.000Z",
    }, null)).toThrow("ETag");
  });
});

