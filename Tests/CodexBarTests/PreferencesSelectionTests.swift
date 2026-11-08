import AppKit
import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct PreferencesSelectionTests {
    @Test
    func `pane persistence tokens round-trip`() {
        for pane in SettingsPane.fixedPanes + [.provider(.claude)] {
            #expect(SettingsPane(persistenceToken: pane.persistenceToken) == pane)
        }
        #expect(SettingsPane(persistenceToken: "provider:definitely-not-a-provider") == nil)
        #expect(SettingsPane(persistenceToken: "") == nil)
    }

    @Test
    func `pane persistence tokens are unique`() {
        let tokens = SettingsPane.fixedPanes.map(\.persistenceToken)
        #expect(Set(tokens).count == tokens.count)
    }

    @Test
    func `legacy tokens restore the pane that now holds their settings`() {
        let expected: [String: SettingsPane] = [
            "display": .menuBar,
            "iCloudSync": .sync,
            "usageSpend": .costs,
            "notifications": .alerts,
            "advanced": .privacy,
            "hooks": .integrations,
        ]
        #expect(SettingsPane.legacyPersistenceTokens == expected)
        for (token, pane) in expected {
            #expect(SettingsPane(persistenceToken: token) == pane)
        }
        #expect(SettingsPane(persistenceToken: "plugins") == .plugins)
    }

    @Test
    func `legacy tokens never shadow a current token`() {
        let currentTokens = Set(SettingsPane.fixedPanes.map(\.persistenceToken))
        #expect(currentTokens.isDisjoint(with: SettingsPane.legacyPersistenceTokens.keys))
    }

    @Test
    func `a stored legacy token reopens Settings on its new pane`() {
        let defaults = InMemoryUserDefaults(values: [PreferencesSelection.paneDefaultsKey: "usageSpend"])

        let selection = PreferencesSelection(userDefaults: defaults)
        #expect(selection.pane == .costs)

        selection.pane = .alerts
        #expect(defaults.string(forKey: PreferencesSelection.paneDefaultsKey) == "alerts")
    }

    @Test
    func `selection restores persisted pane and saves changes`() {
        let defaults = InMemoryUserDefaults()

        #expect(PreferencesSelection(userDefaults: defaults).pane == .general)

        let selection = PreferencesSelection(userDefaults: defaults)
        selection.pane = .provider(.codex)
        #expect(defaults.string(forKey: PreferencesSelection.paneDefaultsKey) == "provider:codex")
        let restored = PreferencesSelection(userDefaults: defaults)
        #expect(restored.pane == .provider(.codex))
        #expect(!restored.canGoBack)
        #expect(!restored.canGoForward)
    }

    @Test
    func `app panes follow the approved sidebar order`() {
        #expect(SettingsPane.appPanes == [
            .general,
            .menuBar,
            .menu,
            .alerts,
            .costs,
            .sync,
            .integrations,
            .privacy,
            .about,
            .debug,
        ])
        #expect(SettingsPane.fixedPanes.last == .plugins)
    }

    @Test
    func `pane titles use the new names`() {
        CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            #expect(SettingsPane.fixedPanes.map(\.title) == [
                "General",
                "Menu Bar",
                "Menu",
                "Alerts",
                "Costs",
                "Sync",
                "Integrations",
                "Privacy & Data",
                "About",
                "Debug",
                "Plugins",
            ])
        }
    }

    @Test
    func `every fixed pane has its own sidebar symbol`() {
        let symbols = SettingsPane.fixedPanes.map(\.systemImage)
        #expect(Set(symbols).count == symbols.count)
        for symbol in symbols {
            #expect(NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil, "\(symbol)")
        }
    }
}
