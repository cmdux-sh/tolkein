import SwiftUI

/// Debug: logging, probes, caches and error simulation. Listed only while the debug-settings switch is on.
/// Shows the old `DebugPane` until the Internal UI rebuild replaces this file.
@MainActor
struct DebugSettingsPane: View {
    let context: SettingsPaneContext

    var body: some View {
        DebugPane(settings: self.context.settings, store: self.context.store)
    }
}

extension DebugSettingsPane {
    static var searchEntries: [SettingsSearchEntry] {
        let pane = SettingsPane.debug
        let logging = L("section_logging")
        return [
            .paneTitle(pane),
            pane.searchEntry("fileLogging", L("enable_file_logging"), keywords: logging),
            pane.searchEntry("verbosity", L("verbosity_title"), keywords: logging),
            pane.searchEntry("forceAnimation", L("force_animation_next_refresh")),
            pane.searchEntry("pluginEngine", L("use_javascriptcore_plugin_engine"), keywords: L("Provider Plugins")),
            pane.searchEntry("loadingAnimations", L("section_loading_animations")),
            pane.searchEntry("probeLogs", L("section_probe_logs")),
            pane.searchEntry("fetchStrategy", L("section_fetch_strategy")),
            pane.searchEntry("caches", L("section_caches")),
            pane.searchEntry("cliSessions", L("section_cli_sessions")),
            pane.searchEntry("errorSimulation", L("section_error_simulation")),
            pane.searchEntry("cliPaths", L("section_cli_paths")),
        ]
    }
}
