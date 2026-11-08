@testable import CodexBarCore
import Foundation
import InternalUI
import SwiftUI
import Testing
@testable import CodexBar

/// Renders provider pages in light and dark with real-length synthetic data: long account labels, three token
/// accounts, an error and many options. Each page renders at the settings detail width and a short
/// height that must scroll, and its sections render once more at full length for review. Set TOLKEIN_SNAPSHOT_DIR
/// to write the PNGs (see Sources/CodexBar/AGENTS.md).
@MainActor
@Suite(CodexCredentialFixtures())
struct ProviderSettingsPageSnapshotTests {
    private static let width: CGFloat = 620
    private static let shortHeight: CGFloat = 520

    private static let providers: [UsageProvider] = [.claude, .codex, .vertexai]

    @Test
    func `provider pages render in both appearances`() throws {
        let directory = ProcessInfo.processInfo.environment["TOLKEIN_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0) }
        if let directory {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try KeychainAccessGate.withTaskOverrideForTesting(true) {
            try CodexBarLocalizationOverride.$appLanguage.withValue("en") {
                for provider in Self.providers {
                    let page = Self.makePage(provider)
                    for appearance in [MacAppearance.light, .dark] {
                        let name = "provider-\(provider.rawValue)-\(appearance.rawValue)"
                        let short = try #require(
                            MacSnapshot.render(
                                ProviderSettingsPage(model: page),
                                appearance: appearance,
                                width: Self.width,
                                height: Self.shortHeight),
                            "\(name) did not render")
                        #expect(short.size == CGSize(width: Self.width, height: Self.shortHeight))
                        let full = try #require(
                            MacSnapshot.render(
                                Self.fullLength(page),
                                appearance: appearance,
                                width: Self.width),
                            "\(name)-full did not render")
                        #expect(full.size.height > Self.shortHeight, "\(name) should need to scroll")
                        if let directory {
                            try short.png.write(to: directory.appending(path: "\(name).png"))
                            try full.png.write(to: directory.appending(path: "\(name)-full.png"))
                        }
                    }
                }
            }
        }
    }

    /// Every section at its natural height, as it reads when scrolled through.
    private static func fullLength(_ page: ProviderSettingsPageModel) -> some View {
        VStack(alignment: .leading, spacing: MacSpace.settingsSectionGap) {
            ProviderSettingsPageSections(model: page, content: page.pageContent())
        }
        .padding(MacSpace.settingsPagePadding)
        .frame(width: Self.width, alignment: .topLeading)
    }

    // MARK: - Fixtures

    private static func makePage(_ provider: UsageProvider) -> ProviderSettingsPageModel {
        let page = ProviderSettingsPageTests.makeModel(provider, suite: "ProviderSettingsPageSnapshotTests-\(provider)")
        let settings = page.settings
        let store = page.store
        let metadata = store.metadata(for: provider)
        settings.setProviderEnabled(provider: provider, metadata: metadata, enabled: true)
        store._setSnapshotForTesting(Self.snapshot(), provider: provider)
        store.versions[provider.instanceID] = "2.41.7 (build 20261105)"

        switch provider {
        case .claude:
            settings.claudeCookieSource = .manual
            for label in Self.longLabels {
                settings.addTokenAccount(provider: .claude, label: label, token: "sk-ant-sid01-synthetic-\(label.count)")
            }
            store._setErrorForTesting(
                "Claude returned HTTP 429 for the usage endpoint after three retries. The session key for "
                    + "“Research team — shared Max subscription (synthetic)” may be rate limited; Tolkein keeps the "
                    + "last good usage until the next refresh succeeds.",
                provider: .claude)
        case .codex:
            settings._test_liveSystemCodexAccount = ObservedSystemCodexAccount(
                email: "very.long.synthetic.person.name@research-laboratory.example.com",
                workspaceAccountID: "synthetic-workspace",
                codexHomePath: "/Users/test/.codex",
                observedAt: Date(),
                identity: .providerAccount(id: "synthetic-workspace"))
        default:
            break
        }
        return page
    }

    private static let longLabels = [
        "Research team — shared Max subscription (synthetic)",
        "Personal account for weekend side projects",
        "Contractor seat · billing@consulting-partners.example.com",
    ]

    private static func snapshot() -> UsageSnapshot {
        let now = Date()
        return UsageSnapshot(
            primary: RateWindow(
                usedPercent: 38,
                windowMinutes: 300,
                resetsAt: now.addingTimeInterval(2 * 3600),
                resetDescription: nil),
            secondary: RateWindow(
                usedPercent: 81,
                windowMinutes: 10080,
                resetsAt: now.addingTimeInterval(3 * 86400),
                resetDescription: nil),
            updatedAt: now.addingTimeInterval(-240))
    }
}
