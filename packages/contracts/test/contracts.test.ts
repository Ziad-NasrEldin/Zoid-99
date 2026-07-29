import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import {
  bootstrapSchema,
  connectionSchema,
  commentsResponseSchema,
  notificationReadQuerySchema,
  notificationSchema,
  opportunityReadQuerySchema,
  opportunitySchema,
  mutationEnvelopeSchema,
  paginatedResponseSchema,
  paginationQuerySchema,
  preferencesPatchSchema,
  preferencesSchema,
  sourceHealthIngestionSchema,
  sourceHealthSchema,
  structuredErrorSchema,
  topicReadQuerySchema,
  topicSchema,
  watchlistSchema,
} from "../src/index.js";

function fixture(name: string): unknown {
  return JSON.parse(readFileSync(new URL(`../fixtures/${name}.json`, import.meta.url), "utf8"));
}

test("cross-language fixtures cover the shared response models", () => {
  const bootstrap = bootstrapSchema.parse(fixture("bootstrap"));
  assert.equal(bootstrap.opportunities[0]?.verification, "Confirmed");
  opportunitySchema.parse(fixture("opportunity"));
  watchlistSchema.array().parse(fixture("watchlist"));
  notificationSchema.parse(fixture("notification"));
  sourceHealthSchema.parse(fixture("source-health"));
  connectionSchema.parse(fixture("connection"));
});

test("pagination and structured errors are bounded and stable", () => {
  assert.equal(
    sourceHealthIngestionSchema.parse({
      ...fixture("source-health") as Record<string, unknown>,
      lastActivity: undefined,
    }).lastActivity,
    null,
  );
  assert.equal(
    sourceHealthSchema.parse({
      ...fixture("source-health") as Record<string, unknown>,
      state: "Unsupported",
    }).state,
    "Unsupported",
  );
  assert.deepEqual(paginationQuerySchema.parse({ cursor: "next", limit: "25" }), {
    cursor: "next",
    limit: 25,
  });
  assert.equal(
    paginatedResponseSchema(opportunitySchema).parse({
      items: [],
      nextCursor: null,
      serverTime: "2026-07-28T13:00:00.000Z",
    }).nextCursor,
    null,
  );
  assert.equal(structuredErrorSchema.parse({
    error: "not_found",
    message: "Opportunity not found",
    requestId: "request-99",
  }).error, "not_found");
  assert.throws(() => paginationQuerySchema.parse({ limit: 201 }));
  assert.deepEqual(opportunityReadQuerySchema.parse({ source: "YouTube", limit: "25", freshness: "lastWeek" }), {
    source: "YouTube",
    limit: 25,
    freshness: "lastWeek",
  });
  assert.deepEqual(notificationReadQuerySchema.parse({ isRead: "false", limit: "10" }), {
    isRead: false,
    limit: 10,
  });
  assert.deepEqual(topicReadQuerySchema.parse({ search: "model", limit: "10" }), {
    search: "model",
    limit: 10,
  });
  topicSchema.parse({
    topicKey: "model-release",
    title: "Model release",
    opportunityCount: 1,
    freshness: "older",
    verificationMix: { confirmed: 1, disputed: 0, unverified: 0 },
    latestPublishedAt: "2026-07-28T13:00:00.000Z",
    latestActivityAt: "2026-07-28T13:00:00.000Z",
  });
  commentsResponseSchema.parse({
    items: [],
    nextCursor: null,
    serverTime: "2026-07-28T13:00:00.000Z",
    availability: {
      group: "Comments",
      state: "Setup required",
      dataTruth: "Missing",
      evidence: "No comments source is connected.",
      repairAction: "Connect a supported comments source.",
    },
  });
  assert.throws(() => structuredErrorSchema.parse({ error: "sql_error", message: "unsafe" }));
});

test("mutation and preference contracts validate bounded web state", () => {
  mutationEnvelopeSchema.parse({
    mutationID: "50000000-0000-4000-8000-000000000099",
    serverTime: "2026-07-28T13:00:00.000Z",
  });
  const preferences = preferencesSchema.parse({
    refreshMinutes: 15,
    notificationsEnabled: false,
    digestHour: 18,
    quietHours: { enabled: true, start: "22:30", end: "08:00" },
    locale: "ar-EG",
    timeZone: "Africa/Cairo",
    updatedAt: "2026-07-28T13:00:00.000Z",
  });
  assert.equal(preferences.quietHours.start, "22:30");
  assert.equal(preferencesPatchSchema.parse({ refreshMinutes: 30 }).refreshMinutes, 30);
  assert.throws(() => preferencesPatchSchema.parse({ refreshMinutes: 4 }));
  assert.throws(() => preferencesPatchSchema.parse({}));
});
