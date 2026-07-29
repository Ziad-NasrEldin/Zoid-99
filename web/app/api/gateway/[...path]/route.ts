import { NextRequest, NextResponse } from "next/server";

import { authenticateOperatorRequest, OperatorSessionError } from "@/lib/auth/operator-session";
import { assertSameOriginMutation, CsrfError } from "@/lib/auth/csrf";
import { createErrorEnvelope, type StructuredErrorCode } from "@/lib/auth/errors";
import { getRequestId, requestIdHeader } from "@/lib/auth/request-id";
import { applyProtectedCookiePolicy, applySecurityHeaders } from "@/lib/auth/security";
import { gatewayRequest, GatewayConfigurationError } from "@/lib/server/gateway";
import { buildGatewayPath } from "@/lib/server/gateway-routes";

type RouteContext = { params: Promise<unknown> };

const MUTATION_METHODS = new Set(["POST", "PUT", "PATCH", "DELETE"]);

function jsonError(error: StructuredErrorCode, message: string, status: number, requestId: string): NextResponse {
  const response = NextResponse.json(createErrorEnvelope(error, message, requestId), { status });
  response.headers.set(requestIdHeader, requestId);
  applyProtectedCookiePolicy(response.headers);
  applySecurityHeaders(response);
  return response;
}

function responseFromBackend(response: Response): NextResponse {
  if (response.status === 204) {
    // Route handlers cannot safely forward an empty upstream stream as HTTP 204.
    const result = NextResponse.json({ ok: true });
    applyProtectedCookiePolicy(result.headers);
    applySecurityHeaders(result);
    return result;
  }

  const headers = new Headers();
  const contentType = response.headers.get("content-type");
  const etag = response.headers.get("etag");
  if (contentType) headers.set("content-type", contentType);
  if (etag) headers.set("etag", etag);
  // HTTP 304 responses must not carry a body, including an empty stream.
  const body = response.status === 304 ? null : response.body;
  const result = new NextResponse(body, { status: response.status, headers });
  applyProtectedCookiePolicy(result.headers);
  applySecurityHeaders(result);
  return result;
}

async function handle(request: NextRequest, context: RouteContext): Promise<NextResponse> {
  const requestId = getRequestId(request.headers);
  try {
    await authenticateOperatorRequest(request.headers);
  } catch (error) {
    const isConfigError = error instanceof OperatorSessionError && error.code === "service_unavailable";
    return jsonError(
      isConfigError ? "service_unavailable" : "unauthorized",
      isConfigError ? "Operator authentication is unavailable" : "A valid operator session is required",
      isConfigError ? 503 : 401,
      requestId,
    );
  }

  if (MUTATION_METHODS.has(request.method)) {
    try {
      assertSameOriginMutation(request);
    } catch (error) {
      if (error instanceof CsrfError) {
        return jsonError("invalid_request", error.message, 403, requestId);
      }
      throw error;
    }
  }

  const params = (await context.params) as { path?: string | string[] };
  const path = Array.isArray(params.path) ? params.path : params.path ? [params.path] : [];
  const backendPath = buildGatewayPath(path);
  if (!backendPath) {
    return jsonError("not_found", "This gateway route is not available", 404, requestId);
  }

  const body = MUTATION_METHODS.has(request.method) ? await request.arrayBuffer() : undefined;
  const headers = new Headers();
  for (const name of ["content-type", "if-match", "if-none-match", "idempotency-key", requestIdHeader]) {
    const value = request.headers.get(name);
    if (value) headers.set(name, value);
  }

  try {
    const upstream = await gatewayRequest(`${backendPath}${new URL(request.url).search}`, {
      method: request.method,
      headers,
      body,
    });
    const result = responseFromBackend(upstream);
    result.headers.set(requestIdHeader, requestId);
    return result;
  } catch (error) {
    if (error instanceof GatewayConfigurationError) {
      return jsonError("service_unavailable", "The private data gateway is not configured", 503, requestId);
    }
    return jsonError("service_unavailable", "The private data gateway is unavailable", 502, requestId);
  }
}

export const GET = handle;
export const POST = handle;
export const PUT = handle;
export const PATCH = handle;
export const DELETE = handle;
