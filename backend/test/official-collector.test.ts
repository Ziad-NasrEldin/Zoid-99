import assert from "node:assert/strict";
import test from "node:test";
import type { ResearchBatch } from "../src/domain.js";
import { collectOfficialSources, officialSourceCatalog } from "../src/official-collector.js";
import { fixtureOpportunity, MemoryRepository } from "./support/memory-repository.js";

test("the server collector persists official RSS research without the macOS app", async () => {
  const repository = new MemoryRepository();
  repository.opportunities = [];
  const batches: ResearchBatch[] = [];
  repository.persistResearchBatch = async (batch) => {
    batches.push(batch);
    return { ...fixtureOpportunity, title: batch.opportunity.title };
  };
  const response = new Response(`
    <rss><channel><item>
      <guid>release-1</guid>
      <title>Official model release</title>
      <description>Verified release notes.</description>
      <link>https://example.test/releases/1</link>
      <pubDate>Thu, 24 Jul 2026 08:00:00 GMT</pubDate>
    </item></channel></rss>
  `, { status: 200, headers: { "content-type": "application/rss+xml" } });

  await collectOfficialSources({
    repository,
    now: () => new Date("2026-07-24T09:00:00.000Z"),
    catalog: [{
      id: "test-official",
      name: "Test Official",
      kind: "rss",
      endpoint: "https://example.test/feed.xml",
      homepage: "https://example.test/",
    }],
    fetchImplementation: async () => response,
  });

  assert.equal(batches.length, 1);
  assert.equal(batches[0]?.opportunity.title, "Official model release");
  assert.equal(batches[0]?.sourceItems[0]?.url, "https://example.test/releases/1");
  assert.equal(batches[0]?.sourceItems[0]?.publishedAt, "2026-07-24T08:00:00.000Z");
  assert.equal(batches[0]?.sourceItems[0]?.collectedAt, "2026-07-24T09:00:00.000Z");
  assert.equal(batches[0]?.sourceItems[0]?.country, "Global");
  const health = repository.sourceHealth.find((entry) => entry.group === "US & Official");
  assert.equal(health?.state, "Connected");
  assert.equal(health?.lastActivity, "2026-07-24T09:00:00.000Z");
  assert.equal(health?.dataTruth, "Live");
});

test("the server collector records truthful health and fails the cycle when every source is unavailable", async () => {
  const repository = new MemoryRepository();
  await assert.rejects(
    collectOfficialSources({
      repository,
      catalog: [{
        id: "test-official",
        name: "Test Official",
        kind: "rss",
        endpoint: "https://example.test/feed.xml",
        homepage: "https://example.test/",
      }],
      fetchImplementation: async () => new Response("", { status: 503 }),
    }),
    /No official sources responded/,
  );
  const health = repository.sourceHealth.find((entry) => entry.group === "US & Official");
  assert.equal(health?.state, "Unavailable");
  assert.equal(health?.dataTruth, "Unavailable");
  assert.match(health?.evidence ?? "", /No official-source items/);
});

test("a healthy official feed with zero records stays connected and does not fail the cycle", async () => {
  const repository = new MemoryRepository();
  const result = await collectOfficialSources({
    repository,
    now: () => new Date("2026-07-24T09:00:00.000Z"),
    catalog: [{
      id: "empty-official",
      name: "Empty Official",
      kind: "rss",
      endpoint: "https://example.test/feed.xml",
      homepage: "https://example.test/",
    }],
    fetchImplementation: async () => new Response("<rss><channel></channel></rss>", { status: 200 }),
  });

  assert.equal(result.successful, 1);
  assert.equal(result.accepted, 0);
  const health = repository.sourceHealth.find((entry) => entry.group === "US & Official");
  assert.equal(health?.state, "Connected");
  assert.equal(health?.dataTruth, "Live");
  assert.match(health?.evidence ?? "", /0 items collected/);
});

test("the server collector preserves source text paragraphs and release-note bullets", async () => {
  const repository = new MemoryRepository();
  repository.opportunities = [];
  const batches: ResearchBatch[] = [];
  repository.persistResearchBatch = async (batch) => {
    batches.push(batch);
    return { ...fixtureOpportunity, title: batch.opportunity.title };
  };
  const response = new Response(JSON.stringify([{
    id: 92001,
    tag_name: "v2.1.219",
    name: "v2.1.219",
    body: "## What's changed\n\n- Added readable source formatting.\n- Fixed collapsed release notes.",
    html_url: "https://github.com/example/runtime/releases/tag/v2.1.219",
    published_at: "2026-07-24T18:14:00.000Z",
    author: { login: "example-runtime" },
    draft: false,
  }]), { status: 200, headers: { "content-type": "application/json" } });

  await collectOfficialSources({
    repository,
    now: () => new Date("2026-07-24T19:00:00.000Z"),
    catalog: [{
      id: "test-github",
      name: "Test GitHub",
      kind: "github",
      endpoint: "https://api.github.com/repos/example/runtime/releases",
      homepage: "https://github.com/example/runtime",
    }],
    fetchImplementation: async () => response,
  });

  assert.equal(
    batches[0]?.opportunity.brief,
    "## What's changed\n\n- Added readable source formatting.\n- Fixed collapsed release notes.",
  );
  assert.equal(batches[0]?.sourceItems[0]?.summary, batches[0]?.opportunity.brief);
});

test("the default catalog includes the credential-free official AI sources", () => {
  assert.deepEqual(
    officialSourceCatalog.map((source) => source.id),
    [
      "openai-news",
      "huggingface-transformers-releases",
      "arxiv-cs-ai",
      "google-ai-news",
      "google-gemini-cli-releases",
      "anthropic-claude-code-releases",
    ],
  );
  assert.ok(officialSourceCatalog.every((source) => source.endpoint.startsWith("https://")));
});
