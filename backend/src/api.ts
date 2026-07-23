import Fastify, { type FastifyInstance, type FastifyReply } from "fastify";
import { z } from "zod";
import type { OpportunityDisposition, WatchlistEntry } from "./domain.js";
import type { ResearchRepository } from "./repository.js";
import { isAuthorized } from "./security.js";

const dispositionSchema = z.enum(["active", "saved", "watched", "dismissed", "muted"]);
const watchlistSchema = z.object({
  kind: z.enum(["Creator", "Official source", "Keyword", "Topic", "Country", "Language"]),
  value: z.string().trim().min(1).max(500),
  highPriority: z.boolean(),
}).strict();

export function buildApi(options: {
  repository: ResearchRepository;
  authenticationKeys?: string[];
  serviceVersion?: string;
  apiToken: string;
  logger?: boolean | { level: string };
}): FastifyInstance {
  const serviceMetadata = {
    service: "zoid99-backend",
    version: options.serviceVersion ?? process.env.SERVICE_VERSION ?? "development",
  };
  const app = Fastify({
    logger: options.logger === false || options.logger === undefined ? false : {
      ...(typeof options.logger === "object" ? options.logger : {}),
      redact: {
        paths: [
          "req.headers.authorization",
          "req.headers.cookie",
          "request.headers.authorization",
          "headers.authorization",
          "body.secret",
          "body.access_token",
          "body.refresh_token",
          "*.encryptedValue",
        ],
        censor: "[REDACTED]",
      },
    },
    bodyLimit: 64 * 1024,
    requestTimeout: 10_000,
  });

  app.get("/health", async () => ({ status: "ok", ...serviceMetadata }));
  app.get("/ready", async (_request, reply) => {
    try {
      await options.repository.ping();
      return { status: "ready", ...serviceMetadata };
    } catch {
      return reply.code(503).send({ error: "service_unavailable", message: "Database is unavailable" });
    }
  });

  app.addHook("onRequest", async (request, reply) => {
    if (request.url === "/health" || request.url === "/ready") return;
    const authenticationKeys = options.authenticationKeys ?? [options.apiToken];
    if (!authenticationKeys.some((key) => isAuthorized(request.headers.authorization, key))) {
      return reply.code(401).send({ error: "unauthorized", message: "A valid bearer token is required" });
    }
  });

  app.get("/v1/bootstrap", async () => options.repository.bootstrap());
  app.get("/v1/sources/health", async () => options.repository.listSourceHealth());
  app.get("/v1/opportunities", async (request, reply) => {
    const query = z.object({ disposition: dispositionSchema.optional() }).safeParse(request.query);
    if (!query.success) return invalidRequest(reply, query.error.issues);
    return options.repository.listOpportunities(query.data.disposition);
  });
  app.get("/v1/opportunities/:id", async (request, reply) => {
    const params = uuidParams(request.params);
    if (!params.success) return invalidRequest(reply, params.error.issues);
    const opportunity = await options.repository.getOpportunity(params.data.id);
    return opportunity ?? reply.code(404).send({ error: "not_found", message: "Opportunity not found" });
  });
  app.patch("/v1/opportunities/:id/disposition", async (request, reply) => {
    const params = uuidParams(request.params);
    const body = z.object({ disposition: dispositionSchema }).strict().safeParse(request.body);
    if (!params.success) return invalidRequest(reply, params.error.issues);
    if (!body.success) return invalidRequest(reply, body.error.issues);
    const opportunity = await options.repository.updateOpportunityDisposition(
      params.data.id,
      body.data.disposition as OpportunityDisposition,
    );
    return opportunity ?? reply.code(404).send({ error: "not_found", message: "Opportunity not found" });
  });

  app.get("/v1/watchlist", async () => options.repository.listWatchlist());
  app.post("/v1/watchlist", async (request, reply) => {
    const body = watchlistSchema.safeParse(request.body);
    if (!body.success) return invalidRequest(reply, body.error.issues);
    const created = await options.repository.createWatchlist(body.data as Omit<WatchlistEntry, "id">);
    return reply.code(201).send(created);
  });
  app.delete("/v1/watchlist/:id", async (request, reply) => {
    const params = uuidParams(request.params);
    if (!params.success) return invalidRequest(reply, params.error.issues);
    return (await options.repository.deleteWatchlist(params.data.id))
      ? reply.code(204).send()
      : reply.code(404).send({ error: "not_found", message: "Watchlist entry not found" });
  });

  app.get("/v1/notifications", async () => options.repository.listNotifications());
  app.patch("/v1/notifications/:id", async (request, reply) => {
    const params = uuidParams(request.params);
    const body = z.object({ isRead: z.boolean() }).strict().safeParse(request.body);
    if (!params.success) return invalidRequest(reply, params.error.issues);
    if (!body.success) return invalidRequest(reply, body.error.issues);
    const notification = await options.repository.markNotificationRead(params.data.id, body.data.isRead);
    return notification ?? reply.code(404).send({ error: "not_found", message: "Notification not found" });
  });

  app.setErrorHandler((error, _request, reply) => {
    if (typeof error === "object" && error !== null && "code" in error && error.code === "23505") {
      return reply.code(409).send({ error: "conflict", message: "The record already exists" });
    }
    app.log.error({
      errorType: error instanceof Error ? error.name : "UnknownError",
      errorCode: typeof error === "object" && error !== null && "code" in error
        ? String(error.code)
        : undefined,
    }, "Unhandled request error");
    return reply.code(500).send({ error: "internal_error", message: "The request could not be completed" });
  });
  return app;
}

function uuidParams(input: unknown) {
  return z.object({ id: z.string().uuid() }).safeParse(input);
}

function invalidRequest(reply: FastifyReply, issues: z.core.$ZodIssue[]) {
  return reply.code(400).send({
    error: "invalid_request",
    message: "Request validation failed",
    details: issues.map((issue) => ({ path: issue.path.join("."), message: issue.message })),
  });
}
