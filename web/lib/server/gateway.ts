export type GatewayEnvironment = Record<string, string | undefined>;

export class GatewayConfigurationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "GatewayConfigurationError";
  }
}

export type GatewayClient = {
  request(path: string, init?: RequestInit): Promise<Response>;
};

function gatewayUrl(baseUrl: string, path: string, production: boolean): string {
  let parsedBaseUrl: URL;
  try {
    parsedBaseUrl = new URL(baseUrl);
  } catch {
    throw new GatewayConfigurationError("ZOID99_BACKEND_BASE_URL must be a URL");
  }

  if (production && parsedBaseUrl.protocol !== "https:") {
    throw new GatewayConfigurationError("ZOID99_BACKEND_BASE_URL must use HTTPS");
  }

  if (!path.startsWith("/v1/")) {
    throw new GatewayConfigurationError("Gateway paths must stay within the versioned API");
  }

  return new URL(path, `${parsedBaseUrl.origin}${parsedBaseUrl.pathname.replace(/\/$/, "")}/`).toString();
}

export function createGatewayClient(
  options: { env?: GatewayEnvironment; fetchImpl?: typeof fetch } = {},
): GatewayClient {
  const env = options.env ?? process.env;
  const baseUrl = env.ZOID99_BACKEND_BASE_URL;
  const serviceToken = env.ZOID99_WEB_SERVICE_TOKEN;
  const production = env.NODE_ENV === "production" || env.NODE_ENV === "prod";

  if (!baseUrl || !serviceToken || serviceToken.length < 32) {
    throw new GatewayConfigurationError(
      "ZOID99_BACKEND_BASE_URL and a 32-character ZOID99_WEB_SERVICE_TOKEN are required",
    );
  }

  const fetchImpl = options.fetchImpl ?? fetch;
  return {
    async request(path, init = {}) {
      const target = gatewayUrl(baseUrl, path, production);
      const headers = new Headers(init.headers);
      headers.set("authorization", `Bearer ${serviceToken}`);
      headers.set("accept", "application/json");
      headers.delete("cookie");
      headers.delete("set-cookie");
      headers.delete("x-zoid-dev-identity");
      headers.delete("cf-access-jwt-assertion");

      return fetchImpl(target, {
        ...init,
        headers,
        redirect: "error",
      });
    },
  };
}

export async function gatewayRequest(
  path: string,
  init?: RequestInit,
  options?: { env?: GatewayEnvironment; fetchImpl?: typeof fetch },
): Promise<Response> {
  return createGatewayClient(options).request(path, init);
}
