import { createHash } from "node:crypto";
import { readdir, readFile } from "node:fs/promises";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import type { PoolClient } from "pg";
import { loadConfig } from "./config.js";
import { createPool } from "./postgres.js";

export async function runMigrations(databaseUrl: string, migrationsDirectory: string): Promise<void> {
  const pool = createPool(databaseUrl);
  let client: PoolClient | undefined;
  try {
    client = await pool.connect();
    const connectedClient = client;
    await connectedClient.query("SELECT pg_advisory_lock(hashtext('zoid99_schema_migrations'))");
    await connectedClient.query(`
      CREATE TABLE IF NOT EXISTS schema_migrations (
        name text PRIMARY KEY,
        checksum text NOT NULL,
        applied_at timestamptz NOT NULL DEFAULT now()
      )
    `);
    const names = (await readdir(migrationsDirectory)).filter((name) => name.endsWith(".sql")).sort();
    for (const name of names) {
      const sql = await readFile(join(migrationsDirectory, name), "utf8");
      const checksum = createHash("sha256").update(sql).digest("hex");
      const existing = await connectedClient.query<{ checksum: string }>(
        "SELECT checksum FROM schema_migrations WHERE name = $1",
        [name],
      );
      if (existing.rows[0]) {
        if (existing.rows[0].checksum !== checksum) throw new Error(`Applied migration changed: ${name}`);
        continue;
      }
      await connectedClient.query("BEGIN");
      try {
        await connectedClient.query(sql);
        await connectedClient.query("INSERT INTO schema_migrations (name, checksum) VALUES ($1, $2)", [name, checksum]);
        await connectedClient.query("COMMIT");
      } catch (error) {
        await connectedClient.query("ROLLBACK");
        throw error;
      }
    }
  } finally {
    await client?.query("SELECT pg_advisory_unlock(hashtext('zoid99_schema_migrations'))").catch(() => undefined);
    client?.release();
    await pool.end();
  }
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const config = loadConfig(process.env);
  const migrationsDirectory = join(process.cwd(), "migrations");
  await runMigrations(config.databaseUrl, migrationsDirectory);
}
