import assert from "node:assert/strict";
import test from "node:test";
import {
  ServerConnectionService,
  type ServerProviderValidator,
} from "../src/connections.js";
import { EncryptedConfigService } from "../src/encrypted-config.js";
import type { EncryptedConfigStore } from "../src/repository.js";
import { SecretCipher } from "../src/security.js";

function fixture() {
  const persisted = new Map<string, string>();
  const store: EncryptedConfigStore = {
    async set(key, value) { persisted.set(key, value); },
    async get(key) { return persisted.get(key) ?? null; },
    async remove(key) { persisted.delete(key); },
  };
  const validator: ServerProviderValidator = {
    async validate(provider) {
      return {
        state: provider === "ai-provider" ? "Connected" : "Unsupported",
        lastActivity: provider === "ai-provider" ? "2026-07-24T12:00:00.000Z" : null,
        evidence: provider === "ai-provider"
          ? "The provider accepted a fixture model-list request."
          : "Official Google Trends API access is not approved for this fixture.",
        repairAction: provider === "ai-provider" ? "Review" : "Review support",
        retryAt: null,
      };
    },
  };
  const encrypted = new EncryptedConfigService(store, new SecretCipher(Buffer.alloc(32, 9)));
  return { service: new ServerConnectionService(encrypted, validator), persisted };
}

test("server connection stores only a verified credential and never returns it", async () => {
  const { service, persisted } = fixture();

  const result = await service.configure("ai-provider", "fixture-server-secret");

  assert.equal(result.state, "Connected");
  assert.equal(JSON.stringify(result).includes("fixture-server-secret"), false);
  assert.notEqual(persisted.get("provider.ai-provider.credential"), "fixture-server-secret");
});

test("unsupported validation does not persist the submitted credential", async () => {
  const { service, persisted } = fixture();

  const result = await service.configure("google-trends", "unapproved-secret");

  assert.equal(result.state, "Unsupported");
  assert.equal(persisted.has("provider.google-trends.credential"), false);
  assert.equal(JSON.stringify(result).includes("unapproved-secret"), false);
});

test("disconnect removes authorization but retains last activity evidence", async () => {
  const { service, persisted } = fixture();
  await service.configure("ai-provider", "fixture-server-secret");

  const result = await service.disconnect("ai-provider");

  assert.equal(result.state, "Disconnected");
  assert.equal(result.lastActivity, "2026-07-24T12:00:00.000Z");
  assert.equal(result.evidence.includes("Previously collected evidence was retained"), true);
  assert.equal(persisted.has("provider.ai-provider.credential"), false);
});
