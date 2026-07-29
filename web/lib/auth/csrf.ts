const MUTATION_METHODS = new Set(["POST", "PUT", "PATCH", "DELETE"]);

export class CsrfError extends Error {
  constructor(message = "A same-origin request is required") {
    super(message);
    this.name = "CsrfError";
  }
}

function originFromRequest(request: Request, publicBaseUrl?: string): string {
  if (publicBaseUrl) {
    try {
      return new URL(publicBaseUrl).origin;
    } catch {
      throw new CsrfError("The public application origin is invalid");
    }
  }
  return new URL(request.url).origin;
}

export function assertSameOriginMutation(
  request: Request,
  options: { publicBaseUrl?: string } = {},
): void {
  if (!MUTATION_METHODS.has(request.method.toUpperCase())) {
    return;
  }

  const origin = request.headers.get("origin");
  const fetchSite = request.headers.get("sec-fetch-site");
  const publicBaseUrl = options.publicBaseUrl ?? (
    process.env.NODE_ENV === "production" ? process.env.PUBLIC_BASE_URL : undefined
  );
  const hasMatchingOrigin = origin !== null
    && origin !== "null"
    && origin === originFromRequest(request, publicBaseUrl);
  const hasSameOriginFetchMetadata = fetchSite === "same-origin";

  if (!hasMatchingOrigin && !hasSameOriginFetchMetadata) {
    throw new CsrfError();
  }

  if (fetchSite && fetchSite !== "same-origin") {
    throw new CsrfError();
  }
}
