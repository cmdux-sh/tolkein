import CodexBarCore
import InternalUI
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
///
/// The routed pane sits in a `ScrollViewReader`: when search picks a result, the row tagged with its
/// `.settingsAnchor(id)` scrolls into view and highlights (see `SettingsSearchJump`).
@MainActor
struct SettingsPaneRouter: View {
    let pane: SettingsPane
    let context: SettingsPaneContext

    var body: some View {
        self.routedPane
            .modifier(SettingsSearchJump(selection: self.context.selection))
    }

    @ViewBuilder
    private var routedPane: some View {
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

/// Carries a search jump into the routed pane: sets `settingsSearchTarget`, scrolls the anchored row into view,
/// and ends the jump after `IUHighlight.searchHold`, once the row's tint has faded.
@MainActor
private struct SettingsSearchJump: ViewModifier {
    let selection: PreferencesSelection

    func body(content: Content) -> some View {
        ScrollViewReader { proxy in
            content
                .environment(\.settingsSearchTarget, self.selection.searchTarget)
                .task(id: self.selection.searchTarget) {
                    guard let target = self.selection.searchTarget else { return }
                    // The pane may have been swapped in by the same change; let it lay out its rows first.
                    await Task.yield()
                    proxy.scrollTo(target, anchor: .center)
                    try? await Task.sleep(for: .seconds(IUHighlight.searchHold))
                    guard !Task.isCancelled else { return }
                    self.selection.clearSearchTarget(matching: target)
                }
        }
    }
}
