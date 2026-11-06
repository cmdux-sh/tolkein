import { authorize } from "./auth"
import { historyToCsv, resolveHistoryRange, TORONTO } from "./daily"
import { listDailyHistory, recordDailySnapshot, runDailyClose } from "./daily-store"
import { parseSnapshot, SnapshotError } from "./snapshot"
import { historyLimit, nextDocument, SNAPSHOT_KEY, type StoredDocument } from "./store"

const MAX_BYTES = 100_000

export default {
  async fetch(request, env): Promise<Response> {
    try {
      return await route(request, env)
    } catch (error) {
      const message = error instanceof Error ? error.message : "unknown error"
      console.error(JSON.stringify({ message: "unhandled error", error: message, path: pathOf(request) }))
      return json({ error: "internal_error" }, 500)
    }
  },
  async scheduled(controller, env, _ctx): Promise<void> {
    try {
      const document = await readDocument(env)
      const result = await runDailyClose(env.HISTORY, controller.scheduledTime, document?.latest ?? null)
      console.log(
        JSON.stringify({
          message: result.acted ? "daily close" : "daily close skipped",
          cron: controller.cron,
          scheduledTime: new Date(controller.scheduledTime).toISOString(),
          date: result.date,
          closed: result.closed,
          sealed: result.sealed,
          pruned: result.pruned,
        }),
      )
    } catch (error) {
      const message = error instanceof Error ? error.message : "unknown error"
      console.error(JSON.stringify({ message: "daily close failed", error: message, cron: controller.cron }))
      throw error
    }
  },
} satisfies ExportedHandler<Env>

async function route(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url)
  if (request.method === "GET" && url.pathname === "/health") return json({ ok: true })
  if (url.pathname === "/v1/snapshot") return postSnapshot(request, env)
  if (url.pathname === "/v1/usage") return getUsage(request, env)
  if (url.pathname === "/v1/history.csv") return getHistoryCsv(request, env, url)
  if (url.pathname === "/v1/history") return getHistory(request, env, url)
  return json({ error: "not_found" }, 404)
}

async function postSnapshot(request: Request, env: Env): Promise<Response> {
  if (request.method !== "POST") return json({ error: "method_not_allowed" }, 405)
  const auth = await authorize(request, [env.WRITE_TOKEN ?? ""])
  if (auth === "misconfigured") return json({ error: "server_misconfigured" }, 500)
  if (auth !== "ok") return json({ error: "unauthorized" }, 401)
  const body = await readBounded(request)
  if (body instanceof Response) return body
  let parsed: unknown
  try {
    parsed = JSON.parse(new TextDecoder().decode(body))
  } catch {
    return json({ error: "invalid_json" }, 400)
  }
  let snapshot
  try {
    snapshot = parseSnapshot(parsed)
  } catch (error) {
    const reason = error instanceof SnapshotError ? error.message : "invalid snapshot"
    console.error(JSON.stringify({ message: "snapshot rejected", path: "/v1/snapshot", reason }))
    return json({ error: "invalid_snapshot", reason }, 400)
  }
  // Await the KV put so a failed write is a 500, not a lost snapshot.
  // The daily row is separate: a failed history write must not pretend the day was recorded.
  await storeSnapshot(env, snapshot, historyLimit(env.HISTORY_LIMIT))
  await recordDailySnapshot(env.HISTORY, snapshot)
  return json({ ok: true, generatedAt: snapshot.generatedAt })
}

async function storeSnapshot(env: Env, snapshot: ReturnType<typeof parseSnapshot>, limit: number): Promise<void> {
  const current = await readDocument(env)
  const next = nextDocument(current, snapshot, limit)
  await env.USAGE.put(SNAPSHOT_KEY, JSON.stringify(next))
}

async function getUsage(request: Request, env: Env): Promise<Response> {
  if (request.method !== "GET") return json({ error: "method_not_allowed" }, 405)
  const auth = await readAuth(request, env)
  if (auth instanceof Response) return auth
  const document = await readDocument(env)
  if (!document) return json({ error: "no_snapshot" }, 404)
  return json(document.latest)
}

async function getHistory(request: Request, env: Env, url: URL): Promise<Response> {
  if (request.method !== "GET") return json({ error: "method_not_allowed" }, 405)
  const auth = await readAuth(request, env)
  if (auth instanceof Response) return auth
  if (url.searchParams.has("from") || url.searchParams.has("to")) return dailyHistory(env, url, "json")
  const document = await readDocument(env)
  const history = document?.history ?? []
  const sliced = sliceHistory(history, url.searchParams.get("limit"))
  if (sliced === "invalid") return json({ error: "invalid_limit" }, 400)
  return json({ history: sliced })
}

async function getHistoryCsv(request: Request, env: Env, url: URL): Promise<Response> {
  if (request.method !== "GET") return json({ error: "method_not_allowed" }, 405)
  const auth = await readAuth(request, env)
  if (auth instanceof Response) return auth
  return dailyHistory(env, url, "csv")
}

async function dailyHistory(env: Env, url: URL, format: "json" | "csv"): Promise<Response> {
  const range = resolveHistoryRange({
    from: url.searchParams.get("from"),
    to: url.searchParams.get("to"),
    now: new Date(),
  })
  if ("error" in range) return json({ error: range.error }, 400)
  const days = await listDailyHistory(env.HISTORY, range.from, range.to)
  if (format === "csv") {
    return new Response(historyToCsv(days), {
      status: 200,
      headers: {
        "cache-control": "no-store",
        "content-type": "text/csv; charset=utf-8",
        "content-disposition": 'attachment; filename="tolkeins-history.csv"',
      },
    })
  }
  return json({ timezone: TORONTO, from: range.from, to: range.to, days })
}

async function readAuth(request: Request, env: Env): Promise<true | Response> {
  const auth = await authorize(request, [env.READ_TOKEN_PHONE ?? "", env.READ_TOKEN_ASSISTANT ?? ""])
  if (auth === "misconfigured") return json({ error: "server_misconfigured" }, 500)
  if (auth !== "ok") return json({ error: "unauthorized" }, 401)
  return true
}

async function readDocument(env: Env): Promise<StoredDocument | null> {
  const raw = await env.USAGE.get(SNAPSHOT_KEY)
  if (!raw) return null
  try {
    const parsed = JSON.parse(raw) as StoredDocument
    if (!parsed || typeof parsed !== "object" || !parsed.latest) return null
    return parsed
  } catch (error) {
    const message = error instanceof Error ? error.message : "bad document"
    console.error(JSON.stringify({ message: "stored document unreadable", error: message }))
    return null
  }
}

async function readBounded(request: Request): Promise<Uint8Array | Response> {
  const declared = request.headers.get("content-length")
  if (declared && Number(declared) > MAX_BYTES) return json({ error: "payload_too_large" }, 413)
  if (!request.body) return new Uint8Array()
  const reader = request.body.getReader()
  const chunks: Uint8Array[] = []
  let total = 0
  while (true) {
    const next = await reader.read()
    if (next.done) break
    total += next.value.byteLength
    if (total > MAX_BYTES) {
      await reader.cancel()
      return json({ error: "payload_too_large" }, 413)
    }
    chunks.push(next.value)
  }
  const body = new Uint8Array(total)
  let offset = 0
  for (const chunk of chunks) {
    body.set(chunk, offset)
    offset += chunk.byteLength
  }
  return body
}

function json(body: unknown, status = 200): Response {
  return Response.json(body, {
    status,
    headers: { "cache-control": "no-store" },
  })
}

function sliceHistory<T>(history: T[], raw: string | null): T[] | "invalid" {
  if (raw === null || raw.trim() === "") return history.slice(-200)
  const requested = Number(raw)
  if (!Number.isInteger(requested) || requested < 0 || requested > 200) return "invalid"
  if (requested === 0) return []
  return history.slice(-requested)
}

function pathOf(request: Request): string {
  return new URL(request.url).pathname
}
