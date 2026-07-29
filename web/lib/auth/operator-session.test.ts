import { describe, expect, it, vi } from "vitest";

import {
  authenticateOperatorRequest,
  OperatorSessionError,
  readOperatorSessionToken,
} from "@/lib/auth/operator-session";

const productionEnvironment = {
  NODE_ENV: "production",
  ZOID99_BACKEND_BASE_URL: "https://zoid.example.test",
  ZOID99_WEB_SERVICE_TOKEN: "service-token-with-more-than-thirty-two-characters",
};

describe("operator session authentication", () => {
  it("reads only the protected operator cookie", () => {
    const headers = new Headers({
      cookie: "other=value; zoid99_operator_session=session-token-value; final=value",
    });
    expect(readOperatorSessionToken(headers)).toBe("session-token-value");
  });

  it("fails closed in production when the cookie is missing", async () => {
    await expect(authenticateOperatorRequest(new Headers(), {
      env: productionEnvironment,
      fetchImpl: vi.fn(),
    })).rejects.toMatchObject({ code: "unauthorized" } satisfies Partial<OperatorSessionError>);
  });

  it("accepts a backend-validated operator session", async () => {
    const fetchImpl = vi.fn().mockResolvedValue(new Response(JSON.stringify({
      authenticated: true,
      authRequired: true,
    }), { status: 200, headers: { "content-type": "application/json" } }));
    const session = await authenticateOperatorRequest(new Headers({
      cookie: "zoid99_operator_session=session-token-value-with-sufficient-length",
    }), {
      env: productionEnvironment,
      fetchImpl,
    });
    expect(session).toEqual({ authenticated: true, authRequired: true });
    const forwarded = new Headers(fetchImpl.mock.calls[0]?.[1]?.headers);
    expect(forwarded.get("authorization")).toBe(`Bearer ${productionEnvironment.ZOID99_WEB_SERVICE_TOKEN}`);
    expect(forwarded.get("x-zoid-operator-session")).toBe("session-token-value-with-sufficient-length");
    expect(forwarded.get("cookie")).toBeNull();
  });
});
