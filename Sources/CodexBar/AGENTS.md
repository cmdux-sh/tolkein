# Mac UI in this target (Tolkein fork)

The app's SwiftUI is built on MacDesignSystem (the private `cmdux-sh/MacDesignSystem` package). Its design-guide
MCP server, `mac-design-system`, gives agents the components, tokens, recipes, checks and review loop. Use it for
any UI change here, before writing code:

1. **New screen:** start from `get_recipe` (`menu-bar-panel`, `settings-window`, `app-window`). **Restyling an
   existing screen:** restructure it to the closest recipe first; do not only swap colours onto its old layout.
2. **Pieces:** `find_component` for each need, then `get_guide` on the page. Use library components and
   `MacColor`/`MacSpace`/`MacSize`/`MacRadius`/`MacTextRole`/`MacSpring` tokens only. No app-local theme enums,
   no forced dark mode, no fixed AppKit layer colours.
3. **Check:** `check_swiftui` every SwiftUI file you change, and fix every finding.
4. **Review:** render the screen in light and dark, with real-length stress data, every state, and a short
   height that must scroll. For the Usage Board:
   `CODEXBAR_SNAPSHOT_DIR=/tmp/tolkein-snapshots swift test --filter UsageBoardSnapshotTests`
   then open the PNGs. Add a case to that suite (or a similar one) for a new screen. Run
   `get_guide("composition/review")`, give a one-line verdict per item, and make targeted fixes.
5. **Missing component:** add it to MacDesignSystem with a catalog page and tests, tag a version, and bump the
   requirement in `Package.swift` (resolve the widget workspace too; see `docs/DEVELOPMENT.md`). Do not
   hand-roll it here.

If the `mac-design-system` tools are not available, install them from a MacDesignSystem clone with
`Scripts/install-mcp.sh` and start a new session.
