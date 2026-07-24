import { createHash } from "node:crypto";
import { XMLParser } from "fast-xml-parser";
import type { ResearchBatch, SourceHealth } from "./domain.js";
import { readBoundedResponse } from "./outbound-http.js";
import type { ResearchRepository } from "./repository.js";

export type CatalogSource = {
  id: string;
  name: string;
  kind: "rss" | "atom" | "github";
  endpoint: string;
  homepage: string;
};

export type CollectedRecord = {
  externalID: string;
  title: string;
  summary: string;
  author: string;
  url: string;
  publishedAt: string;
};

export const officialSourceCatalog: CatalogSource[] = [
  {
    id: "openai-news",
    name: "OpenAI News",
    kind: "rss",
    endpoint: "https://openai.com/news/rss.xml",
    homepage: "https://openai.com/news/",
  },
  {
    id: "huggingface-transformers-releases",
    name: "Hugging Face Transformers Releases",
    kind: "github",
    endpoint: "https://api.github.com/repos/huggingface/transformers/releases?per_page=30",
    homepage: "https://github.com/huggingface/transformers",
  },
  {
    id: "arxiv-cs-ai",
    name: "arXiv Computer Science - Artificial Intelligence",
    kind: "atom",
    endpoint: "https://export.arxiv.org/api/query?search_query=cat%3Acs.AI&start=0&max_results=30&sortBy=submittedDate&sortOrder=descending",
    homepage: "https://arxiv.org/list/cs.AI/recent",
  },
  {
    id: "google-ai-news",
    name: "Google AI News",
    kind: "rss",
    endpoint: "https://blog.google/innovation-and-ai/technology/ai/rss/",
    homepage: "https://blog.google/innovation-and-ai/technology/ai/",
  },
  {
    id: "google-gemini-cli-releases",
    name: "Google Gemini CLI Releases",
    kind: "github",
    endpoint: "https://api.github.com/repos/google-gemini/gemini-cli/releases?per_page=30",
    homepage: "https://github.com/google-gemini/gemini-cli",
  },
  {
    id: "anthropic-claude-code-releases",
    name: "Anthropic Claude Code Releases",
    kind: "github",
    endpoint: "https://api.github.com/repos/anthropics/claude-code/releases?per_page=30",
    homepage: "https://github.com/anthropics/claude-code",
  },
];

export type OfficialCollectorOptions = {
  repository: ResearchRepository;
  fetchImplementation?: typeof fetch;
  now?: () => Date;
  catalog?: CatalogSource[];
};

interface OfficialCollectionResult {
  requests: number;
  successful: number;
  accepted: number;
  failures: number;
  rateLimited: boolean;
}

export async function collectOfficialSources(options: OfficialCollectorOptions): Promise<OfficialCollectionResult> {
  const fetchImplementation = options.fetchImplementation ?? fetch;
  const now = options.now ?? (() => new Date());
  const catalog = options.catalog ?? officialSourceCatalog;
  const collectedAt = now().toISOString();
  let successful = 0;
  let accepted = 0;
  let failures = 0;
  let rateLimited = false;

  for (const source of catalog) {
    try {
      const response = await fetchImplementation(source.endpoint, {
        headers: {
          accept: source.kind === "github"
            ? "application/vnd.github+json"
            : "application/atom+xml, application/rss+xml, application/xml;q=0.9",
          "user-agent": `Zoid99/1.0 (+${source.homepage})`,
        },
        signal: AbortSignal.timeout(15_000),
      });
      if (response.status === 429) rateLimited = true;
      if (!response.ok) {
        failures += 1;
        continue;
      }
      successful += 1;
      const body = await readBoundedResponse(response);
      const records = source.kind === "github"
        ? parseGitHubReleases(JSON.parse(body))
        : parseSyndication(body, source.kind);
      for (const record of records.slice(0, 30)) {
        await options.repository.persistResearchBatch(toResearchBatch(source, record, collectedAt, now()));
        accepted += 1;
      }
    } catch {
      failures += 1;
    }
  }

  const health: SourceHealth = successful > 0
    ? {
        group: "US & Official",
        state: failures > 0 ? "Delayed" : "Connected",
        lastActivity: collectedAt,
        evidence: `${successful} official source${successful === 1 ? "" : "s"} responded; ${accepted} item${accepted === 1 ? "" : "s"} collected; ${failures} source failure${failures === 1 ? "" : "s"}.`,
        repairAction: failures > 0 ? "Review source logs" : "Review",
        dataTruth: failures > 0 ? "Delayed" : "Live",
      }
    : {
        group: "US & Official",
        state: rateLimited ? "Rate limited" : "Unavailable",
        lastActivity: null,
        evidence: `No official-source items were collected; ${failures} source failure${failures === 1 ? "" : "s"}.`,
        repairAction: rateLimited ? "Wait and retry" : "Review source logs",
        dataTruth: rateLimited ? "Rate limited" : "Unavailable",
      };
  await options.repository.upsertSourceHealth(health);
  if (successful === 0) throw new Error("No official sources responded successfully");
  return { requests: catalog.length, successful, accepted, failures, rateLimited };
}

function parseGitHubReleases(value: unknown): CollectedRecord[] {
  if (!Array.isArray(value)) return [];
  return value.flatMap((entry): CollectedRecord[] => {
    if (typeof entry !== "object" || entry === null) return [];
    const release = entry as Record<string, unknown>;
    if (release.draft === true) return [];
    const publishedAt = dateString(release.published_at);
    const url = stringValue(release.html_url);
    const title = stringValue(release.name) || stringValue(release.tag_name);
    if (!publishedAt || !url || !title) return [];
    return [{
      externalID: String(release.id ?? url),
      title,
      summary: stringValue(release.body),
      author: typeof release.author === "object" && release.author !== null
        ? stringValue((release.author as Record<string, unknown>).login)
        : "",
      url,
      publishedAt,
    }];
  });
}

export function parseSyndication(xml: string, kind: "rss" | "atom"): CollectedRecord[] {
  const parser = new XMLParser({
    ignoreAttributes: false,
    processEntities: false,
    trimValues: true,
  });
  const document = parser.parse(xml) as Record<string, unknown>;
  const entries = kind === "rss"
    ? arrayValue(objectValue(objectValue(document.rss).channel).item)
    : arrayValue(objectValue(document.feed).entry);
  return entries.flatMap((value): CollectedRecord[] => {
    const entry = objectValue(value);
    const link = kind === "rss" ? stringValue(entry.link) : atomLink(entry.link);
    const title = textValue(entry.title);
    const publishedAt = dateString(kind === "rss" ? entry.pubDate : entry.published ?? entry.updated);
    if (!link || !title || !publishedAt) return [];
    return [{
      externalID: textValue(kind === "rss" ? entry.guid : entry.id) || link,
      title,
      summary: textValue(kind === "rss" ? entry.description : entry.summary),
      author: textValue(kind === "rss" ? entry.author : objectValue(entry.author).name),
      url: link,
      publishedAt,
    }];
  });
}

function toResearchBatch(
  source: CatalogSource,
  record: CollectedRecord,
  collectedAt: string,
  now: Date,
): ResearchBatch {
  const key = createHash("sha256").update(`${source.id}:${record.externalID}`).digest("hex");
  const ageHours = Math.max(0, (now.getTime() - new Date(record.publishedAt).getTime()) / 3_600_000);
  const freshness = ageHours <= 24 ? 20 : ageHours <= 72 ? 15 : ageHours <= 168 ? 10 : 5;
  const sourceItem = {
    group: "US & Official" as const,
    externalID: `${source.id}:${record.externalID}`,
    title: record.title,
    summary: record.summary,
    author: record.author || source.name,
    url: record.url,
    publishedAt: record.publishedAt,
    collectedAt,
    language: "en",
    country: "Global",
    topicKey: key,
    isOriginalSource: true,
    credibility: 1,
    engagement: 0,
    verification: "Confirmed" as const,
  };
  return {
    clusterKey: key,
    topicKey: key,
    verification: "Confirmed",
    originState: "Identified",
    originalSource: { group: sourceItem.group, externalID: sourceItem.externalID },
    sourceItems: [sourceItem],
    opportunity: {
      title: record.title,
      brief: record.summary || `Published by ${source.name}.`,
      score: {
        freshness,
        credibility: 20,
        momentum: 0,
        creatorActivity: 0,
        arabicCoverageGap: 0,
        regionalRelevance: 0,
      },
      regionalExplanation: "Regional relevance has not yet been evaluated.",
      coverageExplanation: "Arabic coverage has not yet been evaluated.",
      disposition: "active",
    },
    notification: null,
  };
}

function objectValue(value: unknown): Record<string, unknown> {
  return typeof value === "object" && value !== null ? value as Record<string, unknown> : {};
}

function arrayValue(value: unknown): unknown[] {
  if (Array.isArray(value)) return value;
  return value === undefined ? [] : [value];
}

function stringValue(value: unknown): string {
  return typeof value === "string" || typeof value === "number" ? String(value).trim() : "";
}

function textValue(value: unknown): string {
  if (typeof value === "object" && value !== null) {
    const object = value as Record<string, unknown>;
    return stringValue(object["#text"] ?? object.__cdata);
  }
  return stringValue(value);
}

function dateString(value: unknown): string | null {
  const date = new Date(textValue(value));
  return Number.isNaN(date.getTime()) ? null : date.toISOString();
}

function atomLink(value: unknown): string {
  return arrayValue(value)
    .map(objectValue)
    .find((link) => !link["@_rel"] || link["@_rel"] === "alternate")
    ?.[ "@_href" ]?.toString() ?? "";
}
