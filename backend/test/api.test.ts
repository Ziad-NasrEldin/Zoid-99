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
  assert.deepEqual(health.json(), { status: "ok" });

  const protectedResponse = await app.inject({ method: "GET", url: "/v1/bootstrap" });
  assert.equal(protectedResponse.statusCode, 401);
  assert.deepEqual(protectedResponse.json(), {
    error: "unauthorized",
    message: "A valid bearer token is required",
  });
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

test("a disposition update is persisted through the authenticated public API", async (context) => {
  const repository = new MemoryRepository();
  const app = buildApi({ repository, apiToken });
  context.after(() => app.close());

  const response = await app.inject({
    method: "PATCH",
    url: `/v1/opportunities/${fixtureOpportunity.id}/disposition`,
    headers: authorization,
    payload: { disposition: "dismissed" },
  });
  assert.equal(response.statusCode, 200);
  assert.equal(response.json().disposition, "dismissed");
  assert.equal(repository.opportunities[0]?.disposition, "dismissed");
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
    payload: { disposition: "published" },
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
