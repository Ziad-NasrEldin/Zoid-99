import { createHash } from "node:crypto";
import type { CollectedRecord } from "./official-collector.js";
import { parseSyndication } from "./official-collector.js";
import type { ResearchBatch, SourceGroup, SourceHealth, WatchlistEntry } from "./domain.js";
import {
  fetchPublicHTTPS,
  fetchPublicHTTPSWith,
  readBoundedResponse,
  type PublicHostnameResolver,
} from "./outbound-http.js";
import type { ResearchRepository } from "./repository.js";

type WatchlistProvider = "youtube" | "x" | "instagram";
type ProviderSourceGroup = "YouTube" | "X" | "Instagram";

export interface WatchlistCredentialStore {
  get(key: string): Promise<string | null>;
}

export interface WatchlistCollectorOptions {
  repository: ResearchRepository;
  fetchImplementation?: typeof fetch;
  now?: () => Date;
  credentials?: Partial<Record<WatchlistProvider, string>>;
  credentialStore?: WatchlistCredentialStore;
  resolveHostname?: PublicHostnameResolver;
}

export interface WatchlistProviderResult {
  provider: WatchlistProvider;
  requests: number;
  successful: number;
  accepted: number;
  failures: number;
  rateLimited: boolean;
  state: SourceHealth["state"];
}

export interface WatchlistCollectionResult {
  official: { requests: number; successful: number; accepted: number; failures: number; rateLimited: boolean };
  providers: WatchlistProviderResult[];
}

type WatchPlan = {
  kind: WatchlistEntry["kind"];
  term: string;
  country: string;
  language: string;
};

const providerSourceGroups: Record<WatchlistProvider, ProviderSourceGroup> = {
  youtube: "YouTube",
  x: "X",
  instagram: "Instagram",
};

const credentialKeys: Record<WatchlistProvider, string[]> = {
  youtube: ["provider.youtube.credential", "youtube.api-key"],
  x: ["provider.x.credential", "x.bearer-token"],
  instagram: ["provider.instagram.credential", "instagram.access-token"],
};

export async function collectWatchlist(options: WatchlistCollectorOptions): Promise<WatchlistCollectionResult> {
  const fetchImplementation = options.fetchImplementation ?? fetch;
  const now = options.now ?? (() => new Date());
  const entries = await options.repository.listWatchlist();
  const plans = buildWatchPlans(entries);

  await options.repository.upsertSourceHealth({
    group: "Google Trends",
    state: "Setup required",
    lastActivity: null,
    evidence: "Official Google Trends API alpha access is not approved in this runtime; no request was made.",
    repairAction: "Configure an approved official client",
    dataTruth: "Missing",
  });

  const official = await collectUserOfficialSources(options, entries, now);
  const providers = await Promise.all(
    (Object.keys(providerSourceGroups) as WatchlistProvider[]).map((provider) =>
      collectProvider(provider, plans[provider], options, fetchImplementation, now)),
  );

  return { official, providers };
}

function buildWatchPlans(entries: WatchlistEntry[]): Record<WatchlistProvider, WatchPlan[]> {
  const monitored = entries
    .filter((entry) => ["Creator", "Company", "Keyword", "Topic"].includes(entry.kind))
    .map((entry) => ({ kind: entry.kind, term: entry.value.trim() }))
    .filter((entry) => Boolean(entry.term));
  const countries = uniqueValues(entries.filter((entry) => entry.kind === "Country").map((entry) => entry.value))
    .map(countryCode)
    .filter((value): value is string => value !== null);
  const languages = uniqueValues(entries.filter((entry) => entry.kind === "Language").map((entry) => entry.value))
    .map(languageCode)
    .filter((value): value is string => value !== null);
  const countryValues = countries.length > 0 ? countries : ["Global"];
  const languageValues = languages.length > 0 ? languages : ["en"];
  const youtube = monitored.flatMap(({ kind, term }) => countryValues.flatMap((country) => languageValues.map((language) => ({
    kind,
    term,
    country,
    language,
  }))));
  const x = monitored.flatMap(({ kind, term }) => languageValues.map((language) => ({
    kind,
    term,
    country: "Global",
    language,
  })));
  const instagram = monitored
    .filter((entry) => entry.kind === "Creator")
    .map(({ kind, term }) => ({ kind, term, country: "Global", language: "und" }));
  return {
    youtube: dedupePlans(youtube).slice(0, 100),
    x: dedupePlans(x).slice(0, 100),
    instagram: dedupePlans(instagram).slice(0, 25),
  };
}

function dedupePlans(plans: WatchPlan[]): WatchPlan[] {
  const seen = new Set<string>();
  return plans.filter((plan) => {
    const key = `${plan.term.toLocaleLowerCase()}:${plan.country.toLocaleLowerCase()}:${plan.language.toLocaleLowerCase()}`;
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

function uniqueValues(values: string[]): string[] {
  return [...new Set(values.map((value) => value.trim()).filter(Boolean))];
}

function countryCode(value: string): string | null {
  const normalized = value.trim().toLocaleLowerCase();
  const known: Record<string, string> = {
    egypt: "EG",
    "مصر": "EG",
    "saudi arabia": "SA",
    "السعودية": "SA",
    "united arab emirates": "AE",
    uae: "AE",
    "الإمارات": "AE",
    oman: "OM",
    "عمان": "OM",
    "united states": "US",
    usa: "US",
    us: "US",
  };
  return known[normalized] ?? (/^[a-z]{2}$/.test(normalized) ? normalized.toUpperCase() : null);
}

function languageCode(value: string): string | null {
  const normalized = value.trim().toLocaleLowerCase();
  const known: Record<string, string> = {
    arabic: "ar",
    "العربية": "ar",
    english: "en",
    "الإنجليزية": "en",
  };
  return known[normalized] ?? (/^[a-z]{2,3}$/.test(normalized) ? normalized : null);
}

async function collectUserOfficialSources(
  options: WatchlistCollectorOptions,
  entries: WatchlistEntry[],
  now: () => Date,
): Promise<WatchlistCollectionResult["official"]> {
  const sources = uniqueValues(entries.filter((entry) => entry.kind === "Official source").map((entry) => entry.value));
  let requests = 0;
  let successful = 0;
  let accepted = 0;
  let failures = 0;
  let rateLimited = false;
  const collectedAt = now().toISOString();

  for (const endpoint of sources) {
    requests += 1;
    try {
      const headers = {
        accept: "application/atom+xml, application/rss+xml, application/xml;q=0.9",
        "user-agent": "Zoid99/1.0 (watchlist official source)",
      };
      const response = options.fetchImplementation
        ? await fetchPublicHTTPSWith(endpoint, headers, options.fetchImplementation, options.resolveHostname)
        : await fetchPublicHTTPS(endpoint, headers, options.resolveHostname);
      if (response.status === 429) rateLimited = true;
      if (!response.ok) {
        failures += 1;
        continue;
      }
      successful += 1;
      const xml = response.body;
      const rssRecords = parseSyndication(xml, "rss");
      const records = rssRecords.length > 0 ? rssRecords : parseSyndication(xml, "atom");
      for (const record of records.slice(0, 30)) {
        await options.repository.persistResearchBatch(toResearchBatch(
          "US & Official",
          `watchlist-official-${sourceKey(endpoint)}`,
          sourceName(endpoint),
          record,
          "Global",
          "en",
          collectedAt,
          now(),
        ));
        accepted += 1;
      }
    } catch {
      failures += 1;
    }
  }

  if (successful > 0) {
    await options.repository.upsertSourceHealth({
      group: "US & Official",
      state: failures > 0 ? "Delayed" : "Connected",
      lastActivity: collectedAt,
      evidence: `${successful} watchlist source${successful === 1 ? "" : "s"} responded; ${accepted} item${accepted === 1 ? "" : "s"} collected; ${failures} source failure${failures === 1 ? "" : "s"}.`,
      repairAction: failures > 0 ? "Review source logs" : "Review",
      dataTruth: failures > 0 ? "Delayed" : "Live",
    });
  } else if (sources.length > 0) {
    const current = (await options.repository.listSourceHealth()).find((health) => health.group === "US & Official");
    if (!current || !["Connected", "Cached", "Delayed"].includes(current.state)) {
      await options.repository.upsertSourceHealth({
        group: "US & Official",
        state: rateLimited ? "Rate limited" : "Unavailable",
        lastActivity: null,
        evidence: `No watchlist official-source items were collected; ${failures} source failure${failures === 1 ? "" : "s"}.`,
        repairAction: rateLimited ? "Wait and retry" : "Review source logs",
        dataTruth: rateLimited ? "Rate limited" : "Unavailable",
      });
    }
  }

  return { requests, successful, accepted, failures, rateLimited };
}

async function collectProvider(
  provider: WatchlistProvider,
  plans: WatchPlan[],
  options: WatchlistCollectorOptions,
  fetchImplementation: typeof fetch,
  now: () => Date,
): Promise<WatchlistProviderResult> {
  const group = providerSourceGroups[provider];
  const credential = await resolveCredential(provider, options);
  const usableCredential = credential && provider === "instagram"
    ? instagramCredential(credential) !== null
    : Boolean(credential);
  if (!credential || !usableCredential || plans.length === 0) {
    const reason = !credential
      ? `No server credential is configured for ${group}; no ${group} request was made.`
      : !usableCredential
        ? `The ${group} server credential is incomplete; no ${group} request was made.`
      : `No ${group} watchlist entries are configured; no request was made.`;
    await options.repository.upsertSourceHealth({
      group,
      state: "Setup required",
      lastActivity: null,
      evidence: reason,
      repairAction: "Configure",
      dataTruth: "Missing",
    });
    return {
      provider,
      requests: 0,
      successful: 0,
      accepted: 0,
      failures: 0,
      rateLimited: false,
      state: "Setup required",
    };
  }

  const collectedAt = now().toISOString();
  let requests = 0;
  let successful = 0;
  let accepted = 0;
  let failures = 0;
  let rateLimited = false;
  const seenRecords = new Set<string>();
  for (const plan of plans) {
    requests += 1;
    try {
      const response = await fetchImplementation(providerEndpoint(provider, plan, credential), {
        headers: providerHeaders(provider, credential),
        signal: AbortSignal.timeout(15_000),
      });
      if (response.status === 429) rateLimited = true;
      if (!response.ok) {
        failures += 1;
        continue;
      }
      successful += 1;
      const records = parseProviderResponse(provider, JSON.parse(await readBoundedResponse(response)));
      for (const record of records) {
        const dedupeKey = `${record.externalID}:${plan.country}:${plan.language}`;
        if (seenRecords.has(dedupeKey)) continue;
        seenRecords.add(dedupeKey);
        await options.repository.persistResearchBatch(toResearchBatch(
          group,
          provider,
          provider,
          record,
          plan.country,
          plan.language,
          collectedAt,
          now(),
        ));
        accepted += 1;
      }
    } catch {
      failures += 1;
    }
  }

  const state: WatchlistProviderResult["state"] = successful > 0
    ? failures > 0 ? "Delayed" : "Connected"
    : rateLimited ? "Rate limited" : "Unavailable";
  await options.repository.upsertSourceHealth({
    group,
    state,
    lastActivity: successful > 0 ? collectedAt : null,
    evidence: successful > 0
      ? `${successful} ${group} request${successful === 1 ? "" : "s"} succeeded; ${accepted} item${accepted === 1 ? "" : "s"} collected across ${plans.length} plan${plans.length === 1 ? "" : "s"}; ${failures} request failure${failures === 1 ? "" : "s"}.`
      : `No ${group} watchlist items were collected; ${failures} request failure${failures === 1 ? "" : "s"}.`,
    repairAction: state === "Rate limited" ? "Wait and retry" : state === "Unavailable" ? "Review source logs" : "Review",
    dataTruth: state === "Rate limited" ? "Rate limited" : successful > 0 ? failures > 0 ? "Delayed" : "Live" : "Unavailable",
  });
  return { provider, requests, successful, accepted, failures, rateLimited, state };
}

async function resolveCredential(provider: WatchlistProvider, options: WatchlistCollectorOptions): Promise<string | null> {
  const direct = options.credentials?.[provider]?.trim();
  if (direct) return direct;
  if (!options.credentialStore) return null;
  for (const key of credentialKeys[provider]) {
    const value = (await options.credentialStore.get(key))?.trim();
    if (value) return value;
  }
  return null;
}

function providerEndpoint(provider: WatchlistProvider, plan: WatchPlan, credential: string): string {
  if (provider === "youtube") {
    const url = new URL("https://www.googleapis.com/youtube/v3/search");
    url.searchParams.set("part", "snippet");
    url.searchParams.set("type", "video");
    url.searchParams.set("maxResults", "25");
    url.searchParams.set("q", plan.term);
    if (/^[A-Za-z]{2}$/.test(plan.country)) url.searchParams.set("regionCode", plan.country.toUpperCase());
    if (plan.language !== "Global") url.searchParams.set("relevanceLanguage", plan.language.toLowerCase());
    if (isYouTubeApiKey(credential)) url.searchParams.set("key", credential);
    return url.toString();
  }
  if (provider === "x") {
    const url = new URL("https://api.x.com/2/tweets/search/recent");
    const normalizedCreator = plan.term.replace(/^@/, "");
    const monitored = plan.kind === "Creator" ? `from:${normalizedCreator}` : `(${plan.term})`;
    const language = /^[A-Za-z]{2,3}$/.test(plan.language) ? ` lang:${plan.language.toLowerCase()}` : "";
    url.searchParams.set("query", `${monitored}${language} -is:retweet`);
    url.searchParams.set("max_results", "10");
    url.searchParams.set("tweet.fields", "created_at,author_id");
    return url.toString();
  }
  const instagram = instagramCredential(credential);
  if (!instagram) throw new Error("Instagram requires an account ID and access token");
  const username = plan.term.replace(/^@/, "");
  const url = new URL(`https://graph.facebook.com/${instagram.version}/${encodeURIComponent(instagram.accountID)}`);
  url.searchParams.set(
    "fields",
    `business_discovery.username(${username}){id,username,media.limit(25){id,caption,permalink,timestamp,username}}`,
  );
  return url.toString();
}

function providerHeaders(provider: WatchlistProvider, credential: string): Record<string, string> {
  if (provider === "youtube" && isYouTubeApiKey(credential)) return { accept: "application/json" };
  if (provider === "instagram") {
    const instagram = instagramCredential(credential);
    return { accept: "application/json", authorization: `Bearer ${instagram?.accessToken ?? ""}` };
  }
  return { accept: "application/json", authorization: `Bearer ${credential}` };
}

function isYouTubeApiKey(credential: string): boolean {
  return credential.startsWith("AIza");
}

function parseProviderResponse(provider: WatchlistProvider, value: unknown): CollectedRecord[] {
  if (provider === "youtube") return parseYouTube(value);
  if (provider === "x") return parseX(value);
  return parseInstagram(value);
}

function parseYouTube(value: unknown): CollectedRecord[] {
  const items = objectValue(value).items;
  if (!Array.isArray(items)) return [];
  return items.flatMap((item): CollectedRecord[] => {
    const entry = objectValue(item);
    const id = objectValue(entry.id).videoId;
    const snippet = objectValue(entry.snippet);
    const title = stringValue(snippet.title);
    const publishedAt = dateString(snippet.publishedAt);
    if (!id || !title || !publishedAt) return [];
    return [{
      externalID: stringValue(id),
      title,
      summary: stringValue(snippet.description),
      author: stringValue(snippet.channelTitle),
      url: `https://www.youtube.com/watch?v=${encodeURIComponent(stringValue(id))}`,
      publishedAt,
    }];
  });
}

function parseX(value: unknown): CollectedRecord[] {
  const data = objectValue(value).data;
  if (!Array.isArray(data)) return [];
  return data.flatMap((item): CollectedRecord[] => {
    const entry = objectValue(item);
    const id = stringValue(entry.id);
    const text = stringValue(entry.text);
    const publishedAt = dateString(entry.created_at);
    if (!id || !text || !publishedAt) return [];
    return [{
      externalID: id,
      title: text.split(/\s+/).slice(0, 12).join(" "),
      summary: text,
      author: stringValue(entry.author_id),
      url: `https://x.com/i/web/status/${encodeURIComponent(id)}`,
      publishedAt,
    }];
  });
}

function parseInstagram(value: unknown): CollectedRecord[] {
  const root = objectValue(value);
  const discovery = objectValue(root.business_discovery);
  const data = objectValue(discovery.media).data ?? root.data;
  if (!Array.isArray(data)) return [];
  return data.flatMap((item): CollectedRecord[] => {
    const entry = objectValue(item);
    const id = stringValue(entry.id);
    const url = stringValue(entry.permalink);
    const caption = stringValue(entry.caption);
    const publishedAt = dateString(entry.timestamp);
    if (!id || !url || !caption || !publishedAt) return [];
    return [{
      externalID: id,
      title: caption.split(/\s+/).slice(0, 12).join(" "),
      summary: caption,
      author: stringValue(entry.username),
      url,
      publishedAt,
    }];
  });
}

function toResearchBatch(
  group: ProviderSourceGroup | "US & Official",
  provider: string,
  sourceName: string,
  record: CollectedRecord,
  country: string,
  language: string,
  collectedAt: string,
  now: Date,
): ResearchBatch {
  const isOfficialEvidence = group === "US & Official";
  const key = createHash("sha256")
    .update(`${group}:${provider}:${record.externalID}:${country}:${language}`)
    .digest("hex");
  const ageHours = Math.max(0, (now.getTime() - new Date(record.publishedAt).getTime()) / 3_600_000);
  const freshness = ageHours <= 24 ? 20 : ageHours <= 72 ? 15 : ageHours <= 168 ? 10 : 5;
  const item = {
    group: group as SourceGroup,
    externalID: `${provider}:${sourceName}:${record.externalID}:${country}:${language}`,
    title: record.title,
    summary: record.summary,
    author: record.author || sourceName,
    url: record.url,
    publishedAt: record.publishedAt,
    collectedAt,
    language,
    country,
    topicKey: key,
    isOriginalSource: isOfficialEvidence,
    credibility: isOfficialEvidence ? 1 : 0.5,
    engagement: 0,
    verification: isOfficialEvidence ? "Confirmed" as const : "Unverified" as const,
  };
  return {
    clusterKey: key,
    topicKey: key,
    verification: isOfficialEvidence ? "Confirmed" : "Unverified",
    originState: isOfficialEvidence ? "Identified" : "Unknown",
    originalSource: isOfficialEvidence ? { group: item.group, externalID: item.externalID } : null,
    sourceItems: [item],
    opportunity: {
      title: record.title,
      brief: record.summary || `Collected from ${sourceName}.`,
      score: {
        freshness,
        credibility: 20,
        momentum: 0,
        creatorActivity: group === "YouTube" || group === "Instagram" || group === "X" ? 5 : 0,
        arabicCoverageGap: language.toLowerCase().startsWith("ar") ? 0 : 10,
        regionalRelevance: country === "Global" ? 0 : 5,
      },
      regionalExplanation: country === "Global" ? "Regional relevance has not yet been evaluated." : `Planned for ${country}.`,
      coverageExplanation: language.toLowerCase().startsWith("ar")
        ? "Arabic-language evidence was collected."
        : "Arabic coverage has not yet been evaluated.",
      disposition: "active",
    },
    notification: null,
  };
}

function sourceName(endpoint: string): string {
  try {
    return new URL(endpoint).hostname;
  } catch {
    return "Watchlist official source";
  }
}

function sourceKey(endpoint: string): string {
  return createHash("sha256").update(endpoint).digest("hex").slice(0, 12);
}

type InstagramCredential = {
  accountID: string;
  accessToken: string;
  version: string;
};

function instagramCredential(value: string): InstagramCredential | null {
  try {
    const parsed = JSON.parse(value) as Record<string, unknown>;
    const accountID = stringValue(parsed.accountID);
    const accessToken = stringValue(parsed.accessToken);
    const requestedVersion = stringValue(parsed.graphAPIVersion);
    const version = /^v\d+\.\d+$/.test(requestedVersion) ? requestedVersion : "v22.0";
    return accountID && accessToken ? { accountID, accessToken, version } : null;
  } catch {
    return null;
  }
}

function objectValue(value: unknown): Record<string, unknown> {
  return typeof value === "object" && value !== null ? value as Record<string, unknown> : {};
}

function stringValue(value: unknown): string {
  return typeof value === "string" || typeof value === "number" ? String(value).trim() : "";
}

function dateString(value: unknown): string | null {
  const date = new Date(stringValue(value));
  return Number.isNaN(date.getTime()) ? null : date.toISOString();
}
