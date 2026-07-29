import {
  freshnessValues,
  opportunitySchema,
  opportunitySortValues,
  paginatedResponseSchema,
  sourceGroups,
  topicDetailSchema,
  topicSchema,
  verificationStates,
  type Opportunity,
  type OpportunityDisposition,
  type Topic,
  type TopicDetail,
  type VerificationState,
} from "@zoid99/contracts";

export const radarPageSize = 25;

const opportunityPageSchema = paginatedResponseSchema(opportunitySchema);
const topicPageSchema = paginatedResponseSchema(topicSchema);

export type RadarFilters = {
  search: string;
  source: (typeof sourceGroups)[number] | "";
  topic: string;
  country: string;
  language: string;
  freshness: (typeof freshnessValues)[number] | "";
  verification: VerificationState | "";
  disposition: OpportunityDisposition | "";
  sort: (typeof opportunitySortValues)[number] | "";
  cursor: string;
};

export type TopicFilters = {
  search: string;
  cursor: string;
  topic: string;
};

export const defaultRadarFilters: RadarFilters = {
  search: "",
  source: "",
  topic: "",
  country: "",
  language: "",
  freshness: "",
  verification: "",
  disposition: "",
  sort: "",
  cursor: "",
};

export const defaultTopicFilters: TopicFilters = {
  search: "",
  cursor: "",
  topic: "",
};

function clean(value: string | null): string {
  return value?.trim() ?? "";
}

function enumValue<T extends string>(value: string | null, values: readonly T[]): T | "" {
  const cleaned = clean(value);
  return values.includes(cleaned as T) ? (cleaned as T) : "";
}

export function parseRadarFilters(source: string | { toString(): string }): RadarFilters {
  const params = new URLSearchParams(typeof source === "string" ? source : source.toString());
  const cursor = clean(params.get("cursor"));
  return {
    search: clean(params.get("search")),
    source: enumValue(params.get("source"), sourceGroups),
    topic: clean(params.get("topic")),
    country: clean(params.get("country")),
    language: clean(params.get("language")),
    freshness: enumValue(params.get("freshness"), freshnessValues),
    verification: enumValue(params.get("verification"), verificationStates),
    disposition: enumValue(params.get("disposition"), ["active", "saved", "watched", "dismissed", "muted"]),
    sort: enumValue(params.get("sort"), opportunitySortValues),
    cursor: cursor.length <= 512 ? cursor : "",
  };
}

export function parseTopicFilters(source: string | { toString(): string }): TopicFilters {
  const params = new URLSearchParams(typeof source === "string" ? source : source.toString());
  const cursor = clean(params.get("cursor"));
  return {
    search: clean(params.get("search")),
    cursor: cursor.length <= 512 ? cursor : "",
    topic: clean(params.get("topic")),
  };
}

function addParam(params: URLSearchParams, name: string, value: string): void {
  if (value) params.set(name, value);
}

export function serializeRadarFilters(filters: RadarFilters, includeCursor = true): string {
  const params = new URLSearchParams();
  addParam(params, "search", filters.search);
  addParam(params, "source", filters.source);
  addParam(params, "topic", filters.topic);
  addParam(params, "country", filters.country);
  addParam(params, "language", filters.language);
  addParam(params, "freshness", filters.freshness);
  addParam(params, "verification", filters.verification);
  addParam(params, "disposition", filters.disposition);
  addParam(params, "sort", filters.sort);
  if (includeCursor) addParam(params, "cursor", filters.cursor);
  return params.toString();
}

export function serializeTopicFilters(filters: TopicFilters, includeCursor = true): string {
  const params = new URLSearchParams();
  addParam(params, "search", filters.search);
  if (includeCursor) addParam(params, "cursor", filters.cursor);
  addParam(params, "topic", filters.topic);
  return params.toString();
}

function queryString(params: URLSearchParams): string {
  params.set("limit", String(radarPageSize));
  return params.toString();
}

export function buildRadarQuery(filters: RadarFilters): string {
  const params = new URLSearchParams(serializeRadarFilters(filters));
  return queryString(params);
}

export function buildTopicsQuery(filters: TopicFilters): string {
  const params = new URLSearchParams();
  addParam(params, "search", filters.search);
  addParam(params, "cursor", filters.cursor);
  return queryString(params);
}

export class RadarClientError extends Error {
  readonly kind: "unavailable" | "invalid";

  constructor(message: string, kind: "unavailable" | "invalid" = "unavailable") {
    super(message);
    this.name = "RadarClientError";
    this.kind = kind;
  }
}

async function requestJson<T>(path: string, schema: { parse(value: unknown): T }, signal?: AbortSignal): Promise<T> {
  let response: Response;
  try {
    response = await fetch(path, { signal, cache: "no-store" });
  } catch {
    throw new RadarClientError("The private data gateway could not be reached.");
  }

  const body = await response.json().catch(() => null);
  if (!response.ok) {
    const message = typeof body === "object" && body !== null && "msg" in body && typeof body.msg === "string"
      ? body.msg
      : "The private data gateway is unavailable.";
    throw new RadarClientError(message);
  }

  try {
    return schema.parse(body);
  } catch {
    throw new RadarClientError("The gateway returned data in an unexpected shape.", "invalid");
  }
}

export async function fetchRadarPage(filters: RadarFilters, signal?: AbortSignal): Promise<{
  items: Opportunity[];
  nextCursor: string | null;
  serverTime: string;
}> {
  return requestJson(`/api/gateway/opportunities?${buildRadarQuery(filters)}`, opportunityPageSchema, signal);
}

export async function fetchTopicsPage(filters: TopicFilters, signal?: AbortSignal): Promise<{
  items: Topic[];
  nextCursor: string | null;
  serverTime: string;
}> {
  return requestJson(`/api/gateway/topics?${buildTopicsQuery(filters)}`, topicPageSchema, signal);
}

export async function fetchTopicDetail(topicKey: string, signal?: AbortSignal): Promise<TopicDetail> {
  const encodedTopicKey = encodeURIComponent(topicKey);
  return requestJson(`/api/gateway/topics/${encodedTopicKey}`, topicDetailSchema, signal);
}

export const radarFilterOptions = {
  sources: sourceGroups,
  verifications: verificationStates,
  dispositions: ["active", "saved", "watched", "dismissed", "muted"] as const,
  freshness: freshnessValues,
  sort: opportunitySortValues,
};
