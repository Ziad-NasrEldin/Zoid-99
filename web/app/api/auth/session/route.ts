import { NextRequest, NextResponse } from "next/server";

import { authenticateOperatorRequest, OperatorSessionError } from "@/lib/auth/operator-session";
import { applySecurityHeaders } from "@/lib/auth/security";

export async function GET(request: NextRequest): Promise<NextResponse> {
  try {
    const session = await authenticateOperatorRequest(request.headers);
    const response = NextResponse.json(session);
    applySecurityHeaders(response);
    return response;
  } catch (error) {
    const unavailable = error instanceof OperatorSessionError && error.code === "service_unavailable";
    const response = NextResponse.json(
      { authenticated: false, authRequired: true },
      { status: unavailable ? 503 : 401 },
    );
    applySecurityHeaders(response);
    return response;
  }
}
