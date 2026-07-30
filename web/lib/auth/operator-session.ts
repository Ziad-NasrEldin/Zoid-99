import { gatewayRequest, GatewayConfigurationError } from "@/lib/server/gateway";

export const operatorSessionCookieName = "zoid99_operator_session";
export const operatorSessionHeaderName = "x-zoid-operator-session";
export const operatorSessionMaxAgeSeconds = 60 * 60 * 24 * 14;

export type OperatorSession = {
  authenticated: boolean;
  authRequired: true;
};

export class OperatorSessionError extends Error {
  constructor(
    readonly code: "unauthorized" | "service_unavailable",
    message: string,
  ) {
    super(message);
    this.name = "OperatorSessionError";
  }
}

export function readOperatorSessionToken(headers: Headers): string | null {
  const cookieHeader = headers.get("cookie");
  if (!cookieHeader) return null;
  const prefix = `${operatorSessionCookieName}=`;
  return cookieHeader
    .split(";")
    .map((part) => part.trim())
    .find((part) => part.startsWith(prefix))
    ?.slice(prefix.length) ?? null;
}

export async function authenticateOperatorRequest(
  headers: Headers,
  options: { env?: Record<string, string | undefined>; fetchImpl?: typeof fetch } = {},
): Promise<OperatorSession> {
  const env = options.env ?? process.env;
  const production = env.NODE_ENV === "production" || env.NODE_ENV === "prod";
  if (!production && env.ZOID_DEV_AUTH !== "false") {
    return { authenticated: true, authRequired: true };
  }

  const token = readOperatorSessionToken(headers);
  if (!token) {
    throw new OperatorSessionError("unauthorized", "Operator session is required");
  }

  try {
    const response = await gatewayRequest("/v1/operator/session", {
      headers: { [operatorSessionHeaderName]: token },
      cache: "no-store",
    }, options);
    if (!response.ok) {
      throw new OperatorSessionError("service_unavailable", "Operator session verification is unavailable");
    }
    const body = await response.json() as Partial<OperatorSession>;
    if (body.authenticated !== true || body.authRequired !== true) {
      throw new OperatorSessionError("unauthorized", "Operator session is invalid or expired");
    }
    return { authenticated: true, authRequired: true };
  } catch (error) {
    if (error instanceof OperatorSessionError) throw error;
    if (error instanceof GatewayConfigurationError) {
      throw new OperatorSessionError("service_unavailable", "Operator authentication is not configured");
    }
    throw new OperatorSessionError("service_unavailable", "Operator session verification is unavailable");
  }
}
