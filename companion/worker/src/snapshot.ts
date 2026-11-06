// Rebuild a snapshot from known fields so identity and unknown keys never land in KV.

export interface PaceSide {
  stage?: string
  willLastToReset?: boolean
  expectedUsedPercent?: number
  deltaPercent?: number
  summary?: string
  etaSeconds?: number
}

export interface UsageWindow {
  label: string
  usedPercent: number
  resetsAt?: string
  windowMinutes?: number
}

export interface UsageService {
  id: string
  name: string
  plan?: string
  windows: UsageWindow[]
  pace?: { primary?: PaceSide; secondary?: PaceSide }
  credits?: { remaining: number; currencyCode?: string }
  renewsOn?: string
  price?: { amount: number; currency: string; interval: "month" | "year" }
  source: string
  fetchedAt: string
  error?: { message: string; kind: ErrorKind }
}

export interface UsageSnapshot {
  schemaVersion: 1
  generatedAt: string
  services: UsageService[]
}

export interface CompactEntry {
  generatedAt: string
  services: Array<{
    id: string
    windows: Array<{ label: string; usedPercent: number }>
    error?: { message: string; kind: ErrorKind }
  }>
}

type ErrorKind = "needs-sign-in" | "unavailable" | "collector"

const EMAIL = /[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}/g
const ISO_INSTANT = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$/
const ISO_DAY = /^\d{4}-\d{2}-\d{2}$/
const SERVICE_ID = /^[a-z0-9][a-z0-9-]{0,31}$/
const ERROR_KINDS = new Set<ErrorKind>(["needs-sign-in", "unavailable", "collector"])

export class SnapshotError extends Error {
  constructor(message: string) {
    super(message)
    this.name = "SnapshotError"
  }
}

export function parseSnapshot(input: unknown): UsageSnapshot {
  const record = asRecord(input, "snapshot")
  if (record.schemaVersion !== 1) throw new SnapshotError("schemaVersion must be 1")
  const generatedAt = requireInstant(record.generatedAt, "generatedAt")
  if (!Array.isArray(record.services)) throw new SnapshotError("services must be an array")
  if (record.services.length > 24) throw new SnapshotError("services exceeds 24")
  const seen = new Set<string>()
  const services = record.services.map((service, index) => parseService(service, index, seen))
  return { schemaVersion: 1, generatedAt, services }
}

export function compactSnapshot(snapshot: UsageSnapshot): CompactEntry {
  return {
    generatedAt: snapshot.generatedAt,
    services: snapshot.services.map((service) => {
      const entry: CompactEntry["services"][number] = {
        id: service.id,
        windows: service.windows.map((window) => ({
          label: window.label,
          usedPercent: window.usedPercent,
        })),
      }
      if (service.error) entry.error = service.error
      return entry
    }),
  }
}

function parseService(input: unknown, index: number, seen: Set<string>): UsageService {
  const path = `services[${index}]`
  const record = asRecord(input, path)
  const id = requireString(record.id, `${path}.id`, 32)
  if (!SERVICE_ID.test(id)) throw new SnapshotError(`${path}.id is not a provider id`)
  if (seen.has(id)) throw new SnapshotError(`duplicate service id ${id}`)
  seen.add(id)
  const name = requireString(record.name, `${path}.name`, 80)
  if (!Array.isArray(record.windows)) throw new SnapshotError(`${path}.windows must be an array`)
  if (record.windows.length > 16) throw new SnapshotError(`${path}.windows exceeds 16`)
  const labels = new Set<string>()
  const windows = record.windows.map((window, windowIndex) => {
    const parsed = parseWindow(window, `${path}.windows[${windowIndex}]`)
    const key = parsed.label.toLowerCase()
    if (labels.has(key)) throw new SnapshotError(`${path} has a duplicate window label`)
    labels.add(key)
    return parsed
  })
  const service: UsageService = {
    id,
    name,
    windows,
    source: requireString(record.source, `${path}.source`, 64),
    fetchedAt: requireInstant(record.fetchedAt, `${path}.fetchedAt`),
  }
  const plan = optionalString(record.plan, `${path}.plan`, 80)
  if (plan) service.plan = plan
  const pace = parsePace(record.pace, `${path}.pace`)
  if (pace) service.pace = pace
  const credits = parseCredits(record.credits, `${path}.credits`)
  if (credits) service.credits = credits
  const renewsOn = optionalString(record.renewsOn, `${path}.renewsOn`, 10)
  if (renewsOn) {
    if (!ISO_DAY.test(renewsOn)) throw new SnapshotError(`${path}.renewsOn must be YYYY-MM-DD`)
    service.renewsOn = renewsOn
  }
  const price = parsePrice(record.price, `${path}.price`)
  if (price) service.price = price
  const error = parseError(record.error, `${path}.error`)
  if (error) service.error = error
  return service
}

function parseWindow(input: unknown, path: string): UsageWindow {
  const record = asRecord(input, path)
  const usedPercent = requireNumber(record.usedPercent, `${path}.usedPercent`)
  if (usedPercent < 0 || usedPercent > 100) throw new SnapshotError(`${path}.usedPercent must be from 0 to 100`)
  const window: UsageWindow = {
    label: requireString(record.label, `${path}.label`, 80),
    usedPercent,
  }
  const resetsAt = optionalString(record.resetsAt, `${path}.resetsAt`, 40)
  if (resetsAt) window.resetsAt = requireInstant(resetsAt, `${path}.resetsAt`)
  if (record.windowMinutes !== undefined && record.windowMinutes !== null) {
    const minutes = requireNumber(record.windowMinutes, `${path}.windowMinutes`)
    if (!Number.isInteger(minutes) || minutes < 0 || minutes > 525600) {
      throw new SnapshotError(`${path}.windowMinutes must be a whole number of minutes from 0 to 525600`)
    }
    window.windowMinutes = minutes
  }
  return window
}

function parsePace(input: unknown, path: string): UsageService["pace"] | undefined {
  if (input === undefined || input === null) return undefined
  const record = asRecord(input, path)
  const pace: NonNullable<UsageService["pace"]> = {}
  const primary = parsePaceSide(record.primary, `${path}.primary`)
  const secondary = parsePaceSide(record.secondary, `${path}.secondary`)
  if (primary) pace.primary = primary
  if (secondary) pace.secondary = secondary
  return pace.primary || pace.secondary ? pace : undefined
}

function parsePaceSide(input: unknown, path: string): PaceSide | undefined {
  if (input === undefined || input === null) return undefined
  const record = asRecord(input, path)
  const side: PaceSide = {}
  const stage = optionalString(record.stage, `${path}.stage`, 40)
  if (stage) side.stage = stage
  if (typeof record.willLastToReset === "boolean") side.willLastToReset = record.willLastToReset
  if (record.expectedUsedPercent !== undefined) side.expectedUsedPercent = requireNumber(record.expectedUsedPercent, `${path}.expectedUsedPercent`)
  if (record.deltaPercent !== undefined) side.deltaPercent = requireNumber(record.deltaPercent, `${path}.deltaPercent`)
  const summary = optionalString(record.summary, `${path}.summary`, 240)
  if (summary) side.summary = summary
  if (record.etaSeconds !== undefined) {
    const eta = requireNumber(record.etaSeconds, `${path}.etaSeconds`)
    if (eta < 0) throw new SnapshotError(`${path}.etaSeconds must be >= 0`)
    side.etaSeconds = eta
  }
  return Object.keys(side).length > 0 ? side : undefined
}

function parseCredits(input: unknown, path: string): UsageService["credits"] | undefined {
  if (input === undefined || input === null) return undefined
  const record = asRecord(input, path)
  const credits: NonNullable<UsageService["credits"]> = {
    remaining: requireNumber(record.remaining, `${path}.remaining`),
  }
  const currency = optionalString(record.currencyCode, `${path}.currencyCode`, 16)
  if (currency) credits.currencyCode = currency
  return credits
}

function parsePrice(input: unknown, path: string): UsageService["price"] | undefined {
  if (input === undefined || input === null) return undefined
  const record = asRecord(input, path)
  const amount = requireNumber(record.amount, `${path}.amount`)
  const currency = requireString(record.currency, `${path}.currency`, 3)
  if (!/^[A-Za-z]{3}$/.test(currency)) throw new SnapshotError(`${path}.currency must be a 3-letter code`)
  const interval = requireString(record.interval, `${path}.interval`, 8)
  if (interval !== "month" && interval !== "year") throw new SnapshotError(`${path}.interval must be month or year`)
  return { amount, currency: currency.toUpperCase(), interval }
}

const ERROR_MESSAGE_MAX = 240

function parseError(input: unknown, path: string): UsageService["error"] | undefined {
  if (input === undefined || input === null) return undefined
  const record = asRecord(input, path)
  // A long provider error must not reject the rest of the snapshot.
  const message = clampString(record.message, `${path}.message`, ERROR_MESSAGE_MAX)
  const kindText = optionalString(record.kind, `${path}.kind`, 32) ?? "unavailable"
  const kind: ErrorKind = ERROR_KINDS.has(kindText as ErrorKind) ? (kindText as ErrorKind) : "unavailable"
  return { message, kind }
}

function asRecord(input: unknown, path: string): Record<string, unknown> {
  if (typeof input !== "object" || input === null || Array.isArray(input)) {
    throw new SnapshotError(`${path} must be an object`)
  }
  return input as Record<string, unknown>
}

function requireString(input: unknown, path: string, max: number): string {
  if (typeof input !== "string") throw new SnapshotError(`${path} must be a string`)
  const cleaned = stripEmail(input).trim()
  if (!cleaned) throw new SnapshotError(`${path} is empty`)
  if (cleaned.length > max) throw new SnapshotError(`${path} is too long`)
  return cleaned
}

function clampString(input: unknown, path: string, max: number): string {
  if (typeof input !== "string") throw new SnapshotError(`${path} must be a string`)
  const cleaned = stripEmail(input).trim()
  if (!cleaned) throw new SnapshotError(`${path} is empty`)
  if (cleaned.length <= max) return cleaned
  const ellipsis = "..."
  return `${cleaned.slice(0, max - ellipsis.length).trimEnd()}${ellipsis}`
}

function optionalString(input: unknown, path: string, max: number): string | undefined {
  if (input === undefined || input === null || input === "") return undefined
  return requireString(input, path, max)
}

function requireNumber(input: unknown, path: string): number {
  if (typeof input !== "number" || !Number.isFinite(input)) throw new SnapshotError(`${path} must be a finite number`)
  return input
}

function requireInstant(input: unknown, path: string): string {
  const value = requireString(input, path, 40)
  if (!ISO_INSTANT.test(value) || Number.isNaN(Date.parse(value))) {
    throw new SnapshotError(`${path} must be an ISO-8601 timestamp`)
  }
  return value
}

function stripEmail(value: string): string {
  return value.replace(EMAIL, "")
}
