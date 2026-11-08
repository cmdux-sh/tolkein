import Foundation

/// One searchable place in Settings: a pane, or a single setting inside it.
struct SettingsSearchEntry: Identifiable, Hashable {
    /// Stable, unique across the index: the pane's persistence token, plus `/` and the setting's key.
    let id: String
    let pane: SettingsPane
    /// Localized, as the row shows it.
    let title: String
    /// Extra localized words that should find this entry: its section, subtitle or synonyms.
    let keywords: [String]
}

extension SettingsSearchEntry {
    /// The entry for the pane itself, titled like its sidebar row.
    static func paneTitle(_ pane: SettingsPane, keywords: String...) -> SettingsSearchEntry {
        SettingsSearchEntry(id: pane.persistenceToken, pane: pane, title: pane.title, keywords: keywords)
    }
}

extension SettingsSearchEntry {
    /// The retired Advanced pane's name, localized and in English, so searching "Advanced" still finds the settings
    /// that moved to Privacy & Data and Integrations.
    static var formerAdvancedKeyword: String {
        let localized = L("tab_advanced")
        return localized == "Advanced" ? localized : "\(localized) Advanced"
    }
}

extension SettingsPane {
    /// An entry for one setting on this pane. `setting` only needs to be unique within the pane.
    func searchEntry(_ setting: String, _ title: String, keywords: String...) -> SettingsSearchEntry {
        SettingsSearchEntry(id: "\(self.persistenceToken)/\(setting)", pane: self, title: title, keywords: keywords)
    }
}

enum SettingsSearchIndex {
    /// Every searchable entry, pane by pane in sidebar order. Each pane's wrapper in `Settings/Panes/` owns its list.
    @MainActor
    static var allEntries: [SettingsSearchEntry] {
        Array([
            GeneralSettingsPane.searchEntries,
            MenuBarSettingsPane.searchEntries,
            MenuSettingsPane.searchEntries,
            AlertsSettingsPane.searchEntries,
            CostsSettingsPane.searchEntries,
            SyncSettingsPane.searchEntries,
            IntegrationsSettingsPane.searchEntries,
            PrivacySettingsPane.searchEntries,
            AboutSettingsPane.searchEntries,
            DebugSettingsPane.searchEntries,
            PluginsSettingsPane.searchEntries,
            ProviderSettingsPane.searchEntries,
        ].joined())
    }

    /// The searchable entries, leaving out the Debug pane while the debug-settings switch hides it.
    @MainActor
    static func entries(includingDebug: Bool) -> [SettingsSearchEntry] {
        self.allEntries.filter { includingDebug || $0.pane != .debug }
    }

    /// Entries that match `query`, best first. Uses `SettingsSearch`'s rules: every query word must appear in the
    /// title or a keyword, ignoring case and diacritics. Titles that start with the query rank first, then titles
    /// that contain every word, then keyword-only matches; ties keep the index order. An empty query matches nothing.
    static func ranked(_ entries: [SettingsSearchEntry], query: String) -> [SettingsSearchEntry] {
        let words = SettingsSearch.words(in: query)
        guard !words.isEmpty else { return [] }
        let phrase = words.joined(separator: " ")
        return entries.enumerated()
            .compactMap { offset, entry in
                self.tier(of: entry, words: words, phrase: phrase).map { (tier: $0, offset: offset, entry: entry) }
            }
            .sorted { ($0.tier, $0.offset) < ($1.tier, $1.offset) }
            .map(\.entry)
    }

    private static func tier(of entry: SettingsSearchEntry, words: [String], phrase: String) -> Int? {
        guard SettingsSearch.matches(words: words, fields: [entry.title] + entry.keywords) else { return nil }
        if entry.title.range(of: phrase, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) != nil {
            return 0
        }
        return SettingsSearch.matches(words: words, fields: [entry.title]) ? 1 : 2
    }
}
