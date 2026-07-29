import Fastify, { type FastifyInstance, type FastifyReply } from "fastify";
import { createHash, randomBytes } from "node:crypto";
import { z } from "zod";
import {
  dispositionMutationSchema,
  ingestionSchema,
  preferencesPatchSchema,
  notificationReadSchema,
  notificationReadQuerySchema,
  opportunityReadQuerySchema,
  serverProviderSchema,
  topicReadQuerySchema,
  paginationQuerySchema,
  watchlistInputSchema,
  watchlistReplacementSchema,
} from "@zoid99/contracts";
import type { OpportunityDispositionMutation, PreferencesPatch, WatchlistEntry } from "./domain.js";
import type { ResearchRepository } from "./repository.js";
import { hashSecret, isAuthorized, secretsMatch } from "./security.js";
import { type ServerConnectionService } from "./connections.js";

const providerCredentialSchema = z.object({
  credential: z.string().trim().min(1).max(16_384),
}).strict();
const operatorLoginSchema = z.object({
  password: z.string().min(1).max(512),
}).strict();

type RateLimitConfig = { limit: number; windowMs: number };
type MutationResult = { statusCode?: number; body?: unknown };
const OPERATOR_SESSION_HEADER = "x-zoid-operator-session";
const OPERATOR_SESSION_TTL_SECONDS = 60 * 60 * 24 * 14;

export function buildApi(options: {
  repository: ResearchRepository;
  authenticationKeys?: string[];
  serviceVersion?: string;
  apiToken: string;
  operatorPassword?: string;
  logger?: boolean | { level: string };
  connectionService?: ServerConnectionService;
  rateLimits?: { mutations?: RateLimitConfig; connections?: RateLimitConfig };
}): FastifyInstance {
  const serviceMetadata = {
    service: "zoid99-backend",
    version: options.serviceVersion ?? process.env.SERVICE_VERSION ?? "development",
  };
  const app = Fastify({
    requestIdHeader: "x-request-id",
    logger: options.logger === false || options.logger === undefined ? false : {
      ...(typeof options.logger === "object" ? options.logger : {}),
      redact: {
        paths: [
          "req.headers.authorization",
          "req.headers.cookie",
          "request.headers.authorization",
          "headers.authorization",
          "body.secret",
          "body.password",
          "body.access_token",
          "body.refresh_token",
          "*.encryptedValue",
          `req.headers.${OPERATOR_SESSION_HEADER}`,
        ],
        censor: "[REDACTED]",
      },
    },
    bodyLimit: 64 * 1024,
    requestTimeout: 10_000,
  });
  const rateLimitState = new Map<string, { startedAt: number; count: number }>();
  const mutationRateLimit = options.rateLimits?.mutations ?? { limit: 60, windowMs: 60_000 };
  const connectionRateLimit = options.rateLimits?.connections ?? { limit: 10, windowMs: 60_000 };
  const loginRateLimit: RateLimitConfig = { limit: 5, windowMs: 60_000 };

  app.get("/health", async () => ({ status: "ok", ...serviceMetadata }));
  app.get("/ready", async (_request, reply) => {
    try {
      await options.repository.ping();
      return { status: "ready", ...serviceMetadata };
    } catch {
      return sendError(reply, 503, "service_unavailable", "Database is unavailable");
    }
  });

  app.addHook("onRequest", async (request, reply) => {
    reply.header("x-request-id", request.id);
    if (request.url === "/health" || request.url === "/ready") return;
    const authenticationKeys = options.authenticationKeys ?? [options.apiToken];
    if (!authenticationKeys.some((key) => isAuthorized(request.headers.authorization, key))) {
      return sendError(reply, 401, "unauthorized", "A valid bearer token is required");
    }
    const rateLimit = requestRateLimitClass(request.method, request.url);
    if (rateLimit) {
      const config = rateLimit === "connections" ? connectionRateLimit : mutationRateLimit;
      const key = `${rateLimit}:${credentialFingerprint(request.headers.authorization)}`;
      const now = Date.now();
      const current = rateLimitState.get(key);
      const window = !current || now - current.startedAt >= config.windowMs
        ? { startedAt: now, count: 0 }
        : current;
      window.count += 1;
      rateLimitState.set(key, window);
      if (window.count > config.limit) {
        reply.header("Retry-After", String(Math.ceil((window.startedAt + config.windowMs - now) / 1000)));
        return sendError(reply, 429, "rate_limited", "Too many mutation requests; try again later");
      }
    }
  });

  app.get("/v1/operator/session", async (request) => {
    const token = operatorSessionToken(request.headers[OPERATOR_SESSION_HEADER]);
    const authenticated = token
      ? await options.repository.isOperatorSessionValid(hashSecret(token), new Date())
      : false;
    return { authenticated, authRequired: true };
  });

  app.post("/v1/operator/login", async (request, reply) => {
    if (!options.operatorPassword) {
      return sendError(reply, 503, "service_unavailable", "Operator password is not configured");
    }
    const key = `operator-login:${request.ip}`;
    const now = Date.now();
    const current = rateLimitState.get(key);
    const window = !current || now - current.startedAt >= loginRateLimit.windowMs
      ? { startedAt: now, count: 0 }
      : current;
    window.count += 1;
    rateLimitState.set(key, window);
    if (window.count > loginRateLimit.limit) {
      reply.header("Retry-After", String(Math.ceil((window.startedAt + loginRateLimit.windowMs - now) / 1000)));
      return sendError(reply, 429, "rate_limited", "Too many login attempts; try again later");
    }

    const body = operatorLoginSchema.safeParse(request.body);
    if (!body.success) return invalidRequest(reply, body.error.issues);
    if (!secretsMatch(body.data.password, options.operatorPassword)) {
      return sendError(reply, 401, "unauthorized", "Invalid operator password");
    }

    const token = randomBytes(32).toString("base64url");
    const expiresAt = new Date(Date.now() + OPERATOR_SESSION_TTL_SECONDS * 1000);
    await options.repository.createOperatorSession(hashSecret(token), expiresAt);
    return {
      authenticated: true,
      authRequired: true,
      token,
      expiresAt: expiresAt.toISOString(),
    };
  });

  app.post("/v1/operator/logout", async (request) => {
    const token = operatorSessionToken(request.headers[OPERATOR_SESSION_HEADER]);
    if (token) await options.repository.deleteOperatorSession(hashSecret(token));
    return { authenticated: false, authRequired: true };
  });

  app.get("/v1/bootstrap", async (request, reply) => {
    const cursor = await options.repository.syncCursor();
    const etag = `"${cursor}"`;
    reply.header("ETag", etag);
    if (request.headers["if-none-match"] === etag) return reply.code(304).send();
    return options.repository.bootstrap();
  });
  app.post("/v1/ingestion", async (request, reply) => {
    const payload = ingestionSchema.safeParse(request.body);
    if (!payload.success) return invalidRequest(reply, payload.error.issues);
    for (const health of payload.data.sourceHealth) {
      await options.repository.upsertSourceHealth(health);
    }
    const opportunities = [];
    for (const batch of payload.data.batches) {
      opportunities.push(await options.repository.persistResearchBatch(batch));
    }
    return reply.code(202).send({
      acceptedBatches: opportunities.length,
      opportunityIDs: opportunities.map((opportunity) => opportunity.id),
    });
  });
  app.get("/v1/sources/health", async () => options.repository.listSourceHealth());
  if (options.connectionService) {
    app.get("/v1/connections", async () => options.connectionService!.list());
    app.get("/v1/connections/:provider", async (request, reply) => {
      const params = z.object({ provider: serverProviderSchema }).safeParse(request.params);
      if (!params.success) return invalidRequest(reply, params.error.issues);
      return options.connectionService!.status(params.data.provider);
    });
    app.put("/v1/connections/:provider", async (request, reply) => {
      const params = z.object({ provider: serverProviderSchema }).safeParse(request.params);
      const body = providerCredentialSchema.safeParse(request.body);
      if (!params.success) return invalidRequest(reply, params.error.issues);
      if (!body.success) return invalidRequest(reply, body.error.issues);
      return runMutation(request, reply, options.repository, `connection-configure:${params.data.provider}`, body.data, async (serverTime) => ({
        body: {
          ...(await options.connectionService!.configure(params.data.provider, body.data.credential)),
          ...(getIdempotencyKey(request) ? { serverTime } : {}),
        },
      }));
    });
    app.post("/v1/connections/:provider/validate", async (request, reply) => {
      const params = z.object({ provider: serverProviderSchema }).safeParse(request.params);
      if (!params.success) return invalidRequest(reply, params.error.issues);
      return runMutation(request, reply, options.repository, `connection-validate:${params.data.provider}`, null, async (serverTime) => ({
        body: {
          ...(await options.connectionService!.validate(params.data.provider)),
          ...(getIdempotencyKey(request) ? { serverTime } : {}),
        },
      }));
    });
    app.delete("/v1/connections/:provider", async (request, reply) => {
      const params = z.object({ provider: serverProviderSchema }).safeParse(request.params);
      if (!params.success) return invalidRequest(reply, params.error.issues);
      return runMutation(request, reply, options.repository, `connection-disconnect:${params.data.provider}`, null, async (serverTime) => ({
        body: {
          ...(await options.connectionService!.disconnect(params.data.provider)),
          ...(getIdempotencyKey(request) ? { serverTime } : {}),
        },
      }));
    });
  }
  app.get("/v1/opportunities", async (request, reply) => {
    const query = opportunityReadQuerySchema.safeParse(request.query);
    if (!query.success) return invalidRequest(reply, query.error.issues);
    const queryKeys = Object.keys(request.query as Record<string, unknown>);
    const legacyOnly = queryKeys.length === 0 || (queryKeys.length === 1 && queryKeys[0] === "disposition");
    if (legacyOnly) return options.repository.listOpportunities(query.data.disposition);
    const page = await options.repository.listOpportunitiesPage(query.data);
    return { ...page, serverTime: new Date().toISOString() };
  });
  app.get("/v1/opportunities/:id", async (request, reply) => {
    const params = uuidParams(request.params);
    if (!params.success) return invalidRequest(reply, params.error.issues);
    const opportunity = await options.repository.getOpportunity(params.data.id);
    return opportunity ?? sendError(reply, 404, "not_found", "Opportunity not found");
  });
  app.patch("/v1/opportunities/:id/disposition", async (request, reply) => {
    const params = uuidParams(request.params);
    const body = dispositionMutationSchema.safeParse(request.body);
    if (!params.success) return invalidRequest(reply, params.error.issues);
    if (!body.success) return invalidRequest(reply, body.error.issues);
    const hasWebIdempotency = getIdempotencyKey(request) !== null;
    return runMutation(request, reply, options.repository, `opportunity-disposition:${params.data.id}`, body.data, async (serverTime) => {
      const opportunity = await options.repository.updateOpportunityDisposition(
        params.data.id,
        {
          ...(body.data as OpportunityDispositionMutation),
          ...(hasWebIdempotency ? { changedAt: serverTime } : {}),
        },
      );
      if (!opportunity) return { statusCode: 404, body: { error: "not_found", message: "Opportunity not found", requestId: request.id } };
      return {
        body: hasWebIdempotency ? { ...opportunity, serverTime } : opportunity,
      };
    });
  });

  app.get("/v1/preferences", async (_request, reply) => {
    const preferences = await options.repository.getPreferences();
    reply.header("ETag", preferences.etag);
    return stripPreferenceETag(preferences);
  });
  app.patch("/v1/preferences", async (request, reply) => {
    const body = preferencesPatchSchema.safeParse(request.body);
    if (!body.success) return invalidRequest(reply, body.error.issues);
    const expectedETag = request.headers["if-match"];
    if (typeof expectedETag !== "string" || expectedETag.trim().length === 0) {
      return sendError(reply, 409, "conflict", "If-Match is required to update preferences");
    }
    return runMutation(request, reply, options.repository, "preferences", body.data as PreferencesPatch, async () => {
      const result = await options.repository.updatePreferences(body.data as PreferencesPatch, expectedETag);
      if (result.outcome === "conflict") {
        reply.header("ETag", result.current.etag);
        return {
          statusCode: 409,
          body: {
            error: "conflict",
            message: "Preferences changed; reload before saving.",
            requestId: request.id,
            preferences: stripPreferenceETag(result.current),
          },
        };
      }
      reply.header("ETag", result.current.etag);
      return { body: stripPreferenceETag(result.current) };
    });
  });

  app.get("/v1/watchlist", async () => options.repository.listWatchlist());
  app.post("/v1/watchlist", async (request, reply) => {
    const body = watchlistInputSchema.superRefine(validateOfficialSource).safeParse(request.body);
    if (!body.success) return invalidRequest(reply, body.error.issues);
    return runMutation(request, reply, options.repository, "watchlist-create", body.data, async (serverTime) => ({
      statusCode: 201,
      body: {
        ...(await options.repository.createWatchlist(body.data as Omit<WatchlistEntry, "id">)),
        ...(getIdempotencyKey(request) ? { serverTime } : {}),
      },
    }));
  });
  app.patch("/v1/watchlist/:id", async (request, reply) => {
    const params = uuidParams(request.params);
    const body = watchlistInputSchema.superRefine(validateOfficialSource).safeParse(request.body);
    if (!params.success) return invalidRequest(reply, params.error.issues);
    if (!body.success) return invalidRequest(reply, body.error.issues);
    return runMutation(request, reply, options.repository, `watchlist-update:${params.data.id}`, body.data, async (serverTime) => {
      const updated = await options.repository.updateWatchlist(
        params.data.id,
        body.data as Omit<WatchlistEntry, "id">,
      );
      return updated
        ? { body: { ...updated, ...(getIdempotencyKey(request) ? { serverTime } : {}) } }
        : { statusCode: 404, body: { error: "not_found", message: "Watchlist entry not found", requestId: request.id } };
    });
  });
  app.put("/v1/watchlist", async (request, reply) => {
    const body = watchlistReplacementSchema.superRefine((value, context) => {
      value.entries.forEach((entry, index) => {
        if (entry.kind !== "Official source") return;
        try {
          const url = new URL(entry.value);
          if (url.protocol === "https:" && url.hostname) return;
        } catch {
          // The structured validation issue below is the safe public error.
        }
        context.addIssue({
          code: "custom",
          path: ["entries", index, "value"],
          message: "Official sources must use a complete HTTPS URL",
        });
      });
    }).safeParse(request.body);
    if (!body.success) return invalidRequest(reply, body.error.issues);
    const keys = body.data.entries.map(
      (entry) => `${entry.kind}:${entry.value.toLocaleLowerCase()}`,
    );
    if (new Set(keys).size !== keys.length) {
      return sendError(reply, 409, "conflict", "The watchlist contains duplicate entries");
    }
    return runMutation(request, reply, options.repository, "watchlist-replace", body.data, async (serverTime) => {
      const entries = await options.repository.replaceWatchlist(body.data.entries as WatchlistEntry[]);
      return {
        body: getIdempotencyKey(request) ? { entries, serverTime } : entries,
      };
    });
  });
  app.delete("/v1/watchlist/:id", async (request, reply) => {
    const params = uuidParams(request.params);
    if (!params.success) return invalidRequest(reply, params.error.issues);
    return runMutation(request, reply, options.repository, `watchlist-delete:${params.data.id}`, null, async () => (
      (await options.repository.deleteWatchlist(params.data.id))
        ? { statusCode: 204, body: null }
        : { statusCode: 404, body: { error: "not_found", message: "Watchlist entry not found", requestId: request.id } }
    ));
  });

  app.get("/v1/notifications", async (request, reply) => {
    const query = notificationReadQuerySchema.safeParse(request.query);
    if (!query.success) return invalidRequest(reply, query.error.issues);
    if (Object.keys(request.query as Record<string, unknown>).length === 0) {
      return options.repository.listNotifications();
    }
    const page = await options.repository.listNotificationsPage(query.data);
    return { ...page, serverTime: new Date().toISOString() };
  });
  app.patch("/v1/notifications/:id", async (request, reply) => {
    const params = uuidParams(request.params);
    const body = notificationReadSchema.safeParse(request.body);
    if (!params.success) return invalidRequest(reply, params.error.issues);
    if (!body.success) return invalidRequest(reply, body.error.issues);
    return runMutation(request, reply, options.repository, `notification:${params.data.id}`, body.data, async (serverTime) => {
      const notification = await options.repository.markNotificationRead(params.data.id, body.data.isRead);
      return notification
        ? { body: { ...notification, ...(getIdempotencyKey(request) ? { serverTime } : {}) } }
        : { statusCode: 404, body: { error: "not_found", message: "Notification not found", requestId: request.id } };
    });
  });

  app.get("/v1/topics", async (request, reply) => {
    const query = topicReadQuerySchema.safeParse(request.query);
    if (!query.success) return invalidRequest(reply, query.error.issues);
    const page = await options.repository.listTopics(query.data);
    return { ...page, serverTime: new Date().toISOString() };
  });
  app.get("/v1/topics/:topicKey", async (request, reply) => {
    const params = z.object({ topicKey: z.string().trim().min(1).max(200) }).safeParse(request.params);
    if (!params.success) return invalidRequest(reply, params.error.issues);
    const topic = await options.repository.getTopic(params.data.topicKey);
    return topic
      ? { ...topic, serverTime: new Date().toISOString() }
      : sendError(reply, 404, "not_found", "Topic not found");
  });
  app.get("/v1/comments", async (request, reply) => {
    const query = paginationQuerySchema.safeParse(request.query);
    if (!query.success) return invalidRequest(reply, query.error.issues);
    const projection = await options.repository.listComments();
    return {
      ...projection.page,
      serverTime: new Date().toISOString(),
      availability: projection.availability,
    };
  });

  app.setErrorHandler((error, _request, reply) => {
    if (typeof error === "object" && error !== null && "statusCode" in error && error.statusCode === 413) {
      return sendError(reply, 413, "payload_too_large", "The ingestion batch exceeds the size limit");
    }
    if (typeof error === "object" && error !== null && "code" in error && error.code === "23505") {
      return sendError(reply, 409, "conflict", "The record already exists");
    }
    if (typeof error === "object" && error !== null && "code" in error && error.code === "invalid_cursor") {
      return sendError(reply, 400, "invalid_request", "The pagination cursor is invalid");
    }
    app.log.error({
      errorType: error instanceof Error ? error.name : "UnknownError",
      errorCode: typeof error === "object" && error !== null && "code" in error
        ? String(error.code)
        : undefined,
    }, "Unhandled request error");
    return sendError(reply, 500, "internal_error", "The request could not be completed");
  });
  return app;
}

function validateOfficialSource(
  entry: { kind: string; value: string },
  context: z.RefinementCtx,
): void {
  if (entry.kind !== "Official source") return;
  try {
    const url = new URL(entry.value);
    if (url.protocol !== "https:" || !url.hostname) throw new Error("invalid");
  } catch {
    context.addIssue({
      code: "custom",
      path: ["value"],
      message: "Official sources must use a complete HTTPS URL",
    });
  }
}

function uuidParams(input: unknown) {
  return z.object({ id: z.string().uuid() }).safeParse(input);
}

function invalidRequest(reply: FastifyReply, issues: z.core.$ZodIssue[]) {
  return reply.code(400).send({
    error: "invalid_request",
    message: "Request validation failed",
    requestId: reply.request.id,
    details: issues.map((issue) => ({ path: issue.path.join("."), message: issue.message })),
  });
}

function sendError(
  reply: FastifyReply,
  status: number,
  error: "unauthorized" | "service_unavailable" | "invalid_request" | "not_found" | "conflict" | "payload_too_large" | "internal_error" | "rate_limited",
  message: string,
) {
  return reply.code(status).send({ error, message, requestId: reply.request.id });
}

async function runMutation(
  request: { headers: Record<string, string | string[] | undefined>; id: string },
  reply: FastifyReply,
  repository: ResearchRepository,
  scope: string,
  payload: unknown,
  operation: (serverTime: string) => Promise<MutationResult>,
) {
  const idempotencyKey = getIdempotencyKey(request);
  if (!idempotencyKey) return sendMutationResult(reply, await operation(new Date().toISOString()));

  const scopedScope = `${scope}:${credentialFingerprint(request.headers.authorization)}`;
  const requestHash = createHash("sha256").update(stableSerialize(payload)).digest("hex");
  return repository.withIdempotencyLock(scopedScope, idempotencyKey, async () => {
    const existing = await repository.getIdempotencyRecord(scopedScope, idempotencyKey);
    if (existing) {
      if (existing.requestHash !== requestHash) {
        return sendError(reply, 409, "conflict", "The idempotency key was reused for a different request");
      }
      applyResponseHeaders(reply, existing.responseHeaders);
      return reply.code(existing.statusCode).send(existing.responseBody);
    }
    const result = await operation(new Date().toISOString());
    if ((result.statusCode ?? 200) >= 200 && (result.statusCode ?? 200) < 300) {
      const responseHeaders = responseHeadersFrom(reply);
      await repository.saveIdempotencyRecord(scopedScope, idempotencyKey, {
        requestHash,
        statusCode: result.statusCode ?? 200,
        responseBody: result.body ?? null,
        responseHeaders,
      });
      return sendMutationResult(reply, result, responseHeaders);
    }
    return sendMutationResult(reply, result);
  });
}

function sendMutationResult(
  reply: FastifyReply,
  result: MutationResult,
  responseHeaders?: Record<string, string>,
) {
  applyResponseHeaders(reply, responseHeaders);
  const response = reply.code(result.statusCode ?? 200);
  return result.statusCode === 204 ? response.send() : response.send(result.body);
}

function getIdempotencyKey(request: { headers: Record<string, string | string[] | undefined> }): string | null {
  const value = request.headers["idempotency-key"];
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed.length > 0 && trimmed.length <= 255 ? trimmed : null;
}

function stableSerialize(value: unknown): string {
  if (value === null || typeof value !== "object") return JSON.stringify(value) ?? "null";
  if (Array.isArray(value)) return `[${value.map(stableSerialize).join(",")}]`;
  return `{${Object.entries(value as Record<string, unknown>)
    .sort(([left], [right]) => left.localeCompare(right))
    .map(([key, entry]) => `${JSON.stringify(key)}:${stableSerialize(entry)}`)
    .join(",")}}`;
}

function credentialFingerprint(authorization: string | string[] | undefined): string {
  const value = Array.isArray(authorization) ? authorization[0] : authorization;
  return createHash("sha256").update(value ?? "anonymous").digest("hex").slice(0, 16);
}

function operatorSessionToken(value: string | string[] | undefined): string | null {
  const token = Array.isArray(value) ? value[0] : value;
  if (!token || token.length < 32 || token.length > 512) return null;
  return token;
}

function requestRateLimitClass(method: string, url: string): "mutations" | "connections" | null {
  const path = url.split("?", 1)[0] ?? "";
  if (method !== "GET" && path.startsWith("/v1/connections/")) {
    return "connections";
  }
  if (method !== "GET" && (
    path === "/v1/preferences"
    || path.includes("/disposition")
    || path.startsWith("/v1/watchlist")
    || path.startsWith("/v1/notifications/")
  )) {
    return "mutations";
  }
  return null;
}

function stripPreferenceETag(preferences: { etag: string; [key: string]: unknown }) {
  const { etag: _etag, ...publicPreferences } = preferences;
  return publicPreferences;
}

function responseHeadersFrom(reply: FastifyReply): Record<string, string> {
  const etag = reply.getHeader("ETag");
  return typeof etag === "string" ? { ETag: etag } : {};
}

function applyResponseHeaders(reply: FastifyReply, headers?: Record<string, string>): void {
  for (const [name, value] of Object.entries(headers ?? {})) reply.header(name, value);
}
