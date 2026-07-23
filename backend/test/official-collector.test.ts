import assert from "node:assert/strict";
import test from "node:test";
import type { ResearchBatch } from "../src/domain.js";
import { collectOfficialSources } from "../src/official-collector.js";
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
    /No official-source items/,
  );
  const health = repository.sourceHealth.find((entry) => entry.group === "US & Official");
  assert.equal(health?.state, "Unavailable");
  assert.equal(health?.dataTruth, "Unavailable");
  assert.match(health?.evidence ?? "", /No official-source items/);
});
