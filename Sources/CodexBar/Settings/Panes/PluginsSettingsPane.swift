import SwiftUI

/// Plugins: user provider plugins. The last row of the sidebar's Providers section.
/// Shows the old `PluginsPane` until the Internal UI rebuild replaces this file.
@MainActor
struct PluginsSettingsPane: View {
    let context: SettingsPaneContext

    var body: some View {
        PluginsPane(settings: self.context.settings, store: self.context.store)
    }
}

extension PluginsSettingsPane {
    static var searchEntries: [SettingsSearchEntry] {
        let pane = SettingsPane.plugins
        let providerPlugins = L("Provider Plugins")
        return [
            .paneTitle(pane, keywords: providerPlugins),
            pane.searchEntry("install", L("Install plugin"), keywords: providerPlugins),
            pane.searchEntry("directory", L("Plugins directory"), keywords: providerPlugins),
        ]
    }
}
