import { describe, expect, it, vi } from "vitest";
import { NextRequest } from "next/server";

import { OperatorSessionError } from "@/lib/auth/operator-session";
import { protectRequest } from "@/middleware";

describe("operator access middleware", () => {
  it("redirects unauthenticated page requests to login without research data", async () => {
    const response = await protectRequest(new NextRequest("https://zoid.example.test/today", {
      headers: { "x-request-id": "review-request-123" },
    }), {
      authenticate: async () => {
        throw new OperatorSessionError("unauthorized", "invalid");
      },
    });

    expect(response.status).toBe(307);
    expect(response.headers.get("location")).toBe("https://zoid.example.test/login?next=%2Ftoday");
    expect(response.headers.get("x-content-type-options")).toBe("nosniff");
    expect(response.headers.get("cache-control")).toBe("private, no-store");
  });

  it("returns a structured denial for unauthenticated gateway requests", async () => {
    const response = await protectRequest(new NextRequest("https://zoid.example.test/api/gateway/bootstrap", {
      headers: { "x-request-id": "review-request-123" },
    }), {
      authenticate: async () => {
        throw new OperatorSessionError("unauthorized", "invalid");
      },
    });

    expect(response.status).toBe(401);
    expect(await response.json()).toEqual({
      error: "unauthorized",
      message: "A valid operator session is required",
      requestId: "review-request-123",
      details: [],
    });
    expect(response.headers.get("x-request-id")).toBe("review-request-123");
    expect(response.headers.get("x-content-type-options")).toBe("nosniff");
    expect(response.headers.get("cache-control")).toBe("private, no-store");
  });

  it("allows the login and auth endpoints without an existing session", async () => {
    const authenticate = vi.fn();
    const response = await protectRequest(
      new NextRequest("https://zoid.example.test/login"),
      { authenticate },
    );
    expect(response.status).toBe(200);
    expect(authenticate).not.toHaveBeenCalled();
  });
});
