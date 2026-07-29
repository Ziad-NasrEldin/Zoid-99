import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";

import type { ConnectionStatus, Preferences } from "@zoid99/contracts";

import { SettingsForms } from "./settings-forms";

const preferences: Preferences = {
  refreshMinutes: 15,
  notificationsEnabled: true,
  digestHour: 18,
  quietHours: { enabled: true, start: "22:00", end: "08:00" },
  locale: "en",
  timeZone: "Africa/Cairo",
  updatedAt: "2026-07-28T10:00:00.000Z",
};

const connections: ConnectionStatus[] = [
  {
    provider: "google-trends",
    state: "Setup required",
    lastActivity: null,
    evidence: "No encrypted server credential is configured.",
    repairAction: "Configure on server",
    retryAt: null,
  },
  {
    provider: "ai-provider",
    state: "Connected",
    lastActivity: "2026-07-28T10:00:00.000Z",
    evidence: "The provider accepted a health check.",
    repairAction: "Review",
    retryAt: null,
  },
];

describe("SettingsForms", () => {
  it("renders server connection forms with blank secret fields and a reauthentication boundary", () => {
    render(<SettingsForms connections={connections} preferences={preferences} etag={'"preferences-v1"'} loadError={null} />);

    expect(screen.getByText("Reauthentication boundary")).toBeVisible();
    expect(screen.getAllByLabelText("Server credential")).toHaveLength(2);
    expect(screen.getAllByLabelText("Server credential").every((input) => (input as HTMLInputElement).value === "")).toBe(true);
    expect(screen.getAllByText(/never restored after submission/)).toHaveLength(2);
    expect(screen.getAllByRole("button", { name: "Disconnect" })).toHaveLength(2);
  });

  it("shows an honest unavailable state when the settings gateway is down", () => {
    render(<SettingsForms connections={[]} preferences={null} etag={null} loadError="Settings are unavailable from the private data gateway." />);

    expect(screen.getAllByRole("status")).toHaveLength(2);
    expect(screen.getAllByText("Settings are unavailable from the private data gateway.")).toHaveLength(2);
    expect(screen.getByText("No connection status was returned.")).toBeVisible();
    expect(screen.getAllByText("Settings are unavailable from the private data gateway.")).toHaveLength(2);
  });
});
