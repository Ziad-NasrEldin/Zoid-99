import {
  watchlistFieldsSchema,
  watchlistKindSchema,
  watchlistSchema,
  type WatchlistEntry,
  type WatchlistKind,
} from "@zoid99/contracts";

export type WatchlistInput = Omit<WatchlistEntry, "id" | "serverTime">;
export type WatchlistFetcher = (input: RequestInfo | URL, init?: RequestInit) => Promise<Response>;

export type WatchlistClientErrorKind = "unavailable" | "error";

export class WatchlistClientError extends Error {
  readonly kind: WatchlistClientErrorKind;
  readonly status: number;

  constructor(message: string, options: { kind: WatchlistClientErrorKind; status: number }) {
    super(message);
    this.name = "WatchlistClientError";
    this.kind = options.kind;
    this.status = options.status;
  }
}

export const watchlistKinds = [
  "Creator",
  "Official source",
  "Company",
  "Keyword",
  "Topic",
  "Country",
  "Language",
] as const satisfies readonly WatchlistKind[];

export const watchlistKindLabels: Record<WatchlistKind, string> = {
  Creator: "Creator",
  "Official source": "Official source",
  Company: "Company",
  Keyword: "Keyword",
  Topic: "Topic",
  Country: "Country",
  Language: "Language",
};

export const providerSupport: ReadonlyArray<{
  name: string;
  supportedKinds: readonly WatchlistKind[];
  note: string;
}> = [
  {
    name: "YouTube",
    supportedKinds: watchlistKinds,
    note: "All seven kinds. A configured provider credential is required for collection.",
  },
  {
    name: "X",
    supportedKinds: watchlistKinds,
    note: "All seven kinds. A configured provider credential is required for collection.",
  },
  {
    name: "Instagram",
    supportedKinds: ["Creator"],
    note: "Creator entries only. Other kinds are not sent to this connector.",
  },
  {
    name: "Google Trends",
    supportedKinds: [],
    note: "No watchlist connector is currently wired to Google Trends.",
  },
];

const watchlistPath = "/api/gateway/watchlist";

export function normalizeWatchlistValue(value: string): string {
  return value.trim().toLocaleLowerCase();
}

export function duplicateWatchlistEntry(
  entries: readonly Pick<WatchlistEntry, "kind" | "value" | "id">[],
  input: Pick<WatchlistInput, "kind" | "value">,
  excludeID?: string,
): boolean {
  const key = `${input.kind}:${normalizeWatchlistValue(input.value)}`;
  return entries.some((entry) => entry.id !== excludeID && `${entry.kind}:${normalizeWatchlistValue(entry.value)}` === key);
}

export function validateWatchlistInput(input: WatchlistInput): string | null {
  const parsed = watchlistFieldsSchema.safeParse({
    ...input,
    value: input.value.trim(),
  });
  if (!parsed.success) return "Choose a kind and enter a value up to 500 characters.";

  if (input.kind === "Official source") {
    try {
      const url = new URL(input.value.trim());
      if (url.protocol !== "https:" || !url.hostname) {
        return "Official sources must use a complete HTTPS URL.";
      }
    } catch {
      return "Official sources must use a complete HTTPS URL.";
    }
  }

  return null;
}

export function providerSupportForKind(kind: WatchlistKind): string {
  const supported = providerSupport
    .filter((provider) => provider.supportedKinds.includes(kind))
    .map((provider) => provider.name);
  return supported.length > 0 ? supported.join(" + ") : "No connected collector";
}

function requestID(operation: string): string {
  const uuid = globalThis.crypto?.randomUUID?.();
  return `${operation}:${uuid ?? `${Date.now()}-${Math.random().toString(36).slice(2)}`}`;
}

function responseMessage(payload: unknown): string | null {
  if (!payload || typeof payload !== "object") return null;
  const record = payload as Record<string, unknown>;
  if (typeof record.message === "string") return record.message;
  if (typeof record.msg === "string") return record.msg;
  if (record.error && typeof record.error === "object") {
    const nested = record.error as Record<string, unknown>;
    if (typeof nested.message === "string") return nested.message;
  }
  return null;
}

async function readPayload(response: Response): Promise<unknown> {
  if (response.status === 204) return null;
  return response.json().catch(() => null);
}

function parseEntries(payload: unknown): WatchlistEntry[] {
  const entries = Array.isArray(payload)
    ? payload
    : payload && typeof payload === "object" && Array.isArray((payload as { entries?: unknown }).entries)
      ? (payload as { entries: unknown[] }).entries
      : null;
  const parsed = watchlistSchema.array().safeParse(entries);
  if (!parsed.success) throw new WatchlistClientError("The gateway returned an unexpected watchlist shape.", { kind: "error", status: 502 });
  return parsed.data;
}

function parseEntry(payload: unknown): WatchlistEntry {
  const candidate = payload && typeof payload === "object" && "entry" in payload
    ? (payload as { entry: unknown }).entry
    : payload;
  const parsed = watchlistSchema.safeParse(candidate);
  if (!parsed.success) throw new WatchlistClientError("The gateway returned an unexpected watchlist entry.", { kind: "error", status: 502 });
  return parsed.data;
}

export function createWatchlistClient(fetcher: WatchlistFetcher = (...args) => globalThis.fetch(...args)) {
  async function request<T>(path: string, init: RequestInit | undefined, parse: (payload: unknown) => T): Promise<T> {
    let response: Response;
    try {
      response = await fetcher(path, {
        ...init,
        cache: "no-store",
        headers: {
          Accept: "application/json",
          ...(init?.body ? { "Content-Type": "application/json" } : {}),
          ...init?.headers,
        },
      });
    } catch {
      throw new WatchlistClientError("The private data gateway is unavailable.", { kind: "unavailable", status: 503 });
    }

    const payload = await readPayload(response);
    if (!response.ok) {
      throw new WatchlistClientError(
        responseMessage(payload) ?? "The watchlist request could not be completed.",
        { kind: response.status >= 500 ? "unavailable" : "error", status: response.status },
      );
    }
    return parse(payload);
  }

  return {
    list(signal?: AbortSignal) {
      return request(watchlistPath, { method: "GET", signal }, parseEntries);
    },
    add(input: WatchlistInput, idempotencyKey = requestID("watchlist-add")) {
      return request(watchlistPath, {
        method: "POST",
        body: JSON.stringify(input),
        headers: { "Idempotency-Key": idempotencyKey },
      }, parseEntry);
    },
    edit(id: string, input: WatchlistInput, idempotencyKey = requestID("watchlist-edit")) {
      return request(`${watchlistPath}/${encodeURIComponent(id)}`, {
        method: "PATCH",
        body: JSON.stringify(input),
        headers: { "Idempotency-Key": idempotencyKey },
      }, parseEntry);
    },
    replace(entries: WatchlistEntry[], idempotencyKey = requestID("watchlist-replace")) {
      return request(watchlistPath, {
        method: "PUT",
        body: JSON.stringify({ entries }),
        headers: { "Idempotency-Key": idempotencyKey },
      }, parseEntries);
    },
    remove(id: string, idempotencyKey = requestID("watchlist-remove")) {
      return request(`${watchlistPath}/${encodeURIComponent(id)}`, {
        method: "DELETE",
        headers: { "Idempotency-Key": idempotencyKey },
      }, () => null);
    },
    validateKind(kind: string): kind is WatchlistKind {
      return watchlistKindSchema.safeParse(kind).success;
    },
  };
}

export type WatchlistClient = ReturnType<typeof createWatchlistClient>;

export const watchlistClient = createWatchlistClient();
