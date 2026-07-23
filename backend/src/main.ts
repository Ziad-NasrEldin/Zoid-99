import { buildApi } from "./api.js";
import { loadConfig } from "./config.js";
import { createPool, PostgreSqlRepository } from "./postgres.js";

const config = loadConfig(process.env);
const pool = createPool(config.databaseUrl);
const repository = new PostgreSqlRepository(pool);
const app = buildApi({ repository, apiToken: config.apiToken, logger: { level: config.logLevel } });

async function shutdown(signal: string): Promise<void> {
  app.log.info({ signal }, "Stopping backend");
  await app.close();
  await pool.end();
  process.exit(0);
}

process.on("SIGINT", () => void shutdown("SIGINT"));
process.on("SIGTERM", () => void shutdown("SIGTERM"));

try {
  await app.listen({ host: config.host, port: config.port });
} catch (error) {
  app.log.error(error);
  await pool.end();
  process.exit(1);
}
