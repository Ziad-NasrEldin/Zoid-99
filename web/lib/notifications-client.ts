import { z } from "zod";

import { notificationSchema, paginatedResponseSchema } from "@zoid99/contracts";

export const BROWSER_NOTIFICATION_FEATURE_ENABLED = false as const;

export type GatewayFetcher = (path: string, init?: RequestInit) => Promise<Response>;
export type NotificationRecord = z.infer<typeof notificationSchema>;
export const notificationPageSchema = paginatedResponseSchema(notificationSchema);
export type NotificationPage = z.infer<typeof notificationPageSchema>;

export class NotificationsClientError extends Error {
  readonly kind: "unavailable" | "error";
  readonly status: number;

  constructor(message: string, options: { kind: "unavailable" | "error"; status: number }) {
    super(message);
    this.name = "NotificationsClientError";
    this.kind = options.kind;
    this.status = options.status;
  }
}

function defaultFetcher(path: string, init?: RequestInit): Promise<Response> {
  return fetch(`/api/gateway${path}`, {
    ...init,
    headers: {
      accept: "application/json",
      ...(init?.headers ?? {}),
    },
  });
}

async function readGatewayResponse(response: Response): Promise<unknown> {
  if (!response.ok) {
    const payload = (await response.json().catch(() => null)) as { msg?: string; message?: string } | null;
    const message = payload?.msg ?? payload?.message ?? "The private data gateway returned an error.";
    throw new NotificationsClientError(message, {
      kind: response.status >= 500 ? "unavailable" : "error",
      status: response.status,
    });
  }

  return response.json();
}

export async function getNotificationHistory(
  fetcher: GatewayFetcher = defaultFetcher,
  options: { limit?: number } = {},
): Promise<NotificationPage> {
  const query = new URLSearchParams({ limit: String(options.limit ?? 200) });
  const payload = await readGatewayResponse(await fetcher(`/notifications?${query.toString()}`));
  return notificationPageSchema.parse(payload);
}

export async function setNotificationReadState(
  id: string,
  isRead: boolean,
  fetcher: GatewayFetcher = defaultFetcher,
  idempotencyKey = crypto.randomUUID(),
): Promise<NotificationRecord> {
  const payload = await readGatewayResponse(
    await fetcher(`/notifications/${encodeURIComponent(id)}`, {
      method: "PATCH",
      headers: {
        accept: "application/json",
        "content-type": "application/json",
        "idempotency-key": idempotencyKey,
      },
      body: JSON.stringify({ isRead }),
    }),
  );
  return notificationSchema.parse(payload);
}
