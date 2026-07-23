import { createCipheriv, createDecipheriv, createHash, randomBytes, timingSafeEqual } from "node:crypto";

export function isAuthorized(authorizationHeader: string | undefined, expectedToken: string): boolean {
  if (!authorizationHeader?.startsWith("Bearer ")) return false;
  const suppliedToken = authorizationHeader.slice("Bearer ".length);
  const suppliedDigest = createHash("sha256").update(suppliedToken).digest();
  const expectedDigest = createHash("sha256").update(expectedToken).digest();
  return timingSafeEqual(suppliedDigest, expectedDigest);
}

export class SecretCipher {
  constructor(private readonly key: Buffer) {
    if (key.length !== 32) throw new Error("SecretCipher requires a 32-byte key");
  }

  encrypt(plaintext: string): string {
    const initializationVector = randomBytes(12);
    const cipher = createCipheriv("aes-256-gcm", this.key, initializationVector);
    const ciphertext = Buffer.concat([cipher.update(plaintext, "utf8"), cipher.final()]);
    const tag = cipher.getAuthTag();
    return ["v1", initializationVector.toString("base64url"), tag.toString("base64url"), ciphertext.toString("base64url")].join(".");
  }

  decrypt(envelope: string): string {
    const parts = envelope.split(".");
    if (parts.length !== 4 || parts[0] !== "v1") throw new Error("Unsupported encrypted secret envelope");
    const initializationVector = Buffer.from(parts[1]!, "base64url");
    const tag = Buffer.from(parts[2]!, "base64url");
    const ciphertext = Buffer.from(parts[3]!, "base64url");
    const decipher = createDecipheriv("aes-256-gcm", this.key, initializationVector);
    decipher.setAuthTag(tag);
    return Buffer.concat([decipher.update(ciphertext), decipher.final()]).toString("utf8");
  }
}
