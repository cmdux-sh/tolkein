import SwiftUI

/// Plugins: user provider plugins. The last row of the sidebar's Providers section.
@MainActor
struct PluginsSettingsPane: View {
    #if canImport(JavaScriptCore)
    @State private var model: PluginsSettingsModel

    init(context: SettingsPaneContext) {
        self.init(model: PluginsSettingsModel(settings: context.settings, store: context.store))
    }

    /// - Parameter model: the page's state; tests pass one that reads a fixture directory.
    init(model: PluginsSettingsModel) {
        self._model = State(initialValue: model)
    }

    var body: some View {
        PluginsSettingsView(model: self.model)
    }
    #else
    init(context _: SettingsPaneContext) {}

    var body: some View {
        EmptyView()
    }
    #endif
}

extension PluginsSettingsPane {
    /// The settings search can jump to. Each one marks its row with `.settingsAnchor(anchor(_:))`.
    enum SearchSetting: String {
        case install
        case directory
    }

    static func anchor(_ setting: SearchSetting) -> String {
        "\(SettingsPane.plugins.persistenceToken)/\(setting.rawValue)"
    }

    static var searchEntries: [SettingsSearchEntry] {
        let pane = SettingsPane.plugins
        let providerPlugins = L("Provider Plugins")
        return [
            .paneTitle(pane, keywords: providerPlugins),
            SettingsSearchEntry(id: self.anchor(.install), pane: pane, title: L("Install plugin"), keywords: [
                providerPlugins,
            ]),
            SettingsSearchEntry(id: self.anchor(.directory), pane: pane, title: L("Plugins directory"), keywords: [
                providerPlugins,
            ]),
        ]
    }
}
