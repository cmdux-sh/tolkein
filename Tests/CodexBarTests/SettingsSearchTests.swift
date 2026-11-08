import CodexBarCore
import Testing
@testable import CodexBar

struct SettingsSearchTests {
    private static let panes: [SettingsPane] = [.general, .menuBar, .menu, .integrations, .about]

    private static func filtered(_ query: String) -> [SettingsPane] {
        CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            SettingsSearch.filteredPanes(self.panes, query: query)
        }
    }

    @Test
    func `empty query keeps every pane in order`() {
        #expect(Self.filtered("  ") == Self.panes)
    }

    @Test
    func `pane titles match case insensitively`() {
        #expect(Self.filtered("INTEGRAT") == [.integrations])
    }

    @Test
    func `every query word must match the same pane`() {
        #expect(Self.filtered("menu") == [.menuBar, .menu])
        #expect(Self.filtered("menu bar") == [.menuBar])
        #expect(Self.filtered("menu general").isEmpty)
    }

    @Test
    func `matching ignores diacritics`() {
        #expect(SettingsSearch.matches(words: ["CAFE", "lo"], fields: ["Café login"]))
        #expect(!SettingsSearch.matches(words: ["cafe", "missing"], fields: ["Café login"]))
    }
}

struct SettingsSearchIndexRankingTests {
    private static func entry(_ setting: String, _ title: String, keywords: String...) -> SettingsSearchEntry {
        SettingsSearchEntry(id: "general/\(setting)", pane: .general, title: title, keywords: keywords)
    }

    private static let entries: [SettingsSearchEntry] = [
        entry("keychain", "Disable Keychain access", keywords: "Privacy"),
        entry("autoRefresh", "Automatic refresh"),
        entry("refresh", "Refresh interval", keywords: "Refreshing"),
        entry("refreshOnOpen", "Refresh when the menu opens", keywords: "Refreshing"),
        entry("status", "Check provider status", keywords: "Refreshing"),
        entry("cafe", "Café hours", keywords: "Schedule"),
    ]

    private static func ranked(_ query: String) -> [String] {
        SettingsSearchIndex.ranked(self.entries, query: query).map(\.id)
    }

    @Test
    func `empty query has no results`() {
        #expect(Self.ranked("").isEmpty)
        #expect(Self.ranked("   ").isEmpty)
    }

    @Test
    func `titles that start with the query rank before titles that only contain it`() {
        #expect(Self.ranked("refresh") == [
            "general/refresh",
            "general/refreshOnOpen",
            "general/autoRefresh",
            "general/status",
        ])
        #expect(Self.ranked("refresh when") == ["general/refreshOnOpen"])
    }

    @Test
    func `title matches rank before keyword only matches`() {
        let entries = [
            Self.entry("keywordOnly", "Check provider status", keywords: "Refreshing"),
            Self.entry("titleWord", "Interval to refresh"),
        ]
        #expect(SettingsSearchIndex.ranked(entries, query: "refresh").map(\.id)
            == ["general/titleWord", "general/keywordOnly"])
    }

    @Test
    func `ties keep the index order`() {
        let entries = [
            Self.entry("second", "Alpha one"),
            Self.entry("first", "Alpha two"),
        ]
        #expect(SettingsSearchIndex.ranked(entries, query: "alpha").map(\.id) == ["general/second", "general/first"])
    }

    @Test
    func `every word must match the title or a keyword`() {
        #expect(Self.ranked("keychain privacy") == ["general/keychain"])
        #expect(Self.ranked("keychain refreshing").isEmpty)
    }

    @Test
    func `ranking ignores case and diacritics`() {
        #expect(Self.ranked("CAFE") == ["general/cafe"])
        #expect(Self.ranked("schédule") == ["general/cafe"])
    }
}

@MainActor
struct SettingsSearchIndexTests {
    private static func allEntries() -> [SettingsSearchEntry] {
        CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            SettingsSearchIndex.allEntries
        }
    }

    @Test
    func `every pane has entries`() {
        let panes = Set(Self.allEntries().map(\.pane))
        for pane in SettingsPane.fixedPanes {
            #expect(panes.contains(pane), "\(pane)")
        }
        for provider in UsageProvider.allCases {
            #expect(panes.contains(.provider(provider.instanceID)), "\(provider)")
        }
    }

    @Test
    func `every fixed pane is findable by its title`() {
        let entries = Self.allEntries()
        CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            for pane in SettingsPane.fixedPanes {
                let titleEntry = entries.first { $0.id == pane.persistenceToken }
                #expect(titleEntry?.pane == pane, "\(pane)")
                #expect(titleEntry?.title == pane.title, "\(pane)")
            }
        }
    }

    @Test
    func `entry ids are unique`() {
        let ids = Self.allEntries().map(\.id)
        let duplicates = Dictionary(grouping: ids, by: { $0 }).filter { $0.value.count > 1 }.keys.sorted()
        #expect(duplicates.isEmpty, "\(duplicates)")
    }

    @Test
    func `entries have titles and ids scoped to their pane`() {
        for entry in Self.allEntries() {
            #expect(!entry.title.trimmingCharacters(in: .whitespaces).isEmpty, "\(entry.id)")
            #expect(entry.id == entry.pane.persistenceToken || entry.id.hasPrefix(entry.pane.persistenceToken + "/"))
        }
    }

    @Test
    func `index finds individual settings`() {
        CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            let entries = SettingsSearchIndex.allEntries
            #expect(SettingsSearchIndex.ranked(entries, query: "keychain").first?.pane == .privacy)
            #expect(SettingsSearchIndex.ranked(entries, query: "language").first?.pane == .general)
            #expect(SettingsSearchIndex.ranked(entries, query: "hooks").first?.pane == .integrations)
            #expect(SettingsSearchIndex.ranked(entries, query: "export preferences").first?.pane == .privacy)
        }
    }

    @Test
    func `hidden debug pane is left out of the searchable entries`() {
        #expect(!SettingsSearchIndex.entries(includingDebug: false).contains { $0.pane == .debug })
        #expect(SettingsSearchIndex.entries(includingDebug: true).contains { $0.pane == .debug })
    }
}
