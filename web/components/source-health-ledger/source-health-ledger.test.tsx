import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";

import type { SourceHealth } from "@zoid99/contracts";

import { SourceHealthLedger } from "./source-health-ledger";

const sourceHealth: SourceHealth[] = [
  "YouTube",
  "Google Trends",
  "Instagram",
  "Comments",
  "US & Official",
  "X",
].map((group, index) => ({
  group: group as SourceHealth["group"],
  state: index === 0 ? "Connected" : "Setup required",
  lastActivity: index === 0 ? "2026-07-28T10:00:00.000Z" : null,
  evidence: index === 0 ? "The latest collection cycle completed." : "No account or API credential has been connected.",
  repairAction: index === 0 ? "Review" : "Configure",
  dataTruth: index === 0 ? "Live" : "Missing",
}));

describe("SourceHealthLedger", () => {
  it("renders all six source records with written state, evidence, and repair actions", () => {
    render(<SourceHealthLedger sourceHealth={sourceHealth} />);

    expect(screen.getByRole("heading", { name: "Collection health" })).toBeVisible();
    expect(screen.getByLabelText("6 source records")).toBeVisible();
    expect(screen.getAllByText("Setup required")).toHaveLength(5);
    expect(screen.getAllByText("No account or API credential has been connected.")).toHaveLength(5);
    expect(screen.getAllByRole("link", { name: /Configure/ })).toHaveLength(5);
    expect(screen.getByText("The latest collection cycle completed.")).toBeVisible();
  });

  it("fills a missing backend row with an explicit unavailable state", () => {
    render(<SourceHealthLedger sourceHealth={sourceHealth.slice(0, 1)} />);

    expect(screen.getAllByText("The gateway did not return a health record for this source.")).toHaveLength(5);
    expect(screen.getAllByText("Unavailable")).toHaveLength(5);
    expect(screen.getAllByRole("link", { name: /Refresh source health/ })).toHaveLength(5);
  });
});
