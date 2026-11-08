import CodexBarCore
import SwiftUI

/// One provider's page. User plugin providers have no page here yet; their rows show an empty detail.
/// Shows the old `ProvidersPane` until the Internal UI rebuild replaces this file.
@MainActor
struct ProviderSettingsPane: View {
    let instanceID: ProviderInstanceID
    let context: SettingsPaneContext

    var body: some View {
        if let provider = self.instanceID.firstPartyProvider {
            ProvidersPane(
                provider: provider,
                settings: self.context.settings,
                store: self.context.store,
                managedCodexAccountCoordinator: self.context.managedCodexAccountCoordinator,
                codexAccountPromotionCoordinator: self.context.codexAccountPromotionCoordinator,
                runProviderLoginFlow: self.context.runProviderLoginFlow)
                .id(self.instanceID)
        }
    }
}

extension ProviderSettingsPane {
    /// One entry per built-in provider, found by its name or its identifier.
    static var searchEntries: [SettingsSearchEntry] {
        UsageProvider.allCases.map { provider in
            let pane = SettingsPane.provider(provider.instanceID)
            return SettingsSearchEntry(
                id: pane.persistenceToken,
                pane: pane,
                title: pane.title,
                keywords: [provider.rawValue])
        }
    }
}
