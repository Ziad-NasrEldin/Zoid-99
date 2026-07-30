const REQUEST_ID_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$/;

export const requestIdHeader = "x-request-id";

export function getRequestId(headers: Headers): string {
  const supplied = headers.get(requestIdHeader)?.trim();
  return supplied && REQUEST_ID_PATTERN.test(supplied) ? supplied : crypto.randomUUID();
}
