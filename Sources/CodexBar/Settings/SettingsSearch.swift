import CodexBarCore
import Foundation

enum SettingsSearch {
    static func words(in query: String) -> [String] {
        query.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// Every query word must appear in at least one field, ignoring case and diacritics.
    static func matches(words: [String], fields: [String]) -> Bool {
        words.allSatisfy { word in
            fields.contains { $0.range(of: word, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
    }
}

/// What the Settings sidebar lists while its search field has text: the matching settings, best first, each with
/// its pane, then the matching providers.
struct SettingsSearchResults: Equatable {
    /// Matching panes and settings from `SettingsSearchIndex`, ranked by `SettingsSearchIndex.ranked`.
    let settings: [SettingsSearchEntry]
    /// Matching providers, ranked the same way, ties in the sidebar's provider order.
    let providers: [SettingsSearchEntry]

    var isEmpty: Bool {
        self.settings.isEmpty && self.providers.isEmpty
    }

    /// - Parameters:
    ///   - entries: the searchable settings (`SettingsSearchIndex.entries(includingDebug:)`). Their provider entries
    ///     are left out: `providers` covers every provider the sidebar lists, by more of its names.
    ///   - providers: the providers in sidebar order. The chip filter does not apply: search looks everywhere.
    static func results(
        for query: String,
        entries: [SettingsSearchEntry],
        providers: [SettingsSearchEntry]) -> SettingsSearchResults
    {
        let settings = entries.filter { entry in
            if case .provider = entry.pane { return false }
            return true
        }
        return SettingsSearchResults(
            settings: SettingsSearchIndex.ranked(settings, query: query),
            providers: SettingsSearchIndex.ranked(providers, query: query))
    }
}

extension SettingsSearchEntry {
    /// A provider's search entry: found by its name, short name, identifier, CLI name or a CLI alias, as the
    /// sidebar's provider search always has been.
    static func provider(_ provider: UsageProvider, displayName: String) -> SettingsSearchEntry {
        let pane = SettingsPane.provider(provider.instanceID)
        let descriptor = ProviderDescriptorRegistry.descriptor(for: provider)
        let keywords = [descriptor.metadata.shortDisplayName, provider.rawValue, descriptor.cli.name]
            + descriptor.cli.aliases
        return SettingsSearchEntry(id: pane.persistenceToken, pane: pane, title: displayName, keywords: keywords)
    }
}
