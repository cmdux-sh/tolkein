// Bearer checks hash both sides before comparing so length and contents
// do not leak through a short-circuit. Tokens are Wrangler secrets.

export async function tokensMatch(provided: string, expected: string): Promise<boolean> {
  const encoder = new TextEncoder()
  const [providedHash, expectedHash] = await Promise.all([
    crypto.subtle.digest("SHA-256", encoder.encode(provided)),
    crypto.subtle.digest("SHA-256", encoder.encode(expected)),
  ])
  return crypto.subtle.timingSafeEqual(providedHash, expectedHash)
}

export function bearerToken(request: Request): string | null {
  const header = request.headers.get("Authorization")
  if (!header) return null
  const prefix = "Bearer "
  if (!header.startsWith(prefix)) return null
  const token = header.slice(prefix.length).trim()
  if (!token) return null
  return token
}

export async function authorize(request: Request, candidates: string[]): Promise<"ok" | "unauthorized" | "misconfigured"> {
  const configured = candidates.filter((candidate) => candidate.trim() !== "")
  if (configured.length === 0) return "misconfigured"
  const presented = bearerToken(request)
  if (presented === null) return "unauthorized"
  const checks = await Promise.all(configured.map((candidate) => tokensMatch(presented, candidate)))
  return checks.some(Boolean) ? "ok" : "unauthorized"
}
