import { compactSnapshot, type CompactEntry, type UsageSnapshot } from "./snapshot"

export interface StoredDocument {
  latest: UsageSnapshot
  history: CompactEntry[]
}

export const SNAPSHOT_KEY = "v1"

export function historyLimit(raw: string | undefined): number {
  const parsed = Number(raw)
  if (!Number.isInteger(parsed) || parsed < 1) return 48
  return Math.min(parsed, 200)
}

export function nextDocument(current: StoredDocument | null, snapshot: UsageSnapshot, limit: number): StoredDocument {
  const entry = compactSnapshot(snapshot)
  const history = current?.history ? [...current.history] : []
  const last = history[history.length - 1]
  if (last && last.generatedAt === entry.generatedAt) history[history.length - 1] = entry
  else history.push(entry)
  const cap = Math.max(1, Math.min(limit, 200))
  return {
    latest: snapshot,
    history: history.slice(-cap),
  }
}
