import { fixupConfigRules } from "@eslint/compat";
import nextTypescript from "eslint-config-next/typescript";
import nextVitals from "eslint-config-next/core-web-vitals";

const eslintConfig = [
  ...fixupConfigRules(nextVitals),
  ...fixupConfigRules(nextTypescript),
  {
    ignores: [".next/**", "next-env.d.ts", "playwright-report/**", "test-results/**"],
  },
];

export default eslintConfig;
