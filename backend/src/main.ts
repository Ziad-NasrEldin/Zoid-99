import { buildApi } from "./api.js";
import { loadConfig } from "./config.js";
import { reportMonitoringEvent } from "./monitoring.js";
import { collectOfficialSources } from "./official-collector.js";
import { collectWatchlist } from "./watchlist-collector.js";
import { createPool, PostgreSqlRepository } from "./postgres.js";
import { EncryptedConfigService } from "./encrypted-config.js";
import { SecretCipher } from "./security.js";
import { ServerConnectionService } from "./connections.js";
import { CollectionScheduler } from "./scheduler.js";

const config = loadConfig(process.env);
const pool = createPool(config.databaseUrl);
const repository = new PostgreSqlRepository(pool);
const encryptedConfig = new EncryptedConfigService(repository, new SecretCipher(config.encryptionKey));
const connectionService = new ServerConnectionService(encryptedConfig);
const youtubeCredential = process.env.ZOID99_YOUTUBE_API_KEY ?? process.env.ZOID99_YOUTUBE_OAUTH_ACCESS_TOKEN;
const xCredential = process.env.ZOID99_X_BEARER_TOKEN;
const instagramCredential = process.env.ZOID99_INSTAGRAM_ACCOUNT_ID && process.env.ZOID99_INSTAGRAM_ACCESS_TOKEN
  ? JSON.stringify({
      accountID: process.env.ZOID99_INSTAGRAM_ACCOUNT_ID,
      accessToken: process.env.ZOID99_INSTAGRAM_ACCESS_TOKEN,
      graphAPIVersion: process.env.ZOID99_INSTAGRAM_GRAPH_API_VERSION,
    })
  : undefined;
const app = buildApi({
  repository,
  apiToken: config.apiToken,
  ...(config.operatorPassword ? { operatorPassword: config.operatorPassword } : {}),
  authenticationKeys: config.authenticationKeys,
  serviceVersion: config.serviceVersion,
  logger: { level: config.logLevel },
  connectionService,
});
const scheduler = new CollectionScheduler({
  intervalMilliseconds: config.collectionIntervalSeconds * 1_000,
  runCollection: async () => {
    const startedAt = Date.now();
    const officialResult = await settleCollection(() => collectOfficialSources({ repository }));
    const watchlistResult = await settleCollection(
      () => collectWatchlist({
        repository,
        credentialStore: encryptedConfig,
        credentials: {
          ...(youtubeCredential ? { youtube: youtubeCredential } : {}),
          ...(xCredential ? { x: xCredential } : {}),
          ...(instagramCredential ? { instagram: instagramCredential } : {}),
        },
      }),
    );
    const officialFailed = officialResult.status === "rejected";
    const watchlistFailed = watchlistResult.status === "rejected";
    if (officialFailed || watchlistFailed) {
      app.log.error({
        event: "collection_cycle_partial",
        durationMilliseconds: Date.now() - startedAt,
        official: officialResult.status,
        watchlist: watchlistResult.status,
      }, "Collection cycle completed with one or more failed collectors");
      const failedCount = Number(officialFailed) + Number(watchlistFailed);
      throw new Error(`${failedCount} collection collector${failedCount === 1 ? "" : "s"} failed`);
    }
    app.log.info({
      event: "collection_cycle_completed",
      durationMilliseconds: Date.now() - startedAt,
      official: officialResult.value,
      watchlist: watchlistResult.value,
    }, "Official and watchlist collection cycle completed");
  },
  onError: (error) => {
    app.log.error({
      event: "collection_cycle_failed",
      errorType: error instanceof Error ? error.name : "UnknownError",
    }, "Collection cycle failed");
    void reportMonitoringEvent({
      endpoint: config.errorMonitoringWebhookUrl,
      event: "collection_cycle_failed",
      serviceVersion: config.serviceVersion,
    }).catch(() => app.log.warn({ event: "monitoring_delivery_failed" }, "Monitoring event delivery failed"));
  },
});

async function settleCollection<T>(task: () => Promise<T>): Promise<PromiseSettledResult<T>> {
  try {
    return { status: "fulfilled", value: await task() };
  } catch (reason) {
    return { status: "rejected", reason };
  }
}

async function shutdown(signal: string): Promise<void> {
  app.log.info({ signal }, "Stopping backend");
  await scheduler.stop();
  await app.close();
  await pool.end();
  process.exit(0);
}

process.on("SIGINT", () => void shutdown("SIGINT"));
process.on("SIGTERM", () => void shutdown("SIGTERM"));

try {
  await app.listen({ host: config.host, port: config.port });
  scheduler.start();
} catch (error) {
  app.log.error({
    errorType: error instanceof Error ? error.name : "UnknownError",
    errorCode: typeof error === "object" && error !== null && "code" in error
      ? String(error.code)
      : undefined,
  }, "Backend startup failed");
  await reportMonitoringEvent({
    endpoint: config.errorMonitoringWebhookUrl,
    event: "backend_startup_failed",
    serviceVersion: config.serviceVersion,
  }).catch(() => undefined);
  await pool.end();
  process.exit(1);
}
