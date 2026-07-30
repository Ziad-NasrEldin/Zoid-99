import { NextRequest, NextResponse } from "next/server";

import { authenticateOperatorRequest, OperatorSessionError } from "@/lib/auth/operator-session";
import { createErrorEnvelope } from "@/lib/auth/errors";
import { getRequestId, requestIdHeader } from "@/lib/auth/request-id";
import { applyProtectedCookiePolicy, applySecurityHeaders } from "@/lib/auth/security";

type MiddlewareDependencies = {
  authenticate?: typeof authenticateOperatorRequest;
};

const PUBLIC_PATHS = new Set(["/login", "/api/auth/login", "/api/auth/logout", "/api/auth/session"]);

function protectedResponse(error: "unauthorized" | "service_unavailable", message: string, status: number, requestId: string, nodeEnv?: string): NextResponse {
  const response = NextResponse.json(createErrorEnvelope(error, message, requestId), { status });
  response.headers.set(requestIdHeader, requestId);
  applyProtectedCookiePolicy(response.headers);
  applySecurityHeaders(response, nodeEnv);
  return response;
}

export async function protectRequest(
  request: NextRequest,
  dependencies: MiddlewareDependencies = {},
): Promise<NextResponse> {
  const requestId = getRequestId(request.headers);
  const pathname = request.nextUrl.pathname;
  if (PUBLIC_PATHS.has(pathname)) {
    const response = NextResponse.next();
    applySecurityHeaders(response);
    return response;
  }
  try {
    await (dependencies.authenticate ?? authenticateOperatorRequest)(request.headers);
    const forwardedHeaders = new Headers(request.headers);
    forwardedHeaders.set(requestIdHeader, requestId);
    const response = NextResponse.next({ request: { headers: forwardedHeaders } });
    response.headers.set("cache-control", "private, no-store");
    response.headers.set(requestIdHeader, requestId);
    applyProtectedCookiePolicy(response.headers);
    applySecurityHeaders(response);
    return response;
  } catch (error) {
    const isConfigError = error instanceof OperatorSessionError && error.code === "service_unavailable";
    if (!pathname.startsWith("/api/") && !isConfigError) {
      const loginUrl = new URL("/login", request.url);
      loginUrl.searchParams.set("next", `${pathname}${request.nextUrl.search}`);
      const response = NextResponse.redirect(loginUrl);
      applySecurityHeaders(response);
      return response;
    }
    return protectedResponse(
      isConfigError ? "service_unavailable" : "unauthorized",
      isConfigError ? "Operator authentication is unavailable" : "A valid operator session is required",
      isConfigError ? 503 : 401,
      requestId,
    );
  }
}

export async function middleware(request: NextRequest): Promise<NextResponse> {
  return protectRequest(request);
}

export const config = {
  matcher: ["/((?!_next/static|_next/image|favicon.ico).*)"],
};
