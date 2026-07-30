import { describe, expect, it } from "vitest";

import { assertSameOriginMutation, CsrfError } from "@/lib/auth/csrf";

describe("mutation origin checks", () => {
  it("accepts browser same-origin metadata when Origin is omitted", () => {
    expect(() =>
      assertSameOriginMutation(
        new Request("https://zoid.example.test/api/gateway/watchlist", {
          method: "POST",
          headers: { "sec-fetch-site": "same-origin" },
        }),
      ),
    ).not.toThrow();
  });

  it("allows same-origin mutations", () => {
    expect(() =>
      assertSameOriginMutation(
        new Request("https://zoid.example.test/api/gateway/watchlist", {
          method: "POST",
          headers: { origin: "https://zoid.example.test", "sec-fetch-site": "same-origin" },
        }),
      ),
    ).not.toThrow();
  });

  it("uses the configured public origin behind an HTTPS-terminating reverse proxy", () => {
    expect(() =>
      assertSameOriginMutation(
        new Request("http://web:3100/api/auth/login", {
          method: "POST",
          headers: { origin: "https://zoid99.mavoid.com" },
        }),
        { publicBaseUrl: "https://zoid99.mavoid.com" },
      ),
    ).not.toThrow();
  });

  it("rejects cross-origin mutations", () => {
    expect(() =>
      assertSameOriginMutation(
        new Request("https://zoid.example.test/api/gateway/watchlist", {
          method: "POST",
          headers: { origin: "https://attacker.example.test" },
        }),
      ),
    ).toThrow(CsrfError);
  });

  it("rejects missing origin and cross-site fetch metadata", () => {
    expect(() =>
      assertSameOriginMutation(
        new Request("https://zoid.example.test/api/gateway/watchlist", { method: "DELETE" }),
      ),
    ).toThrow(CsrfError);

    expect(() =>
      assertSameOriginMutation(
        new Request("https://zoid.example.test/api/gateway/watchlist", {
          method: "PATCH",
          headers: { origin: "https://zoid.example.test", "sec-fetch-site": "cross-site" },
        }),
      ),
    ).toThrow(CsrfError);
  });
});
