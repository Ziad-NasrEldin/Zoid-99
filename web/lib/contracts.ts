import { apiVersion, bootstrapSchema } from "@zoid99/contracts";

export const webApiVersion = apiVersion;

export function parseBootstrap(input: unknown) {
  return bootstrapSchema.parse(input);
}
