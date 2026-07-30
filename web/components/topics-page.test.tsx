import { describe, expect, it } from "vitest";

import { topicDetailFixture } from "@/lib/radar-fixtures";

describe("Topics vertical slice", () => {
  it("retains server-computed evidence links and timestamps in the fixture contract", () => {
    const source = topicDetailFixture.opportunities[0]?.originalSource;
    expect(source?.url).toBe("https://official.example/releases/99");
    expect(source?.publishedAt).toBe("2026-07-28T08:00:00.000Z");
  });
});
