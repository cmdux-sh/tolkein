-- One row per America/Toronto date. Keep in sync with DAILY_SCHEMA in src/daily-store.ts.
CREATE TABLE IF NOT EXISTS daily_usage (
  date TEXT PRIMARY KEY,
  start_at TEXT NOT NULL,
  end_at TEXT NOT NULL,
  track_json TEXT NOT NULL,
  last_generated_at TEXT NOT NULL,
  last_generated_ms INTEGER NOT NULL,
  closed INTEGER NOT NULL DEFAULT 0
);
