import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";

import { describe, expect, it } from "vitest";
import { structuredErrorSchema } from "@zoid99/contracts";

import { applySecurityHeaders, protectedCookiePolicy } from "@/lib/auth/security";
import { createErrorEnvelope } from "@/lib/auth/errors";
import { buildGatewayPath } from "@/lib/server/gateway-routes";

function filesUnder(directory: string): string[] {
  return readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const path = join(directory, entry.name);
    return entry.isDirectory() ? filesUnder(path) : [path];
  });
}

describe("web security boundaries", () => {
  it("keeps the gateway restricted to existing versioned API projections", () => {
    expect(buildGatewayPath(["bootstrap"])).toBe("/v1/bootstrap");
    expect(buildGatewayPath(["opportunities", "abc-123"])).toBe("/v1/opportunities/abc-123");
    expect(buildGatewayPath(["topics"])).toBe("/v1/topics");
    expect(buildGatewayPath(["topics", "arabic-ai"])).toBe("/v1/topics/arabic-ai");
    expect(buildGatewayPath(["comments"])).toBe("/v1/comments");
    expect(buildGatewayPath(["health"])).toBeNull();
    expect(buildGatewayPath(["connections", "youtube"])).toBeNull();
    expect(buildGatewayPath(["../../etc/passwd"])).toBeNull();
  });

  it("sets security headers and a strict protected-cookie policy", () => {
    const response = applySecurityHeaders(new Response("ok"), "production");
    expect(response.headers.get("x-frame-options")).toBe("DENY");
    expect(response.headers.get("x-content-type-options")).toBe("nosniff");
    expect(response.headers.get("strict-transport-security")).toContain("max-age=31536000");
    expect(protectedCookiePolicy).toContain("HttpOnly");
    expect(protectedCookiePolicy).toContain("Secure");
    expect(protectedCookiePolicy).toContain("SameSite=Lax");
  });

  it("uses the frozen error/message/requestId/details envelope", () => {
    const envelope = createErrorEnvelope("invalid_request", "Origin check failed", "req-123");
    expect(envelope).toEqual({
      error: "invalid_request",
      message: "Origin check failed",
      requestId: "req-123",
      details: [],
    });
    expect(structuredErrorSchema.parse(envelope)).toEqual(envelope);
    expect(envelope).not.toHaveProperty("err");
    expect(envelope).not.toHaveProperty("msg");
  });

  it("does not place the backend secret name in browser-owned source", () => {
    const browserFiles = [
      ...filesUnder(join(process.cwd(), "app")),
      ...filesUnder(join(process.cwd(), "components")),
      ...filesUnder(join(process.cwd(), "lib")),
    ].filter((path) => !path.includes(`${join("lib", "server")}${process.platform === "win32" ? "\\" : "/"}`) && !path.includes(".test."));
    const source = browserFiles.map((path) => readFileSync(path, "utf8")).join("\n");

    expect(source).not.toContain("ZOID99_WEB_SERVICE_TOKEN");
    expect(source).not.toContain("NEXT_PUBLIC_ZOID99_WEB_SERVICE_TOKEN");
  });
});
