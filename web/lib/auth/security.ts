export const protectedCookiePolicy = "Path=/; HttpOnly; Secure; SameSite=Lax";

const SECURITY_HEADERS: Readonly<Record<string, string>> = {
  "content-security-policy":
    "default-src 'self'; base-uri 'self'; frame-ancestors 'none'; form-action 'self'; object-src 'none'; script-src 'self' 'unsafe-inline' 'unsafe-eval'",
  "permissions-policy": "camera=(), geolocation=(), microphone=(), payment=()",
  "referrer-policy": "no-referrer",
  "x-content-type-options": "nosniff",
  "x-frame-options": "DENY",
};

export function applySecurityHeaders(response: Response, nodeEnv: string | undefined = process.env.NODE_ENV): Response {
  for (const [name, value] of Object.entries(SECURITY_HEADERS)) {
    response.headers.set(name, value);
  }

  response.headers.set("cache-control", "private, no-store");
  if (nodeEnv === "production" || nodeEnv === "prod") {
    response.headers.set("strict-transport-security", "max-age=31536000; includeSubDomains");
  }

  return response;
}

export function applyProtectedCookiePolicy(headers: Headers): Headers {
  headers.set("x-zoid-cookie-policy", protectedCookiePolicy);
  return headers;
}
