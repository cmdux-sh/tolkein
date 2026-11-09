# Tolkein

> Every AI coding limit, in your menu bar.

Tolkein is a macOS 15+ menu bar app that keeps AI coding-provider limits visible and shows when each window resets.
It started as a fork of [CodexBar](https://github.com/steipete/CodexBar) by Peter Steinberger and is now its own
app, rebuilt on the Internal UI design system. See the [supported providers](#providers) below.

## Why

- **Plan around resets.** Per-provider session, weekly, and monthly windows with countdowns to the next reset — stop guessing whether to start that long task.
- **Credits, spend, and cost scans.** Credit balances, Admin API spend dashboards, provider billing summaries, and local cost scans where the source exposes enough detail.
- **Live status.** Provider status polling surfaces incident badges in the menu and an indicator overlay on the bar icon.
- **Privacy-first.** Reuses existing provider sessions — OAuth, device flow, API keys, browser cookies, local files — so no passwords are stored.

## Install

Tolkein isn't published yet. Build it from source (see [Build from source](#build-from-source)), or run `make start`
for the development loop.

### macOS first run
- Open Settings → Providers and enable what you use.
- Install/sign in to the provider sources you rely on: CLIs, browser sessions, OAuth/device flow, API keys, local app files, or provider apps depending on the provider.
- Optional: Settings → Providers → Codex → OpenAI cookies (Automatic or Manual) to add dashboard extras.

### Set API keys from the CLI
Provider toggles and API keys live in the resolved CodexBar config file. New installs use
`~/.config/codexbar/config.json`; existing `~/.codexbar/config.json` installs still load from the legacy path. You can
script the same provider list that Settings → Providers uses:

```bash
codexbar config providers
codexbar config enable --provider grok
codexbar config disable --provider cursor
```

For API-key providers, store a key without opening Settings:

```bash
printf '%s' "$ELEVENLABS_API_KEY" | codexbar config set-api-key --provider elevenlabs --stdin
```

`set-api-key` trims the piped value, stores it with restrictive config-file permissions, and enables the provider by default. Use `--no-enable` to only save the key, or `--api-key <key>` for one-off local scripts where shell history is not a concern.
See [CLI configuration](docs/cli-configuration.md) for the full flow.

## Providers

- [Codex](docs/codex.md) — OAuth API or local Codex CLI, plus optional OpenAI web dashboard extras.
- [OpenAI](docs/openai.md) — Admin API key usage/cost graphs with legacy credit-balance fallback.
- [Azure OpenAI](docs/azure-openai.md) — API key, endpoint, and deployment validation probe.
- [Claude](docs/claude.md) — OAuth API, browser cookies, or CLI PTY fallback; session and weekly usage where available.
- [ClinePass](docs/clinepass.md) — API key for five-hour, weekly, and monthly subscription limits.
- [Cursor](docs/cursor.md) — Browser session cookies for plan + usage + billing resets.
- [OpenCode](docs/opencode.md) — Browser cookies for workspace subscription usage.
- [OpenCode Go](docs/opencodego.md) — Usage API, browser fallback, and local SQLite cost history.
- [Alibaba Coding Plan](docs/alibaba-coding-plan.md) — Web cookies or API key for coding-plan quotas.
- [Alibaba Token Plan](docs/alibaba-token-plan.md) — Bailian browser/manual cookies for token-plan credits.
- [Qwen Cloud](docs/qwen-cloud.md) — 5-hour and weekly individual Token Plan usage via browser/manual cookies.
- [Gemini](docs/gemini.md) — OAuth-backed quota API using Gemini CLI credentials (no browser cookies).
- [Antigravity](docs/antigravity.md) — Local language server probe, `agy` CLI HTTPS source, and Google OAuth fallback (experimental).
- [Droid](docs/factory.md) — Browser cookies + WorkOS token flows for Factory usage + billing.
- [Copilot](docs/copilot.md) — GitHub device flow + Copilot internal usage API.
- [Devin](docs/devin.md) — Chrome localStorage session or manual Bearer token for daily and weekly quotas.
- [z.ai](docs/zai.md) — API token for personal/team quota, MCP, 5-hour, and hourly usage windows.
- [Manus](docs/manus.md) — Browser `session_id` auth for credit balance, monthly credits, and daily refresh tracking.
- [MiniMax](docs/minimax.md) — API token, cookie header, or browser cookies for coding-plan usage.
- [T3 Chat](docs/t3chat.md) — Browser cookies capture for Base and Overage usage buckets.
- [ZoomMate](docs/zoommate.md) — Chrome cookie auto-import or manual cURL capture for credits usage.
- [Kimi](docs/kimi.md) — Auth token (JWT from `kimi-auth` cookie) for weekly quota + 5‑hour rate limit.
- [Kilo](docs/kilo.md) — API token with CLI-auth fallback for Kilo Pass usage.
- [Kiro](docs/kiro.md) — CLI-based usage; monthly credits + bonus credits.
- [Vertex AI](docs/vertexai.md) — Google Cloud gcloud OAuth with token cost tracking from local Claude logs.
- [Augment](docs/augment.md) — Augment CLI or browser cookies for credits tracking and usage monitoring.
- [Amp](docs/amp.md) — Browser cookie-based authentication with Amp Free usage tracking.
- [Ollama](docs/ollama.md) — API key access plus browser cookies for Ollama Cloud usage windows.
- [llmman](docs/llmman.md) — Local daemon memory used by loaded models, with an optional API key.
- [Synthetic](docs/synthetic.md) — API key quota endpoint for rolling five-hour, weekly token, and search-hourly usage.
- [JetBrains AI](docs/jetbrains.md) — Local XML-based quota from JetBrains IDE configuration; monthly credits tracking.
- [Warp](docs/warp.md) — API token for GraphQL request limits and monthly credits.
- [ElevenLabs](docs/elevenlabs.md) — API key for character credits and voice slot usage.
- [OpenRouter](docs/openrouter.md) — API token for credit-based usage tracking across multiple AI providers.
- [Windsurf](docs/windsurf.md) — Browser localStorage session import or local SQLite cache for plan usage.
- [Zed](docs/zed.md) — Zed editor Keychain session for plan, edit-prediction quota, billing cycle, and overdue invoices.
- [Perplexity](docs/perplexity.md) — Account usage credits from Perplexity usage data.
- [Xiaomi MiMo](docs/mimo.md) — Browser cookies for balance and token-plan usage.
- [Doubao](docs/doubao.md) — API key for Volcengine Ark request-limit probes.
- [Sakana AI](docs/sakana.md) — Manual Cookie header for 5-hour and weekly quota windows.
- [Abacus AI](docs/abacus.md) — Browser cookie auth for ChatLLM/RouteLLM compute credit tracking.
- [Mistral](docs/mistral.md) — Browser cookies for API spend, credit balance, and monthly-plan usage.
- [DeepSeek](docs/deepseek.md) — API key for credit balance tracking (paid vs. granted breakdown).
- [Fireworks](docs/fireworks.md) — API key + account slug for 30-day spend from the billing summary API.
- [Charm Hyper](docs/hyper.md) — Bundled plugin for native Hypercredit balance, using Chrome/manual sessions with API-key fallback.
- [DeepInfra](docs/deepinfra.md) — API key for prepaid balance, current-month spend, and spending-limit tracking.
- [Moonshot / Kimi API](docs/moonshot.md) — API key for Moonshot/Kimi API account balance tracking.
- [Venice](docs/venice.md) — API key for DIEM or USD balance tracking.
- [Codebuff](docs/codebuff.md) — API token (or `~/.config/manicode/credentials.json`) for credit balance + weekly rate limit.
- [Command Code](docs/command-code.md) — API key or browser/manual cookies for monthly USD credits and rolling usage limits.
- [Qoder](docs/qoder.md) — Browser or manual cookies for Qoder big model credit usage.
- [StepFun](docs/stepfun.md) — Username + password login for Step Plan rate limits (5‑hour + weekly windows) and subscription plan name.
- [AWS Bedrock](docs/bedrock.md) — AWS access keys or a named AWS profile (SSO/assume-role via the AWS CLI) for Cost Explorer spend, monthly budgets, and optional CloudWatch Claude activity.
- [Grok](docs/grok.md) — Grok CLI billing RPC plus grok.com browser-session fallback.
- [Groq](docs/groq.md) — Browser session for console spend and usage, with an Enterprise Prometheus API-key fallback.
- [LLM Proxy](docs/llm-proxy.md) — API key + base URL for aggregate proxy quota stats and provider breakdowns.
- [ClawRouter](docs/clawrouter.md) — API key for monthly budget, spend, requests, tokens, and routed-provider usage.
- [sub2api](docs/sub2api.md) — Self-hosted gateway key quota, subscription limits, wallet balance, and per-key usage.
- [Wayfinder](docs/wayfinder.md) — Local router gateway polling for health, per-route breakdown, savings, and decision latency.
- [LiteLLM](docs/litellm.md) — Virtual key + proxy URL for personal and team budget/spend tracking.
- [Bifrost](docs/bifrost.md) — Virtual key + self-hosted gateway URL for budgets, rate limits, and model spend.
- [Aixy](docs/aixy.md) — API key for key-scoped spend, tokens, and applicable personal/shared budgets.
- [Deepgram](docs/deepgram.md) — API key usage summaries across speech, agent, token, and TTS metrics.
- [Poe](docs/poe.md) — API key for current point balance and recent points history.
- [Chutes](docs/chutes.md) — API key for subscription usage, rolling and monthly quota windows, and pay-as-you-go quotas.
- [Neuralwatt](docs/neuralwatt.md) — API key for subscription kWh usage and prepaid credit balance.
- [Helmcode](docs/helmcode.md) — Cloud and NaN Builders dashboard sessions for per-model quotas and Cloud prepaid balance.
- [ZenMux](docs/zenmux.md) — Management API key for rolling five-hour and seven-day quota windows plus PAYG balance.
- [xAI](docs/xai.md) — Management API key + team ID for prepaid credit balance and daily platform spend.
- [IBM Bob](docs/ibm-bob.md) — API key for monthly Bobcoin budget and usage across subscription teams.
- [LongCat](docs/longcat.md) — Browser or manual cookies for token-pack quota and fuel-pack balances.
- [ai&](docs/aiand.md) — API key for 30-day organization spend from request logs.
- [Notion AI](docs/notion.md) — Browser or manual cookies for rolling and monthly workspace allowances.
- [Nous Portal](docs/nous.md) — Existing Hermes OAuth login for monthly credits and purchased top-ups.
- [Muse Code](docs/muse.md) — Existing Muse CLI login for subscription quotas, plus local token history.
- [Muse (muse.ai)](docs/museai.md) — Browser or manual muse.ai session for the Free, Power, or Maximum weekly allowance.
- [CodeRabbit](docs/coderabbit.md) — Local CLI usage report for review counts, billing state, and period resets.
- [Replicate](docs/replicate.md) — Browser or manual cookies for monthly spend and optional prepaid credits.
- [Hugging Face](docs/huggingface.md) — Access token for Inference Providers charges and optional ZeroGPU quota.
- [Raycast](docs/raycast.md) — Chrome or manual website session for monthly AI credits and renewal.
- [Pi](docs/pi.md) — Local Pi/OMP transcripts for token history and API-rate cost estimates.
- [v0](docs/v0.md) — Platform API key for billing and on-demand balances, plus rate limits.
- [TypeSafe](docs/typesafe.md) — Browser or manual console cookies for billing spend, balance, and credit expirations.
- [GitKraken AI](docs/gitkraken.md) — Account access token for personal weekly credits, reset time, and organization pool sharing.
- [DevPass](docs/devpass.md) — API key for plan credits, premium weekly allowances, and key-scoped spending.
- [Atlas Cloud](docs/atlascloud.md) — API key for the account's available USD balance.
- [Vercel AI Gateway](docs/vercel.md) — API key for the team's USD balance and lifetime spend.
- [xKiro](docs/xkiro.md) — API key for daily free-token usage, remaining allowance, and the midnight UTC reset.
- Open to new providers: [provider authoring guide](docs/provider.md).

<!-- Generated provider additions: Scripts/regenerate-provider-docs.mjs -->
- [Langdock](docs/langdock.md) — Selected Edge, Chrome, or Safari profile → personal included session and weekly limits (`web`, macOS).
- [Soniox](docs/soniox.md) — Organization API key for prepaid USD balance and monthly spend against the organization budget.
- [X API](docs/xapi.md) — Browser or manual console.x.com cookies for prepaid and free credits, including negative balances.
- [Future AGI](docs/futureagi.md) — API key and secret key (billing-period usage, allowances, and estimated cost).
- [LithosAI](docs/lithosai.md) — Browser or manual console cookies for prepaid USD balance and optional UTC spend.
- [WorkBuddy](docs/workbuddy.md) — Chrome or manual www.workbuddy.cn cookies for the monthly credits allowance, plan name, cycle reset, and the platform reward credits.
- [Tavily](docs/tavily.md) — API key for account-plan, per-key, and pay-as-you-go credit totals.
- [Linkup](docs/linkup.md) — API key for the current prepaid USD credit balance.
- [TinyApi](docs/tinyapi.md) — Browser or manual session cookies for aggregate available credits.
- [Exa](docs/exa.md) — Team Management service key plus an explicit API key ID for month-to-date USD spend.
- [Cosmic AI](docs/cosmic.md) — Explicit Personal Access Token and Project ID for separate project AI input/output counters and allowances.
- [Aerostack](docs/aerostack.md) — Explicit account JWT for monthly AI tokens used and the observed account allowance.
- [Sail Research](docs/sailresearch.md) — API key for organization credit balance and combined inference/Sailbox spend.
- [Sofya](docs/sofya.md) — API key for separate account plan and purchased credit balances, eligibility, and the reported monthly reset.
- [fal](docs/fal.md) — API key with billing read access for the current account credit balance.
- [FLORA](docs/flora.md) — API key with billing permission plus a workspace ID for the available USD balance and month-to-date spend.
- [Parallel](docs/parallel.md) — Browser session on platform.parallel.ai for the prepaid credit balance and pending debit.
- [Claude Platform](docs/claudeplatform.md) — Browser or manual platform.claude.com session cookies for Console API credit balance, expiring credit grants, and month-to-date spend.
- [Munito](docs/munito.md) — Admin API key with Read account data permission for today's and this month's spend against the organization's spend limits.
- [Trae CN](docs/traecn.md) — Browser session for account credit usage.
- [Chatbox AI](docs/chatbox.md) — API token
- [abliteration.ai](docs/abliteration.md) — API key for prepaid USD credits and cumulative usage.
- [OpenDesign](docs/opendesign.md) — Browser or manual session cookies for the active workspace's five-hour and weekly subscription allowance.
- [SiliconFlow](docs/siliconflow.md) — API key for the prepaid account balance on the China (CNY) or international (USD) API.
<!-- End generated provider additions -->

## Icon & Screenshot
The menu bar icon is a tiny usage meter. Bar meaning is provider-specific, and errors/stale data can dim the icon or
show an incident indicator.

## Features
- Multi-provider menu bar with per-provider toggles (Settings → Providers).
- Provider-specific usage meters with reset countdowns.
- Optional Codex web dashboard enrichments (code review remaining, usage breakdown, credits history).
- Inline spend and usage charts for API-backed providers such as OpenAI, Claude Admin API, OpenRouter, LiteLLM, z.ai, MiniMax, Mistral, and AWS Bedrock.
- Codex and Claude Plan Usage menus show a quota burndown from recorded snapshots, with the capture time and an even-use guide. The existing utilization history remains below it, and the line fills in as the app collects samples.
- Configurable cost-usage scans for Codex + Claude, plus reused chart UI for supported provider histories. Codex history uses a WAL-enabled SQLite store capped at 25,000 retained session entries and 256 MiB.
- A persistent Settings → Costs view for local estimates, grouped by native currency and provider. Each provider shows its accounts or history sources alongside its model breakdown; project/session views and daily/hourly trends share compact selectors. Incomplete history stays labeled, and source, privacy, export, and sharing controls remain available.
- Provider status polling with incident badges in the menu and icon overlay.
- Merge Icons mode to combine providers into one status item + switcher. With **Icon + Percent** and two enabled built-in providers, choose **Stacked** to show their first layout lines together. Automatic rows follow provider order and reserve explicit choices; disabling a selected provider uses a fallback and restores the saved choice when re-enabled. The dropdown menu stays available, and each provider keeps its own layout settings.
- Display controls for provider icons, labels, bars, reset-time style, and highest-usage auto-selection.
- Fresh installs default to Adaptive refresh. Existing users keep every valid stored choice, while legacy unset or
  invalid preferences resolve to 5 minutes. Manual and fixed 1m, 2m, 5m, 15m, and 30m alternatives remain available.
- Bundled CLI (`codexbar`) for scripts and CI (including `codexbar cost --provider codex`, `claude`, or `both` for local cost usage); macOS and Linux CLI builds available.
- WidgetKit widgets for supported providers.
- Localized app and website with a shared 23-language catalog, automatic website detection, persistent pickers, and RTL support.
- Optional session quota notifications, upcoming-reset warnings for unused Codex quota, and weekly-reset confetti.
- Privacy-first: on-device parsing by default; browser cookies are opt-in and reused (no passwords stored).

## Privacy note
Wondering if Tolkein scans your disk? It doesn’t crawl your filesystem; it reads a small set of known locations (browser cookies/local storage, provider config files, local JSONL logs) when the related features are enabled. Plain Adaptive refresh never inspects local agent activity. The separate Adaptive (agent-aware) option asks before inspecting the running-process list (including command lines) to identify Codex/Claude and reading bounded known-session metadata. Declining returns to plain Adaptive. When allowed with Agent Sessions hidden, CodexBar retains only the latest activity time and discards session paths and identities. Provider tokens and token-account settings live in the CodexBar config file with restrictive file permissions. See the discussion and audit notes in [issue #12](https://github.com/steipete/CodexBar/issues/12).

## macOS permissions (why they’re needed)
- **Full Disk Access (optional)**: only required to read Safari cookies/local storage for web-based providers. If you don’t grant it, use another supported browser, manual cookies/API keys, OAuth, or CLI/local sources where that provider supports them.
- **Keychain access (prompted by macOS)**:
  Chromium cookie import needs the browser’s Safe Storage item, and an explicitly enabled Claude OAuth repair may
  read Claude Code’s own Keychain item. Background CodexBar paths fail or skip instead of requesting authorization;
  a user-initiated import or repair can still show the macOS prompt. **Settings → Privacy & Data → Disable Keychain
  access** blocks CodexBar-owned Keychain operations and browser decryption, but cannot constrain provider-owned CLIs
  that CodexBar launches. Manual cookie headers, API keys, and file-backed sources remain alternatives where
  supported. See [Keychain prompts](docs/keychain-prompts.md) for Allow Once vs. Always Allow, recurring grants, and
  safe troubleshooting.
- **Files & Folders prompts (folder/volume access)**: CodexBar launches provider CLIs and local probes for some providers. If those helpers read a project directory or external drive, macOS may ask CodexBar for that folder/volume (e.g., Desktop or an external volume). This is driven by the helper’s working directory, not background disk scanning.
- **What we do not request in the background**: no Screen Recording or Accessibility permissions; user-triggered helper actions may ask macOS for Automation permission to open Terminal. No passwords are stored (browser cookies are reused when you opt in).

## Docs
- Providers overview: [docs/providers.md](docs/providers.md)
- Provider authoring: [docs/provider.md](docs/provider.md)
- UI & icon notes: [docs/ui.md](docs/ui.md)
- CLI reference: [docs/cli.md](docs/cli.md)
- Configuration: [docs/configuration.md](docs/configuration.md)
- Keychain prompts: [docs/keychain-prompts.md](docs/keychain-prompts.md)
- CLI configuration: [docs/cli-configuration.md](docs/cli-configuration.md)
- Widgets: [docs/widgets.md](docs/widgets.md)
- Architecture: [docs/architecture.md](docs/architecture.md)
- Refresh loop: [docs/refresh-loop.md](docs/refresh-loop.md)
- Status polling: [docs/status.md](docs/status.md)
- Packaging: [docs/packaging.md](docs/packaging.md)
- Development: [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)

## Getting started (dev)
- Clone the repo and open it in Xcode or run the scripts directly.
- Launch once, then toggle providers in Settings → Providers.
- Install/sign in to provider sources you rely on (CLIs, browser cookies, OAuth/device flow, API keys, or local app/config files).
- Optional: set OpenAI cookies (Automatic or Manual) for Codex dashboard extras.

## Build from source
Requires macOS 15+ and Swift 6.2+.

```bash
./Scripts/package_app.sh        # builds CodexBar.app in-place with ad-hoc signing
open CodexBar.app
```

Dev loop:
```bash
./Scripts/compile_and_run.sh
./Scripts/compile_and_run.sh --test  # also run the sharded test suite before packaging/relaunching
make check                           # format, lint and English strings (about 30 s)
make check-all                       # plus packaging, CI and site self-tests
make docs-list                       # list docs with frontmatter summaries
```

CLI install:
```bash
# after installing CodexBar.app in /Applications
./bin/install-codexbar-cli.sh
```

## Credits
- Based on [CodexBar](https://github.com/steipete/CodexBar) by Peter Steinberger (MIT License).
- Cost usage tracking inspired by [ccusage](https://github.com/ryoppippi/ccusage) (MIT).

## License
MIT. Tolkein includes code from CodexBar, © Peter Steinberger; see [LICENSE](LICENSE).
