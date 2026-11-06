import { createExecutionContext, createScheduledController, waitOnExecutionContext } from "cloudflare:test"
import { env } from "cloudflare:workers"
import { beforeEach, describe, expect, it } from "vitest"
import {
  addCalendarDays,
  applySnapshot,
  createTrack,
  historyToCsv,
  isTorontoClose,
  resolveHistoryRange,
  retentionCutoff,
  summarizeCredits,
  summarizeTrack,
  torontoDate,
  torontoParts,
} from "../src/daily"
import { ensureDailySchema } from "../src/daily-store"
import worker from "../src/index"
import { parseSnapshot, type UsageSnapshot } from "../src/snapshot"

const WRITE = "test-write-token"
const PHONE = "test-phone-token"
const ASSISTANT = "test-assistant-token"

describe("daily change math", () => {
  it("uses end minus start when the window does not reset", () => {
    const track = fold([
      point("2026-10-26T04:08:00Z", 20),
      point("2026-10-26T15:00:00Z", 31),
      point("2026-10-27T03:50:00Z", 47),
    ])
    expect(summarizeTrack(track)[0]?.windows[0]).toMatchObject({
      start: 20,
      end: 47,
      change: 27,
      reset: false,
      used: 27,
    })
  })

  it("counts a drop as a reset and adds the pre-reset climb to the end", () => {
    const track = fold([
      point("2026-10-26T04:08:00Z", 10, "2026-10-26T09:00:00Z"),
      point("2026-10-26T15:00:00Z", 80, "2026-10-26T09:00:00Z"),
      point("2026-10-27T03:50:00Z", 12, "2026-10-26T14:00:00Z"),
    ])
    expect(summarizeTrack(track)[0]?.windows[0]).toMatchObject({
      start: 10,
      end: 12,
      change: 2,
      reset: true,
      used: 82,
    })
  })

  it("adds every finished stretch when the window resets twice", () => {
    const track = fold([
      point("2026-10-26T04:00:00Z", 10),
      point("2026-10-26T08:00:00Z", 40),
      point("2026-10-26T12:00:00Z", 5),
      point("2026-10-26T16:00:00Z", 35),
      point("2026-10-26T20:00:00Z", 8),
    ])
    expect(summarizeTrack(track)[0]?.windows[0]).toMatchObject({
      start: 10,
      end: 8,
      change: -2,
      reset: true,
      used: 68,
    })
  })

  it("counts a later resetsAt as a reset even when usage rose", () => {
    const track = fold([
      point("2026-10-26T04:00:00Z", 30, "2026-10-26T12:00:00Z"),
      point("2026-10-26T18:00:00Z", 55, "2026-10-27T12:00:00Z"),
    ])
    expect(summarizeTrack(track)[0]?.windows[0]).toMatchObject({
      start: 30,
      end: 55,
      change: 25,
      reset: true,
      used: 55,
    })
  })

  it("treats a few minutes of resetsAt drift as the same window", () => {
    const track = fold([
      point("2026-10-26T04:00:00Z", 50, "2026-10-26T12:00:00Z"),
      point("2026-10-26T04:10:00Z", 51, "2026-10-26T12:00:07Z"),
      point("2026-10-26T04:20:00Z", 52, "2026-10-26T12:04:00Z"),
    ])
    expect(summarizeTrack(track)[0]?.windows[0]).toMatchObject({ reset: false, change: 2, used: 2 })
  })

  it("treats a dip under one point as noise and never reports negative use", () => {
    const track = fold([point("2026-10-26T04:00:00Z", 50), point("2026-10-26T05:00:00Z", 49.6)])
    expect(summarizeTrack(track)[0]?.windows[0]).toMatchObject({ reset: false, change: -0.4, used: 0 })
  })

  it("ignores a sub-thousandth dip and rounds a tenth of a point", () => {
    const flat = fold([point("2026-10-26T04:00:00Z", 20), point("2026-10-26T05:00:00Z", 19.9995)])
    expect(summarizeTrack(flat)[0]?.windows[0]).toMatchObject({ reset: false, change: -0.0005 })
    const climbed = fold([point("2026-10-26T04:00:00Z", 0.1), point("2026-10-26T05:00:00Z", 0.3)])
    expect(summarizeTrack(climbed)[0]?.windows[0]).toMatchObject({ reset: false, change: 0.2, used: 0.2 })
  })

  it("reports credits spent, or credits added when the balance rises", () => {
    expect(summarizeCredits({ start: 40, end: 28, currencyCode: "USD" })).toEqual({
      start: 40,
      end: 28,
      used: 12,
      added: 0,
      currencyCode: "USD",
    })
    expect(summarizeCredits({ start: 10, end: 25 })).toEqual({ start: 10, end: 25, used: 0, added: 15 })
    expect(summarizeCredits({ start: 10.25, end: 8.1, currencyCode: "USD" }).used).toBe(2.15)
  })

  it("puts service credits on the first CSV row only and escapes commas", () => {
    const track = createTrack()
    applySnapshot(
      track,
      snapshot("2026-10-26T04:00:00Z", [
        {
          id: "claude",
          name: "Claude, Max",
          windows: [
            { label: "Weekly", usedPercent: 1 },
            { label: "Session", usedPercent: 2 },
          ],
          credits: { remaining: 9, currencyCode: "USD" },
        },
      ]),
    )
    const csv = historyToCsv([
      {
        date: "2026-10-26",
        startAt: "2026-10-26T04:00:00Z",
        endAt: "2026-10-26T04:00:00Z",
        closed: false,
        services: summarizeTrack(track),
      },
    ])
    const lines = csv.trim().split("\n")
    expect(lines[1]).toContain('"Claude, Max"')
    expect(lines[1]).toContain(",9,9,0,0,USD")
    expect(lines[2]?.endsWith(",,,,")).toBe(true)
  })

  it("defuses names a spreadsheet would run as a formula", () => {
    const track = fold([
      snapshot("2026-10-26T04:00:00Z", [{ id: "x", name: "=HYPERLINK(1)", windows: [{ label: "-Weekly", usedPercent: 5 }] }]),
    ])
    const csv = historyToCsv([
      { date: "2026-10-26", startAt: "2026-10-26T04:00:00Z", endAt: "2026-10-26T04:00:00Z", closed: false, services: summarizeTrack(track) },
    ])
    const row = csv.trim().split("\n")[1] ?? ""
    expect(row).toContain(",'=HYPERLINK(1),'-Weekly,")
  })
})

describe("Toronto day boundary", () => {
  it("keys the day in America/Toronto, including both sides of midnight", () => {
    expect(torontoDate("2026-10-26T03:59:59Z")).toBe("2026-10-25")
    expect(torontoDate("2026-10-26T04:00:00Z")).toBe("2026-10-26")
    expect(torontoDate("2026-01-16T04:59:59Z")).toBe("2026-01-15")
    expect(torontoDate("2026-01-16T05:00:00Z")).toBe("2026-01-16")
  })

  it("closes only when the planned instant is 23:xx in Toronto", () => {
    expect(torontoParts(new Date("2026-07-16T03:55:00Z")).hour).toBe(23)
    expect(isTorontoClose(Date.parse("2026-07-16T03:55:00Z"))).toBe(true)
    expect(isTorontoClose(Date.parse("2026-07-16T04:55:00Z"))).toBe(false)
    expect(isTorontoClose(Date.parse("2026-01-16T04:55:00Z"))).toBe(true)
    expect(isTorontoClose(Date.parse("2026-01-16T03:55:00Z"))).toBe(false)
    expect(isTorontoClose(Date.parse("2026-11-02T04:55:00Z"))).toBe(true)
    expect(isTorontoClose(Date.parse("2026-11-02T03:55:00Z"))).toBe(false)
    expect(isTorontoClose(Date.parse("2026-03-09T03:55:00Z"))).toBe(true)
    expect(isTorontoClose(Date.parse("2026-03-09T04:55:00Z"))).toBe(false)
  })

  it("keeps 400 dates and steps across month ends", () => {
    expect(retentionCutoff("2026-01-15")).toBe("2024-12-12")
    expect(addCalendarDays("2026-03-01", -1)).toBe("2026-02-28")
    expect(addCalendarDays("2024-03-01", -1)).toBe("2024-02-29")
    expect(resolveHistoryRange({ from: "2026-02-31", to: "2026-03-01", now: new Date() })).toEqual({
      error: "invalid_date",
    })
    expect(resolveHistoryRange({ from: "2026-10-27", to: "2026-10-26", now: new Date() })).toEqual({
      error: "invalid_range",
    })
    expect(resolveHistoryRange({ from: null, to: "2026-10-26", now: new Date("2026-10-27T12:00:00Z") })).toEqual({
      from: "2026-09-27",
      to: "2026-10-26",
    })
  })
})

describe("daily history endpoints", () => {
  beforeEach(async () => {
    await env.USAGE.delete("v1")
    await ensureDailySchema(env.HISTORY)
    await env.HISTORY.prepare("DELETE FROM daily_usage").run()
  })

  it("records the first snapshot after Toronto midnight and seals the day at 23:55", async () => {
    await post(readmeSnapshots[0])
    await post(readmeSnapshots[1])
    await post(readmeSnapshots[2])

    const open = await history("2026-10-26", "2026-10-26")
    expect(open.days[0]?.closed).toBe(false)
    expect(open.days[0]?.startAt).toBe("2026-10-26T04:08:00Z")
    expect(open.days[0]?.endAt).toBe("2026-10-27T03:50:00Z")

    await runCron("55 4 * * *", "2026-10-27T04:55:00Z")
    expect((await history("2026-10-26", "2026-10-26")).days[0]?.closed).toBe(false)

    await runCron("55 3 * * *", "2026-10-27T03:55:00Z")
    const body = await history("2026-10-26", "2026-10-26")
    expect(body).toEqual({
      timezone: "America/Toronto",
      from: "2026-10-26",
      to: "2026-10-26",
      days: [
        {
          date: "2026-10-26",
          startAt: "2026-10-26T04:08:00Z",
          endAt: "2026-10-27T03:50:00Z",
          closed: true,
          services: [
            {
              id: "claude",
              name: "Claude",
              windows: [
                {
                  label: "Weekly",
                  start: 20,
                  end: 47,
                  change: 27,
                  reset: false,
                  used: 27,
                  resetsAtStart: "2026-11-01T04:00:00Z",
                  resetsAtEnd: "2026-11-01T04:00:00Z",
                  windowMinutes: 10080,
                },
                {
                  label: "Session",
                  start: 10,
                  end: 12,
                  change: 2,
                  reset: true,
                  used: 82,
                  resetsAtStart: "2026-10-26T09:00:00Z",
                  resetsAtEnd: "2026-10-26T14:00:00Z",
                  windowMinutes: 300,
                },
              ],
            },
            {
              id: "codex",
              name: "Codex",
              windows: [
                { label: "Weekly", start: 15, end: 33, change: 18, reset: false, used: 18, windowMinutes: 10080 },
              ],
              credits: { start: 40, end: 28, used: 12, added: 0, currencyCode: "USD" },
            },
          ],
        },
      ],
    })

    const csv = await call("/v1/history.csv?from=2026-10-26&to=2026-10-26", { headers: auth(ASSISTANT) })
    expect(csv.headers.get("content-type")).toContain("text/csv")
    expect(csv.headers.get("cache-control")).toBe("no-store")
    const lines = (await csv.text()).trim().split("\n")
    expect(lines[0]).toBe(
      "date,service_id,service_name,window,start,end,change,reset,used,resets_at_start,resets_at_end,window_minutes,credits_start,credits_end,credits_used,credits_added,currency",
    )
    expect(lines[2]).toContain(",Session,10,12,2,true,82,")
    expect(lines[3]).toContain(",40,28,12,0,USD")
    expect(lines[2]).not.toContain(",40,28,")

    const usage = (await (await call("/v1/usage", { headers: auth(PHONE) })).json()) as UsageSnapshot
    expect(usage.generatedAt).toBe("2026-10-27T03:50:00Z")
    expect(usage.services[0]?.windows[0]?.usedPercent).toBe(47)
    expect(JSON.stringify(usage)).not.toContain('"closed"')
    expect(JSON.stringify(usage)).not.toContain('"days"')

    const rolling = (await (await call("/v1/history?limit=10", { headers: auth(PHONE) })).json()) as {
      history: Array<{ generatedAt: string }>
    }
    expect(rolling.history.map((entry) => entry.generatedAt)).toEqual([
      "2026-10-26T04:08:00Z",
      "2026-10-26T15:00:00Z",
      "2026-10-27T03:50:00Z",
    ])
    const keys = await env.USAGE.list()
    expect(keys.keys.map((key) => key.name)).toEqual(["v1"])
  })

  it("splits the UTC date across Toronto midnight", async () => {
    await post(snapshot("2026-10-26T03:50:00Z", [{ id: "claude", name: "Claude", windows: [{ label: "Weekly", usedPercent: 90 }] }]))
    await post(snapshot("2026-10-26T04:10:00Z", [{ id: "claude", name: "Claude", windows: [{ label: "Weekly", usedPercent: 5 }] }]))
    const body = await history("2026-10-25", "2026-10-26")
    expect(body.days.map((day) => [day.date, day.services[0]?.windows[0]?.start, day.services[0]?.windows[0]?.end])).toEqual([
      ["2026-10-25", 90, 90],
      ["2026-10-26", 5, 5],
    ])
  })

  it("seals during standard time and ignores an older snapshot", async () => {
    await post(snapshot("2026-01-16T03:00:00Z", [{ id: "claude", name: "Claude", windows: [{ label: "Weekly", usedPercent: 40 }] }]))
    await post(snapshot("2026-01-16T02:00:00Z", [{ id: "claude", name: "Claude", windows: [{ label: "Weekly", usedPercent: 1 }] }]))
    await runCron("55 3 * * *", "2026-01-16T03:55:00Z")
    expect((await history("2026-01-15", "2026-01-15")).days[0]?.closed).toBe(false)
    await runCron("55 4 * * *", "2026-01-16T04:55:00Z")
    const day = (await history("2026-01-15", "2026-01-15")).days[0]
    expect(day?.closed).toBe(true)
    expect(day?.services[0]?.windows[0]).toMatchObject({ start: 40, end: 40, used: 0, reset: false })
  })

  it("seals the fall-back and spring-forward dates at local 23:55", async () => {
    await post(snapshot("2026-11-01T23:00:00Z", [{ id: "claude", name: "Claude", windows: [{ label: "Weekly", usedPercent: 11 }] }]))
    await runCron("55 3 * * *", "2026-11-02T03:55:00Z")
    expect((await history("2026-11-01", "2026-11-01")).days[0]?.closed).toBe(false)
    await runCron("55 4 * * *", "2026-11-02T04:55:00Z")
    expect((await history("2026-11-01", "2026-11-01")).days[0]?.closed).toBe(true)

    await post(snapshot("2026-03-08T22:00:00Z", [{ id: "claude", name: "Claude", windows: [{ label: "Weekly", usedPercent: 22 }] }]))
    await runCron("55 3 * * *", "2026-03-09T03:55:00Z")
    expect((await history("2026-03-08", "2026-03-08")).days[0]?.closed).toBe(true)
    await runCron("55 4 * * *", "2026-03-09T04:55:00Z")
    expect((await history("2026-03-09", "2026-03-09")).days).toEqual([])
  })

  it("keeps 400 days and drops the older one on the close", async () => {
    await post(snapshot("2024-12-11T17:00:00Z", [{ id: "claude", name: "Claude", windows: [{ label: "Weekly", usedPercent: 1 }] }]))
    await post(snapshot("2024-12-12T17:00:00Z", [{ id: "claude", name: "Claude", windows: [{ label: "Weekly", usedPercent: 2 }] }]))
    await runCron("55 3 * * *", "2026-01-16T03:55:00Z")
    expect((await history("2024-12-11", "2024-12-12")).days).toHaveLength(2)
    await runCron("55 4 * * *", "2026-01-16T04:55:00Z")
    const kept = await history("2024-12-11", "2024-12-12")
    expect(kept.days.map((day) => day.date)).toEqual(["2024-12-12"])
    expect(kept.days[0]?.closed).toBe(true)
  })

  it("rejects bad ranges and missing tokens, and defaults a partial range", async () => {
    expect((await call("/v1/history?from=2026-10-01&to=2026-10-02")).status).toBe(401)
    expect((await call("/v1/history.csv", { headers: auth(WRITE) })).status).toBe(401)
    expect((await call("/v1/history?from=2026-10-26", { method: "POST", headers: auth(PHONE) })).status).toBe(405)
    expect((await call("/v1/history.csv", { method: "POST", headers: auth(PHONE) })).status).toBe(405)
    expect((await (await call("/v1/history?from=2026-02-31&to=2026-03-01", { headers: auth(PHONE) })).json())).toEqual({
      error: "invalid_date",
    })
    expect((await (await call("/v1/history?from=2026-10-02&to=2026-10-01", { headers: auth(PHONE) })).json())).toEqual({
      error: "invalid_range",
    })
    expect((await (await call("/v1/history?from=2024-01-01&to=2026-01-01", { headers: auth(ASSISTANT) })).json())).toEqual({
      error: "range_too_large",
    })
    const partial = await history(null, "2026-10-26")
    expect(partial.from).toBe("2026-09-27")
    expect(partial.to).toBe("2026-10-26")
    const csv = await call("/v1/history.csv?from=2020-01-01&to=2020-01-01", { headers: auth(PHONE) })
    expect(await csv.text()).toBe(
      "date,service_id,service_name,window,start,end,change,reset,used,resets_at_start,resets_at_end,window_minutes,credits_start,credits_end,credits_used,credits_added,currency\n",
    )
  })
})

const readmeSnapshots = [
  snapshot("2026-10-26T04:08:00Z", [
    {
      id: "claude",
      name: "Claude",
      windows: [
        { label: "Weekly", usedPercent: 20, resetsAt: "2026-11-01T04:00:00Z", windowMinutes: 10080 },
        { label: "Session", usedPercent: 10, resetsAt: "2026-10-26T09:00:00Z", windowMinutes: 300 },
      ],
    },
    {
      id: "codex",
      name: "Codex",
      windows: [{ label: "Weekly", usedPercent: 15, windowMinutes: 10080 }],
      credits: { remaining: 40, currencyCode: "USD" },
    },
  ]),
  snapshot("2026-10-26T15:00:00Z", [
    {
      id: "claude",
      name: "Claude",
      windows: [
        { label: "Weekly", usedPercent: 31, resetsAt: "2026-11-01T04:00:00Z", windowMinutes: 10080 },
        { label: "Session", usedPercent: 80, resetsAt: "2026-10-26T09:00:00Z", windowMinutes: 300 },
      ],
    },
    {
      id: "codex",
      name: "Codex",
      windows: [{ label: "Weekly", usedPercent: 20, windowMinutes: 10080 }],
      credits: { remaining: 36, currencyCode: "USD" },
    },
  ]),
  snapshot("2026-10-27T03:50:00Z", [
    {
      id: "claude",
      name: "Claude",
      windows: [
        { label: "Weekly", usedPercent: 47, resetsAt: "2026-11-01T04:00:00Z", windowMinutes: 10080 },
        { label: "Session", usedPercent: 12, resetsAt: "2026-10-26T14:00:00Z", windowMinutes: 300 },
      ],
    },
    {
      id: "codex",
      name: "Codex",
      windows: [{ label: "Weekly", usedPercent: 33, windowMinutes: 10080 }],
      credits: { remaining: 28, currencyCode: "USD" },
    },
  ]),
]

interface WindowInput {
  label: string
  usedPercent: number
  resetsAt?: string
  windowMinutes?: number
}

interface ServiceInput {
  id: string
  name: string
  windows: WindowInput[]
  credits?: { remaining: number; currencyCode?: string }
}

function point(generatedAt: string, usedPercent: number, resetsAt?: string): UsageSnapshot {
  return snapshot(generatedAt, [{ id: "claude", name: "Claude", windows: [{ label: "Weekly", usedPercent, resetsAt }] }])
}

function fold(samples: UsageSnapshot[]) {
  const track = createTrack()
  for (const sample of samples) applySnapshot(track, sample)
  return track
}

function snapshot(generatedAt: string, services: ServiceInput[]) {
  return parseSnapshot({
    schemaVersion: 1,
    generatedAt,
    services: services.map((service) => ({
      id: service.id,
      name: service.name,
      windows: service.windows,
      source: service.id,
      fetchedAt: generatedAt,
      credits: service.credits,
    })),
  })
}

function auth(token: string): HeadersInit {
  return { Authorization: `Bearer ${token}` }
}

async function post(body: UsageSnapshot) {
  const response = await call("/v1/snapshot", {
    method: "POST",
    headers: auth(WRITE),
    body: JSON.stringify(body),
  })
  expect(response.status).toBe(200)
}

async function history(from: string | null, to: string) {
  const params = new URLSearchParams()
  if (from) params.set("from", from)
  params.set("to", to)
  const response = await call(`/v1/history?${params}`, { headers: auth(ASSISTANT) })
  expect(response.status).toBe(200)
  return response.json() as Promise<{
    timezone: string
    from: string
    to: string
    days: Array<{
      date: string
      startAt: string
      endAt: string
      closed: boolean
      services: Array<{ id: string; windows: Array<{ start: number; end: number; used: number; reset: boolean }> }>
    }>
  }>
}

async function runCron(cron: string, scheduledTime: string) {
  if (!worker.scheduled) throw new Error("scheduled handler missing")
  const ctx = createExecutionContext()
  await worker.scheduled(createScheduledController({ cron, scheduledTime: Date.parse(scheduledTime) }), env, ctx)
  await waitOnExecutionContext(ctx)
}

async function call(path: string, init?: RequestInit): Promise<Response> {
  return worker.fetch(new Request(`https://tolkeins.test${path}`, init), env)
}
