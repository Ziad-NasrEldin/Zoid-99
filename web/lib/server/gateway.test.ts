import { describe, expect, it, vi } from "vitest";

import { createGatewayClient, GatewayConfigurationError } from "@/lib/server/gateway";

const token = "server-only-token-that-is-long-enough-for-production";

describe("server-only gateway", () => {
  it("adds the service credential only to the upstream request", async () => {
    const upstream = vi.fn<typeof fetch>(async () => new Response(JSON.stringify({ ok: true })));
    const client = createGatewayClient({
      env: {
        NODE_ENV: "production",
        ZOID99_BACKEND_BASE_URL: "https://private-backend.example.test/api",
        ZOID99_WEB_SERVICE_TOKEN: token,
      },
      fetchImpl: upstream,
    });

    const response = await client.request("/v1/bootstrap", {
      headers: {
        cookie: "CF_Authorization=do-not-forward",
        "x-zoid-dev-identity": "do-not-forward",
        "x-request-id": "review-request-123",
      },
    });
    const [, init] = upstream.mock.calls[0];
    const headers = new Headers(init?.headers);

    expect(headers.get("authorization")).toBe(`Bearer ${token}`);
    expect(headers.get("cookie")).toBeNull();
    expect(headers.get("x-zoid-dev-identity")).toBeNull();
    expect(headers.get("x-request-id")).toBe("review-request-123");
    const responseBody = await response.text();
    expect(JSON.parse(responseBody)).toEqual({ ok: true });
    expect(responseBody).not.toContain(token);
  });

  it("rejects missing or short service credentials", () => {
    expect(() =>
      createGatewayClient({
        env: { NODE_ENV: "production", ZOID99_BACKEND_BASE_URL: "https://private-backend.example.test" },
      }),
    ).toThrow(GatewayConfigurationError);
  });

  it("cannot target an unversioned backend path", async () => {
    const client = createGatewayClient({
      env: { ZOID99_BACKEND_BASE_URL: "http://127.0.0.1:4000", ZOID99_WEB_SERVICE_TOKEN: token },
      fetchImpl: vi.fn<typeof fetch>(),
    });

    await expect(client.request("/health")).rejects.toThrow(GatewayConfigurationError);
  });
});
