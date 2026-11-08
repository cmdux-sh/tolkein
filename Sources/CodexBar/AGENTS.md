# Mac UI in this target (Tolkein fork)

The app's SwiftUI is built on Internal UI (the private `cmdux-sh/internal-ui` package, module `InternalUI`). Its design-guide
MCP server, `internal-ui`, gives agents the components, tokens, recipes, checks and review loop. Use it for
any UI change here, before writing code:

1. **New screen:** start from `get_recipe` (`menu-bar-panel`, `settings-window`, `app-window`). **Restyling an
   existing screen:** restructure it to the closest recipe first; do not only swap colours onto its old layout.
2. **Pieces:** `find_component` for each need, then `get_guide` on the page. Use library components and
   `MacColor`/`MacSpace`/`MacSize`/`MacRadius`/`MacTextRole`/`MacSpring` tokens only. No app-local theme enums,
   no forced dark mode, no fixed AppKit layer colours.
3. **Check:** `check_swiftui` every SwiftUI file you change, and fix every finding. In Claude Code, a hook in
   `.claude/settings.json` runs the same checker after every edit to a file that imports InternalUI and reports
   findings back (`internal-ui-mcp hook`); fix them before moving on, including any that were already there.
4. **Review:** render the screen in light and dark, with real-length stress data, every state, and a short
   height that must scroll. For the Usage Board:
   `CODEXBAR_SNAPSHOT_DIR=/tmp/tolkein-snapshots swift test --filter UsageBoardSnapshotTests`
   then open the PNGs. Add a case to that suite (or a similar one) for a new screen. Run
   `get_guide("composition/review")`, give a one-line verdict per item, and make targeted fixes.
5. **Missing component:** add it to Internal UI with a catalog page and tests, tag a version, and bump the
   requirement in `Package.swift` (resolve the widget workspace too; see `docs/DEVELOPMENT.md`). Do not
   hand-roll it here.

## Settings panes

`SettingsPane` (`Settings/PreferencesView.swift`) lists the panes; `Settings/SettingsPaneRouter.swift` maps each one
to a wrapper view in `Settings/Panes/` (`GeneralSettingsPane`, `AlertsSettingsPane`, and so on). Rebuilding a pane
means replacing its one wrapper file: keep `init(context: SettingsPaneContext)` and `static var searchEntries`, list
every setting the pane shows in `searchEntries` (`pane.searchEntry(_:_:keywords:)`, ids unique within the pane), and
delete the old view it wrapped once nothing else uses it. Leave the router and `SettingsSearchIndex` alone unless a
pane is added or removed.

If the `internal-ui` tools are not available, install them from an Internal UI clone (`cmdux-sh/internal-ui`) with
`Scripts/install-mcp.sh` and start a new session.
