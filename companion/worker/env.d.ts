// Secrets live in Wrangler (`wrangler secret put`), not in wrangler.jsonc, so they
// are merged onto the generated Env. Bindings such as USAGE stay in
// worker-configuration.d.ts and are not repeated here.

interface Env {
  WRITE_TOKEN?: string
  READ_TOKEN_PHONE?: string
  READ_TOKEN_ASSISTANT?: string
}

declare namespace Cloudflare {
  interface Env {
    WRITE_TOKEN?: string
    READ_TOKEN_PHONE?: string
    READ_TOKEN_ASSISTANT?: string
  }
}
