import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
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

function retagBatch(
  batch: ResearchBatch,
  clusterKey: string,
  externalID: string,
  topicKey: string,
  publishedAt: string,
): ResearchBatch {
  batch.clusterKey = clusterKey;
  batch.topicKey = topicKey;
  batch.originalSource = { group: "US & Official", externalID };
  batch.sourceItems[0] = {
    ...batch.sourceItems[0]!,
    externalID,
    topicKey,
    publishedAt,
    collectedAt: publishedAt,
    url: `https://example.com/${externalID}`,
  };
  batch.opportunity = { ...batch.opportunity, title: topicKey };
  batch.notification = batch.notification ? { ...batch.notification, title: topicKey, createdAt: publishedAt } : null;
  return batch;
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

test("fresh migration accepts the maximum idempotency key without widening the persisted scope", {
  skip: databaseUrl ? false : "TEST_DATABASE_URL is not configured",
}, async (context) => {
  const pool = createPool(databaseUrl!);
  context.after(() => pool.end());
  const repository = new PostgreSqlRepository(pool);
  const opportunity = await repository.persistResearchBatch(researchBatch("max-idempotency-cluster", "max-idempotency"));
  const app = buildApi({ repository, apiToken });
  context.after(() => app.close());
  const key = "k".repeat(255);
  const headers = { authorization: `Bearer ${apiToken}`, "idempotency-key": key };
  const payload = {
    disposition: "watched",
    changedAt: "2026-07-28T10:00:00.000Z",
    mutationID: "50000000-0000-4000-8000-000000000020",
  };
  const first = await app.inject({
    method: "PATCH",
    url: `/v1/opportunities/${opportunity.id}/disposition`,
    headers,
    payload,
  });
  const retry = await app.inject({
    method: "PATCH",
    url: `/v1/opportunities/${opportunity.id}/disposition`,
    headers,
    payload,
  });

  assert.equal(first.statusCode, 200);
  assert.equal(retry.statusCode, 200);
  assert.equal(retry.json().serverTime, first.json().serverTime);
  const result = await pool.query<{ scope_length: number; key_length: number }>(`
    SELECT length(scope) AS scope_length, length(idempotency_key) AS key_length
    FROM mutation_idempotency
    WHERE idempotency_key = $1
  `, [key]);
  const expectedScopeLength = "opportunity-disposition".length + 1 + opportunity.id.length + 1 + 16;
  assert.equal(result.rows[0]?.scope_length, expectedScopeLength);
  assert.equal(result.rows[0]?.key_length, 255);
  await pool.query("DELETE FROM mutation_idempotency WHERE idempotency_key = $1", [key]);
});

test("an idempotent watchlist delete persists and replays an empty response", {
  skip: databaseUrl ? false : "TEST_DATABASE_URL is not configured",
}, async (context) => {
  const pool = createPool(databaseUrl!);
  context.after(() => pool.end());
  const repository = new PostgreSqlRepository(pool);
  const app = buildApi({ repository, apiToken });
  context.after(() => app.close());
  const entry = await repository.createWatchlist({ kind: "Keyword", value: "delete replay", highPriority: false });
  const headers = { authorization: `Bearer ${apiToken}`, "idempotency-key": "watchlist-delete-replay" };

  const first = await app.inject({ method: "DELETE", url: `/v1/watchlist/${entry.id}`, headers });
  const retry = await app.inject({ method: "DELETE", url: `/v1/watchlist/${entry.id}`, headers });

  assert.equal(first.statusCode, 204);
  assert.equal(retry.statusCode, 204);
  assert.equal((await repository.listWatchlist()).some((candidate) => candidate.id === entry.id), false);
  await pool.query("DELETE FROM mutation_idempotency WHERE idempotency_key = $1", [headers["idempotency-key"]]);
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
  const runID = randomUUID();
  const opportunity = await firstRepository.persistResearchBatch(
    researchBatch(`durable-disposition-${runID}`, `durable-evidence-${runID}`),
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

test("PostgreSQL preferences use server versions and preserve fields from a newer writer", {
  skip: databaseUrl ? false : "TEST_DATABASE_URL is not configured",
}, async (context) => {
  const pool = createPool(databaseUrl!);
  context.after(() => pool.end());
  const repository = new PostgreSqlRepository(pool);
  const initial = await repository.getPreferences();
  const updated = await repository.updatePreferences({
    refreshMinutes: 30,
    quietHours: { enabled: true, start: "22:30", end: "08:15" },
  }, initial.etag);

  assert.equal(updated.outcome, "updated");
  if (updated.outcome !== "updated") return;
  assert.equal(updated.current.refreshMinutes, 30);
  assert.equal(updated.current.quietHours.end, "08:15");

  const stale = await repository.updatePreferences({ notificationsEnabled: true }, initial.etag);
  assert.equal(stale.outcome, "conflict");
  assert.equal(stale.current.refreshMinutes, 30);
  assert.equal(stale.current.notificationsEnabled, initial.notificationsEnabled);
});

test("PostgreSQL read projections paginate with filters and preserve comment truth", {
  skip: databaseUrl ? false : "TEST_DATABASE_URL is not configured",
}, async (context) => {
  const pool = createPool(databaseUrl!);
  context.after(() => pool.end());
  const repository = new PostgreSqlRepository(pool);
  await repository.persistResearchBatch(retagBatch(
    researchBatch("read-api-cluster-a", "read-api-a"),
    "read-api-cluster-a",
    "read-api-a",
    "read-api-topic",
    "2026-07-27T08:00:00.000Z",
  ));
  await repository.persistResearchBatch(retagBatch(
    researchBatch("read-api-cluster-b", "read-api-b"),
    "read-api-cluster-b",
    "read-api-b",
    "read-api-topic",
    "2026-07-28T08:00:00.000Z",
  ));

  const app = buildApi({ repository, apiToken });
  context.after(() => app.close());
  const first = await app.inject({
    method: "GET",
    url: "/v1/opportunities?topic=read-api-topic&limit=1&sort=newest",
    headers: { authorization: `Bearer ${apiToken}` },
  });
  assert.equal(first.statusCode, 200);
  assert.equal(first.json().items.length, 1);
  assert.equal(first.json().items[0].items[0].externalID, "read-api-b");
  assert.ok(first.json().nextCursor);

  const second = await app.inject({
    method: "GET",
    url: `/v1/opportunities?topic=read-api-topic&limit=1&sort=newest&cursor=${encodeURIComponent(first.json().nextCursor)}`,
    headers: { authorization: `Bearer ${apiToken}` },
  });
  assert.equal(second.statusCode, 200);
  assert.equal(second.json().items[0].items[0].externalID, "read-api-a");
  assert.equal(second.json().nextCursor, null);

  const topics = await app.inject({
    method: "GET",
    url: "/v1/topics?search=read-api-topic&limit=10",
    headers: { authorization: `Bearer ${apiToken}` },
  });
  assert.equal(topics.statusCode, 200);
  assert.equal(topics.json().items[0].opportunityCount, 2);
  assert.equal(topics.json().items[0].verificationMix.confirmed, 2);

  const detail = await app.inject({
    method: "GET",
    url: "/v1/topics/read-api-topic",
    headers: { authorization: `Bearer ${apiToken}` },
  });
  assert.equal(detail.statusCode, 200);
  assert.equal(detail.json().opportunities.length, 2);

  const comments = await app.inject({
    method: "GET",
    url: "/v1/comments?limit=10",
    headers: { authorization: `Bearer ${apiToken}` },
  });
  assert.equal(comments.statusCode, 200);
  assert.deepEqual(comments.json().items, []);
  assert.equal(comments.json().availability.dataTruth, "Missing");
});

test("PostgreSQL cursors retain microsecond boundaries for opportunity and notification pages", {
  skip: databaseUrl ? false : "TEST_DATABASE_URL is not configured",
}, async (context) => {
  const pool = createPool(databaseUrl!);
  context.after(() => pool.end());
  const repository = new PostgreSqlRepository(pool);
  const newer = await repository.persistResearchBatch(retagBatch(
    researchBatch("microsecond-cluster-newer", "microsecond-newer"),
    "microsecond-cluster-newer",
    "microsecond-newer",
    "microsecond-boundary",
    "2026-07-28T08:00:00.123456Z",
  ));
  const older = await repository.persistResearchBatch(retagBatch(
    researchBatch("microsecond-cluster-older", "microsecond-older"),
    "microsecond-cluster-older",
    "microsecond-older",
    "microsecond-boundary",
    "2026-07-28T08:00:00.123455Z",
  ));

  await pool.query(`
    UPDATE notifications
    SET id = CASE opportunity_id WHEN $1 THEN $3::uuid ELSE $4::uuid END,
        title = 'microsecond-boundary',
        created_at = CASE opportunity_id WHEN $1 THEN $5::timestamptz ELSE $6::timestamptz END
    WHERE opportunity_id IN ($1, $2)
  `, [newer.id, older.id, "70000000-0000-4000-8000-000000000001", "70000000-0000-4000-8000-000000000002", "2026-07-28T08:00:00.123456Z", "2026-07-28T08:00:00.123455Z"]);

  const app = buildApi({ repository, apiToken });
  context.after(() => app.close());
  const first = await app.inject({
    method: "GET",
    url: "/v1/opportunities?topic=microsecond-boundary&limit=1&sort=newest",
    headers: { authorization: `Bearer ${apiToken}` },
  });
  assert.equal(first.json().items[0].items[0].externalID, "microsecond-newer");
  const opportunityCursor = JSON.parse(Buffer.from(first.json().nextCursor, "base64url").toString("utf8")) as { timestamp: string };
  assert.match(opportunityCursor.timestamp, /\.123456/);
  const second = await app.inject({
    method: "GET",
    url: `/v1/opportunities?topic=microsecond-boundary&limit=1&sort=newest&cursor=${encodeURIComponent(first.json().nextCursor)}`,
    headers: { authorization: `Bearer ${apiToken}` },
  });
  assert.equal(second.json().items[0].items[0].externalID, "microsecond-older");

  const notificationFirst = await app.inject({
    method: "GET",
    url: "/v1/notifications?search=microsecond-boundary&limit=1",
    headers: { authorization: `Bearer ${apiToken}` },
  });
  assert.equal(notificationFirst.json().items[0].opportunityID, newer.id);
  const notificationCursor = JSON.parse(Buffer.from(notificationFirst.json().nextCursor, "base64url").toString("utf8")) as { timestamp: string };
  assert.match(notificationCursor.timestamp, /\.123456/);
  const notificationSecond = await app.inject({
    method: "GET",
    url: `/v1/notifications?search=microsecond-boundary&limit=1&cursor=${encodeURIComponent(notificationFirst.json().nextCursor)}`,
    headers: { authorization: `Bearer ${apiToken}` },
  });
  assert.equal(notificationSecond.json().items[0].opportunityID, older.id);
});

test("topic detail uses an exact query even when fuzzy matches exceed the index cap", {
  skip: databaseUrl ? false : "TEST_DATABASE_URL is not configured",
}, async (context) => {
  const pool = createPool(databaseUrl!);
  context.after(() => pool.end());
  const repository = new PostgreSqlRepository(pool);
  await repository.persistResearchBatch(retagBatch(
    researchBatch("exact-topic-cluster", "exact-topic-evidence"),
    "exact-topic-cluster",
    "exact-topic-evidence",
    "topic",
    "2026-07-01T08:00:00.000Z",
  ));
  for (let index = 0; index <= 200; index += 1) {
    const suffix = String(index).padStart(3, "0");
    await repository.persistResearchBatch(retagBatch(
      researchBatch(`fuzzy-topic-cluster-${suffix}`, `fuzzy-topic-evidence-${suffix}`),
      `fuzzy-topic-cluster-${suffix}`,
      `fuzzy-topic-evidence-${suffix}`,
      `topic-${suffix}`,
      "2026-07-28T08:00:00.000Z",
    ));
  }
  await pool.query(`
    UPDATE opportunities o
    SET updated_at = '2026-07-01T08:00:00Z'
    FROM story_clusters sc
    WHERE sc.id = o.story_cluster_id AND sc.topic_key = 'topic'
  `);
  await pool.query("UPDATE story_clusters SET updated_at = '2026-07-01T08:00:00Z' WHERE topic_key = 'topic'");

  const app = buildApi({ repository, apiToken });
  context.after(() => app.close());
  const response = await app.inject({
    method: "GET",
    url: "/v1/topics/topic",
    headers: { authorization: `Bearer ${apiToken}` },
  });
  assert.equal(response.statusCode, 200);
  assert.equal(response.json().topicKey, "topic");
  assert.equal(response.json().title, "topic");
  assert.equal(response.json().opportunityCount, 1);
});
