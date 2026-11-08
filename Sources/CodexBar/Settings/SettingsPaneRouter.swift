import CodexBarCore
import SwiftUI

/// Everything a Settings pane may need. `PreferencesView` builds it; each pane reads only what it uses, so a
/// rebuilt pane can take a new dependency without changing the router.
@MainActor
struct SettingsPaneContext {
    let settings: SettingsStore
    let store: UsageStore
    let cloudSyncState: CloudSyncState
    let updater: UpdaterProviding
    let selection: PreferencesSelection
    let managedCodexAccountCoordinator: ManagedCodexAccountCoordinator
    let codexAccountPromotionCoordinator: CodexAccountPromotionCoordinator
    let runProviderLoginFlow: @MainActor (UsageProvider) async -> Void
}

/// Maps each Settings pane to its view. Every pane owns one wrapper type in `Settings/Panes/`, so a rebuilt pane
/// replaces its own file and leaves this switch alone.
@MainActor
struct SettingsPaneRouter: View {
    let pane: SettingsPane
    let context: SettingsPaneContext

    var body: some View {
        switch self.pane {
        case .general: GeneralSettingsPane(context: self.context)
        case .menuBar: MenuBarSettingsPane(context: self.context)
        case .menu: MenuSettingsPane(context: self.context)
        case .alerts: AlertsSettingsPane(context: self.context)
        case .costs: CostsSettingsPane(context: self.context)
        case .sync: SyncSettingsPane(context: self.context)
        case .integrations: IntegrationsSettingsPane(context: self.context)
        case .privacy: PrivacySettingsPane(context: self.context)
        case .about: AboutSettingsPane(context: self.context)
        case .debug: DebugSettingsPane(context: self.context)
        case .plugins: PluginsSettingsPane(context: self.context)
        case let .provider(instanceID): ProviderSettingsPane(instanceID: instanceID, context: self.context)
        }
    }
}
