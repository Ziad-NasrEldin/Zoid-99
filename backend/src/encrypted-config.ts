import type { EncryptedConfigStore } from "./repository.js";
import { SecretCipher } from "./security.js";

export class EncryptedConfigService {
  constructor(
    private readonly store: EncryptedConfigStore,
    private readonly cipher: SecretCipher,
  ) {}

  async set(key: string, plaintext: string): Promise<void> {
    await this.store.set(key, this.cipher.encrypt(plaintext));
  }

  async get(key: string): Promise<string | null> {
    const encrypted = await this.store.get(key);
    return encrypted === null ? null : this.cipher.decrypt(encrypted);
  }
}
