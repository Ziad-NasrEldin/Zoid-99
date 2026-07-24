import assert from "node:assert/strict";
import test from "node:test";
import { collectWatchlist } from "../src/watchlist-collector.js";
import { MemoryRepository } from "./support/memory-repository.js";

const now = () => new Date("2026-07-24T09:00:00.000Z");

test("watchlist collection reports setup-required providers without making credentialless requests", async () => {
  const repository = new MemoryRepository();
  repository.watchlist = [
    { id: "40000000-0000-4000-8000-000000000001", kind: "Creator", value: "@ai_agents", highPriority: true },
    { id: "40000000-0000-4000-8000-000000000006", kind: "Keyword", value: "AI agents", highPriority: true },
  ];
  const requests: string[] = [];

  const result = await collectWatchlist({
    repository,
    now,
    credentials: { instagram: "token-without-account-id" },
    fetchImplementation: async (input) => {
      requests.push(String(input));
      return new Response("unexpected", { status: 500 });
    },
  });

  assert.equal(requests.length, 0);
  assert.deepEqual(result.providers.map((provider) => [provider.provider, provider.requests, provider.state]), [
    ["youtube", 0, "Setup required"],
    ["x", 0, "Setup required"],
    ["instagram", 0, "Setup required"],
  ]);
  for (const group of ["YouTube", "X", "Instagram", "Google Trends"] as const) {
    const health = repository.sourceHealth.find((entry) => entry.group === group);
    assert.equal(health?.state, "Setup required");
    assert.equal(health?.dataTruth, "Missing");
  }
  assert.match(repository.sourceHealth.find((entry) => entry.group === "Google Trends")?.evidence ?? "", /no request/i);
  assert.match(repository.sourceHealth.find((entry) => entry.group === "Instagram")?.evidence ?? "", /incomplete/i);
});

test("configured official APIs receive bounded country-language plans and preserve source evidence", async () => {
  const repository = new MemoryRepository();
  repository.watchlist = [
    { id: "40000000-0000-4000-8000-000000000001", kind: "Creator", value: "@ai_agents", highPriority: true },
    { id: "40000000-0000-4000-8000-000000000006", kind: "Keyword", value: "AI agents", highPriority: true },
    { id: "40000000-0000-4000-8000-000000000002", kind: "Country", value: "Egypt", highPriority: false },
    { id: "40000000-0000-4000-8000-000000000003", kind: "Country", value: "Saudi Arabia", highPriority: false },
    { id: "40000000-0000-4000-8000-000000000004", kind: "Language", value: "English", highPriority: false },
    { id: "40000000-0000-4000-8000-000000000005", kind: "Language", value: "Arabic", highPriority: false },
  ];
  repository.opportunities = [];
  const requests: Array<{ url: string; authorization: string | undefined }> = [];
  const responseFor = (url: string): object => {
    if (url.includes("googleapis.com")) {
      return {
        items: [{
          id: { videoId: "video-1" },
          snippet: {
            title: "AI agents update",
            description: "Official YouTube evidence.",
            channelTitle: "Official channel",
            publishedAt: "2026-07-24T08:00:00.000Z",
          },
        }],
      };
    }
    if (url.includes("api.x.com")) {
      return { data: [{ id: "post-1", text: "AI agents update", created_at: "2026-07-24T08:00:00.000Z" }] };
    }
    return {
      data: [{
        id: "media-1",
        caption: "AI agents update",
        username: "official-account",
        permalink: "https://www.instagram.com/p/media-1/",
        timestamp: "2026-07-24T08:00:00.000Z",
      }],
    };
  };

  const result = await collectWatchlist({
    repository,
    now,
    credentials: {
      youtube: "AIza-test-key",
      x: "x-bearer-token",
      instagram: JSON.stringify({
        accountID: "17841400000000000",
        accessToken: "ig-access-token",
        graphAPIVersion: "v22.0",
      }),
    },
    fetchImplementation: async (input, init) => {
      requests.push({
        url: String(input),
        authorization: new Headers(init?.headers).get("authorization") ?? undefined,
      });
      return new Response(JSON.stringify(responseFor(String(input))), {
        status: 200,
        headers: { "content-type": "application/json" },
      });
    },
  });

  assert.deepEqual(result.providers.map((provider) => [provider.provider, provider.requests, provider.accepted]), [
    ["youtube", 8, 4],
    ["x", 4, 2],
    ["instagram", 1, 1],
  ]);
  assert.equal(requests.length, 13);
  assert.ok(requests.some((request) => request.url.includes("regionCode=EG") && request.url.includes("relevanceLanguage=ar")));
  assert.ok(requests.some((request) => request.url.includes("regionCode=SA") && request.url.includes("relevanceLanguage=en")));
  assert.ok(requests.some((request) => request.url.includes("api.x.com") && request.authorization === "Bearer x-bearer-token"));
  assert.ok(requests.some((request) =>
    request.url.includes("api.x.com")
      && decodeURIComponent(request.url).includes("lang:ar")
      && decodeURIComponent(request.url).includes("from:ai_agents")));
  assert.ok(requests.some((request) => request.url.includes("graph.facebook.com") && request.authorization === "Bearer ig-access-token"));
  assert.ok(requests.some((request) =>
    request.url.includes("17841400000000000")
      && decodeURIComponent(request.url).includes("business_discovery.username(ai_agents)")));
  assert.equal(repository.opportunities.length, 7);
  assert.equal(repository.opportunities[0]?.items[0]?.url, "https://www.youtube.com/watch?v=video-1");
  assert.equal(repository.opportunities[0]?.items[0]?.publishedAt, "2026-07-24T08:00:00.000Z");
  assert.equal(repository.opportunities[0]?.verification, "Unverified");
  assert.equal(repository.opportunities[0]?.originalSource, null);
  assert.equal(repository.sourceHealth.find((entry) => entry.group === "YouTube")?.state, "Connected");
  assert.equal(repository.sourceHealth.find((entry) => entry.group === "Google Trends")?.state, "Setup required");
});

test("watchlist official-source URLs use the shared RSS parser and retain links and timestamps", async () => {
  const repository = new MemoryRepository();
  repository.watchlist = [{
    id: "40000000-0000-4000-8000-000000000001",
    kind: "Official source",
    value: "https://example.test/watchlist.xml",
    highPriority: false,
  }];
  repository.opportunities = [];
  await collectWatchlist({
    repository,
    now,
    resolveHostname: async () => [{ address: "93.184.216.34", family: 4 }],
    fetchImplementation: async () => new Response(`
      <rss><channel><item>
        <guid>watchlist-release-1</guid>
        <title>Watchlist release</title>
        <description>Official evidence.</description>
        <link>https://example.test/releases/1</link>
        <pubDate>Thu, 24 Jul 2026 08:00:00 GMT</pubDate>
      </item></channel></rss>
    `, { status: 200 }),
  });

  assert.equal(repository.opportunities.length, 1);
  assert.equal(repository.opportunities[0]?.items[0]?.url, "https://example.test/releases/1");
  assert.equal(repository.opportunities[0]?.items[0]?.publishedAt, "2026-07-24T08:00:00.000Z");
  assert.equal(repository.sourceHealth.find((entry) => entry.group === "US & Official")?.state, "Connected");
});

test("successful provider queries with zero matches remain connected live results", async () => {
  const repository = new MemoryRepository();
  repository.watchlist = [{
    id: "40000000-0000-4000-8000-000000000001",
    kind: "Keyword",
    value: "no-current-match",
    highPriority: false,
  }];

  const result = await collectWatchlist({
    repository,
    now,
    credentials: { youtube: "AIza-test-key", x: "x-bearer-token" },
    fetchImplementation: async () => new Response(JSON.stringify({ data: [], items: [] }), { status: 200 }),
  });

  for (const provider of result.providers.filter((entry) => entry.provider !== "instagram")) {
    assert.equal(provider.successful, 1);
    assert.equal(provider.accepted, 0);
    assert.equal(provider.state, "Connected");
  }
  for (const group of ["YouTube", "X"] as const) {
    const health = repository.sourceHealth.find((entry) => entry.group === group);
    assert.equal(health?.state, "Connected");
    assert.equal(health?.dataTruth, "Live");
  }
});


test("a failed watchlist official source does not erase an existing fixed-collector success", async () => {
  const repository = new MemoryRepository();
  repository.watchlist = [{
    id: "40000000-0000-4000-8000-000000000001",
    kind: "Official source",
    value: "https://example.test/watchlist.xml",
    highPriority: false,
  }];
  await repository.upsertSourceHealth({
    group: "US & Official",
    state: "Connected",
    lastActivity: "2026-07-24T08:55:00.000Z",
    evidence: "Fixed official catalog is live.",
    repairAction: "Review",
    dataTruth: "Live",
  });

  await collectWatchlist({
    repository,
    now,
    resolveHostname: async () => [{ address: "93.184.216.34", family: 4 }],
    fetchImplementation: async () => new Response("", { status: 503 }),
  });

  const health = repository.sourceHealth.find((entry) => entry.group === "US & Official");
  assert.equal(health?.state, "Connected");
  assert.equal(health?.evidence, "Fixed official catalog is live.");
});
