import { NextRequest, NextResponse } from "next/server";

import { assertSameOriginMutation, CsrfError } from "@/lib/auth/csrf";
import { createErrorEnvelope } from "@/lib/auth/errors";
import {
  operatorSessionCookieName,
  operatorSessionHeaderName,
  readOperatorSessionToken,
} from "@/lib/auth/operator-session";
import { getRequestId, requestIdHeader } from "@/lib/auth/request-id";
import { applySecurityHeaders } from "@/lib/auth/security";
import { gatewayRequest } from "@/lib/server/gateway";

export async function POST(request: NextRequest): Promise<NextResponse> {
  const requestId = getRequestId(request.headers);
  try {
    assertSameOriginMutation(request);
  } catch (error) {
    if (error instanceof CsrfError) {
      const response = NextResponse.json(createErrorEnvelope("invalid_request", error.message, requestId), { status: 403 });
      applySecurityHeaders(response);
      return response;
    }
    throw error;
  }

  const token = readOperatorSessionToken(request.headers);
  if (token) {
    await gatewayRequest("/v1/operator/logout", {
      method: "POST",
      headers: { [operatorSessionHeaderName]: token, [requestIdHeader]: requestId },
      cache: "no-store",
    }).catch(() => undefined);
  }

  const response = NextResponse.json({ authenticated: false, authRequired: true });
  response.cookies.set({
    name: operatorSessionCookieName,
    value: "",
    httpOnly: true,
    secure: process.env.NODE_ENV === "production",
    sameSite: "lax",
    path: "/",
    maxAge: 0,
    priority: "high",
  });
  response.headers.set(requestIdHeader, requestId);
  applySecurityHeaders(response);
  return response;
}
