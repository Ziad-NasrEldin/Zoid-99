import {
  bootstrapSchema,
  dispositionSchema,
  opportunityDispositionStateSchema,
  opportunitySchema,
  type BootstrapPayload,
  type Opportunity,
  type OpportunityDisposition,
  type OpportunityDispositionState,
  type SourceHealth,
} from "@zoid99/contracts";

export type GatewayFetcher = (path: string, init?: RequestInit) => Promise<Response>;

export type ResearchDataTruth = "Live" | "Cached" | "Missing" | "Unavailable";

export class ResearchClientError extends Error {
  readonly kind: "unavailable" | "error";
  readonly status: number;

  constructor(message: string, options: { kind: "unavailable" | "error"; status: number }) {
    super(message);
    this.name = "ResearchClientError";
    this.kind = options.kind;
    this.status = options.status;
  }
}

export type TodayData = BootstrapPayload & {
  dataTruth: ResearchDataTruth;
  lastSuccessfulSync: string | null;
};

export type OpportunityData = {
  opportunity: Opportunity;
  dataTruth: ResearchDataTruth;
};

function browserGateway(path: string, init?: RequestInit): Promise<Response> {
  return fetch(`/api/gateway${path}`, {
    ...init,
    credentials: "same-origin",
    headers: {
      accept: "application/json",
      ...init?.headers,
    },
  });
}

async function readJson<T>(response: Response, parse: (input: unknown) => T): Promise<T> {
  if (!response.ok) {
    let message = "The research gateway returned an error.";
    try {
      const payload = (await response.json()) as { message?: unknown };
      if (typeof payload.message === "string") message = payload.message;
    } catch {
      // Keep the safe public message when the gateway did not return JSON.
    }

    throw new ResearchClientError(message, {
      kind: response.status >= 500 ? "unavailable" : "error",
      status: response.status,
    });
  }

  try {
    return parse(await response.json());
  } catch (error) {
    if (error instanceof ResearchClientError) throw error;
    throw new ResearchClientError("The research response could not be read.", {
      kind: "error",
      status: response.status,
    });
  }
}

function latestDate(values: Array<string | null | undefined>): string | null {
  return values.filter((value): value is string => Boolean(value)).sort().at(-1) ?? null;
}

function dataTruthForHealth(sourceHealth: SourceHealth[]): ResearchDataTruth {
  if (sourceHealth.length === 0) return "Missing";
  if (sourceHealth.some((health) => health.dataTruth === "Unavailable")) return "Unavailable";
  if (sourceHealth.some((health) => health.dataTruth === "Cached" || health.dataTruth === "Delayed")) return "Cached";
  if (sourceHealth.every((health) => health.dataTruth === "Missing")) return "Missing";
  return "Live";
}

export async function getTodayData(fetcher: GatewayFetcher = browserGateway): Promise<TodayData> {
  const bootstrap = await readJson(await fetcher("/bootstrap"), (input) => bootstrapSchema.parse(input));
  const lastSuccessfulSync = latestDate([
    ...bootstrap.sourceHealth.map((health) => health.lastActivity),
    ...bootstrap.opportunities.map((opportunity) => opportunity.dispositionUpdatedAt),
    ...bootstrap.opportunities.flatMap((opportunity) => opportunity.items.map((item) => item.collectedAt)),
  ]);

  return {
    ...bootstrap,
    dataTruth: dataTruthForHealth(bootstrap.sourceHealth),
    lastSuccessfulSync,
  };
}

export async function getOpportunityData(
  id: string,
  fetcher: GatewayFetcher = browserGateway,
): Promise<OpportunityData> {
  if (!id.trim()) {
    throw new ResearchClientError("An opportunity identifier is required.", { kind: "error", status: 400 });
  }

  const opportunity = await readJson(
    await fetcher(`/opportunities/${encodeURIComponent(id)}`),
    (input) => opportunitySchema.parse(input),
  );
  return { opportunity, dataTruth: "Live" };
}

function fallbackUuid(): string {
  return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, (character) => {
    const random = Math.floor(Math.random() * 16);
    const value = character === "x" ? random : (random & 0x3) | 0x8;
    return value.toString(16);
  });
}

export function createDispositionMutation(
  disposition: OpportunityDisposition,
  options: { changedAt?: string; mutationID?: string } = {},
) {
  return {
    disposition: dispositionSchema.parse(disposition),
    changedAt: options.changedAt ?? new Date().toISOString(),
    mutationID: options.mutationID ?? globalThis.crypto?.randomUUID?.() ?? fallbackUuid(),
  };
}

export async function updateOpportunityDisposition(
  id: string,
  disposition: OpportunityDisposition,
  fetcher: GatewayFetcher = browserGateway,
  options: { changedAt?: string; mutationID?: string } = {},
): Promise<OpportunityDispositionState> {
  const mutation = createDispositionMutation(disposition, options);
  return readJson(
    await fetcher(`/opportunities/${encodeURIComponent(id)}/disposition`, {
      method: "PATCH",
      headers: { "content-type": "application/json", "idempotency-key": mutation.mutationID },
      body: JSON.stringify(mutation),
    }),
    (input) => opportunityDispositionStateSchema.parse(input),
  );
}

export function formatResearchDate(value: string | null): string {
  if (!value) return "Not available";
  return new Intl.DateTimeFormat("en-GB", {
    day: "2-digit",
    month: "short",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
    timeZoneName: "short",
  }).format(new Date(value));
}

export function isArabicText(value: string): boolean {
  return /[\u0600-\u06ff]/u.test(value);
}
