import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct SettingsSearchTests {
    @Test
    func `matching ignores diacritics`() {
        #expect(SettingsSearch.matches(words: ["CAFE", "lo"], fields: ["Café login"]))
        #expect(!SettingsSearch.matches(words: ["cafe", "missing"], fields: ["Café login"]))
    }

    @Test
    func `choosing the best result opens its pane and targets its row until the jump ends`() throws {
        try CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            let providers = UsageProvider.allCases.map { provider in
                SettingsSearchEntry.provider(provider, displayName: SettingsPane.provider(provider.instanceID).title)
            }
            let results = SettingsSearchResults.results(
                for: "keychain",
                entries: SettingsSearchIndex.entries(includingDebug: false),
                providers: providers)
            let best = try #require(results.settings.first)
            #expect(best.pane == .privacy)
            #expect(results.settings.allSatisfy {
                if case .provider = $0.pane {
                    false
                } else {
                    true
                }
            })

            let selection = PreferencesSelection(userDefaults: InMemoryUserDefaults())
            selection.reveal(best)
            #expect(selection.pane == .privacy)
            #expect(selection.searchTarget == best.id)

            // A newer jump wins; ending an older one leaves it alone.
            selection.clearSearchTarget(matching: "general/language")
            #expect(selection.searchTarget == best.id)
            selection.clearSearchTarget(matching: best.id)
            #expect(selection.searchTarget == nil)

            // Going back to a pane does not tint its row again.
            selection.reveal(best)
            selection.goBack()
            #expect(selection.pane == .general)
            #expect(selection.searchTarget == nil)

            // Providers are found by their CLI aliases too, and only in the providers group.
            let kilo = SettingsSearchResults.results(for: "kilo-ai", entries: [], providers: providers)
            #expect(kilo.settings.isEmpty)
            #expect(kilo.providers.map(\.pane) == [.provider(UsageProvider.kilo.instanceID)])
            #expect(SettingsSearchResults.results(
                for: "zzqx",
                entries: SettingsSearchIndex.allEntries,
                providers: providers)
                .isEmpty)
        }
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
    func `every localization key in the pane entry lists resolves`() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let panes = root.appendingPathComponent("Sources/CodexBar/Settings/Panes")
        let english = try #require(NSDictionary(contentsOf: root.appendingPathComponent(
            "Sources/CodexBar/Resources/en.lproj/Localizable.strings")) as? [String: String])
        let keyPattern = try NSRegularExpression(pattern: #"\bL\("((?:[^"\\]|\\.)*)"\)"#)
        var keys: Set<String> = []
        for file in try FileManager.default.contentsOfDirectory(at: panes, includingPropertiesForKeys: nil) {
            let source = try String(contentsOf: file, encoding: .utf8)
            let range = NSRange(source.startIndex..., in: source)
            for match in keyPattern.matches(in: source, range: range) {
                let key = try #require(Range(match.range(at: 1), in: source))
                keys.insert(String(source[key]))
            }
        }
        #expect(keys.count > 80)
        CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            for key in keys.sorted() {
                #expect(english[key] != nil, "missing English entry for \(key)")
                // Identifier-style keys fall back to themselves when missing; English-text keys resolve to their text.
                if key.range(of: #"^[a-z0-9_]+$"#, options: .regularExpression) != nil {
                    #expect(L(key) != key, "\(key) does not resolve")
                }
            }
        }
    }

    @Test
    func `entry titles and keywords are resolved strings`() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let resources = root.appendingPathComponent("Sources/CodexBar/Resources")
        for language in ["en", "de"] {
            let catalog = try #require(NSDictionary(contentsOf: resources.appendingPathComponent(
                "\(language).lproj/Localizable.strings")) as? [String: String])
            let values = Set(catalog.values)
            CodexBarLocalizationOverride.$appLanguage.withValue(language) {
                for entry in SettingsSearchIndex.allEntries {
                    // Provider entries use provider display names and identifiers, not catalog strings.
                    if case .provider = entry.pane { continue }
                    #expect(values.contains(entry.title), "\(language): \(entry.id) title \(entry.title)")
                    let keywords = entry.keywords.filter { $0 != SettingsSearchEntry.formerAdvancedKeyword }
                    for keyword in keywords {
                        #expect(values.contains(keyword), "\(language): \(entry.id) keyword \(keyword)")
                    }
                }
            }
        }
    }

    @Test
    func `searching Advanced still finds the settings that moved out of it`() {
        let moved = [
            "privacy",
            "privacy/hidePersonalInfo",
            "privacy/keychainAccess",
            "privacy/storageFootprints",
            "privacy/debugSettings",
            "integrations",
            "integrations/httpServer",
            "integrations/httpServerToken",
            "integrations/installCLI",
        ]
        for language in ["en", "de"] {
            CodexBarLocalizationOverride.$appLanguage.withValue(language) {
                let entries = SettingsSearchIndex.allEntries
                let found = Set(SettingsSearchIndex.ranked(entries, query: "advanced").map(\.id))
                #expect(found.isSuperset(of: moved), "\(language): \(Set(moved).subtracting(found))")
                let localized = Set(SettingsSearchIndex.ranked(entries, query: L("tab_advanced")).map(\.id))
                #expect(localized.isSuperset(of: moved), "\(language): \(Set(moved).subtracting(localized))")
            }
        }
    }

    @Test
    func `hidden debug pane is left out of the searchable entries`() {
        #expect(!SettingsSearchIndex.entries(includingDebug: false).contains { $0.pane == .debug })
        #expect(SettingsSearchIndex.entries(includingDebug: true).contains { $0.pane == .debug })
    }
}
