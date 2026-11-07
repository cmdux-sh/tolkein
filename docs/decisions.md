# Decisions

Fork-specific decisions for Tolkein (the cmdux-sh CodexBar fork), newest last, each with the reason.

## 2026-11-07 — Adopt MacDesignSystem for the Mac UI

Tolkein's Mac UI moves to the shared SwiftUI package `cmdux-sh/MacDesignSystem`, one surface at a time:
the Usage Board panel first, then the Settings panes (simplest first), and the menu cards last, visuals only.

**Why:** one set of tokens, controls and surfaces across Arturo's Mac apps, matching macOS 26 Liquid Glass.
The menu cards come last because their measured heights, row recycling and click regions are fragile.

## 2026-11-07 — Minimum macOS 15

The deployment target rises from macOS 14 to macOS 15 everywhere it is declared: `Package.swift`, the packaging
link flag and `minos` check, both `LSMinimumSystemVersion` values, the widget project, the release jobs, and the
Sparkle appcast minimum in `.github/release.json`.

**Why:** MacDesignSystem targets macOS 15. The appcast minimum keeps Sparkle from offering macOS 14 users an
update that would not launch; their last compatible build keeps working.

## 2026-11-07 — Private package, read by CI through a deploy key

MacDesignSystem stays private. `Package.swift` declares it only on macOS, so Linux jobs never fetch it. macOS CI and
release jobs read it with a read-only SSH deploy key, stored as the `MAC_DESIGN_SYSTEM_DEPLOY_KEY` secret and installed
by `Scripts/ci-grant-mac-design-system.sh`, which rewrites only that package URL to SSH and pins GitHub's host keys.

**Why:** Arturo chose to keep the package private with a CI credential. A deploy key is scoped to one repository and
read-only, unlike a personal access token. The package is first-party, so it needs no bundled third-party notice.
