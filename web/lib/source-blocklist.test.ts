import { describe, expect, it } from "vitest";

import { isBlockedSourceURL, normalizeSourceDomain } from "./source-blocklist";

describe("source blocklist", () => {
  it("normalizes a URL and blocks its subdomains without blocking lookalikes", () => {
    expect(normalizeSourceDomain("HTTPS://www.Example.com/path")).toBe("example.com");
    expect(isBlockedSourceURL("https://news.example.com/item", ["example.com"])).toBe(true);
    expect(isBlockedSourceURL("https://example.com.evil.test/item", ["example.com"])).toBe(false);
  });
});
