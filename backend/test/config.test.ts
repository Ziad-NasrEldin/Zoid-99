import assert from "node:assert/strict";
import test from "node:test";
import { loadConfig } from "../src/config.js";

const validEnvironment = {
  DATABASE_URL: "postgresql://zoid99:zoid99@127.0.0.1:54329/zoid99",
  ZOID99_API_TOKEN: "a-secure-api-token-with-more-than-32-characters",
  SECRETS_ENCRYPTION_KEY: Buffer.alloc(32, 7).toString("base64"),
};

test("configuration accepts explicit production-safe values", () => {
  const config = loadConfig(validEnvironment);
  assert.equal(config.port, 8099);
  assert.equal(config.encryptionKey.length, 32);
  assert.equal(config.databaseUrl, validEnvironment.DATABASE_URL);
});

test("configuration fails closed when authentication or encryption material is weak", () => {
  assert.throws(
    () => loadConfig({ ...validEnvironment, ZOID99_API_TOKEN: "short" }),
    /ZOID99_API_TOKEN/,
  );
  assert.throws(
    () => loadConfig({ ...validEnvironment, SECRETS_ENCRYPTION_KEY: Buffer.alloc(16).toString("base64") }),
    /SECRETS_ENCRYPTION_KEY/,
  );
});

test("production configuration requires PostgreSQL transport encryption", () => {
  assert.throws(
    () => loadConfig({ ...validEnvironment, NODE_ENV: "production" }),
    /DATABASE_URL.*TLS/,
  );
  const config = loadConfig({
    ...validEnvironment,
    NODE_ENV: "production",
    DATABASE_URL: `${validEnvironment.DATABASE_URL}?sslmode=require`,
    PUBLIC_BASE_URL: "https://zoid99.example.test",
  });
  assert.equal(config.nodeEnv, "production");
});

test("production configuration requires an explicit public health URL and bounded collection schedule", () => {
  assert.throws(
    () => loadConfig({
      ...validEnvironment,
      NODE_ENV: "production",
      DATABASE_URL: `${validEnvironment.DATABASE_URL}?sslmode=require`,
    }),
    /PUBLIC_BASE_URL/,
  );
  assert.throws(
    () => loadConfig({
      ...validEnvironment,
      COLLECTION_INTERVAL_SECONDS: "30",
    }),
    /COLLECTION_INTERVAL_SECONDS/,
  );
  assert.throws(
    () => loadConfig({
      ...validEnvironment,
      NODE_ENV: "production",
      DATABASE_URL: `${validEnvironment.DATABASE_URL}?sslmode=require`,
      PUBLIC_BASE_URL: "http://zoid99.example.test",
    }),
    /PUBLIC_BASE_URL.*HTTPS/,
  );
});

test("authentication accepts a staged previous token only when explicitly configured", () => {
  const config = loadConfig({
    ...validEnvironment,
    ZOID99_API_TOKEN_PREVIOUS: "a-previous-api-token-with-more-than-32-characters",
  });
  assert.equal(config.authenticationKeys.length, 2);
  assert.equal(config.authenticationKeys[1], "a-previous-api-token-with-more-than-32-characters");
});
