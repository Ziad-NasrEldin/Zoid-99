import { readFileSync } from "node:fs";
import { resolve } from "node:path";

import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it } from "vitest";

import { OpportunityDetail } from "@/components/opportunity-detail/opportunity-detail";
import type { BootstrapPayload } from "@zoid99/contracts";

const fixture = JSON.parse(
  readFileSync(resolve(process.cwd(), "../packages/contracts/fixtures/bootstrap.json"), "utf8"),
) as BootstrapPayload;
const opportunity = fixture.opportunities[0]!;

describe("OpportunityDetail", () => {
  it("renders verification, original evidence, score factors, regional text, and sources", async () => {
    render(<OpportunityDetail id={opportunity.id} loadOpportunity={async () => ({ opportunity, dataTruth: "Live" })} />);

    expect(screen.getByRole("status")).toHaveTextContent(/Reading opportunity evidence|Evidence response/);
    expect((await screen.findAllByRole("heading", { name: "Official release 99" }))[0]).toBeVisible();
    expect(screen.getByText("Verification: Confirmed")).toBeVisible();
    expect(screen.getByRole("heading", { name: "Score breakdown" })).toBeVisible();
    expect(screen.getByText("Arabic coverage")).toBeVisible();
    expect(screen.getByText("Open original source")).toHaveAttribute("href", "https://official.example/releases/99");
    expect(screen.getAllByText(/Published 28 Jul 2026/).length).toBeGreaterThanOrEqual(2);
  });

  it("optimistically changes disposition and restores it after a failed gateway write", async () => {
    const user = userEvent.setup();
    render(
      <OpportunityDetail
        id={opportunity.id}
        loadOpportunity={async () => ({ opportunity, dataTruth: "Live" })}
        mutateDisposition={async () => {
          throw new Error("offline");
        }}
      />,
    );

    await screen.findAllByRole("heading", { name: "Official release 99" });
    await user.click(screen.getByRole("button", { name: "Watch" }));
    await waitFor(() => expect(screen.getByRole("alert")).toHaveTextContent("previous state has been restored"));
    expect(screen.getAllByRole("button", { name: "Active" })[0]).toHaveAttribute("aria-pressed", "true");
  });
});
