import CodexBarCore
import Foundation
import SwiftUI
import Testing
@testable import CodexBar

/// Reads the routed view values, without rendering, to prove which wrapper and sections each pane shows.
@MainActor
struct SettingsPaneRouterTests {
    @Test
    func `router produces the wrapper view for every pane`() {
        let context = Self.makeContext()
        let expected: [SettingsPane: String] = [
            .general: "GeneralSettingsPane",
            .menuBar: "MenuBarSettingsPane",
            .menu: "MenuSettingsPane",
            .alerts: "AlertsSettingsPane",
            .costs: "CostsSettingsPane",
            .sync: "SyncSettingsPane",
            .integrations: "IntegrationsSettingsPane",
            .privacy: "PrivacySettingsPane",
            .about: "AboutSettingsPane",
            .debug: "DebugSettingsPane",
            .plugins: "PluginsSettingsPane",
            .provider(UsageProvider.codex.instanceID): "ProviderSettingsPane",
        ]
        #expect(Set(expected.keys) == Set(SettingsPane.fixedPanes + [.provider(UsageProvider.codex.instanceID)]))
        let wrapperNames = Set(expected.values)

        for (pane, wrapper) in expected {
            let routed = Self.typeNames(in: SettingsPaneRouter(pane: pane, context: context).body)
            #expect(routed.contains(wrapper), "\(pane) should show \(wrapper)")
            #expect(routed.intersection(wrapperNames) == [wrapper], "\(pane) shows one wrapper")
        }
    }

    @Test
    func `integrations shows the HTTP server and CLI sections from Advanced with Hooks`() {
        let names = Self.typeNames(in: IntegrationsSettingsPane(context: Self.makeContext()).body)
        #expect(names.isSuperset(of: ["HTTPServerSection", "CommandLineInstallSection", "HooksSections"]))
        #expect(names.isDisjoint(with: ["AdvancedPrivacySection", "AdvancedDiagnosticsSection"]))
    }

    @Test
    func `privacy and general are built from the settings form, without the old sections`() {
        let context = Self.makeContext()
        let privacy = Self.typeNames(in: PrivacySettingsPane(context: context).body)
        #expect(privacy.contains("PrivacySettingsPage"))
        #expect(privacy.isDisjoint(with: [
            "AdvancedPrivacySection",
            "AdvancedDiagnosticsSection",
            "PreferencesTransferSection",
            "HTTPServerSection",
            "CommandLineInstallSection",
            "HooksSections",
        ]))
        let general = Self.typeNames(in: GeneralSettingsPane(context: context).body)
        #expect(general.contains("GeneralSettingsPage"))
        #expect(!general.contains("PreferencesTransferSection"))
    }

    /// Type names of every value in a view tree. Generic wrappers such as `_ConditionalContent` hold only the
    /// branch that is showing, so a name appears only when that view is actually produced. Class instances (stores,
    /// controllers) are not followed.
    private static func typeNames(in value: Any, depth: Int = 0) -> Set<String> {
        guard depth < 48 else { return [] }
        let mirror = Mirror(reflecting: value)
        guard mirror.displayStyle != .class else { return [] }
        var names: Set<String> = [String(describing: type(of: value))]
        for child in mirror.children {
            names.formUnion(self.typeNames(in: child.value, depth: depth + 1))
        }
        return names
    }

    private static func makeContext() -> SettingsPaneContext {
        let settings = testSettingsStore(
            suiteName: "SettingsPaneRouterTests",
            userDefaults: InMemoryUserDefaults(),
            config: CodexBarConfig(providers: []))
        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing)
        let accounts = ManagedCodexAccountCoordinator()
        return SettingsPaneContext(
            settings: settings,
            store: store,
            cloudSyncState: CloudSyncState(),
            updater: DisabledUpdaterController(),
            selection: PreferencesSelection(userDefaults: InMemoryUserDefaults()),
            managedCodexAccountCoordinator: accounts,
            codexAccountPromotionCoordinator: CodexAccountPromotionCoordinator(
                settingsStore: settings,
                usageStore: store,
                managedAccountCoordinator: accounts),
            runProviderLoginFlow: { _ in })
    }
}
