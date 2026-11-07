# Decisions

## 2026-11-06: One repository for the app and the companion

`cmdux-sh/tolkein` holds both projects. The CodexBar fork (the Mac menu-bar app) stays at the repository root. The former `cmdux-sh/tolkeins` repository (collector, Cloudflare Worker, iPhone widget) lives in `companion/`, imported with its history.

Why: the two repositories had nearly the same name and were easy to confuse. The companion reads the app, so the two belong together.

The app stays at the root and the root README is left as upstream wrote it, so syncing with `steipete/CodexBar` keeps merging cleanly.

## 2026-11-06: Archive cmdux-sh/tolkeins

The old `cmdux-sh/tolkeins` repository is archived (read-only), and its README points here. Its two open drafts moved to tolkein PRs #3 and #4.

Why: everything from it now lives in `companion/` with its history. Archiving keeps old links working and can be undone.

## 2026-11-06: Manus reads a saved session token first

When a Manus session token is saved (environment or pasted header), the app uses only that token and does not open browser cookies, even when Manus cookies are set to off. A rejected token fails with "Invalid Manus session token." instead of falling back to the browser.

Why: reading browser cookies triggers macOS privacy prompts. Pasting a fresh token is the accepted cost when one expires.

## 2026-11-07: Adopt MacDesignSystem for the Mac UI

Tolkein's Mac UI moves to the shared SwiftUI package `cmdux-sh/MacDesignSystem`, one surface at a time:
the Usage Board panel first, then the Settings panes (simplest first), and the menu cards last, visuals only.

Why: one set of tokens, controls and surfaces across Arturo's Mac apps, matching macOS 26 Liquid Glass.
The menu cards come last because their measured heights, row recycling and click regions are fragile.

## 2026-11-07: Minimum macOS 15

The deployment target rises from macOS 14 to macOS 15 everywhere it is declared: `Package.swift`, the packaging
link flag and `minos` check, both `LSMinimumSystemVersion` values, the widget project, the release jobs, and the
Sparkle appcast minimum in `.github/release.json`.

Why: MacDesignSystem targets macOS 15. The appcast minimum keeps Sparkle from offering macOS 14 users an
update that would not launch; their last compatible build keeps working.

The floor is package-wide, so the macOS CLI also needs macOS 15; Linux builds are unaffected. The root README and
the codexbar.app site (`docs/index.html`, `docs/site-locales.mjs`) still say macOS 14+, because they are upstream's and
stay as upstream wrote them. The Homebrew tap's `depends_on macos:` moves to `:sequoia` with the first macOS 15 release.

## 2026-11-07: Private package, read by CI through a deploy key

MacDesignSystem stays private. `Package.swift` declares it only on macOS, so Linux never builds it; SwiftPM still
clones every pinned package, so every CI and release job that runs SwiftPM reads it with a read-only SSH deploy key, stored as the `MAC_DESIGN_SYSTEM_DEPLOY_KEY` secret and installed
by `Scripts/ci-grant-mac-design-system.sh`, which gives the key its own SSH host alias, rewrites only that package URL to
it, and pins GitHub's host keys.

Why: Arturo chose to keep the package private with a CI credential. A deploy key is scoped to one repository and
read-only, unlike a personal access token. The package is first-party, so it needs no bundled third-party notice.

## 2026-11-07: The Usage Board follows the app's appearance

The Usage Board takes its colors, radii, card surface and buttons from MacDesignSystem and no longer forces dark mode. It follows light or dark like the rest of the Mac UI. Dark keeps the near-black floor; light uses white raised cards on the near-white window. The board's amber warning color stays local until MacDesignSystem has a warning token.

Why: one appearance-aware look across the app. Arturo's design system already defines both appearances, so the board needs no separate dark-only palette.

## 2026-11-07: The Usage Board is rebuilt from library components

The first restyle only swapped token colours onto the board's own hand-built rows, cards and bars, and Arturo judged it a mess. The board is now built from MacDesignSystem 0.3.0 components, guided by its design-guide MCP:
- The sidebar is `MacSourceList`, with each provider's logo, a short value ("42%") and a status symbol.
- App commands are plain library buttons in a footer.
- Usage windows are `MacMeter` and statuses are `MacStatusLabel`.
- Overview cards are `macCard`, and only clickable providers get one.

Providers that need attention share one "Needs attention" card instead of a red pill each. The board's local theme (colours, metrics, fonts) is gone.

Why: Arturo asked for the board to be rebuilt with the MCP. The missing pieces (meter, status label, richer sidebar rows) were added to the library first, so other apps get them too.

## 2026-11-07: The Usage Board uses the panel chrome

After reviewing the rebuilt board in the running app, Arturo found that nothing was pinned at the top, provider actions formed a band of big buttons, fact labels wrapped and notes repeated facts. He also flagged button sizes, the chrome, font sizes, hierarchy, spacing and the bars. The board moves to MacDesignSystem 0.4.0:
- `MacWindow(chrome: .panel)`: a glass rim and inset sidebar, with a pinned title row showing the selected provider, its plan and freshness.
- Refresh and a "…" menu of provider commands sit in the title row.
- "All providers" is the first row of the provider list.
- App commands (Classic menu, Settings, Quit) form a small footer.
- Facts are a `MacKeyValueList`.
- Notes that only restate facts are dropped.
- Meter captions are one line each.
- When every failing provider has the same problem, the "Needs attention" card says it once.

Why: Arturo chose to add the missing components and MCP rules first, then redo the board with them. The review rendered real-length data, a mostly failing provider list, and a short height that must scroll.
