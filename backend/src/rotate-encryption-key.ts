import { fileURLToPath } from "node:url";
import pg from "pg";
import { z } from "zod";
import { SecretCipher } from "./security.js";

const { Client } = pg;

function required(environment: NodeJS.ProcessEnv, parts: string[]): string {
  const name = parts.join("_");
  return z.string().min(1, `${name} is required`).parse(environment[name]);
}

function decodeKey(value: string, name: string): Buffer {
  const key = Buffer.from(value, "base64");
  if (key.length !== 32 || key.toString("base64").replace(/=+$/, "") !== value.replace(/=+$/, "")) {
    throw new Error(`${name} must be exactly 32 base64-encoded bytes`);
  }
  return key;
}

export async function rotateEncryptionKey(environment: NodeJS.ProcessEnv): Promise<number> {
  const databaseUrl = required(environment, ["DATABASE", "URL"]);
  const oldName = ["OLD", "SECRETS", "ENCRYPTION", "KEY"];
  const newName = ["NEW", "SECRETS", "ENCRYPTION", "KEY"];
  const oldCipher = new SecretCipher(decodeKey(required(environment, oldName), oldName.join("_")));
  const newCipher = new SecretCipher(decodeKey(required(environment, newName), newName.join("_")));
  const client = new Client({ connectionString: databaseUrl });
  await client.connect();
  try {
    await client.query("BEGIN");
    await client.query("LOCK TABLE encrypted_configs IN ACCESS EXCLUSIVE MODE");
    const result = await client.query<{ config_key: string; encrypted_value: string }>(
      "SELECT config_key, encrypted_value FROM encrypted_configs ORDER BY config_key",
    );
    for (const row of result.rows) {
      const plaintext = oldCipher.decrypt(row.encrypted_value);
      await client.query(
        "UPDATE encrypted_configs SET encrypted_value = $2, updated_at = now() WHERE config_key = $1",
        [row.config_key, newCipher.encrypt(plaintext)],
      );
    }
    await client.query("COMMIT");
    return result.rowCount ?? 0;
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    await client.end();
  }
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const rotated = await rotateEncryptionKey(process.env);
  process.stdout.write(`Rotated ${rotated} encrypted configuration record(s).\n`);
}
