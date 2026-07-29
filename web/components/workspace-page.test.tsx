import React from "react";
import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";

import { WorkspacePage } from "@/components/workspace-page";
import { workspacePages } from "@/lib/workspace-pages";

describe("WorkspacePage", () => {
  it("states that records are unavailable while disconnected", () => {
    render(<WorkspacePage config={workspacePages.today} />);

    expect(screen.getByRole("heading", { name: "Today" })).toBeVisible();
    expect(screen.getByText("Records unavailable")).toBeVisible();
    expect(screen.queryByText("0 records")).not.toBeInTheDocument();
    expect(screen.getByText("DATA STATE / NOT CONNECTED")).toBeVisible();
    expect(screen.getByText(/intentionally empty until the server gateway is connected/)).toBeVisible();
  });
});
