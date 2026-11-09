import CodexBarCore
import Foundation
import InternalUI
import SwiftUI
import Testing
@testable import CodexBar

/// Renders General, Privacy & Data, About (Sparkle, Homebrew failure, unavailable), Debug and the Acknowledgements
/// sheet in light and dark, with real-length data: long language and currency names, German strings, a long probe
/// log, long CLI paths and the Homebrew failure state. Each page renders tall enough to show every section, and
/// General also at the window height, where it must scroll under its pinned title. Every render must succeed; set
/// TOLKEIN_SNAPSHOT_DIR to also write the PNGs for design review (see Sources/CodexBar/AGENTS.md).
@MainActor
@Suite(.serialized)
struct GeneralPanesSnapshotTests {
    private struct Case {
        let name: String
        let width: CGFloat
        let height: CGFloat
        var language = "en"
        let view: () -> AnyView
    }

    /// The detail column of the Settings window at its default size.
    private static let width = SettingsPane.windowWidth - SettingsPane.sidebarWidth
    private static let height = SettingsPane.windowHeight

    @Test func `general privacy about debug and acknowledgements render in both appearances`() async throws {
        let directory = ProcessInfo.processInfo.environment["TOLKEIN_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0) }
        if let directory {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let homebrew = Fixture.failingHomebrewUpdater()
        await homebrew.performCheck()
        let fixture = Fixture(homebrew: homebrew)
        for appearance in [IUAppearance.light, .dark] {
            for item in fixture.cases {
                let shot = CodexBarLocalizationOverride.$appLanguage.withValue(item.language) {
                    IUSnapshot.render(
                        item.view(),
                        appearance: appearance,
                        width: item.width,
                        height: item.height,
                        background: nil)
                }
                let rendered = try #require(shot, "\(item.name) \(appearance.rawValue) did not render")
                #expect(rendered.size == CGSize(width: item.width, height: item.height))
                if let directory {
                    try rendered.png.write(to: directory.appending(path: "\(item.name)-\(appearance.rawValue).png"))
                }
            }
        }
    }

    /// Stores and updaters shared by the cases, built once so every render sees the same state.
    @MainActor
    private final class Fixture {
        let settings: SettingsStore
        let keychainOffSettings: SettingsStore
        let store: UsageStore
        let keychainOffStore: UsageStore
        let homebrew: HomebrewUpdaterController
        let appStorage = InMemoryUserDefaults(values: ["autoUpdateEnabled": true, "SUAutomaticallyUpdate": false])

        init(homebrew: HomebrewUpdaterController) {
            self.homebrew = homebrew
            self.settings = testSettingsStore(suiteName: "GeneralPanesSnapshotTests") { defaults in
                defaults.set("pt-BR", forKey: "appLanguage")
                defaults.set("auto", forKey: "preferredCurrencyCode")
                defaults.set(RefreshFrequency.manual.rawValue, forKey: "refreshFrequency")
            }
            self.keychainOffSettings = testSettingsStore(suiteName: "GeneralPanesSnapshotTests-keychain-off")
            self.keychainOffSettings.debugDisableKeychainAccess = true
            self.store = Self.makeStore(self.settings)
            self.keychainOffStore = Self.makeStore(self.keychainOffSettings)
            self.store.pathDebugInfo = PathDebugSnapshot(
                codexBinary: "/Users/someone/.local/share/mise/installs/node/22.11.0/bin/codex",
                claudeBinary: nil,
                effectivePATH: Self.longPATH,
                loginShellPATH: Self.longPATH + ":/Users/someone/.cargo/bin:/Users/someone/go/bin")
        }

        var cases: [Case] {
            let width = GeneralPanesSnapshotTests.width
            let height = GeneralPanesSnapshotTests.height
            return [
                Case(name: "general", width: width, height: height) { AnyView(self.general()) },
                Case(name: "general-full", width: width, height: 1720) { AnyView(self.general()) },
                Case(name: "general-de-full", width: width, height: 1820, language: "de") {
                    AnyView(self.general())
                },
                Case(name: "general-search-hit", width: width, height: height) {
                    AnyView(self.general().environment(\.settingsSearchTarget, "general/currency"))
                },
                Case(name: "privacy-full", width: width, height: 900) {
                    AnyView(PrivacySettingsPane(context: self.context(self.settings, self.store)))
                },
                Case(name: "privacy-de-full", width: width, height: 960, language: "de") {
                    AnyView(PrivacySettingsPane(context: self.context(self.settings, self.store)))
                },
                Case(name: "about-sparkle-full", width: width, height: 1000) {
                    AnyView(self.about(SnapshotSparkleUpdater()))
                },
                Case(name: "about-homebrew-failed-full", width: width, height: 1000) {
                    AnyView(self.about(self.homebrew))
                },
                Case(name: "about-unavailable", width: width, height: height) {
                    AnyView(self.about(DisabledUpdaterController()))
                },
                Case(
                    name: "acknowledgements",
                    width: IUSize.settingsContentWidth,
                    height: SettingsPane.windowMinHeight)
                {
                    let acknowledgements = Acknowledgement.load()
                    return AnyView(AcknowledgementsSheet(
                        acknowledgements: acknowledgements,
                        initiallyExpanded: Set(acknowledgements.prefix(1).map(\.id))))
                },
                Case(name: "debug-full", width: width, height: 2600) {
                    AnyView(DebugSettingsPage(
                        settings: self.settings,
                        store: self.store,
                        loadsPathInfo: false,
                        initialLogText: Self.longLog))
                },
                Case(name: "debug-keychain-off", width: width, height: height) {
                    AnyView(DebugSettingsPage(
                        settings: self.keychainOffSettings,
                        store: self.keychainOffStore,
                        loadsPathInfo: false))
                },
            ]
        }

        private func general() -> some View {
            GeneralSettingsPane(context: self.context(self.settings, self.store))
        }

        private func about(_ updater: UpdaterProviding) -> some View {
            AboutSettingsPage(updater: updater).defaultAppStorage(self.appStorage)
        }

        private func context(_ settings: SettingsStore, _ store: UsageStore) -> SettingsPaneContext {
            SettingsPaneContext(
                settings: settings,
                store: store,
                cloudSyncState: CloudSyncState(),
                updater: DisabledUpdaterController(),
                selection: PreferencesSelection(userDefaults: InMemoryUserDefaults()),
                managedCodexAccountCoordinator: ManagedCodexAccountCoordinator(),
                codexAccountPromotionCoordinator: CodexAccountPromotionCoordinator(
                    settingsStore: settings,
                    usageStore: store,
                    managedAccountCoordinator: ManagedCodexAccountCoordinator()),
                runProviderLoginFlow: { _ in })
        }

        private static func makeStore(_ settings: SettingsStore) -> UsageStore {
            UsageStore(
                fetcher: UsageFetcher(environment: [:]),
                browserDetection: BrowserDetection(cacheTTL: 0),
                settings: settings)
        }

        /// A Homebrew install whose update check fails with brew's own long message, once `performCheck()` runs.
        static func failingHomebrewUpdater() -> HomebrewUpdaterController {
            HomebrewUpdaterController(
                savedAutoCheck: true,
                dependencies: .init(
                    installedVersion: { "0.65.0" },
                    fetchCaskSource: {
                        throw HomebrewUpdateError.recoveryFailed(
                            "Error: Cask 'tolkein' is unavailable: the tap cmdux-sh/tap could not be updated "
                                + "because github.com refused the connection. Run brew update, then try again.")
                    },
                    runUpgrade: { _ in },
                    relaunch: {},
                    cask: { .tap }),
                startScheduledChecks: false)
        }

        private static let longPATH = [
            "/Users/someone/.local/share/mise/installs/node/22.11.0/bin", "/opt/homebrew/bin", "/opt/homebrew/sbin",
            "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin", "/Applications/Ghostty.app/Contents/MacOS",
            "/Users/someone/.bun/bin",
        ].joined(separator: ":")

        private static let longLog = (1...40).map { line in
            "2026-11-07T21:\(String(format: "%02d", line)):04Z codex probe step \(line): "
                + "fetched rate limits for workspace personal-account-with-a-long-name (200 OK, 182 ms)"
        }.joined(separator: "\n")
    }
}

/// A Sparkle-style updater for snapshots: available, with nothing to check or install.
private final class SnapshotSparkleUpdater: UpdaterProviding {
    var automaticallyChecksForUpdates = true
    var automaticallyDownloadsUpdates = false
    let isAvailable = true
    let unavailableReason: String? = nil
    let updateStatus = UpdateStatus()
    func checkForUpdates(_: Any?) {}
    func installUpdate() {}
}
