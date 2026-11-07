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
