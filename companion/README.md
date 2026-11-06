# tolkeins

This folder used to be the separate `cmdux-sh/tolkeins` repository. It now lives inside `cmdux-sh/tolkein` next to the CodexBar fork it reads. Run every command below from this `companion/` folder.

Personal tracker for AI subscription usage, reset times, and renewal dates. A collector on your Mac reads [CodexBar](https://github.com/steipete/CodexBar) and posts numbers only. A Cloudflare Worker stores the latest snapshot. An iPhone widget and an assistant read it over HTTPS.

Nothing in this repo is deployed. Commands below are for you to run.

## Why the collector is Python

It is a short glue program: spawn CodexBar, merge a YAML file, POST JSON. Python 3.9+ from the standard library (no pip packages) is already on macOS, and the same code runs under `unittest` on Linux. Swift would need Xcode just to test the glue.

The collector runs `codexbar usage --provider <id> --json` and does **not** pass `--source`. On CodexBar 0.80.0, `--json` selects JSON output and the default source is `auto`. Warp rejects `cli`, and Grok's explicit `cli` source failed on the Mac that produced the fixtures. Account emails and identity objects are stripped before the POST. Service tokens never leave the Mac.

## 1. Sign CodexBar in

Install CodexBar 0.80.0 or newer and confirm the binary:

```bash
/opt/homebrew/bin/codexbar --version
```

Sign in for each provider you care about. `codexbar usage --provider <id> --json` should return an array. A per-provider error is fine; the collector still posts the other services.

| Provider | What to do |
| --- | --- |
| `claude` | Sign in. Session, weekly, and extra windows (for example Fable) are read from CodexBar. |
| `codex` | Sign in. Weekly usage and credit balance are read from CodexBar. `primary` may be null. |
| `cursor` | Sign in so a Cursor session exists. Until then the snapshot says **Needs sign-in**. |
| `warp` | Warp is API-token only. Add the `wk-…` key in CodexBar or set `WARP_API_KEY`. Do not force `--source cli`. |
| `grok` | CodexBar 0.80.0 has no fetch strategy for Grok. Leave it on auto. The weekly pool is entered by hand in `subscriptions.yaml` until CodexBar returns a window with the same label. |

## 2. Edit subscriptions.yaml

`collector/subscriptions.example.yaml` has placeholder plans, prices, and renewal dates. The collector install copies it once to `~/.config/tolkeins/subscriptions.yaml` and will not overwrite it later.

Set `renewsOn`, `plan`, and `price` for each service. For Grok Bot, set `usedPercent` when you check the pool, plus `resetWeekday`, `resetTime`, and an IANA `timezone`. Monday is `monday` (0). The next reset is strictly after the collector runs. A manual window is dropped when CodexBar already returned that label.

## 3. Install the collector

On the Mac mini:

```bash
chmod +x collector/install.sh collector/uninstall.sh
./collector/install.sh
```

This copies the package to `~/.local/share/tolkeins`, creates `~/.config/tolkeins/` (mode 700) and `config.env` (mode 600) if they are missing, and loads a user LaunchAgent (`com.tolkeins.collector`) that runs every 10 minutes. Logs go to `~/Library/Logs/tolkeins/`.

Fill in the URL and write token after the Worker exists (step 4). Until then a launchd run exits without posting.

```bash
# ~/.config/tolkeins/config.env
WORKER_URL=https://tolkeins.<your-subdomain>.workers.dev
WRITE_TOKEN=<the WRITE_TOKEN secret>
```

Environment variables override the file. A dry run prints the snapshot and does not POST:

```bash
cd ~/.local/share/tolkeins
TOLKEINS_CONFIG_DIR=~/.config/tolkeins python3 -m tolkeins --dry-run
```

Remove the agent with `./collector/uninstall.sh`. Add `--purge` to also delete `~/.config/tolkeins` (that deletes the write token).

## 4. Deploy the Worker (you run this)

From `worker/`, with Wrangler logged in:

```bash
npm install
npx wrangler kv namespace create USAGE
```

Replace the all-zero `id` in `worker/wrangler.jsonc` with the printed namespace id. Then mint three different tokens and store them as secrets (they are not in the config file):

```bash
openssl rand -base64 32   # run three times
npx wrangler secret put WRITE_TOKEN
npx wrangler secret put READ_TOKEN_PHONE
npx wrangler secret put READ_TOKEN_ASSISTANT
npx wrangler d1 create tolkeins-history --location enam
```

`enam` is only a location hint (Eastern North America). Replace the zero `database_id` on the `HISTORY` binding in `worker/wrangler.jsonc` with the printed id. If Wrangler offers to rewrite the config, decline, and paste the id yourself so the binding stays `HISTORY`.

Apply the migration before the first deploy, then deploy. Deploy publishes the Worker and the two cron triggers together. There is no new KV namespace and no new secret. Confirm the migration prompt when Wrangler asks.

```bash
npx wrangler d1 migrations apply tolkeins-history --remote
npx wrangler deploy
```

The migration is `worker/migrations/0001_daily_usage.sql` (table `daily_usage`). The Worker also runs that `CREATE TABLE IF NOT EXISTS` on the first daily write, so a skipped migration is repaired by the next snapshot. Apply it anyway so `d1_migrations` records the schema before traffic. Do not deploy until you have reviewed this change. Nothing in this repo deploys itself.

`WRITE_TOKEN` is only for `POST /v1/snapshot`. `READ_TOKEN_PHONE` is for the iPhone app. `READ_TOKEN_ASSISTANT` is for curl and your assistant. A write token cannot read, and a read token cannot write.

Each POST is one KV write (latest snapshot and a rolling history share the key `v1`) and one D1 row write for that Toronto day's usage. At a 10-minute interval that is 144 writes per day to each. The Workers KV free tier is often quoted at 1,000 writes per day; confirm the quota on your account before you rely on it. D1 on the Workers Free plan includes 100,000 row writes per day. `HISTORY_LIMIT` defaults to 48 compact entries (about 8 hours) and is capped at 200. Daily history is separate and keeps 400 Toronto dates.

Local checks, with no deploy:

```bash
cd worker && npm test && npm run typecheck
cd collector && python3 -m unittest discover -s tests -t . -v
```

Copy `worker/.dev.vars.example` to `worker/.dev.vars` only if you run `npx wrangler dev` yourself.

## 5. Build the iOS app

Open `ios/Tolkeins.xcodeproj` in Xcode 15 or newer (iOS 17+). Before you archive or run on a device, edit `ios/Config/Shared.xcconfig` and replace every `PLACEHOLDER`:

- `DEVELOPMENT_TEAM` — 10-character Team ID from the Apple Developer account
- `TOLKEINS_BUNDLE_IDENTIFIER` — for example `app.yourname.tolkeins`
- `TOLKEINS_APP_GROUP` — for example `group.yourname.tolkeins`

Create that App Group for both the app and the widget (the entitlements already reference `$(TOLKEINS_APP_GROUP)`). The read token is stored in the Keychain access group `$(AppIdentifierPrefix)$(TOLKEINS_APP_GROUP)` with `kSecAttrAccessibleAfterFirstUnlock`, so the lock-screen widget can read it after the first unlock. The Worker URL and the last snapshot live in the App Group container.

Run the app on your iPhone, enter the Worker origin (no path) and **the phone read token**, then add the Tolkeins widget. Small, medium, large, and lock-screen circular, rectangular, and inline families are included. The timeline refreshes about every 20 minutes. Data older than 30 minutes is marked stale. Percentages use monospaced digits, and status words (In budget, Near limit, At limit, Needs sign-in, Unavailable) sit next to the color.

## Ask an assistant for the latest snapshot

```bash
curl -sS \
  -H "Authorization: Bearer $TOLKEINS_READ_TOKEN" \
  "https://tolkeins.<your-subdomain>.workers.dev/v1/usage"
```

`$TOLKEINS_READ_TOKEN` is `READ_TOKEN_ASSISTANT`. Query-string tokens are ignored. `GET /v1/history?limit=10` returns the compact rolling history (the last few hours) with the same read token. Daily totals are a different query, below. `GET /health` needs no token.

Treat `generatedAt` older than 30 minutes as stale. Sort windows yourself if you want the hottest quota first; the widget scores a window by percent used and adds weight when a reset is inside two hours and usage is already at least 50%.

### Snapshot shape

```json
{
  "schemaVersion": 1,
  "generatedAt": "2026-10-24T05:22:00Z",
  "services": [
    {
      "id": "claude",
      "name": "Claude",
      "plan": "Max",
      "windows": [
        { "label": "Session", "usedPercent": 20, "resetsAt": "2026-10-24T06:40:00Z", "windowMinutes": 300 }
      ],
      "pace": { "primary": { "stage": "farBehind", "willLastToReset": true, "expectedUsedPercent": 73 } },
      "renewsOn": "2026-11-12",
      "source": "claude",
      "fetchedAt": "2026-10-24T05:18:46Z"
    }
  ]
}
```

Optional fields are omitted when empty. `error.kind` is `needs-sign-in`, `unavailable`, or `collector`. A service with windows does not also carry an error. `source` is `manual` when the only windows came from `subscriptions.yaml`.

## Daily history

The Worker stores one row per America/Toronto date. The first snapshot after local midnight is that day's start. Each later snapshot the same day updates the end, so a reset between the 10-minute samples is counted. At 23:55 Toronto time a cron seals the day (`"closed": true`). Until then `"closed"` is false and `end` is the latest snapshot. A missed night is sealed on the next close. The close keeps 400 Toronto dates, counting that day, and deletes anything older.

Read it with either read token. `from` and `to` are Toronto dates, inclusive. On the daily routes, an omitted `to` means today in Toronto, and an omitted `from` means 29 days before `to` (30 dates). `GET /v1/history.csv` with neither parameter is that default window. `GET /v1/history` with neither parameter is still the short rolling history, and `limit` applies only then. More than 400 dates in one request returns `range_too_large`. Days with no snapshot are absent, not filled with zeros.

```bash
curl -sS \
  -H "Authorization: Bearer $TOLKEINS_READ_TOKEN" \
  "https://tolkeins.<your-subdomain>.workers.dev/v1/history?from=2026-10-26&to=2026-10-26"
```

```bash
curl -sS \
  -H "Authorization: Bearer $TOLKEINS_READ_TOKEN" \
  "https://tolkeins.<your-subdomain>.workers.dev/v1/history.csv?from=2026-10-26&to=2026-10-26"
```

```json
{
  "timezone": "America/Toronto",
  "from": "2026-10-26",
  "to": "2026-10-26",
  "days": [
    {
      "date": "2026-10-26",
      "startAt": "2026-10-26T04:08:00Z",
      "endAt": "2026-10-27T03:50:00Z",
      "closed": true,
      "services": [
        {
          "id": "claude",
          "name": "Claude",
          "windows": [
            {
              "label": "Weekly",
              "start": 20,
              "end": 47,
              "change": 27,
              "reset": false,
              "used": 27,
              "resetsAtStart": "2026-11-01T04:00:00Z",
              "resetsAtEnd": "2026-11-01T04:00:00Z",
              "windowMinutes": 10080
            },
            {
              "label": "Session",
              "start": 10,
              "end": 12,
              "change": 2,
              "reset": true,
              "used": 82,
              "resetsAtStart": "2026-10-26T09:00:00Z",
              "resetsAtEnd": "2026-10-26T14:00:00Z",
              "windowMinutes": 300
            }
          ]
        },
        {
          "id": "codex",
          "name": "Codex",
          "windows": [
            {
              "label": "Weekly",
              "start": 15,
              "end": 33,
              "change": 18,
              "reset": false,
              "used": 18,
              "windowMinutes": 10080
            }
          ],
          "credits": { "start": 40, "end": 28, "used": 12, "added": 0, "currencyCode": "USD" }
        }
      ]
    }
  ]
}
```

That Monday (still EDT) starts at 00:08 Toronto (`04:08Z`) and the last snapshot is 23:50 (`03:50Z` the next UTC date). The session window climbed from 10% to 80%, then reset, and finished at 12%. `change` is always end minus start, in percentage points, so the session change is `2` even though the window reset. `used` is `82`: `(80 - 10) + 12`. The 80 is the highest percent observed before the drop. The ending percent stands in for usage after a restart near zero. If the window resets more than once, each finished stretch is added the same way, and the final end is added once. When `resetsAt` moves forward but no higher sample was seen, the value before the reset is the start of that stretch, so `used` collapses to the ending percent.

`reset` is true when the percent drops by more than one point, or when `resetsAt` moves forward by more than half the window (at least 30 minutes; 30 minutes when the window length is unknown). A smaller dip or a few minutes of `resetsAt` drift is noise, not a restart. Without a reset, `used` is the net change and never below 0.

A snapshot whose `generatedAt` is more than 5 minutes ahead of the Worker's clock is kept as the latest snapshot but is not added to the daily history.

Credits compare the first and last balance only. `used` is start minus end. If the balance rose, `used` is 0 and `added` is the increase. A spend and a top-up on the same day are not both visible.

CSV uses the same rows. Credit columns are filled on the first window of each service and left blank on the rest, so a sum of `credits_used` does not count the service twice. A service with credits and no windows gets one row with an empty `window`.

```text
date,service_id,service_name,window,start,end,change,reset,used,resets_at_start,resets_at_end,window_minutes,credits_start,credits_end,credits_used,credits_added,currency
2026-10-26,claude,Claude,Weekly,20,47,27,false,27,2026-11-01T04:00:00Z,2026-11-01T04:00:00Z,10080,,,,,
2026-10-26,claude,Claude,Session,10,12,2,true,82,2026-10-26T09:00:00Z,2026-10-26T14:00:00Z,300,,,,,
2026-10-26,codex,Codex,Weekly,15,33,18,false,18,,,10080,40,28,12,0,USD
```

The cron expressions are `55 3 * * *` and `55 4 * * *` UTC. Cron Triggers have no timezone. 23:55 America/Toronto is 03:55 UTC while daylight time is in effect (UTC-4, from the second Sunday in March until the first Sunday in November) and 04:55 UTC during standard time (UTC-5). The handler seals a day only when `controller.scheduledTime` falls in hour 23 in Toronto, so the other firing returns without writing. It uses the planned `scheduledTime`, not the moment the isolate actually ran. 23:55 is outside the spring-forward gap and the fall-back repeated hour, so each local date is sealed once.

Daily rows live in D1 (`HISTORY` → database `tolkeins-history`), not in the KV document `GET /v1/usage` reads. A date range and a retention delete fit SQL. KV list is eventually consistent, and putting 400 days into the `v1` document would make every usage read carry the archive. Each row stores the start and end timestamps plus the window and credit numbers used for the math. It does not store a second copy of the full snapshot: a snapshot may be 100KB and a D1 statement is limited to 100KB.

## Layout

| Path | Role |
| --- | --- |
| `collector/` | Python package, LaunchAgent installer, fixtures from the Mac mini |
| `worker/` | TypeScript Worker, KV snapshot, D1 daily history, Vitest |
| `ios/` | SwiftUI app and WidgetKit extension |

This environment did not compile the Swift project (no Xcode or iOS SDK) and did not run the CodexBar binary. CLI flags were checked against the CodexBar 0.80.0 source. The Worker was not deployed.
