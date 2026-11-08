import CodexBarCore
import Foundation
import InternalUI
import SwiftUI
import Testing
@testable import CodexBar

/// Renders the Settings sidebar, and the window shell around a placeholder pane, in light and dark. The data is
/// real-length: every built-in provider, a dozen of them enabled, some failing, some refreshing and some reporting
/// a service incident. Every render must succeed; set TOLKEIN_SNAPSHOT_DIR to also write the PNGs for design review
/// (see Sources/CodexBar/AGENTS.md).
@MainActor
@Suite(.serialized)
struct SettingsShellSnapshotTests {
    private struct Case {
        let name: String
        let width: CGFloat
        let height: CGFloat
        let view: (Fixture) -> AnyView
    }

    private static let sidebarWidth = SettingsPane.sidebarWidth

    private static var cases: [Case] {
        [
            Case(name: "sidebar", width: sidebarWidth, height: SettingsPane.windowHeight) { fixture in
                AnyView(fixture.sidebar(selection: .provider(fixture.providers[3].instanceID)))
            },
            Case(name: "sidebar-search", width: sidebarWidth, height: SettingsPane.windowHeight) { fixture in
                AnyView(fixture.sidebar(selection: .general, query: "refresh"))
            },
            Case(name: "sidebar-search-empty", width: sidebarWidth, height: SettingsPane.windowHeight) { fixture in
                AnyView(fixture.sidebar(selection: .general, query: "zzqx"))
            },
            Case(name: "shell", width: SettingsPane.windowWidth, height: SettingsPane.windowHeight) { fixture in
                AnyView(fixture.shell())
            },
        ]
    }

    @Test
    func `sidebar and shell render in every state and appearance`() throws {
        let directory = ProcessInfo.processInfo.environment["TOLKEIN_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0) }
        if let directory {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        for appearance in [MacAppearance.light, .dark] {
            for item in Self.cases {
                let fixture = Fixture()
                let shot = CodexBarLocalizationOverride.$appLanguage.withValue("en") {
                    MacSnapshot.render(
                        item.view(fixture),
                        appearance: appearance,
                        width: item.width,
                        height: item.height)
                }
                let rendered = try #require(shot, "\(item.name) \(appearance.rawValue) did not render")
                #expect(rendered.size == CGSize(width: item.width, height: item.height))
                if let directory {
                    try rendered.png.write(to: directory.appending(path: "\(item.name)-\(appearance.rawValue).png"))
                }
            }
        }
    }
}

/// Every built-in provider in the default order, with a mix of states near the top of the list.
@MainActor
private final class Fixture {
    let settings: SettingsStore
    let store: UsageStore
    let selection: PreferencesSelection
    let providers = UsageProvider.allCases

    init() {
        let settings = testSettingsStore(
            suiteName: "SettingsShellSnapshotTests",
            userDefaults: InMemoryUserDefaults())
        settings.statusChecksEnabled = true
        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing,
            environmentBase: [:])
        self.settings = settings
        self.store = store
        self.selection = PreferencesSelection(userDefaults: InMemoryUserDefaults())

        let enabled = Set([0, 1, 3, 4, 5, 6, 8, 10, 13, 20, 33, 47].map { self.providers[$0] })
        for provider in self.providers {
            settings.setProviderEnabled(
                provider: provider,
                metadata: store.metadata(for: provider),
                enabled: enabled.contains(provider))
        }
        // Avoid Codex and Claude for errors: their error mappers rewrite the text.
        store._setErrorForTesting("Sign-in expired. Sign in again to refresh usage.", provider: self.providers[4])
        store._setErrorForTesting("The service returned an error (HTTP 503).", provider: self.providers[8])
        store.refreshingProviders = [self.providers[3].instanceID, self.providers[6].instanceID]
        store.statuses = [
            self.providers[0].instanceID: ProviderStatus(indicator: .minor, description: nil, updatedAt: nil),
            self.providers[5].instanceID: ProviderStatus(indicator: .critical, description: nil, updatedAt: nil),
            self.providers[10].instanceID: ProviderStatus(indicator: .maintenance, description: nil, updatedAt: nil),
            self.providers[1].instanceID: ProviderStatus(indicator: .none, description: nil, updatedAt: nil),
        ]
    }

    func sidebar(selection: SettingsPane, query: String = "") -> some View {
        SettingsSidebarView(
            settings: self.settings,
            store: self.store,
            selection: .constant(selection),
            query: query)
    }

    func shell() -> some View {
        SettingsWindowLayout(selection: self.selection, sidebarWidth: .constant(Double(SettingsPane.sidebarWidth))) {
            self.sidebar(selection: .general)
        } detail: {
            PlaceholderPane()
        }
    }
}

/// Stands in for a rebuilt pane: a settings page with a title row and a couple of sections.
private struct PlaceholderPane: View {
    @State private var launchAtLogin = true
    @State private var refreshOnOpen = false

    var body: some View {
        MacSettingsPage("General", subtitle: "Placeholder pane for the window shell snapshot") {
            MacSettingsSection("System") {
                MacSettingsToggleRow("Start at login", subtitle: "Opens in the menu bar when you log in.", isOn: self.$launchAtLogin)
                MacSettingsRow("Language") {
                    Text("System")
                }
            }
            MacSettingsSection("Refreshing", footer: "Usage refreshes in the background while the app is open.") {
                MacSettingsToggleRow("Refresh when the menu opens", isOn: self.$refreshOnOpen)
            }
        }
    }
}
