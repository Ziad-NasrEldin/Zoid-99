import { NextRequest, NextResponse } from "next/server";

import { assertSameOriginMutation, CsrfError } from "@/lib/auth/csrf";
import { createErrorEnvelope } from "@/lib/auth/errors";
import {
  operatorSessionCookieName,
  operatorSessionMaxAgeSeconds,
} from "@/lib/auth/operator-session";
import { getRequestId, requestIdHeader } from "@/lib/auth/request-id";
import { applySecurityHeaders } from "@/lib/auth/security";
import { gatewayRequest, GatewayConfigurationError } from "@/lib/server/gateway";

export async function POST(request: NextRequest): Promise<NextResponse> {
  const requestId = getRequestId(request.headers);
  try {
    assertSameOriginMutation(request);
  } catch (error) {
    if (error instanceof CsrfError) {
      return errorResponse("invalid_request", error.message, 403, requestId);
    }
    throw error;
  }

  let password = "";
  try {
    const body = await request.json() as { password?: unknown };
    password = typeof body.password === "string" ? body.password : "";
  } catch {
    return errorResponse("invalid_request", "A password is required", 400, requestId);
  }
  if (!password || password.length > 512) {
    return errorResponse("invalid_request", "A password is required", 400, requestId);
  }

  try {
    const upstream = await gatewayRequest("/v1/operator/login", {
      method: "POST",
      headers: { "content-type": "application/json", [requestIdHeader]: requestId },
      body: JSON.stringify({ password }),
      cache: "no-store",
    });
    const body = await upstream.json() as { token?: unknown; expiresAt?: unknown; message?: unknown };
    if (!upstream.ok) {
      const message = typeof body.message === "string" ? body.message : "Operator login failed";
      return errorResponse(
        upstream.status === 429 ? "service_unavailable" : "unauthorized",
        message,
        upstream.status,
        requestId,
      );
    }
    if (typeof body.token !== "string" || body.token.length < 32) {
      return errorResponse("service_unavailable", "Operator login returned an invalid session", 502, requestId);
    }

    const response = NextResponse.json({ authenticated: true, authRequired: true });
    response.cookies.set({
      name: operatorSessionCookieName,
      value: body.token,
      httpOnly: true,
      secure: process.env.NODE_ENV === "production",
      sameSite: "lax",
      path: "/",
      maxAge: operatorSessionMaxAgeSeconds,
      priority: "high",
    });
    response.headers.set(requestIdHeader, requestId);
    applySecurityHeaders(response);
    return response;
  } catch (error) {
    const message = error instanceof GatewayConfigurationError
      ? "Operator authentication is not configured"
      : "Operator authentication is unavailable";
    return errorResponse("service_unavailable", message, 503, requestId);
  }
}

function errorResponse(
  error: "unauthorized" | "service_unavailable" | "invalid_request",
  message: string,
  status: number,
  requestId: string,
): NextResponse {
  const response = NextResponse.json(createErrorEnvelope(error, message, requestId), { status });
  response.headers.set(requestIdHeader, requestId);
  applySecurityHeaders(response);
  return response;
}
