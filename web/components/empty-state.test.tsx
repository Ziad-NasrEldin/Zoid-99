import React from "react";
import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";

import { EmptyState } from "@/components/empty-state";

describe("EmptyState", () => {
  it("communicates an honest unavailable state without research records", () => {
    render(
      <EmptyState
        eyebrow="DATA STATE / NOT CONNECTED"
        title="No verified opportunities yet"
        body="No research records have been fabricated for the web shell."
      />,
    );

    expect(screen.getByRole("status")).toHaveTextContent("DATA STATE / NOT CONNECTED");
    expect(screen.getByRole("heading", { name: "No verified opportunities yet" })).toBeVisible();
    expect(screen.getByText(/No research records have been fabricated/)).toBeVisible();
  });
});
