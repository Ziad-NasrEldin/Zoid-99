import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";
import { createPool } from "../src/postgres.js";

const databaseUrl = process.env.TEST_DATABASE_URL;

test("watchlist rollback archives Company rows before restoring the old constraint", {
  skip: databaseUrl ? false : "TEST_DATABASE_URL is not configured",
}, async () => {
  const pool = createPool(databaseUrl!);
  const client = await pool.connect();
  const entryID = "40000000-0000-4000-8000-000000000099";
  try {
    await client.query("BEGIN");
    await client.query("SET LOCAL search_path = pg_temp, public");
    await client.query(`
      CREATE TEMP TABLE watchlist_entries (
        id uuid PRIMARY KEY,
        kind text NOT NULL,
        value text NOT NULL,
        normalized_value text GENERATED ALWAYS AS (lower(btrim(value))) STORED,
        high_priority boolean NOT NULL,
        created_at timestamptz NOT NULL,
        updated_at timestamptz NOT NULL,
        CONSTRAINT watchlist_entries_kind_check CHECK (
          kind IN ('Creator', 'Official source', 'Company', 'Keyword', 'Topic', 'Country', 'Language')
        )
      )
    `);
    await client.query(`
      INSERT INTO watchlist_entries (id, kind, value, high_priority, created_at, updated_at)
      VALUES ($1, 'Company', 'OpenAI', true, '2026-07-23T08:00:00Z', '2026-07-23T08:05:00Z')
    `, [entryID]);

    const rollback = await readFile(
      join(dirname(fileURLToPath(import.meta.url)), "../migrations/rollback/005_watchlist_companies.sql"),
      "utf8",
    );
    await client.query(rollback);
    await client.query(rollback);

    const active = await client.query("SELECT id FROM watchlist_entries");
    assert.equal(active.rowCount, 0);
    const archived = await client.query<{
      id: string;
      kind: string;
      value: string;
      normalized_value: string;
      high_priority: boolean;
    }>(`SELECT id, kind, value, normalized_value, high_priority
        FROM watchlist_entries_company_archive
        WHERE id = $1`, [entryID]);
    assert.deepEqual(archived.rows[0], {
      id: entryID,
      kind: "Company",
      value: "OpenAI",
      normalized_value: "openai",
      high_priority: true,
    });

    await assert.rejects(
      client.query(`
        INSERT INTO watchlist_entries (id, kind, value, high_priority, created_at, updated_at)
        VALUES ('40000000-0000-4000-8000-000000000100', 'Company', 'Anthropic', false, now(), now())
      `),
      /watchlist_entries_kind_check/,
    );
  } finally {
    await client.query("ROLLBACK").catch(() => undefined);
    client.release();
    await pool.end();
  }
});
