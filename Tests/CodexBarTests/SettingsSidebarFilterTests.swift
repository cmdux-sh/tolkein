import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct SettingsSidebarFilterTests {
    @Test
    func `filter chips are All then Enabled and map to the stored enabled-only flag`() {
        CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            let chips = SettingsSidebarProviderFilter.chips
            #expect(chips.map(\.id) == [.all, .enabled])
            #expect(chips.map(\.title) == ["All", "Enabled"])
            #expect(chips.allSatisfy { $0.count == nil })
        }
        #expect(SettingsSidebarProviderFilter(enabledOnly: false) == .all)
        #expect(SettingsSidebarProviderFilter(enabledOnly: true) == .enabled)
        #expect(!SettingsSidebarProviderFilter.all.enabledOnly)
        #expect(SettingsSidebarProviderFilter.enabled.enabledOnly)
    }

    @Test(arguments: [
        (false, SettingsSidebarProviderFilter.all, true),
        (false, .enabled, false),
        (true, .all, false),
        (true, .enabled, false),
    ])
    func `dragging providers works only in the full custom order`(
        sortedAlphabetically: Bool,
        filter: SettingsSidebarProviderFilter,
        allowed: Bool)
    {
        #expect(SettingsSidebarProviderFilter.allowsReordering(
            sortedAlphabetically: sortedAlphabetically,
            filter: filter) == allowed)
    }

    @Test
    func `a move while filtered leaves the provider order alone`() {
        let settings = testSettingsStore(suiteName: #function, userDefaults: InMemoryUserDefaults())
        let order = settings.configSnapshot.providers.map(\.id)
        settings.providersEnabledOnly = true
        #expect(!settings.moveVisibleProviders(Array(order.prefix(3)), fromOffsets: [0], toOffset: 2))
        #expect(settings.configSnapshot.providers.map(\.id) == order)
    }
}
