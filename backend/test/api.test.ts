import assert from "node:assert/strict";
import test from "node:test";
import { buildApi } from "../src/api.js";
import { fixtureOpportunity, MemoryRepository } from "./support/memory-repository.js";

const apiToken = "test-api-token-with-more-than-thirty-two-characters";
const authorization = { authorization: `Bearer ${apiToken}` };

test("health is public but research data is protected", async (context) => {
  const app = buildApi({ repository: new MemoryRepository(), apiToken });
  context.after(() => app.close());

  const health = await app.inject({ method: "GET", url: "/health" });
  assert.equal(health.statusCode, 200);
  assert.deepEqual(health.json(), {
    status: "ok",
    service: "zoid99-backend",
    version: "development",
  });

  const protectedResponse = await app.inject({ method: "GET", url: "/v1/bootstrap" });
  assert.equal(protectedResponse.statusCode, 401);
  assert.deepEqual(protectedResponse.json(), {
    error: "unauthorized",
    message: "A valid bearer token is required",
  });
});

test("a staged previous machine credential remains valid during rotation", async (context) => {
  const previousKey = "previous-machine-credential-with-more-than-32-characters";
  const app = buildApi({
    repository: new MemoryRepository(),
    apiToken,
    authenticationKeys: [apiToken, previousKey],
  });
  context.after(() => app.close());

  const response = await app.inject({
    method: "GET",
    url: "/v1/bootstrap",
    headers: { authorization: `Bearer ${previousKey}` },
  });
  assert.equal(response.statusCode, 200);
});

test("readiness reports database failure without leaking internal details", async (context) => {
  const repository = new MemoryRepository();
  repository.available = false;
  const app = buildApi({ repository, apiToken });
  context.after(() => app.close());

  const response = await app.inject({ method: "GET", url: "/ready" });
  assert.equal(response.statusCode, 503);
  assert.deepEqual(response.json(), {
    error: "service_unavailable",
    message: "Database is unavailable",
  });
});

test("health endpoints expose stable machine-readable service metadata", async (context) => {
  const app = buildApi({
    repository: new MemoryRepository(),
    apiToken,
    serviceVersion: "test-sha",
  });
  context.after(() => app.close());

  const live = await app.inject({ method: "GET", url: "/health" });
  assert.deepEqual(live.json(), { status: "ok", service: "zoid99-backend", version: "test-sha" });

  const ready = await app.inject({ method: "GET", url: "/ready" });
  assert.deepEqual(ready.json(), { status: "ready", service: "zoid99-backend", version: "test-sha" });
});

test("bootstrap preserves the existing macOS model contract", async (context) => {
  const app = buildApi({ repository: new MemoryRepository(), apiToken });
  context.after(() => app.close());

  const response = await app.inject({ method: "GET", url: "/v1/bootstrap", headers: authorization });
  assert.equal(response.statusCode, 200);
  const body = response.json();
  assert.equal(body.opportunities[0].originalSource.url, "https://example.com/release");
  assert.equal(body.opportunities[0].items[0].publishedAt, "2026-07-23T08:00:00.000Z");
  assert.equal(body.opportunities[0].verification, "Confirmed");
  assert.equal(body.opportunities[0].isHighPriority, true);
  assert.equal(body.sourceHealth[0].state, "Setup required");
  assert.equal("encryptedValue" in body, false);
});

test("authenticated ingestion persists one official-feed opportunity and supports conditional refresh", async (context) => {
  const repository = new MemoryRepository();
  repository.opportunities = [];
  repository.notifications = [];
  const app = buildApi({ repository, apiToken });
  context.after(() => app.close());

  const sourceItem = {
    group: "US & Official",
    externalID: "official-feed-entry-1",
    title: "Official feed release",
    summary: "Published by the official source.",
    author: "Official source",
    url: "https://example.com/official-release",
    publishedAt: "2026-07-24T08:00:00.000Z",
    collectedAt: "2026-07-24T08:05:00.000Z",
    language: "en",
    country: "US",
    topicKey: "official-feed-entry-1",
    isOriginalSource: true,
    credibility: 1,
    engagement: 0,
    verification: "Confirmed",
  };
  const ingestion = await app.inject({
    method: "POST",
    url: "/v1/ingestion",
    headers: authorization,
    payload: {
      sourceHealth: [{
        group: "US & Official",
        state: "Connected",
        lastActivity: sourceItem.collectedAt,
        evidence: "1 live official-feed item accepted.",
        repairAction: "Review",
        dataTruth: "Live",
      }],
      batches: [{
        clusterKey: sourceItem.topicKey,
        topicKey: sourceItem.topicKey,
        verification: "Confirmed",
        originState: "Identified",
        originalSource: { group: sourceItem.group, externalID: sourceItem.externalID },
        sourceItems: [sourceItem],
        opportunity: {
          title: sourceItem.title,
          brief: sourceItem.summary,
          score: {
            freshness: 20, credibility: 20, momentum: 4,
            creatorActivity: 0, arabicCoverageGap: 15, regionalRelevance: 7,
          },
          regionalExplanation: "Regional demand evidence is not yet available.",
          coverageExplanation: "No Arabic-language coverage appears in the evidence.",
          disposition: "active",
        },
        notification: {
          title: sourceItem.title,
          delivery: "Digest",
          createdAt: sourceItem.collectedAt,
          isRead: false,
        },
      }],
    },
  });
  assert.equal(ingestion.statusCode, 202);
  assert.equal(ingestion.json().acceptedBatches, 1);

  const bootstrap = await app.inject({ method: "GET", url: "/v1/bootstrap", headers: authorization });
  assert.equal(bootstrap.statusCode, 200);
  assert.equal(bootstrap.json().opportunities[0].items[0].url, sourceItem.url);
  assert.equal(
    bootstrap.json().sourceHealth.find((health: { group: string }) => health.group === "US & Official").dataTruth,
    "Live",
  );
  assert.equal(bootstrap.json().notifications[0].delivery, "Digest");

  const unchanged = await app.inject({
    method: "GET",
    url: "/v1/bootstrap",
    headers: { ...authorization, "if-none-match": bootstrap.headers.etag! },
  });
  assert.equal(unchanged.statusCode, 304);
  assert.equal(unchanged.body, "");
});

test("a disposition update is persisted through the authenticated public API", async (context) => {
  const repository = new MemoryRepository();
  const app = buildApi({ repository, apiToken });
  context.after(() => app.close());

  const response = await app.inject({
    method: "PATCH",
    url: `/v1/opportunities/${fixtureOpportunity.id}/disposition`,
    headers: authorization,
    payload: {
      disposition: "dismissed",
      changedAt: "2026-07-23T09:00:00.000Z",
      mutationID: "50000000-0000-4000-8000-000000000001",
    },
  });
  assert.equal(response.statusCode, 200);
  assert.equal(response.json().disposition, "dismissed");
  assert.equal(response.json().outcome, "applied");
  assert.equal(repository.opportunities[0]?.disposition, "dismissed");
});

test("disposition retries are idempotent and stale offline writes return canonical state", async (context) => {
  const repository = new MemoryRepository();
  const app = buildApi({ repository, apiToken });
  context.after(() => app.close());
  const url = `/v1/opportunities/${fixtureOpportunity.id}/disposition`;
  const latest = {
    disposition: "watched",
    changedAt: "2026-07-23T10:00:00.000Z",
    mutationID: "50000000-0000-4000-8000-000000000002",
  };

  const applied = await app.inject({ method: "PATCH", url, headers: authorization, payload: latest });
  const retried = await app.inject({ method: "PATCH", url, headers: authorization, payload: latest });
  const stale = await app.inject({
    method: "PATCH",
    url,
    headers: authorization,
    payload: {
      disposition: "dismissed",
      changedAt: "2026-07-23T09:30:00.000Z",
      mutationID: "50000000-0000-4000-8000-000000000003",
    },
  });

  assert.equal(applied.json().outcome, "applied");
  assert.equal(retried.json().outcome, "idempotent");
  assert.equal(stale.json().outcome, "superseded");
  assert.equal(stale.json().disposition, "watched");
});

test("invalid identifiers and unsupported states return stable client errors", async (context) => {
  const app = buildApi({ repository: new MemoryRepository(), apiToken });
  context.after(() => app.close());

  const badIdentifier = await app.inject({
    method: "GET",
    url: "/v1/opportunities/not-a-uuid",
    headers: authorization,
  });
  assert.equal(badIdentifier.statusCode, 400);
  assert.equal(badIdentifier.json().error, "invalid_request");

  const badDisposition = await app.inject({
    method: "PATCH",
    url: `/v1/opportunities/${fixtureOpportunity.id}/disposition`,
    headers: authorization,
    payload: {
      disposition: "published",
      changedAt: "2026-07-23T09:00:00.000Z",
      mutationID: "50000000-0000-4000-8000-000000000004",
    },
  });
  assert.equal(badDisposition.statusCode, 400);
  assert.equal(badDisposition.json().error, "invalid_request");
});

test("watchlist creation trims input and rejects unknown fields", async (context) => {
  const app = buildApi({ repository: new MemoryRepository(), apiToken });
  context.after(() => app.close());

  const response = await app.inject({
    method: "POST",
    url: "/v1/watchlist",
    headers: authorization,
    payload: { kind: "Topic", value: "  AI agents  ", highPriority: true },
  });
  assert.equal(response.statusCode, 201);
  assert.equal(response.json().value, "AI agents");

  const rejected = await app.inject({
    method: "POST",
    url: "/v1/watchlist",
    headers: authorization,
    payload: { kind: "Topic", value: "AI agents", highPriority: true, secret: "leak" },
  });
  assert.equal(rejected.statusCode, 400);
});

test("a duplicate watchlist value returns a stable conflict", async (context) => {
  const repository = new MemoryRepository();
  repository.createWatchlist = async () => {
    const error = new Error("duplicate") as Error & { code: string };
    error.code = "23505";
    throw error;
  };
  const app = buildApi({ repository, apiToken });
  context.after(() => app.close());

  const response = await app.inject({
    method: "POST",
    url: "/v1/watchlist",
    headers: authorization,
    payload: { kind: "Topic", value: "AI agents", highPriority: true },
  });
  assert.equal(response.statusCode, 409);
  assert.deepEqual(response.json(), {
    error: "conflict",
    message: "The record already exists",
  });
});

test("watchlists support company edits and atomic private-user replacement", async (context) => {
  const repository = new MemoryRepository();
  const app = buildApi({ repository, apiToken });
  context.after(() => app.close());
  const id = "40000000-0000-4000-8000-000000000099";

  const replaced = await app.inject({
    method: "PUT",
    url: "/v1/watchlist",
    headers: authorization,
    payload: {
      entries: [{ id, kind: "Company", value: "OpenAI", highPriority: true }],
    },
  });
  assert.equal(replaced.statusCode, 200);
  assert.equal(repository.watchlist[0]?.kind, "Company");

  const edited = await app.inject({
    method: "PATCH",
    url: `/v1/watchlist/${id}`,
    headers: authorization,
    payload: { kind: "Company", value: "Anthropic", highPriority: false },
  });
  assert.equal(edited.statusCode, 200);
  assert.equal(edited.json().value, "Anthropic");
  assert.equal(repository.watchlist[0]?.highPriority, false);
});

test("official-source watchlists require complete HTTPS links", async (context) => {
  const app = buildApi({ repository: new MemoryRepository(), apiToken });
  context.after(() => app.close());

  const response = await app.inject({
    method: "POST",
    url: "/v1/watchlist",
    headers: authorization,
    payload: {
      kind: "Official source",
      value: "example.com/feed",
      highPriority: false,
    },
  });
  assert.equal(response.statusCode, 400);
  assert.equal(response.json().error, "invalid_request");
});
