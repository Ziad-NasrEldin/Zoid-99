import assert from "node:assert/strict";
import test from "node:test";
import { buildApi } from "../src/api.js";
import { fixtureOpportunity, MemoryRepository } from "./support/memory-repository.js";

const apiToken = "test-api-token-with-more-than-thirty-two-characters";
const authorization = { authorization: `Bearer ${apiToken}` };
const operatorPassword = "correct-horse-battery-staple";

function opportunityVariant(id: string, topicKey: string, group: "YouTube" | "US & Official"): typeof fixtureOpportunity {
  const opportunity = structuredClone(fixtureOpportunity);
  const item = {
    ...opportunity.items[0]!,
    id: `${id.slice(0, 8)}-0000-4000-8000-000000000001`,
    group,
    topicKey,
    country: group === "YouTube" ? "EG" : "US",
    language: group === "YouTube" ? "ar" : "en",
  };
  return {
    ...opportunity,
    id,
    topicKey,
    title: `${topicKey} opportunity`,
    items: [item],
    originalSource: item,
  };
}

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
    requestId: "req-2",
  });
});

test("trusted gateway request IDs match the read error body and response header", async (context) => {
  const app = buildApi({ repository: new MemoryRepository(), apiToken });
  context.after(() => app.close());

  const response = await app.inject({
    method: "GET",
    url: "/v1/opportunities?limit=not-a-number",
    headers: { ...authorization, "x-request-id": "gateway-read-42" },
  });

  assert.equal(response.statusCode, 400);
  assert.equal(response.headers["x-request-id"], "gateway-read-42");
  assert.equal(response.json().requestId, "gateway-read-42");
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

test("operator login creates a revocable session without exposing it to unauthenticated callers", async (context) => {
  const repository = new MemoryRepository();
  const app = buildApi({ repository, apiToken, operatorPassword });
  context.after(() => app.close());

  const directLogin = await app.inject({
    method: "POST",
    url: "/v1/operator/login",
    payload: { password: operatorPassword },
  });
  assert.equal(directLogin.statusCode, 401);

  const rejected = await app.inject({
    method: "POST",
    url: "/v1/operator/login",
    headers: authorization,
    payload: { password: "incorrect-password" },
  });
  assert.equal(rejected.statusCode, 401);
  assert.equal(rejected.json().message, "Invalid operator password");

  const login = await app.inject({
    method: "POST",
    url: "/v1/operator/login",
    headers: authorization,
    payload: { password: operatorPassword },
  });
  assert.equal(login.statusCode, 200);
  const token = login.json().token as string;
  assert.ok(token.length >= 32);

  const session = await app.inject({
    method: "GET",
    url: "/v1/operator/session",
    headers: { ...authorization, "x-zoid-operator-session": token },
  });
  assert.deepEqual(session.json(), { authenticated: true, authRequired: true });

  const logout = await app.inject({
    method: "POST",
    url: "/v1/operator/logout",
    headers: { ...authorization, "x-zoid-operator-session": token },
  });
  assert.deepEqual(logout.json(), { authenticated: false, authRequired: true });

  const expired = await app.inject({
    method: "GET",
    url: "/v1/operator/session",
    headers: { ...authorization, "x-zoid-operator-session": token },
  });
  assert.deepEqual(expired.json(), { authenticated: false, authRequired: true });
});

test("operator login fails closed when the production password is missing", async (context) => {
  const app = buildApi({ repository: new MemoryRepository(), apiToken });
  context.after(() => app.close());
  const response = await app.inject({
    method: "POST",
    url: "/v1/operator/login",
    headers: authorization,
    payload: { password: operatorPassword },
  });
  assert.equal(response.statusCode, 503);
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
    requestId: "req-1",
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

test("read list expansion keeps legacy arrays and adds stable filtered pages", async (context) => {
  const repository = new MemoryRepository();
  repository.opportunities = [
    opportunityVariant("20000000-0000-4000-8000-000000000002", "youtube-one", "YouTube"),
    opportunityVariant("20000000-0000-4000-8000-000000000003", "youtube-two", "YouTube"),
    structuredClone(fixtureOpportunity),
  ];
  const app = buildApi({ repository, apiToken });
  context.after(() => app.close());

  const legacy = await app.inject({
    method: "GET",
    url: "/v1/opportunities?disposition=active",
    headers: authorization,
  });
  assert.equal(legacy.statusCode, 200);
  assert.ok(Array.isArray(legacy.json()));

  const first = await app.inject({
    method: "GET",
    url: "/v1/opportunities?source=YouTube&limit=1&sort=totalScore",
    headers: authorization,
  });
  assert.equal(first.statusCode, 200);
  assert.equal(first.json().items.length, 1);
  assert.equal(first.json().items[0].items[0].group, "YouTube");
  assert.ok(first.json().nextCursor);
  assert.match(first.json().serverTime, /^2026|^20/);

  const second = await app.inject({
    method: "GET",
    url: `/v1/opportunities?source=YouTube&limit=1&sort=totalScore&cursor=${encodeURIComponent(first.json().nextCursor)}`,
    headers: authorization,
  });
  assert.equal(second.statusCode, 200);
  assert.notEqual(second.json().items[0].id, first.json().items[0].id);

  const invalid = await app.inject({
    method: "GET",
    url: "/v1/opportunities?limit=1&cursor=not-a-cursor",
    headers: authorization,
  });
  assert.equal(invalid.statusCode, 400);
  assert.equal(invalid.json().error, "invalid_request");
  assert.ok(invalid.json().requestId);
});

test("notification, topic, and comment read projections are bounded and truthful", async (context) => {
  const repository = new MemoryRepository();
  repository.notifications = [
    ...repository.notifications,
    {
      id: "30000000-0000-4000-8000-000000000002",
      opportunityID: fixtureOpportunity.id,
      title: "Older digest",
      delivery: "Digest",
      createdAt: "2026-07-22T08:10:00.000Z",
      isRead: true,
    },
  ];
  repository.sourceHealth.push({
    group: "Comments",
    state: "Setup required",
    lastActivity: null,
    evidence: "No comments source is connected.",
    repairAction: "Connect a supported comments source.",
    dataTruth: "Missing",
  });
  const app = buildApi({ repository, apiToken });
  context.after(() => app.close());

  const notifications = await app.inject({
    method: "GET",
    url: "/v1/notifications?isRead=false&limit=1",
    headers: authorization,
  });
  assert.equal(notifications.statusCode, 200);
  assert.deepEqual(notifications.json().items.map((item: { isRead: boolean }) => item.isRead), [false]);
  assert.equal(typeof notifications.json().serverTime, "string");

  const topics = await app.inject({ method: "GET", url: "/v1/topics?limit=10", headers: authorization });
  assert.equal(topics.statusCode, 200);
  assert.equal(topics.json().items[0].topicKey, "model-release");
  assert.equal(topics.json().items[0].title, "Official model release");
  assert.equal(topics.json().items[0].verificationMix.confirmed, 1);

  const detail = await app.inject({
    method: "GET",
    url: "/v1/topics/model-release",
    headers: authorization,
  });
  assert.equal(detail.statusCode, 200);
  assert.equal(detail.json().opportunities.length, 1);

  const comments = await app.inject({ method: "GET", url: "/v1/comments?limit=1", headers: authorization });
  assert.equal(comments.statusCode, 200);
  assert.deepEqual(comments.json().items, []);
  assert.equal(comments.json().availability.dataTruth, "Missing");
  assert.match(comments.json().availability.evidence, /comments source/i);
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

test("ingestion rejects malformed nested source items", async (context) => {
  const app = buildApi({ repository: new MemoryRepository(), apiToken });
  context.after(() => app.close());

  const response = await app.inject({
    method: "POST",
    url: "/v1/ingestion",
    headers: authorization,
    payload: {
      sourceHealth: [{
        group: "US & Official",
        state: "Connected",
        lastActivity: "2026-07-24T08:05:00.000Z",
        evidence: "A source was checked.",
        repairAction: "Review",
        dataTruth: "Live",
      }],
      batches: [{
        clusterKey: "malformed-nested-item",
        topicKey: "malformed-nested-item",
        verification: "Confirmed",
        originState: "Identified",
        originalSource: null,
        sourceItems: [{
          group: "US & Official",
          externalID: "malformed-item",
          title: "Malformed item",
          summary: "This item has an invalid publication date.",
          author: "Official publisher",
          url: "https://official.example/releases/malformed",
          publishedAt: "not-an-iso-date",
          collectedAt: "2026-07-24T08:05:00.000Z",
          language: "en",
          country: "US",
          topicKey: "malformed-nested-item",
          isOriginalSource: true,
          credibility: 1,
          engagement: 0,
          verification: "Confirmed",
        }],
        opportunity: {
          title: "Malformed item",
          brief: "This opportunity must not be persisted.",
          score: {
            freshness: 1,
            credibility: 1,
            momentum: 1,
            creatorActivity: 1,
            arabicCoverageGap: 1,
            regionalRelevance: 1,
          },
          regionalExplanation: "No regional evidence.",
          coverageExplanation: "No coverage evidence.",
          disposition: "active",
        },
        notification: null,
      }],
    },
  });

  assert.equal(response.statusCode, 400);
  assert.equal(response.json().error, "invalid_request");
  assert.ok(response.json().details.some((detail: { path: string }) => (
    detail.path === "batches.0.sourceItems.0.publishedAt"
  )));
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

test("web mutation idempotency deduplicates effects and rejects key reuse", async (context) => {
  const repository = new MemoryRepository();
  const app = buildApi({ repository, apiToken });
  context.after(() => app.close());
  const headers = { ...authorization, "idempotency-key": "web-watchlist-create-1" };
  const payload = { kind: "Topic", value: "AI agents", highPriority: true };

  const first = await app.inject({ method: "POST", url: "/v1/watchlist", headers, payload });
  const retry = await app.inject({ method: "POST", url: "/v1/watchlist", headers, payload });
  const reused = await app.inject({
    method: "POST",
    url: "/v1/watchlist",
    headers,
    payload: { ...payload, value: "Different topic" },
  });

  assert.equal(first.statusCode, 201);
  assert.equal(retry.statusCode, 201);
  assert.equal(retry.json().id, first.json().id);
  assert.equal(repository.watchlist.length, 1);
  assert.equal(reused.statusCode, 409);
  assert.equal(reused.json().error, "conflict");
});

test("a maximum-length idempotency key is persisted separately from its scope", async (context) => {
  const repository = new MemoryRepository();
  const app = buildApi({ repository, apiToken });
  context.after(() => app.close());
  const opportunityID = fixtureOpportunity.id;
  const headers = { ...authorization, "idempotency-key": "k".repeat(255) };
  const payload = {
    disposition: "watched",
    changedAt: "2026-07-23T10:00:00.000Z",
    mutationID: "50000000-0000-4000-8000-000000000004",
  };

  const first = await app.inject({
    method: "PATCH",
    url: `/v1/opportunities/${opportunityID}/disposition`,
    headers,
    payload,
  });
  const retry = await app.inject({
    method: "PATCH",
    url: `/v1/opportunities/${opportunityID}/disposition`,
    headers,
    payload,
  });

  assert.equal(first.statusCode, 200);
  assert.equal(retry.statusCode, 200);
  assert.equal(retry.json().disposition, "watched");
  assert.equal(retry.json().serverTime, first.json().serverTime);
});

test("preferences use ETag and If-Match without losing newer server state", async (context) => {
  const repository = new MemoryRepository();
  const app = buildApi({ repository, apiToken });
  context.after(() => app.close());

  const initial = await app.inject({ method: "GET", url: "/v1/preferences", headers: authorization });
  const etag = initial.headers.etag!;
  assert.equal(initial.statusCode, 200);
  assert.equal(initial.json().quietHours.start, "22:00");

  const updated = await app.inject({
    method: "PATCH",
    url: "/v1/preferences",
    headers: { ...authorization, "if-match": etag, "idempotency-key": "preferences-update-1" },
    payload: {
      refreshMinutes: 30,
      quietHours: { enabled: true, start: "22:30", end: "08:15" },
    },
  });
  assert.equal(updated.statusCode, 200);
  assert.ok(updated.headers.etag);
  assert.equal(updated.json().refreshMinutes, 30);
  assert.equal(updated.json().quietHours.end, "08:15");

  const stale = await app.inject({
    method: "PATCH",
    url: "/v1/preferences",
    headers: { ...authorization, "if-match": etag, "idempotency-key": "preferences-update-2" },
    payload: { notificationsEnabled: true },
  });
  assert.equal(stale.statusCode, 409);
  assert.equal(stale.json().error, "conflict");
  assert.equal(stale.json().preferences.refreshMinutes, 30);
  assert.equal((await repository.getPreferences()).notificationsEnabled, false);
});

test("mutation rate limiting is scoped to mutation routes", async (context) => {
  const repository = new MemoryRepository();
  const app = buildApi({
    repository,
    apiToken,
    rateLimits: { mutations: { limit: 1, windowMs: 60_000 } },
  });
  context.after(() => app.close());

  const first = await app.inject({
    method: "POST",
    url: "/v1/watchlist",
    headers: authorization,
    payload: { kind: "Topic", value: "one", highPriority: false },
  });
  const second = await app.inject({
    method: "POST",
    url: "/v1/watchlist",
    headers: authorization,
    payload: { kind: "Topic", value: "two", highPriority: false },
  });
  const read = await app.inject({ method: "GET", url: "/v1/watchlist", headers: authorization });

  assert.equal(first.statusCode, 201);
  assert.equal(second.statusCode, 429);
  assert.equal(second.json().error, "rate_limited");
  assert.equal(read.statusCode, 200);
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
    requestId: "req-1",
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
