import assert from "node:assert/strict";
import test from "node:test";
import { SecretCipher, isAuthorized } from "../src/security.js";

test("bearer authentication accepts only the configured complete token", () => {
  const expected = "correct-token-that-is-long-enough-for-production";
  assert.equal(isAuthorized(`Bearer ${expected}`, expected), true);
  assert.equal(isAuthorized("Bearer incorrect", expected), false);
  assert.equal(isAuthorized(undefined, expected), false);
  assert.equal(isAuthorized(`Basic ${expected}`, expected), false);
});

test("encrypted configuration round-trips without storing plaintext", () => {
  const cipher = new SecretCipher(Buffer.alloc(32, 9));
  const plaintext = "connector-secret-value";
  const encrypted = cipher.encrypt(plaintext);
  assert.match(encrypted, /^v1\./);
  assert.equal(encrypted.includes(plaintext), false);
  assert.equal(cipher.decrypt(encrypted), plaintext);
});

test("encrypted configuration rejects tampering", () => {
  const cipher = new SecretCipher(Buffer.alloc(32, 9));
  const encrypted = cipher.encrypt("connector-secret-value");
  const parts = encrypted.split(".");
  const ciphertext = Buffer.from(parts[3]!, "base64url");
  ciphertext[0] = ciphertext[0]! ^ 1;
  parts[3] = ciphertext.toString("base64url");
  assert.throws(() => cipher.decrypt(parts.join(".")));
});
