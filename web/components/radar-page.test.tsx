import { describe, expect, it } from "vitest";

import { radarPageSize } from "@/lib/radar-client";

describe("Radar vertical slice", () => {
  it("keeps the user-visible gateway limit small and explicit", () => {
    expect(radarPageSize).toBe(25);
  });
});
