import assert from "node:assert/strict";
import test from "node:test";
import { EncryptedConfigService } from "../src/encrypted-config.js";
import type { EncryptedConfigStore } from "../src/repository.js";
import { SecretCipher } from "../src/security.js";

test("encrypted config abstraction never passes plaintext to persistence", async () => {
  const persisted = new Map<string, string>();
  const store: EncryptedConfigStore = {
    async set(key, encryptedValue) {
      persisted.set(key, encryptedValue);
    },
    async get(key) {
      return persisted.get(key) ?? null;
    },
    async remove(key) {
      persisted.delete(key);
    },
  };
  const service = new EncryptedConfigService(store, new SecretCipher(Buffer.alloc(32, 5)));
  await service.set("youtube.oauth", "private-token");

  assert.notEqual(persisted.get("youtube.oauth"), "private-token");
  assert.equal(await service.get("youtube.oauth"), "private-token");
  assert.equal(await service.get("missing"), null);
});
