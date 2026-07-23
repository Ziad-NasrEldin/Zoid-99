import assert from "node:assert/strict";
import test from "node:test";
import { buildApi } from "../src/api.js";
import type { ResearchBatch } from "../src/domain.js";
import { createPool, PostgreSqlRepository } from "../src/postgres.js";

const databaseUrl = process.env.TEST_DATABASE_URL;
const apiToken = "integration-token-with-more-than-thirty-two-characters";

function researchBatch(clusterKey: string, externalID: string): ResearchBatch {
  const publishedAt = "2026-07-23T08:00:00.000Z";
  return {
    clusterKey,
    topicKey: "model-releases",
    verification: "Confirmed",
    originState: "Identified",
    originalSource: { group: "US & Official", externalID },
    sourceItems: [{
      group: "US & Official",
      externalID,
      title: "Official release",
      summary: "Original evidence.",
      author: "Official source",
      url: `https://example.com/${externalID}`,
      publishedAt,
      collectedAt: "2026-07-23T08:05:00.000Z",
      language: "en",
      country: "US",
      topicKey: "model-releases",
      isOriginalSource: true,
      credibility: 1,
      engagement: 100,
      verification: "Confirmed",
    }],
    opportunity: {
      title: "Official release",
      brief: "Original evidence.",
      score: {
        freshness: 20,
        credibility: 20,
        momentum: 15,
        creatorActivity: 10,
        arabicCoverageGap: 15,
        regionalRelevance: 10,
      },
      regionalExplanation: "Relevant to Egypt and Gulf audiences.",
      coverageExplanation: "No Arabic coverage found.",
      disposition: "active",
    },
    notification: {
      title: "Official release",
      delivery: "Immediate",
      createdAt: "2026-07-23T08:10:00.000Z",
      isRead: false,
    },
  };
}

test("transactional PostgreSQL persistence returns a complete Swift-compatible opportunity", {
  skip: databaseUrl ? false : "TEST_DATABASE_URL is not configured",
}, async (context) => {
  const pool = createPool(databaseUrl!);
  context.after(() => pool.end());
  const repository = new PostgreSqlRepository(pool);
  const first = await repository.persistResearchBatch(researchBatch("release-2026-07-23", "official-1"));

  const app = buildApi({ repository, apiToken });
  context.after(() => app.close());
  const response = await app.inject({
    method: "GET",
    url: `/v1/opportunities/${first.id}`,
    headers: { authorization: `Bearer ${apiToken}` },
  });

  assert.equal(response.statusCode, 200);
  assert.equal(response.json().originalSource.externalID, "official-1");
  assert.equal(response.json().originalSource.url, "https://example.com/official-1");
  assert.equal(response.json().earliestPublishedAt, "2026-07-23T08:00:00.000Z");
  assert.equal(response.json().items.length, 1);
  assert.equal(response.json().isHighPriority, true);
});

test("the same topic can contain separate developments without crossing evidence", {
  skip: databaseUrl ? false : "TEST_DATABASE_URL is not configured",
}, async (context) => {
  const pool = createPool(databaseUrl!);
  context.after(() => pool.end());
  const repository = new PostgreSqlRepository(pool);
  await repository.persistResearchBatch(researchBatch("release-a", "official-a"));
  await repository.persistResearchBatch(researchBatch("release-b", "official-b"));

  const opportunities = await repository.listOpportunities();
  const matching = opportunities.filter((opportunity) => opportunity.topicKey === "model-releases");
  assert.equal(matching.length >= 2, true);
  assert.deepEqual(
    matching.filter((opportunity) => ["official-a", "official-b"].includes(opportunity.items[0]?.externalID ?? ""))
      .map((opportunity) => opportunity.items.map((item) => item.externalID)),
    [["official-a"], ["official-b"]],
  );
});

test("a source-less research batch is rejected before any opportunity is written", {
  skip: databaseUrl ? false : "TEST_DATABASE_URL is not configured",
}, async (context) => {
  const pool = createPool(databaseUrl!);
  context.after(() => pool.end());
  const repository = new PostgreSqlRepository(pool);
  const before = await repository.listOpportunities();
  const invalid = researchBatch("invalid-empty-cluster", "missing");
  invalid.sourceItems = [];

  await assert.rejects(() => repository.persistResearchBatch(invalid), /at least one source item/);
  assert.equal((await repository.listOpportunities()).length, before.length);
});

test("one normalized source item cannot cross story-cluster boundaries", {
  skip: databaseUrl ? false : "TEST_DATABASE_URL is not configured",
}, async (context) => {
  const pool = createPool(databaseUrl!);
  context.after(() => pool.end());
  const repository = new PostgreSqlRepository(pool);
  const original = await repository.persistResearchBatch(researchBatch("isolated-cluster-a", "shared-evidence"));

  await assert.rejects(
    () => repository.persistResearchBatch(researchBatch("isolated-cluster-b", "shared-evidence")),
    (error: unknown) => typeof error === "object" && error !== null && "code" in error && error.code === "23505",
  );
  const unchanged = await repository.getOpportunity(original.id);
  assert.deepEqual(unchanged?.items.map((item) => item.externalID), ["shared-evidence"]);
});

test("research refreshes preserve user disposition and notification read state", {
  skip: databaseUrl ? false : "TEST_DATABASE_URL is not configured",
}, async (context) => {
  const pool = createPool(databaseUrl!);
  context.after(() => pool.end());
  const repository = new PostgreSqlRepository(pool);
  const batch = researchBatch("preserved-user-state", "preserved-evidence");
  const first = await repository.persistResearchBatch(batch);
  await repository.updateOpportunityDisposition(first.id, {
    disposition: "muted",
    changedAt: "2026-07-25T09:00:00.000Z",
    mutationID: "50000000-0000-4000-8000-000000000010",
  });
  const notification = (await repository.listNotifications())
    .find((candidate) => candidate.opportunityID === first.id)!;
  await repository.markNotificationRead(notification.id, true);

  batch.opportunity.disposition = "active";
  batch.notification!.isRead = false;
  await repository.persistResearchBatch(batch);

  assert.equal((await repository.getOpportunity(first.id))?.disposition, "muted");
  assert.equal((await repository.listNotifications())
    .find((candidate) => candidate.opportunityID === first.id)?.isRead, true);
});

test("PostgreSQL disposition writes survive repository restart and reject stale retries", {
  skip: databaseUrl ? false : "TEST_DATABASE_URL is not configured",
}, async (context) => {
  const pool = createPool(databaseUrl!);
  context.after(() => pool.end());
  const firstRepository = new PostgreSqlRepository(pool);
  const opportunity = await firstRepository.persistResearchBatch(
    researchBatch("durable-disposition", "durable-evidence"),
  );
  const latest = {
    disposition: "dismissed" as const,
    changedAt: "2026-07-25T11:00:00.000Z",
    mutationID: "50000000-0000-4000-8000-000000000011",
  };

  assert.equal((await firstRepository.updateOpportunityDisposition(opportunity.id, latest))?.outcome, "applied");
  assert.equal((await firstRepository.updateOpportunityDisposition(opportunity.id, latest))?.outcome, "idempotent");
  const restartedRepository = new PostgreSqlRepository(pool);
  assert.equal((await restartedRepository.getOpportunity(opportunity.id))?.disposition, "dismissed");
  assert.equal((await restartedRepository.updateOpportunityDisposition(opportunity.id, {
    disposition: "saved",
    changedAt: "2026-07-25T10:59:00.000Z",
    mutationID: "50000000-0000-4000-8000-000000000012",
  }))?.outcome, "superseded");
  assert.equal((await restartedRepository.getOpportunity(opportunity.id))?.disposition, "dismissed");
});
