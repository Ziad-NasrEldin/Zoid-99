"use server";

import { headers } from "next/headers";
import { revalidatePath } from "next/cache";

import {
  connectionSchema,
  preferencesPatchSchema,
  preferencesSchema,
  serverProviderSchema,
  type ConnectionStatus,
  type Preferences,
} from "@zoid99/contracts";

import { authenticateOperatorRequest } from "@/lib/auth/operator-session";
import { gatewayRequest } from "@/lib/server/gateway";
import {
  idleConnectionActionState,
  preferencePatchFromFormData,
  safeGatewayMessage,
  type ConnectionActionState,
  type PreferenceActionState,
} from "@/lib/settings-client";

const connectionFailureMessage = "The provider change could not be completed. Nothing was written to the form.";

async function requireRecentIdentityVerification(): Promise<void> {
  const requestHeaders = await headers();
  await authenticateOperatorRequest(new Headers(requestHeaders));
}

function nextFormKey(): string {
  return crypto.randomUUID();
}

async function responseJSON(response: Response): Promise<unknown> {
  try {
    return await response.json();
  } catch {
    return null;
  }
}

function connectionError(message = connectionFailureMessage): ConnectionActionState {
  return { ...idleConnectionActionState, status: "error", message, formKey: nextFormKey() };
}

function parsedConnection(input: unknown): ConnectionStatus | null {
  const result = connectionSchema.safeParse(input);
  return result.success ? result.data : null;
}

async function mutateConnection(
  formData: FormData,
  method: "PUT" | "POST" | "DELETE",
): Promise<ConnectionActionState> {
  const providerResult = serverProviderSchema.safeParse(formData.get("provider"));
  if (!providerResult.success) return connectionError("Choose a supported provider before submitting.");

  const provider = providerResult.data;
  let credential = "";
  if (method === "PUT") {
    const rawCredential = formData.get("credential");
    credential = typeof rawCredential === "string" ? rawCredential.trim() : "";
    if (!credential) return connectionError("Enter a credential to configure this provider.");
  }

  try {
    await requireRecentIdentityVerification();
    const response = await gatewayRequest(`/v1/connections/${provider}${method === "POST" ? "/validate" : ""}`, {
      method,
      headers: {
        "content-type": "application/json",
        "idempotency-key": crypto.randomUUID(),
      },
      body: method === "PUT" ? JSON.stringify({ credential }) : undefined,
      cache: "no-store",
    });
    const body = await responseJSON(response);

    if (!response.ok) {
      if (response.status === 401 || response.status === 403) {
        return connectionError("Reauthentication is required before changing provider access.");
      }
      return connectionError(safeGatewayMessage(body, connectionFailureMessage));
    }

    const connection = parsedConnection(body);
    if (!connection) return connectionError("The gateway returned an unexpected provider status.");
    revalidatePath("/settings");
    revalidatePath("/sources");
    return { status: "success", message: "Provider status updated. The credential was not returned.", connection, formKey: nextFormKey() };
  } catch {
    return connectionError("Reauthentication or the private data gateway is unavailable. Try again.");
  }
}

export async function configureConnection(_previous: ConnectionActionState, formData: FormData): Promise<ConnectionActionState> {
  return mutateConnection(formData, "PUT");
}

export async function validateConnection(_previous: ConnectionActionState, formData: FormData): Promise<ConnectionActionState> {
  return mutateConnection(formData, "POST");
}

export async function disconnectConnection(_previous: ConnectionActionState, formData: FormData): Promise<ConnectionActionState> {
  return mutateConnection(formData, "DELETE");
}

function preferenceError(message: string, preferences?: Preferences, etag?: string): PreferenceActionState {
  return { status: "error", message, preferences, etag };
}

export async function savePreferences(_previous: PreferenceActionState, formData: FormData): Promise<PreferenceActionState> {
  const etag = formData.get("etag");
  if (typeof etag !== "string" || !etag) {
    return preferenceError("This settings copy is stale. Reload before saving.");
  }

  let patch;
  try {
    patch = preferencesPatchSchema.parse(preferencePatchFromFormData(formData));
  } catch {
    return preferenceError("Check the preference values and try again.");
  }

  try {
    await requireRecentIdentityVerification();
    const response = await gatewayRequest("/v1/preferences", {
      method: "PATCH",
      headers: {
        "content-type": "application/json",
        "if-match": etag,
        "idempotency-key": crypto.randomUUID(),
      },
      body: JSON.stringify(patch),
      cache: "no-store",
    });
    const body = await responseJSON(response);
    const responseETag = response.headers.get("etag") ?? undefined;

    if (response.status === 409 && body && typeof body === "object") {
      const current = (body as { preferences?: unknown }).preferences;
      try {
        const preferences = preferencesSchema.parse(current);
        return {
          status: "conflict",
          message: "Preferences changed elsewhere. Reload the current values before saving.",
          preferences,
          etag: responseETag,
        };
      } catch {
        return preferenceError("Preferences changed elsewhere. Reload before saving.", undefined, responseETag);
      }
    }

    if (!response.ok) return preferenceError(safeGatewayMessage(body, "Preferences could not be saved."));

    const preferences = preferencesSchema.parse(body);
    if (!responseETag) return preferenceError("The preferences response did not include an ETag.");
    revalidatePath("/settings");
    return { status: "success", message: "Preferences saved.", preferences, etag: responseETag };
  } catch {
    return preferenceError("The private data gateway is unavailable. Preferences were not saved.");
  }
}
