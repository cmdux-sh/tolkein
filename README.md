# tolkeins

Personal tracker for AI subscription usage, reset times, and renewal dates. A collector on your Mac reads [CodexBar](https://github.com/steipete/CodexBar) and posts numbers only. A Cloudflare Worker stores the latest snapshot. An iPhone widget and an assistant read it over HTTPS.

Nothing in this repo is deployed. Commands below are for you to run.

## Why the collector is Python

It is a short glue program: spawn CodexBar, merge a YAML file, POST JSON. Python 3.9+ from the standard library (no pip packages) is already on macOS, and the same code runs under `unittest` on Linux. Swift would need Xcode just to test the glue.

The collector runs `codexbar usage --provider <id> --json` and does **not** pass `--source`. On CodexBar 0.80.0, `--json` selects JSON output and the default source is `auto`. Warp rejects `cli`, and Grok's explicit `cli` source failed on the Mac that produced the fixtures. Account emails and identity objects are stripped before the POST. Service tokens never leave the Mac.

The LaunchAgent starts **Tolkeins Collector.app**, a small signed helper. The helper stays running and spawns `python3 -m tolkeins`, which spawns CodexBar. macOS attributes Chrome folder access to that helper. Cookie decryption still needs CodexBar itself allowed on the **Chrome Safe Storage** Keychain item; `collector/grant-chrome-keychain.sh` is the one-time Terminal step. The helper is signed with an Apple Development or Developer ID identity when one is installed, and otherwise with a local certificate `install.sh` creates. Ad-hoc signatures are not used, because each rebuild would be a new identity.

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
| `cursor` | Sign in at cursor.com so a Cursor session exists. Until then the snapshot says **Needs sign-in**. The collector does not sign in for you. |
| `gemini` | CodexBar reads Chrome cookies. Grant Chrome to **Tolkeins Collector** under Files & Folders. |
| `claudeplatform` | Same Chrome grant as Gemini. |
| `warp` | Warp is API-token only. Add the `wk-…` key in CodexBar or set `WARP_API_KEY`. Do not force `--source cli`. |
| `grok` | CodexBar 0.80.0 has no fetch strategy for Grok. Leave it on auto. The weekly pool is entered by hand in `subscriptions.yaml` until CodexBar returns a window with the same label. |

## 2. Edit subscriptions.yaml

`collector/subscriptions.example.yaml` has placeholder plans, prices, and renewal dates. The collector install copies it once to `~/.config/tolkeins/subscriptions.yaml` and will not overwrite it later.

Set `renewsOn`, `plan`, and `price` for each service. For Grok Bot, set `usedPercent` when you check the pool, plus `resetWeekday`, `resetTime`, and an IANA `timezone`. Monday is `monday` (0). The next reset is strictly after the collector runs. A manual window is dropped when CodexBar already returned that label.

## 3. Install the collector

On the Mac mini, from this repo:

```bash
chmod +x collector/install.sh collector/uninstall.sh collector/verify-chrome.sh collector/grant-chrome-keychain.sh collector/macos/*.sh
./collector/install.sh
```

This copies the package to `~/.local/share/tolkeins`, creates `~/.config/tolkeins/` (mode 700) and `config.env` (mode 600) if they are missing, and loads a user LaunchAgent (`com.tolkeins.collector`, every 10 minutes). It leaves an existing `config.env` and `subscriptions.yaml` in place. Logs go to `~/Library/Logs/tolkeins/`.

The agent program is `~/Applications/Tolkeins Collector.app` (bundle id `com.tolkeins.collector`). `install.sh` signs that app with the first **Apple Development** identity from `security find-identity -p codesigning`, then a **Developer ID Application** identity, then a self-signed certificate named `Tolkeins Collector` when neither Apple identity exists. `TOLKEINS_SIGN_IDENTITY` forces one of those names, or `local` for the self-signed certificate. The local key stays in `~/.config/tolkeins/codesign/` (mode 700) and the keychain `tolkeins-collector`, and is created only for that fallback. The script does not print the keychain password, the signing key, or `WRITE_TOKEN`.

Switching identity changes the designated requirement. Turn Chrome on again for Tolkeins Collector after that. Re-running the installer with the same identity keeps the grant.

### Grant Chrome once

1. Run `./collector/verify-chrome.sh` once. Gemini and Claude Platform fail until the grant exists. That run is what makes **Tolkeins Collector** appear in Settings.
2. Open **System Settings → Privacy & Security → Files and Folders**.
3. Under **Tolkeins Collector**, turn **Chrome** on.
4. CodexBar's error text says to enable Chrome under CodexBar. For this agent the switch that applies is **Tolkeins Collector**. Leave Full Disk Access for `/usr/bin/python3` off.
5. Run `./collector/verify-chrome.sh` again. If the error is Chrome Safe Storage / Keychain permission, continue below.

### Grant Chrome Safe Storage once

Chrome encrypts cookies with the Keychain item `Chrome Safe Storage`. CodexBar's `usage` command is a background read and will not show a prompt, including from the LaunchAgent. In Terminal.app:

```bash
./collector/grant-chrome-keychain.sh
```

When macOS asks CodexBar to use **Chrome Safe Storage**, click **Always Allow**. Allow Once does not cover the later LaunchAgent run. If the dialog names Terminal or python3, click Deny and add `/Applications/CodexBar.app/Contents/Helpers/CodexBarCLI` (the script prints the resolved path) under that item's Access Control. Do not reveal the password.

Then run `./collector/verify-chrome.sh` again.

A passing run prints `gemini ok` and `claudeplatform ok` with window counts, then `result=pass`. It prints the full provider error text, with emails and token-like strings redacted.

`cursor` still needs a cursor.com sign-in. The helper does not do that. A `needs-sign-in` line for cursor is the same state as before.

Fill in the URL and write token after the Worker exists (step 4). Until then a launchd run exits without posting. `verify-chrome.sh` passes `--dry-run`, so it does not POST.

```bash
# ~/.config/tolkeins/config.env
WORKER_URL=https://tolkeins.<your-subdomain>.workers.dev
WRITE_TOKEN=<the WRITE_TOKEN secret>
```

Environment variables override the file.

Remove the agent, the helper app, and the installed copy with `./collector/uninstall.sh`. Config, the write token, and the signing certificate stay, so a later install keeps the Chrome grant. Add `--purge` to also delete `~/.config/tolkeins` and the signing keychain. A new certificate is a new identity, and Chrome must be granted again.

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
npx wrangler deploy
```

`WRITE_TOKEN` is only for `POST /v1/snapshot`. `READ_TOKEN_PHONE` is for the iPhone app. `READ_TOKEN_ASSISTANT` is for curl and your assistant. A write token cannot read, and a read token cannot write.

Each POST is one KV write (latest snapshot and a rolling history share the key `v1`). At a 10-minute interval that is 144 writes per day. The Workers KV free tier is often quoted at 1,000 writes per day; confirm the quota on your account before you rely on it. `HISTORY_LIMIT` defaults to 48 compact entries (about 8 hours) and is capped at 200.

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

`$TOLKEINS_READ_TOKEN` is `READ_TOKEN_ASSISTANT`. Query-string tokens are ignored. `GET /v1/history?limit=10` returns the compact rolling history with the same read token. `GET /health` needs no token.

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

## Layout

| Path | Role |
| --- | --- |
| `collector/` | Python package, LaunchAgent installer, Chrome grant check, fixtures from the Mac mini |
| `collector/macos/` | Tolkeins Collector.app launcher, local signing script, prebuilt Mach-O slices |
| `worker/` | TypeScript Worker, KV document, Vitest |
| `ios/` | SwiftUI app and WidgetKit extension |

This environment did not compile the Swift project (no Xcode or iOS SDK) and did not run the CodexBar binary. CLI flags were checked against the CodexBar 0.80.0 source. The Worker was not deployed.
