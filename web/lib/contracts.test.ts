import { readFileSync } from "node:fs";
import { resolve } from "node:path";

import { describe, expect, it } from "vitest";

import { parseBootstrap, webApiVersion } from "@/lib/contracts";

const bootstrapFixture = JSON.parse(
  readFileSync(resolve(process.cwd(), "../packages/contracts/fixtures/bootstrap.json"), "utf8"),
) as Record<string, unknown>;

describe("shared bootstrap contract", () => {
  it("accepts the shared bootstrap fixture", () => {
    const bootstrap = parseBootstrap(bootstrapFixture);

    expect(bootstrap.opportunities).toHaveLength(1);
    expect(webApiVersion).toBe("v1");
  });

  it("rejects malformed bootstrap payloads", () => {
    expect(() => parseBootstrap({ opportunities: [] })).toThrow();
    expect(() => parseBootstrap({ ...bootstrapFixture, notifications: "not-an-array" })).toThrow();
  });
});
