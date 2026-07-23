import { fileURLToPath } from "node:url";
import { loadConfig } from "./config.js";

export function validateProductionConfig(environment: NodeJS.ProcessEnv): void {
  loadConfig({ ...environment, NODE_ENV: "production" });
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  validateProductionConfig(process.env);
  process.stdout.write("Production configuration is valid.\n");
}
