const ALLOWED_GATEWAY_PATHS = [
  /^\/v1\/bootstrap$/,
  /^\/v1\/opportunities(?:\/[A-Za-z0-9_-]+(?:\/disposition)?)?$/,
  /^\/v1\/topics(?:\/[A-Za-z0-9_-]+)?$/,
  /^\/v1\/comments$/,
  /^\/v1\/watchlist(?:\/[A-Za-z0-9_-]+)?$/,
  /^\/v1\/notifications(?:\/[A-Za-z0-9_-]+)?$/,
  /^\/v1\/sources\/health$/,
];

export function buildGatewayPath(path: string[]): string | null {
  if (path.length === 0 || path.some((segment) => segment.length === 0)) {
    return null;
  }

  const candidate = `/v1/${path.join("/")}`;
  return ALLOWED_GATEWAY_PATHS.some((pattern) => pattern.test(candidate)) ? candidate : null;
}
