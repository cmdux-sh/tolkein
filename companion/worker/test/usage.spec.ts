import { env } from "cloudflare:workers"
import { beforeEach, describe, expect, it } from "vitest"
import { authorize, tokensMatch } from "../src/auth"
import worker from "../src/index"
import { parseSnapshot } from "../src/snapshot"
import { nextDocument } from "../src/store"

const WRITE = "test-write-token"
const PHONE = "test-phone-token"
const ASSISTANT = "test-assistant-token"

describe("auth", () => {
  it("matches equal tokens and rejects different lengths", async () => {
    expect(await tokensMatch("abc", "abc")).toBe(true)
    expect(await tokensMatch("abc", "abcd")).toBe(false)
    expect(await tokensMatch("abc", "abd")).toBe(false)
  })

  it("fails closed when no secret is configured", async () => {
    const request = new Request("https://tolkeins.test/v1/usage", {
      headers: { Authorization: `Bearer ${PHONE}` },
    })
    expect(await authorize(request, ["", "  "])).toBe("misconfigured")
    expect(await authorize(new Request("https://tolkeins.test/v1/usage"), [PHONE])).toBe("unauthorized")
  })
})

describe("snapshot document", () => {
  it("caps history and replaces a duplicate timestamp", () => {
    const first = sample({ generatedAt: "2026-10-24T05:00:00Z", used: 10 })
    const second = sample({ generatedAt: "2026-10-24T05:10:00Z", used: 20 })
    const third = sample({ generatedAt: "2026-10-24T05:20:00Z", used: 30 })
    const capped = [first, second, third].reduce<ReturnType<typeof nextDocument> | null>(
      (document, snapshot) => nextDocument(document, snapshot, 2),
      null,
    )
    expect(capped?.history.map((entry) => entry.generatedAt)).toEqual([
      "2026-10-24T05:10:00Z",
      "2026-10-24T05:20:00Z",
    ])
    const retried = nextDocument(capped, sample({ generatedAt: "2026-10-24T05:20:00Z", used: 31 }), 2)
    expect(retried.history).toHaveLength(2)
    expect(retried.history[1]?.services[0]?.windows[0]?.usedPercent).toBe(31)
  })

  it("drops identity fields while keeping usage", () => {
    const snapshot = parseSnapshot({
      schemaVersion: 1,
      generatedAt: "2026-10-24T05:22:00Z",
      services: [
        {
          id: "claude",
          name: "Claude",
          accountEmail: "person@example.com",
          identity: { accountEmail: "person@example.com" },
          plan: "Max",
          windows: [{ label: "Weekly", usedPercent: 47, resetsAt: "2026-10-25T00:00:00Z", windowMinutes: 10080 }],
          source: "claude",
          fetchedAt: "2026-10-24T05:18:46Z",
          pace: { primary: { summary: "ping person@example.com", expectedUsedPercent: 73 } },
        },
      ],
    })
    const encoded = JSON.stringify(snapshot)
    expect(encoded).not.toContain("accountEmail")
    expect(encoded).not.toContain("example.com")
    expect(snapshot.services[0]?.windows[0]?.usedPercent).toBe(47)
    expect(snapshot.services[0]?.pace?.primary?.summary).toContain("ping")
  })

  it("truncates a long service error instead of rejecting the snapshot", () => {
    const full = `cursor detail ${"x".repeat(400)}`
    const snapshot = parseSnapshot({
      schemaVersion: 1,
      generatedAt: "2026-10-24T05:22:00Z",
      services: [
        {
          id: "cursor",
          name: "Cursor",
          windows: [],
          source: "cursor",
          fetchedAt: "2026-10-24T05:22:00Z",
          error: { message: full, kind: "needs-sign-in" },
        },
        {
          id: "claude",
          name: "Claude",
          windows: [{ label: "Weekly", usedPercent: 12 }],
          source: "claude",
          fetchedAt: "2026-10-24T05:22:00Z",
        },
      ],
    })
    const message = snapshot.services[0]?.error?.message ?? ""
    expect(message.length).toBeLessThanOrEqual(240)
    expect(message.endsWith("...")).toBe(true)
    expect(message.startsWith("cursor detail")).toBe(true)
    expect(snapshot.services[1]?.windows[0]?.usedPercent).toBe(12)
  })
})

describe("worker", () => {
  beforeEach(async () => {
    await env.USAGE.delete("v1")
  })

  it("serves health without a token and hides usage", async () => {
    const response = await call("/health")
    expect(response.status).toBe(200)
    expect(await response.json()).toEqual({ ok: true })
    expect(response.headers.get("cache-control")).toBe("no-store")
  })

  it("rejects missing, query, and wrong-role tokens", async () => {
    expect((await call("/v1/usage")).status).toBe(401)
    expect((await call("/v1/usage?token=" + PHONE)).status).toBe(401)
    expect((await call("/v1/usage", { headers: { Authorization: `Bearer ${WRITE}` } })).status).toBe(401)
    expect((await call("/v1/snapshot", { method: "POST", body: "{}", headers: auth(PHONE) })).status).toBe(401)
    expect((await call("/v1/usage", { headers: { Authorization: "Bearer test-write-token-extra" } })).status).toBe(401)
  })

  it("stores one document and lets both read tokens fetch it", async () => {
    const posted = await call("/v1/snapshot", {
      method: "POST",
      headers: { ...auth(WRITE), "content-type": "application/json" },
      body: JSON.stringify(sample({ generatedAt: "2026-10-24T05:22:00Z", used: 47 })),
    })
    expect(posted.status).toBe(200)
    expect(await posted.json()).toEqual({ ok: true, generatedAt: "2026-10-24T05:22:00Z" })

    const phone = await call("/v1/usage", { headers: auth(PHONE) })
    const assistant = await call("/v1/usage", { headers: auth(ASSISTANT) })
    expect(phone.status).toBe(200)
    expect(assistant.status).toBe(200)
    const body = await phone.json()
    expect(body).toMatchObject({
      schemaVersion: 1,
      services: [{ id: "claude", windows: [{ label: "Weekly", usedPercent: 47 }] }],
    })
    expect(JSON.stringify(body)).not.toContain("accountEmail")

    const stored = await env.USAGE.get("v1")
    expect(stored).toBeTruthy()
    expect(stored).not.toContain("accountEmail")
    expect(stored).not.toContain(WRITE)
    const keys = await env.USAGE.list()
    expect(keys.keys.map((key) => key.name)).toEqual(["v1"])

    const history = await call("/v1/history?limit=10", { headers: auth(ASSISTANT) })
    expect(await history.json()).toEqual({
      history: [{ generatedAt: "2026-10-24T05:22:00Z", services: [{ id: "claude", windows: [{ label: "Weekly", usedPercent: 47 }] }] }],
    })
  })

  it("keeps a rolling history inside the same key", async () => {
    await postAt("2026-10-24T05:00:00Z", 10)
    await postAt("2026-10-24T05:10:00Z", 20)
    const history = await call("/v1/history", { headers: auth(PHONE) })
    const body = (await history.json()) as { history: Array<{ generatedAt: string }> }
    expect(body.history.map((entry) => entry.generatedAt)).toEqual([
      "2026-10-24T05:00:00Z",
      "2026-10-24T05:10:00Z",
    ])
    const keys = await env.USAGE.list()
    expect(keys.keys).toHaveLength(1)
    const latest = (await (await call("/v1/usage", { headers: auth(PHONE) })).json()) as { generatedAt: string }
    expect(latest.generatedAt).toBe("2026-10-24T05:10:00Z")
  })

  it("returns 404 before the first snapshot and 400 for a bad body", async () => {
    expect((await call("/v1/usage", { headers: auth(PHONE) })).status).toBe(404)
    const invalid = await call("/v1/snapshot", {
      method: "POST",
      headers: auth(WRITE),
      body: JSON.stringify({ schemaVersion: 1, generatedAt: "2026-10-24T05:22:00Z", services: [{ id: "claude" }] }),
    })
    expect(invalid.status).toBe(400)
    const notJson = await call("/v1/snapshot", { method: "POST", headers: auth(WRITE), body: "nope" })
    expect(notJson.status).toBe(400)
    expect((await call("/v1/usage", { method: "POST", headers: auth(PHONE) })).status).toBe(405)
    expect((await call("/missing", { headers: auth(PHONE) })).status).toBe(404)
  })

  it("rejects an oversized body", async () => {
    const response = await call("/v1/snapshot", {
      method: "POST",
      headers: { ...auth(WRITE), "content-length": "100001" },
      body: "x".repeat(100001),
    })
    expect(response.status).toBe(413)
  })
})

function auth(token: string): HeadersInit {
  return { Authorization: `Bearer ${token}` }
}

function sample(input: { generatedAt: string; used: number }) {
  return {
    schemaVersion: 1,
    generatedAt: input.generatedAt,
    services: [
      {
        id: "claude",
        name: "Claude",
        plan: "Max",
        windows: [
          {
            label: "Weekly",
            usedPercent: input.used,
            resetsAt: "2026-10-25T00:00:00Z",
            windowMinutes: 10080,
          },
        ],
        source: "claude",
        fetchedAt: input.generatedAt,
        accountEmail: "person@example.com",
      },
    ],
  }
}

async function postAt(generatedAt: string, used: number) {
  const response = await call("/v1/snapshot", {
    method: "POST",
    headers: auth(WRITE),
    body: JSON.stringify(sample({ generatedAt, used })),
  })
  expect(response.status).toBe(200)
}

async function call(path: string, init?: RequestInit): Promise<Response> {
  return worker.fetch(new Request(`https://tolkeins.test${path}`, init), env)
}
