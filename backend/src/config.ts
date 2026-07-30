import { z } from "zod";

const environmentSchema = z.object({
  NODE_ENV: z.enum(["development", "test", "production"]).default("development"),
  HOST: z.string().min(1).default("127.0.0.1"),
  PORT: z.coerce.number().int().min(1).max(65_535).default(8099),
  LOG_LEVEL: z.enum(["fatal", "error", "warn", "info", "debug", "trace", "silent"]).default("info"),
  SERVICE_VERSION: z.string().min(1).max(100).default("development"),
  PUBLIC_BASE_URL: z.string().url().optional(),
  ERROR_MONITORING_WEBHOOK_URL: z.string().url().optional(),
  COLLECTION_INTERVAL_SECONDS: z.coerce.number().int().min(60).max(3600).default(900),
  DATABASE_URL: z.string().url().refine((value) => value.startsWith("postgresql://") || value.startsWith("postgres://"), {
    message: "DATABASE_URL must use postgres:// or postgresql://",
  }),
  ZOID99_API_TOKEN: z.string().min(32),
  ZOID99_OPERATOR_PASSWORD: z.string().min(8).max(512).optional(),
  SECRETS_ENCRYPTION_KEY: z.string().transform((value, context) => {
    const key = Buffer.from(value, "base64");
    if (key.length !== 32 || key.toString("base64").replace(/=+$/, "") !== value.replace(/=+$/, "")) {
      context.addIssue({ code: "custom", message: "SECRETS_ENCRYPTION_KEY must be exactly 32 base64-encoded bytes" });
      return z.NEVER;
    }
    return key;
  }),
}).superRefine((environment, context) => {
  if (environment.NODE_ENV === "production") {
    if (!environment.PUBLIC_BASE_URL) {
      context.addIssue({
        code: "custom",
        path: ["PUBLIC_BASE_URL"],
        message: "PUBLIC_BASE_URL is required in production",
      });
    } else if (new URL(environment.PUBLIC_BASE_URL).protocol !== "https:") {
      context.addIssue({
        code: "custom",
        path: ["PUBLIC_BASE_URL"],
        message: "PUBLIC_BASE_URL must use HTTPS in production",
      });
    }
    if (!environment.ZOID99_OPERATOR_PASSWORD) {
      context.addIssue({
        code: "custom",
        path: ["ZOID99_OPERATOR_PASSWORD"],
        message: "ZOID99_OPERATOR_PASSWORD is required in production",
      });
    }
    if (
      environment.ERROR_MONITORING_WEBHOOK_URL
      && new URL(environment.ERROR_MONITORING_WEBHOOK_URL).protocol !== "https:"
    ) {
      context.addIssue({
        code: "custom",
        path: ["ERROR_MONITORING_WEBHOOK_URL"],
        message: "ERROR_MONITORING_WEBHOOK_URL must use HTTPS in production",
      });
    }
    const url = new URL(environment.DATABASE_URL);
    const sslMode = url.searchParams.get("sslmode");
    if (!["require", "verify-ca", "verify-full"].includes(sslMode ?? "")) {
      context.addIssue({
        code: "custom",
        path: ["DATABASE_URL"],
        message: "production DATABASE_URL must require TLS with sslmode=require, verify-ca, or verify-full",
      });
    }
  }
});

export type AppConfig = {
  nodeEnv: "development" | "test" | "production";
  host: string;
  port: number;
  logLevel: "fatal" | "error" | "warn" | "info" | "debug" | "trace" | "silent";
  serviceVersion: string;
  publicBaseUrl: string | undefined;
  errorMonitoringWebhookUrl: string | undefined;
  collectionIntervalSeconds: number;
  databaseUrl: string;
  apiToken: string;
  operatorPassword: string | undefined;
  encryptionKey: Buffer;
  authenticationKeys: string[];
};

export function loadConfig(environment: NodeJS.ProcessEnv): AppConfig {
  const parsed = environmentSchema.safeParse(environment);
  if (!parsed.success) {
    const details = parsed.error.issues.map((issue) => `${issue.path.join(".")}: ${issue.message}`).join("; ");
    throw new Error(`Invalid backend configuration: ${details}`);
  }
  const previousKeyName = ["ZOID99", "API", "TOKEN", "PREVIOUS"].join("_");
  const previousAuthenticationKey = environment[previousKeyName];
  if (
    previousAuthenticationKey !== undefined
    && (previousAuthenticationKey.length < 32 || previousAuthenticationKey.length > 512)
  ) {
    throw new Error(`Invalid backend configuration: ${previousKeyName}: must contain 32 to 512 characters`);
  }
  const config = {
    nodeEnv: parsed.data.NODE_ENV,
    host: parsed.data.HOST,
    port: parsed.data.PORT,
    logLevel: parsed.data.LOG_LEVEL,
    serviceVersion: parsed.data.SERVICE_VERSION,
    publicBaseUrl: parsed.data.PUBLIC_BASE_URL,
    errorMonitoringWebhookUrl: parsed.data.ERROR_MONITORING_WEBHOOK_URL,
    collectionIntervalSeconds: parsed.data.COLLECTION_INTERVAL_SECONDS,
    databaseUrl: parsed.data.DATABASE_URL,
    apiToken: parsed.data.ZOID99_API_TOKEN,
    operatorPassword: parsed.data.ZOID99_OPERATOR_PASSWORD,
    encryptionKey: parsed.data.SECRETS_ENCRYPTION_KEY,
  };
  return {
    ...config,
    authenticationKeys: previousAuthenticationKey
      ? [config.apiToken, previousAuthenticationKey]
      : [config.apiToken],
  };
}
