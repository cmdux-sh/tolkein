import CodexBarCore
import SwiftUI

/// One provider's page. User plugin providers have no page here yet; their rows show an empty detail.
@MainActor
struct ProviderSettingsPane: View {
    let instanceID: ProviderInstanceID
    let context: SettingsPaneContext

    var body: some View {
        if let provider = self.instanceID.firstPartyProvider {
            // A new identity per provider, so each page starts with its own model.
            ProviderSettingsPaneHost(provider: provider, context: self.context)
                .id(self.instanceID)
        }
    }
}

/// Owns the page model for one provider while its page is shown.
@MainActor
private struct ProviderSettingsPaneHost: View {
    @State private var model: ProviderSettingsPageModel

    init(provider: UsageProvider, context: SettingsPaneContext) {
        self._model = State(initialValue: ProviderSettingsPageModel(
            provider: provider,
            settings: context.settings,
            store: context.store,
            managedCodexAccountCoordinator: context.managedCodexAccountCoordinator,
            codexAccountPromotionCoordinator: context.codexAccountPromotionCoordinator,
            runProviderLoginFlow: context.runProviderLoginFlow))
    }

    var body: some View {
        ProviderSettingsPage(model: self.model)
    }
}

extension ProviderSettingsPane {
    /// Per built-in provider: its page, found by name or identifier, and the page's Sign-in & connection, Display,
    /// Alerts and Options sections, found with the provider's name.
    static var searchEntries: [SettingsSearchEntry] {
        UsageProvider.allCases.flatMap { provider in
            let pane = SettingsPane.provider(provider.instanceID)
            let page = SettingsSearchEntry(
                id: pane.persistenceToken,
                pane: pane,
                title: pane.title,
                keywords: [provider.rawValue])
            let sections = ProviderSettingsPageSection.searchable.compactMap { section in
                section.searchEntryID(for: provider).map { id in
                    SettingsSearchEntry(id: id, pane: pane, title: section.title, keywords: [pane.title, provider.rawValue])
                }
            }
            return [page] + sections
        }
    }
}
