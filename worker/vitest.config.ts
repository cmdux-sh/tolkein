import { cloudflareTest } from "@cloudflare/vitest-plugin"
import { defineConfig } from "vitest/config"

export default defineConfig({
  test: {
    // Daily rows are cleared in beforeEach. Serial files cannot delete each other's rows.
    fileParallelism: false,
  },
  plugins: [
    cloudflareTest({
      wrangler: { configPath: "./wrangler.jsonc" },
      miniflare: {
        bindings: {
          WRITE_TOKEN: "test-write-token",
          READ_TOKEN_PHONE: "test-phone-token",
          READ_TOKEN_ASSISTANT: "test-assistant-token",
        },
      },
    }),
  ],
})
