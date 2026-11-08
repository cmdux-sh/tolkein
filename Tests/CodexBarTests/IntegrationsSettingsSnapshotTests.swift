import CodexBarCore
import Foundation
import InternalUI
import SwiftUI
import Testing
@testable import CodexBar

/// Renders the Integrations and Plugins panes and the plugin approval sheet in light and dark, with
/// real-length data, the states the panes can show and a short height that must scroll. Each render must
/// succeed; set TOLKEIN_SNAPSHOT_DIR to also write the PNGs for design review (see Sources/CodexBar/AGENTS.md).
@MainActor
@Suite(.serialized)
struct IntegrationsSettingsSnapshotTests {
    /// The Settings window's detail column at its default size.
    private static let width = SettingsPane.windowWidth - SettingsPane.sidebarWidth
    private static let height = SettingsPane.windowHeight
    /// Tall enough to show every section at once.
    private static let fullHeight: CGFloat = 2400

    @Test
    func `integrations renders in every state and appearance`() throws {
        try self.render("integrations-running", height: Self.fullHeight) {
            Self.integrations(
                suite: "running",
                server: Self.runningServer(),
                hooks: IntegrationsSettingsFixtures.longPathRules)
        }
        try self.render("integrations-running-short", height: Self.height) {
            Self.integrations(
                suite: "short",
                server: Self.runningServer(),
                hooks: IntegrationsSettingsFixtures.longPathRules)
        }
        try self.render("integrations-empty", height: Self.fullHeight) {
            Self.integrations(suite: "empty", server: StubHTTPServer(), hooks: [], cliReport: nil)
        }
        try self.render("integrations-unapplied-alert", height: Self.height) {
            let server = StubHTTPServer()
            let drafts = HTTPServerDraftStore()
            var edited = server.configuration
            edited.port = 9090
            drafts.close(draft: edited, applied: server.configuration)
            return Self.integrations(suite: "unapplied", server: server, drafts: drafts, hooks: [], cliReport: nil)
        }
    }

    #if canImport(JavaScriptCore)
    @Test
    func `plugins render valid needing approval and invalid in both appearances`() throws {
        let fixture = try PluginsSettingsFixture()
        defer { fixture.remove() }
        _ = try fixture.write(name: "acme.js", source: PluginsSettingsFixture.activeSource)
        _ = try fixture.write(name: "local.js", source: PluginsSettingsFixture.localSource)
        _ = try fixture.write(
            name: "broken-plugin-with-a-long-file-name.js",
            source: PluginsSettingsFixture.brokenSource)
        let acme = try fixture.loader.load(fileURL: fixture.providers.appendingPathComponent("acme.js"))
        try fixture.approvals.record(acme.approvalBinding(settings: [:]))

        try self.render("plugins", height: Self.fullHeight) {
            let settings = IntegrationsSettingsFixtures.settingsStore(suite: "PluginsSnapshot")
            let store = IntegrationsSettingsFixtures.usageStore(settings: settings, approvals: fixture.approvals)
            store.errors[ProviderInstanceID(rawValue: "local-meter")!] =
                "Provider plugin 'local-meter' needs approval before network access"
            return PluginsSettingsPane(model: fixture.model(
                suite: "PluginsSnapshot",
                settings: settings,
                store: store,
                isEnabled: { _ in true }))
        }
        try self.render("plugins-short", height: Self.height) {
            PluginsSettingsPane(model: fixture.model(suite: "PluginsSnapshot-short", isEnabled: { _ in true }))
        }

        let local = try fixture.loader.load(fileURL: fixture.providers.appendingPathComponent("local.js"))
        let pending = PendingPluginApproval(
            plugin: local,
            sourceURL: URL(fileURLWithPath: "/Users/fixture/Downloads/local.js"),
            initialSettings: ["BASE_URL": "http://127.0.0.1:11434/v1/usage"])
        try self.render("approval-sheet", width: PluginApprovalSheet.width, height: nil) {
            PluginApprovalSheet(pending: pending, onCancel: {}, onApprove: { _, _ in })
        }
        try self.render("approval-sheet-missing-endpoint", width: PluginApprovalSheet.width, height: nil) {
            PluginApprovalSheet(
                pending: PendingPluginApproval(plugin: local, sourceURL: nil, initialSettings: [:]),
                onCancel: {},
                onApprove: { _, _ in })
        }
    }

    @Test
    func `plugins render the empty state`() throws {
        let fixture = try PluginsSettingsFixture()
        defer { fixture.remove() }
        try self.render("plugins-empty", height: Self.height) {
            PluginsSettingsPane(model: fixture.model(suite: "PluginsSnapshot-empty"))
        }
    }
    #endif

    // MARK: Fixtures

    private static func runningServer() -> StubHTTPServer {
        var configuration = HTTPServerConfiguration()
        configuration.enabled = true
        configuration.host = "0.0.0.0"
        configuration.token = "4f9c2a7e1b3d5f60718293a4b5c6d7e8f9a0b1c2d3e4f5061728394a5b6c7d8e"
        configuration.allowPlainHTTP = true
        configuration.allAccounts = true
        let server = StubHTTPServer(configuration: configuration)
        server.status = "Running"
        server.runningURL = configuration.url
        return server
    }

    private static func integrations(
        suite: String,
        server: StubHTTPServer,
        drafts: HTTPServerDraftStore = HTTPServerDraftStore(),
        hooks: [HookRule],
        cliReport: CLIInstallReport? = .results([
            CLIInstallResult(directory: "/opt/homebrew/bin", outcome: .installed),
            CLIInstallResult(directory: "/usr/local/bin", outcome: .exists),
        ])) -> IntegrationsSettingsPane
    {
        IntegrationsSettingsPane(
            settings: IntegrationsSettingsFixtures.settingsStore(
                suite: "IntegrationsSnapshot-\(suite)",
                hooks: hooks,
                hooksEnabled: !hooks.isEmpty),
            server: server,
            drafts: drafts,
            cliReport: cliReport)
    }

    // MARK: Rendering

    private func render(
        _ name: String,
        width: CGFloat = Self.width,
        height: CGFloat?,
        view: () -> some View) throws
    {
        let directory = ProcessInfo.processInfo.environment["TOLKEIN_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0) }
        if let directory {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            for appearance in [MacAppearance.light, .dark] {
                let shot = MacSnapshot.render(view(), appearance: appearance, width: width, height: height)
                let rendered = try #require(shot, "\(name) \(appearance.rawValue) did not render")
                if let height {
                    #expect(rendered.size == CGSize(width: width, height: height))
                }
                if let directory {
                    try rendered.png.write(to: directory.appending(path: "\(name)-\(appearance.rawValue).png"))
                }
            }
        }
    }
}
