import { readFileSync } from "node:fs";
import { resolve } from "node:path";

import { cleanup, render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, describe, expect, it } from "vitest";

import { TodayResearch } from "@/components/today-research/today-research";
import type { BootstrapPayload, OpportunityDispositionState } from "@zoid99/contracts";

const fixture = JSON.parse(
  readFileSync(resolve(process.cwd(), "../packages/contracts/fixtures/bootstrap.json"), "utf8"),
) as BootstrapPayload;

function todayFixture(overrides: Partial<BootstrapPayload> = {}) {
  return {
    ...fixture,
    ...overrides,
    dataTruth: "Live" as const,
    lastSuccessfulSync: "2026-07-28T08:05:00.000Z",
  };
}

describe("TodayResearch", () => {
  afterEach(cleanup);

  it("renders server-backed evidence and rolls back a failed optimistic action", async () => {
    const user = userEvent.setup();
    let calls = 0;
    render(
      <TodayResearch
        loadToday={async () => todayFixture()}
        mutateDisposition={async () => {
          calls += 1;
          throw new Error("gateway failed");
        }}
      />,
    );

    expect(screen.getByRole("status")).toHaveTextContent(/Loading Today research|Reading the research ledger/);
    await screen.findByRole("link", { name: "Official release 99" });
    expect(screen.getByText("Live data")).toBeVisible();
    expect(screen.getByText("Open original")).toBeVisible();
    expect(screen.getByText("Digest delivery")).toBeVisible();

    await user.click(screen.getByRole("button", { name: "Watch" }));
    await waitFor(() => expect(screen.getByRole("alert")).toHaveTextContent("previous state has been restored"));
    expect(calls).toBe(1);
    expect(screen.getByRole("button", { name: "Save" })).toHaveAttribute("aria-pressed", "false");
  });

  it("applies the canonical state when the backend supersedes an optimistic action", async () => {
    const user = userEvent.setup();
    let resolveMutation!: (state: OpportunityDispositionState) => void;
    const mutation = new Promise<OpportunityDispositionState>((resolve) => {
      resolveMutation = resolve;
    });

    render(
      <TodayResearch
        loadToday={async () => todayFixture()}
        mutateDisposition={async () => mutation}
      />,
    );

    await screen.findByRole("link", { name: "Official release 99" });
    await user.click(screen.getByRole("button", { name: "Watch" }));
    await waitFor(() => expect(screen.getByRole("button", { name: "Watch" })).toHaveAttribute("aria-pressed", "true"));

    resolveMutation({
      opportunityID: fixture.opportunities[0]!.id,
      disposition: "saved",
      changedAt: "2026-07-28T08:25:00.000Z",
      mutationID: "50000000-0000-4000-8000-000000000100",
      outcome: "superseded",
    });

    await waitFor(() => expect(screen.getByRole("button", { name: "Save" })).toHaveAttribute("aria-pressed", "true"));
    expect(screen.getByRole("button", { name: "Watch" })).toHaveAttribute("aria-pressed", "false");
    expect(screen.queryByRole("alert")).not.toBeInTheDocument();
  });

  it("states an empty result explicitly and sets Arabic titles right-to-left", async () => {
    const arabic = structuredClone(fixture.opportunities[0]!);
    arabic.title = "إطلاق نموذج رسمي";
    render(
      <TodayResearch
        loadToday={async () => todayFixture({ opportunities: [{ ...arabic, isHighPriority: true }] })}
      />,
    );

    const title = await screen.findByRole("link", { name: "إطلاق نموذج رسمي" });
    expect(title).toHaveAttribute("dir", "rtl");

    render(
      <TodayResearch
        loadToday={async () => todayFixture({ opportunities: [] })}
      />,
    );
    expect(await screen.findByText("No active opportunities today")).toBeVisible();
    expect(screen.getByText(/empty result, not a fabricated zero/)).toBeVisible();
  });

  it("shows active standard-priority opportunities like the native Today view", async () => {
    const standardPriority = {
      ...structuredClone(fixture.opportunities[0]!),
      isHighPriority: false,
    };

    render(
      <TodayResearch
        loadToday={async () => todayFixture({ opportunities: [standardPriority] })}
      />,
    );

    expect(await screen.findByRole("link", { name: "Official release 99" })).toBeVisible();
    expect(screen.getByText("1 active item")).toBeVisible();
    expect(screen.getByLabelText("Standard priority")).toBeVisible();
  });
});
