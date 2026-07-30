import {
  connectionSchema,
  preferencesPatchSchema,
  preferencesSchema,
  sourceHealthSchema,
  type ConnectionStatus,
  type Preferences,
  type PreferencesPatch,
  type SourceHealth,
} from "@zoid99/contracts";

export type ConnectionActionState = {
  status: "idle" | "success" | "error";
  message: string;
  connection?: ConnectionStatus;
  formKey: string;
};

export type PreferenceActionState = {
  status: "idle" | "success" | "conflict" | "error";
  message: string;
  preferences?: Preferences;
  etag?: string;
};

export const idleConnectionActionState: ConnectionActionState = {
  status: "idle",
  message: "",
  formKey: "initial",
};

export const idlePreferenceActionState: PreferenceActionState = {
  status: "idle",
  message: "",
};

export function parseSourceHealthPayload(input: unknown): SourceHealth[] {
  return sourceHealthSchema.array().parse(input);
}

export function parseConnectionsPayload(input: unknown): ConnectionStatus[] {
  return connectionSchema.array().parse(input);
}

export function parsePreferencesPayload(input: unknown, etag: string | null): { preferences: Preferences; etag: string } {
  if (!etag) throw new Error("The preferences response did not include an ETag");
  return { preferences: preferencesSchema.parse(input), etag };
}

export function preferencePatchFromFormData(formData: FormData): PreferencesPatch {
  const quietHours = {
    enabled: formData.get("quietHoursEnabled") === "on",
    start: String(formData.get("quietHoursStart") ?? "22:00"),
    end: String(formData.get("quietHoursEnd") ?? "08:00"),
  };

  return preferencesPatchSchema.parse({
    refreshMinutes: Number(formData.get("refreshMinutes")),
    notificationsEnabled: formData.get("notificationsEnabled") === "on",
    digestHour: Number(formData.get("digestHour")),
    quietHours,
    locale: String(formData.get("locale") ?? "en"),
    timeZone: String(formData.get("timeZone") ?? "UTC"),
  });
}

export function safeGatewayMessage(input: unknown, fallback: string): string {
  if (!input || typeof input !== "object") return fallback;
  const message = (input as { message?: unknown }).message;
  return typeof message === "string" && message.length > 0 ? message : fallback;
}

