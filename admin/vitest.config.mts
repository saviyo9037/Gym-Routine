import { defineConfig } from "vitest/config";
import path from "node:path";

export default defineConfig({
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "src"),
      // `server-only` throws outside the RSC bundler condition; stub it for unit tests.
      "server-only": path.resolve(__dirname, "src/tests/helpers/empty.ts"),
    },
  },
  test: { environment: "node", include: ["src/tests/**/*.test.ts"], setupFiles: ["src/tests/setup-mocks.ts"] },
});
