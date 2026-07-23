import type { EncryptedConfigService } from "./encrypted-config.js";

export const serverProviders = ["google-trends", "ai-provider"] as const;
export type ServerProvider = (typeof serverProviders)[number];
export type ServerConnectionState =
  | "Setup required"
  | "Connected"
  | "Disconnected"
  | "Unavailable"
  | "Delayed"
  | "Rate limited"
  | "Cached"
  | "Unsupported";

export interface ServerConnectionStatus {
  provider: ServerProvider;
  state: ServerConnectionState;
  lastActivity: string | null;
  evidence: string;
  repairAction: string;
  retryAt: string | null;
}

export interface ServerProviderValidator {
  validate(provider: ServerProvider, credential: string): Promise<Omit<ServerConnectionStatus, "provider">>;
}

export class DisabledLiveProviderValidator implements ServerProviderValidator {
  async validate(provider: ServerProvider, _credential: string): Promise<Omit<ServerConnectionStatus, "provider">> {
    return {
      state: "Unavailable",
      lastActivity: null,
      evidence: `Live validation for ${provider} is disabled. Use the explicit opt-in validation runner.`,
      repairAction: "Enable live validation",
      retryAt: null,
    };
  }
}

export class ServerConnectionService {
  private readonly statuses = new Map<ServerProvider, ServerConnectionStatus>();

  constructor(
    private readonly encryptedConfig: EncryptedConfigService,
    private readonly validator: ServerProviderValidator = new DisabledLiveProviderValidator(),
  ) {}

  async list(): Promise<ServerConnectionStatus[]> {
    return Promise.all(serverProviders.map((provider) => this.status(provider)));
  }

  async status(provider: ServerProvider): Promise<ServerConnectionStatus> {
    const recorded = this.statuses.get(provider);
    if (recorded) return recorded;
    const configured = await this.encryptedConfig.has(this.configKey(provider));
    return {
      provider,
      state: configured ? "Cached" : "Setup required",
      lastActivity: null,
      evidence: configured
        ? "An encrypted server credential exists, but it has not been validated in this process."
        : "No encrypted server credential is configured.",
      repairAction: configured ? "Validate again" : "Configure on server",
      retryAt: null,
    };
  }

  async configure(provider: ServerProvider, credential: string): Promise<ServerConnectionStatus> {
    const trimmed = credential.trim();
    if (!trimmed) {
      return {
        provider,
        state: "Setup required",
        lastActivity: null,
        evidence: "A credential is required. Nothing was stored.",
        repairAction: "Configure on server",
        retryAt: null,
      };
    }
    const validation = await this.validator.validate(provider, trimmed);
    if (validation.state === "Connected") await this.encryptedConfig.set(this.configKey(provider), trimmed);
    const status = { provider, ...validation };
    this.statuses.set(provider, status);
    return status;
  }

  async validate(provider: ServerProvider): Promise<ServerConnectionStatus> {
    const credential = await this.encryptedConfig.get(this.configKey(provider));
    if (credential === null) return this.status(provider);
    const result = { provider, ...(await this.validator.validate(provider, credential)) };
    this.statuses.set(provider, result);
    return result;
  }

  async disconnect(provider: ServerProvider): Promise<ServerConnectionStatus> {
    await this.encryptedConfig.remove(this.configKey(provider));
    const result: ServerConnectionStatus = {
      provider,
      state: "Disconnected",
      lastActivity: this.statuses.get(provider)?.lastActivity ?? null,
      evidence: "The encrypted server credential was removed. Previously collected evidence was retained.",
      repairAction: "Configure on server",
      retryAt: null,
    };
    this.statuses.set(provider, result);
    return result;
  }

  private configKey(provider: ServerProvider): string {
    return `provider.${provider}.credential`;
  }
}
