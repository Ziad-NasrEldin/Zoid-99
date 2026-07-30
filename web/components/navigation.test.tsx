import React from "react";
import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";

import { NavigationLinks } from "@/components/navigation";
import { primaryNavigation } from "@/lib/navigation";

describe("NavigationLinks", () => {
  it("renders accessible links and marks the current destination", () => {
    render(<NavigationLinks items={primaryNavigation} currentPath="/radar" />);

    expect(screen.getByRole("link", { name: "Today" })).toHaveAttribute("href", "/today");
    expect(screen.getByRole("link", { name: "Radar" })).toHaveAttribute("aria-current", "page");
    expect(screen.getByRole("link", { name: "Today" })).not.toHaveAttribute("aria-current");
  });
});
