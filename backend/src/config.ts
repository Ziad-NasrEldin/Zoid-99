import { z } from "zod";

const environmentSchema = z.object({
  NODE_ENV: z.enum(["development", "test", "production"]).default("development"),
  HOST: z.string().min(1).default("127.0.0.1"),
  PORT: z.coerce.number().int().min(1).max(65_535).default(8099),
  LOG_LEVEL: z.enum(["fatal", "error", "warn", "info", "debug", "trace", "silent"]).default("info"),
  DATABASE_URL: z.string().url().refine((value) => value.startsWith("postgresql://") || value.startsWith("postgres://"), {
    message: "DATABASE_URL must use postgres:// or postgresql://",
  }),
  ZOID99_API_TOKEN: z.string().min(32),
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
  databaseUrl: string;
  apiToken: string;
  encryptionKey: Buffer;
};

export function loadConfig(environment: NodeJS.ProcessEnv): AppConfig {
  const parsed = environmentSchema.safeParse(environment);
  if (!parsed.success) {
    const details = parsed.error.issues.map((issue) => `${issue.path.join(".")}: ${issue.message}`).join("; ");
    throw new Error(`Invalid backend configuration: ${details}`);
  }
  return {
    nodeEnv: parsed.data.NODE_ENV,
    host: parsed.data.HOST,
    port: parsed.data.PORT,
    logLevel: parsed.data.LOG_LEVEL,
    databaseUrl: parsed.data.DATABASE_URL,
    apiToken: parsed.data.ZOID99_API_TOKEN,
    encryptionKey: parsed.data.SECRETS_ENCRYPTION_KEY,
  };
}
