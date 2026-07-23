import { buildApi } from "./api.js";
import { loadConfig } from "./config.js";
import { reportMonitoringEvent } from "./monitoring.js";
import { collectOfficialSources } from "./official-collector.js";
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
const app = buildApi({
  repository,
  apiToken: config.apiToken,
  authenticationKeys: config.authenticationKeys,
  serviceVersion: config.serviceVersion,
  logger: { level: config.logLevel },
  connectionService,
});
const scheduler = new CollectionScheduler({
  intervalMilliseconds: config.collectionIntervalSeconds * 1_000,
  runCollection: async () => {
    const startedAt = Date.now();
    await collectOfficialSources({ repository });
    app.log.info({
      event: "collection_cycle_completed",
      durationMilliseconds: Date.now() - startedAt,
    }, "Official-source collection cycle completed");
  },
  onError: (error) => {
    app.log.error({
      event: "collection_cycle_failed",
      errorType: error instanceof Error ? error.name : "UnknownError",
    }, "Official-source collection cycle failed");
    void reportMonitoringEvent({
      endpoint: config.errorMonitoringWebhookUrl,
      event: "collection_cycle_failed",
      serviceVersion: config.serviceVersion,
    }).catch(() => app.log.warn({ event: "monitoring_delivery_failed" }, "Monitoring event delivery failed"));
  },
});

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
