export type StructuredErrorCode =
  | "unauthorized"
  | "service_unavailable"
  | "invalid_request"
  | "not_found"
  | "conflict"
  | "payload_too_large"
  | "internal_error";

export type StructuredErrorDetail = {
  path: string;
  message: string;
};

export type StructuredError = {
  error: StructuredErrorCode;
  message: string;
  requestId: string;
  details: StructuredErrorDetail[];
};

export function createErrorEnvelope(
  error: StructuredErrorCode,
  message: string,
  requestId: string,
  details: StructuredErrorDetail[] = [],
): StructuredError {
  return { error, message, requestId, details };
}
