import type { UsageService, UsageSnapshot, UsageWindow } from "./snapshot"

export const TORONTO = "America/Toronto"
export const RETENTION_DAYS = 400

const USAGE_DROP = 0.001

export interface WindowTrack {
  label: string
  start: number
  end: number
  high: number
  segmentStart: number
  closedUse: number
  reset: boolean
  resetsAtStart?: string
  resetsAtEnd?: string
  windowMinutes?: number
}

export interface CreditTrack {
  start: number
  end: number
  currencyCode?: string
}

export interface ServiceTrack {
  id: string
  name: string
  windows: WindowTrack[]
  credits?: CreditTrack
}

export interface DayTrack {
  services: ServiceTrack[]
}

export interface HistoryWindow {
  label: string
  start: number
  end: number
  change: number
  reset: boolean
  used: number
  resetsAtStart?: string
  resetsAtEnd?: string
  windowMinutes?: number
}

export interface HistoryCredits {
  start: number
  end: number
  used: number
  added: number
  currencyCode?: string
}

export interface HistoryService {
  id: string
  name: string
  windows: HistoryWindow[]
  credits?: HistoryCredits
}

export interface HistoryDay {
  date: string
  startAt: string
  endAt: string
  closed: boolean
  services: HistoryService[]
}

export interface DailyHistoryBody {
  timezone: typeof TORONTO
  from: string
  to: string
  days: HistoryDay[]
}

interface TorontoParts {
  year: string
  month: string
  day: string
  hour: number
  minute: number
}

export function roundPoints(value: number): number {
  return Math.round(value * 10000) / 10000
}

export function torontoParts(instant: Date): TorontoParts {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: TORONTO,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  }).formatToParts(instant)
  let hour = Number(part(parts, "hour"))
  if (hour === 24) hour = 0
  return {
    year: part(parts, "year"),
    month: part(parts, "month"),
    day: part(parts, "day"),
    hour,
    minute: Number(part(parts, "minute")),
  }
}

export function torontoDate(instant: string | number | Date): string {
  const date = instant instanceof Date ? instant : new Date(instant)
  const parts = torontoParts(date)
  return `${parts.year}-${parts.month}-${parts.day}`
}

// Cron Triggers are UTC. Closing uses scheduledTime, the planned instant,
// so a late invocation still sees 23:55 Toronto rather than the delayed clock.
export function isTorontoClose(scheduledTime: number): boolean {
  return torontoParts(new Date(scheduledTime)).hour === 23
}

export function addCalendarDays(isoDate: string, days: number): string {
  const [year, month, day] = isoDate.split("-").map(Number)
  const utc = new Date(Date.UTC(year, month - 1, day + days))
  const nextYear = String(utc.getUTCFullYear())
  const nextMonth = String(utc.getUTCMonth() + 1).padStart(2, "0")
  const nextDay = String(utc.getUTCDate()).padStart(2, "0")
  return `${nextYear}-${nextMonth}-${nextDay}`
}

// Oldest Toronto date that is still kept when `today` is sealed. 400 dates, including today.
export function retentionCutoff(today: string): string {
  return addCalendarDays(today, -(RETENTION_DAYS - 1))
}

export function daysInclusive(from: string, to: string): number {
  const start = Date.parse(`${from}T00:00:00Z`)
  const end = Date.parse(`${to}T00:00:00Z`)
  return Math.round((end - start) / 86_400_000) + 1
}

export function parseDay(value: string | null): string | "invalid" | "missing" {
  if (value === null || value.trim() === "") return "missing"
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return "invalid"
  const [year, month, day] = value.split("-").map(Number)
  const utc = new Date(Date.UTC(year, month - 1, day))
  if (utc.getUTCFullYear() !== year || utc.getUTCMonth() !== month - 1 || utc.getUTCDate() !== day) return "invalid"
  return value
}

export function resolveHistoryRange(input: {
  from: string | null
  to: string | null
  now: Date
}): { from: string; to: string } | { error: "invalid_date" | "invalid_range" | "range_too_large" } {
  const fromParsed = parseDay(input.from)
  const toParsed = parseDay(input.to)
  if (fromParsed === "invalid" || toParsed === "invalid") return { error: "invalid_date" }
  const today = torontoDate(input.now)
  const to = toParsed === "missing" ? today : toParsed
  const from = fromParsed === "missing" ? addCalendarDays(to, -29) : fromParsed
  if (from > to) return { error: "invalid_range" }
  if (daysInclusive(from, to) > RETENTION_DAYS) return { error: "range_too_large" }
  return { from, to }
}

export function createTrack(): DayTrack {
  return { services: [] }
}

export function applySnapshot(track: DayTrack, snapshot: UsageSnapshot): void {
  for (const service of snapshot.services) {
    if (service.windows.length === 0 && !service.credits) continue
    const serviceTrack = findOrCreateService(track, service)
    for (const window of service.windows) applyWindow(serviceTrack, window)
    if (service.credits) applyCredits(serviceTrack, service.credits.remaining, service.credits.currencyCode)
  }
}

export function summarizeTrack(track: DayTrack): HistoryService[] {
  const services: HistoryService[] = []
  for (const service of track.services) {
    const windows = service.windows.map(summarizeWindow)
    const credits = service.credits ? summarizeCredits(service.credits) : undefined
    if (windows.length === 0 && !credits) continue
    const item: HistoryService = { id: service.id, name: service.name, windows }
    if (credits) item.credits = credits
    services.push(item)
  }
  return services
}

export function summarizeWindow(track: WindowTrack): HistoryWindow {
  const change = roundPoints(track.end - track.start)
  // No reset: consumption is the net change. A reset adds the climb before the
  // reset to the ending percent, which stands in for usage since a restart near zero.
  const used = track.reset ? roundPoints(track.closedUse + track.end) : change
  const window: HistoryWindow = {
    label: track.label,
    start: track.start,
    end: track.end,
    change,
    reset: track.reset,
    used,
  }
  if (track.resetsAtStart) window.resetsAtStart = track.resetsAtStart
  if (track.resetsAtEnd) window.resetsAtEnd = track.resetsAtEnd
  if (track.windowMinutes !== undefined) window.windowMinutes = track.windowMinutes
  return window
}

export function summarizeCredits(credits: CreditTrack): HistoryCredits {
  const delta = roundPoints(credits.start - credits.end)
  const summary: HistoryCredits = {
    start: credits.start,
    end: credits.end,
    used: delta > 0 ? delta : 0,
    added: delta < 0 ? roundPoints(-delta) : 0,
  }
  if (credits.currencyCode) summary.currencyCode = credits.currencyCode
  return summary
}

export function toHistoryDay(row: {
  date: string
  start_at: string
  end_at: string
  track_json: string
  closed: number | boolean
}): HistoryDay | null {
  const track = parseTrack(row.track_json)
  if (!track) return null
  return {
    date: row.date,
    startAt: row.start_at,
    endAt: row.end_at,
    closed: Number(row.closed) === 1 || row.closed === true,
    services: summarizeTrack(track),
  }
}

const CSV_HEADER = [
  "date",
  "service_id",
  "service_name",
  "window",
  "start",
  "end",
  "change",
  "reset",
  "used",
  "resets_at_start",
  "resets_at_end",
  "window_minutes",
  "credits_start",
  "credits_end",
  "credits_used",
  "credits_added",
  "currency",
]

export function historyToCsv(days: HistoryDay[]): string {
  const lines = [CSV_HEADER.join(",")]
  for (const day of days) {
    for (const service of day.services) {
      if (service.windows.length === 0) {
        lines.push(csvLine(csvValues(day.date, service, undefined, service.credits)))
        continue
      }
      service.windows.forEach((window, index) => {
        const credits = index === 0 ? service.credits : undefined
        lines.push(csvLine(csvValues(day.date, service, window, credits)))
      })
    }
  }
  return `${lines.join("\n")}\n`
}

export function parseTrack(raw: string): DayTrack | null {
  try {
    const parsed = JSON.parse(raw) as DayTrack
    if (!parsed || !Array.isArray(parsed.services)) return null
    return parsed
  } catch {
    return null
  }
}

function findOrCreateService(track: DayTrack, service: UsageService): ServiceTrack {
  const found = track.services.find((item) => item.id === service.id)
  if (found) {
    found.name = service.name
    return found
  }
  const created: ServiceTrack = { id: service.id, name: service.name, windows: [] }
  track.services.push(created)
  return created
}

function applyWindow(service: ServiceTrack, window: UsageWindow): void {
  const key = window.label.toLowerCase()
  const existing = service.windows.find((item) => item.label.toLowerCase() === key)
  if (!existing) {
    const created: WindowTrack = {
      label: window.label,
      start: window.usedPercent,
      end: window.usedPercent,
      high: window.usedPercent,
      segmentStart: window.usedPercent,
      closedUse: 0,
      reset: false,
    }
    if (window.resetsAt) {
      created.resetsAtStart = window.resetsAt
      created.resetsAtEnd = window.resetsAt
    }
    if (window.windowMinutes !== undefined) created.windowMinutes = window.windowMinutes
    service.windows.push(created)
    return
  }
  if (isReset(existing, window)) {
    existing.closedUse += existing.high - existing.segmentStart
    existing.segmentStart = window.usedPercent
    existing.high = window.usedPercent
    existing.reset = true
  } else if (window.usedPercent > existing.high) {
    existing.high = window.usedPercent
  }
  existing.end = window.usedPercent
  if (window.resetsAt) existing.resetsAtEnd = window.resetsAt
  if (window.windowMinutes !== undefined) existing.windowMinutes = window.windowMinutes
}

// resetsAt moving forward means the window restarted. A lower percent does too:
// the highest reading before that drop is the value before the reset.
function isReset(track: WindowTrack, window: UsageWindow): boolean {
  if (track.end - window.usedPercent > USAGE_DROP) return true
  if (!window.resetsAt || !track.resetsAtEnd) return false
  const next = Date.parse(window.resetsAt)
  const previous = Date.parse(track.resetsAtEnd)
  return Number.isFinite(next) && Number.isFinite(previous) && next > previous
}

function applyCredits(service: ServiceTrack, remaining: number, currencyCode: string | undefined): void {
  if (!service.credits) {
    const credits: CreditTrack = { start: remaining, end: remaining }
    if (currencyCode) credits.currencyCode = currencyCode
    service.credits = credits
    return
  }
  service.credits.end = remaining
  if (currencyCode) service.credits.currencyCode = currencyCode
}

function csvValues(
  date: string,
  service: HistoryService,
  window: HistoryWindow | undefined,
  credits: HistoryCredits | undefined,
): Array<string | number | boolean | undefined> {
  return [
    date,
    service.id,
    service.name,
    window?.label,
    window?.start,
    window?.end,
    window?.change,
    window ? window.reset : undefined,
    window?.used,
    window?.resetsAtStart,
    window?.resetsAtEnd,
    window?.windowMinutes,
    credits?.start,
    credits?.end,
    credits?.used,
    credits?.added,
    credits?.currencyCode,
  ]
}

function csvLine(values: Array<string | number | boolean | undefined>): string {
  return values.map(csvField).join(",")
}

function csvField(value: string | number | boolean | undefined): string {
  if (value === undefined) return ""
  const text = String(value)
  if (/[",\n\r]/.test(text)) return `"${text.replace(/"/g, '""')}"`
  return text
}

function part(parts: Intl.DateTimeFormatPart[], type: string): string {
  const value = parts.find((item) => item.type === type)?.value
  if (!value) throw new Error(`missing ${type} in Toronto time`)
  return value
}
