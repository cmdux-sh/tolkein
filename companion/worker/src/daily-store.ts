import {
  applySnapshot,
  createTrack,
  isTorontoClose,
  parseTrack,
  retentionCutoff,
  toHistoryDay,
  torontoDate,
  type HistoryDay,
} from "./daily"
import type { UsageSnapshot } from "./snapshot"

// Keep in sync with migrations/0001_daily_usage.sql.
export const DAILY_SCHEMA = `CREATE TABLE IF NOT EXISTS daily_usage (
  date TEXT PRIMARY KEY,
  start_at TEXT NOT NULL,
  end_at TEXT NOT NULL,
  track_json TEXT NOT NULL,
  last_generated_at TEXT NOT NULL,
  last_generated_ms INTEGER NOT NULL,
  closed INTEGER NOT NULL DEFAULT 0
);`

interface DailyRow {
  date: string
  start_at: string
  end_at: string
  track_json: string
  last_generated_at: string
  last_generated_ms: number
  closed: number
}

export interface CloseResult {
  acted: boolean
  date: string | null
  closed: boolean
  sealed: number
  pruned: number
}

const MAX_CLOCK_SKEW_MS = 5 * 60_000

export async function ensureDailySchema(db: D1Database): Promise<void> {
  // prepare().run() keeps the whole statement. exec() in the local runtime
  // splits on newlines and would send only "CREATE TABLE ... (".
  await db.prepare(DAILY_SCHEMA).run()
}

export async function recordDailySnapshot(db: D1Database, snapshot: UsageSnapshot): Promise<void> {
  await ensureDailySchema(db)
  const date = torontoDate(snapshot.generatedAt)
  const generatedMs = instantMs(snapshot.generatedAt)
  // A collector clock far ahead would start a future day or block the rest of today.
  if (generatedMs > Date.now() + MAX_CLOCK_SKEW_MS) return
  const existing = await getRow(db, date)
  if (!existing) {
    const track = createTrack()
    applySnapshot(track, snapshot)
    try {
      await db
        .prepare(
          `INSERT INTO daily_usage (date, start_at, end_at, track_json, last_generated_at, last_generated_ms, closed)
           VALUES (?, ?, ?, ?, ?, ?, 0)`,
        )
        .bind(date, snapshot.generatedAt, snapshot.generatedAt, JSON.stringify(track), snapshot.generatedAt, generatedMs)
        .run()
      return
    } catch (error) {
      if (!isConstraintError(error)) throw error
    }
  }
  // Two overlapping POSTs can read the same row. Retry so neither merge is lost.
  for (let attempt = 0; attempt < 3; attempt += 1) {
    if (await updateRow(db, date, snapshot, generatedMs)) return
  }
  throw new Error("daily row kept changing; snapshot not merged")
}

export async function listDailyHistory(db: D1Database, from: string, to: string): Promise<HistoryDay[]> {
  await ensureDailySchema(db)
  const { results } = await db
    .prepare(
      `SELECT date, start_at, end_at, track_json, closed
       FROM daily_usage
       WHERE date >= ? AND date <= ?
       ORDER BY date`,
    )
    .bind(from, to)
    .all<DailyRow>()
  const days: HistoryDay[] = []
  for (const row of results) {
    const day = toHistoryDay(row)
    if (!day) {
      console.error(JSON.stringify({ message: "daily row unreadable", date: row.date }))
      continue
    }
    days.push(day)
  }
  return days
}

export async function runDailyClose(db: D1Database, scheduledTime: number, latest: UsageSnapshot | null): Promise<CloseResult> {
  if (!isTorontoClose(scheduledTime)) return { acted: false, date: null, closed: false, sealed: 0, pruned: 0 }
  await ensureDailySchema(db)
  const date = torontoDate(new Date(scheduledTime))
  const pruned = await prune(db, date)
  const sealed = await sealPastDays(db, date)
  let closed = false
  if (latest && torontoDate(latest.generatedAt) === date) {
    await recordDailySnapshot(db, latest)
    const updated = await db.prepare("UPDATE daily_usage SET closed = 1 WHERE date = ?").bind(date).run()
    closed = (updated.meta.changes ?? 0) > 0
  }
  return { acted: true, date, closed, sealed, pruned }
}

async function updateRow(db: D1Database, date: string, snapshot: UsageSnapshot, generatedMs: number): Promise<boolean> {
  const existing = await getRow(db, date)
  if (!existing) throw new Error("daily row missing")
  if (generatedMs <= existing.last_generated_ms) return true
  const track = parseTrack(existing.track_json)
  if (!track) throw new Error("daily track unreadable")
  applySnapshot(track, snapshot)
  const result = await db
    .prepare(
      `UPDATE daily_usage
       SET end_at = ?, track_json = ?, last_generated_at = ?, last_generated_ms = ?
       WHERE date = ? AND last_generated_ms = ?`,
    )
    .bind(snapshot.generatedAt, JSON.stringify(track), snapshot.generatedAt, generatedMs, date, existing.last_generated_ms)
    .run()
  return (result.meta.changes ?? 0) > 0
}

async function getRow(db: D1Database, date: string): Promise<DailyRow | null> {
  return db
    .prepare(
      `SELECT date, start_at, end_at, track_json, last_generated_at, last_generated_ms, closed
       FROM daily_usage WHERE date = ?`,
    )
    .bind(date)
    .first<DailyRow>()
}

async function sealPastDays(db: D1Database, today: string): Promise<number> {
  const result = await db.prepare("UPDATE daily_usage SET closed = 1 WHERE date < ? AND closed = 0").bind(today).run()
  return result.meta.changes ?? 0
}

async function prune(db: D1Database, today: string): Promise<number> {
  const cutoff = retentionCutoff(today)
  const result = await db.prepare("DELETE FROM daily_usage WHERE date < ?").bind(cutoff).run()
  return result.meta.changes ?? 0
}

function instantMs(iso: string): number {
  const ms = Date.parse(iso)
  if (Number.isNaN(ms)) throw new Error("daily snapshot time is invalid")
  return ms
}

function isConstraintError(error: unknown): boolean {
  const message = error instanceof Error ? error.message : String(error)
  return /unique constraint/i.test(message)
}
