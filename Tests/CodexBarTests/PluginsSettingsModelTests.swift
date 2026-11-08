#if canImport(JavaScriptCore)
import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct PluginsSettingsModelTests {
    @Test
    func `plugin status follows enabled first then approval`() {
        #expect(PluginStatus(enabled: false, approved: true) == .disabled)
        #expect(PluginStatus(enabled: false, approved: false) == .disabled)
        #expect(PluginStatus(enabled: true, approved: true) == .active)
        #expect(PluginStatus(enabled: true, approved: false) == .needsApproval)
        #expect(PluginStatus.needsApproval.tone == .warning)
        #expect(PluginStatus.error.tone == .error)
        #expect(PluginStatus.active.title == L("Active"))
    }

    @Test
    func `deleting an invalid plugin file waits for confirmation`() throws {
        let fixture = try PluginsSettingsFixture()
        defer { fixture.remove() }
        let file = try fixture.write(name: "broken.js", source: PluginsSettingsFixture.brokenSource)
        let model = fixture.model(suite: "PluginsDelete-confirm")
        model.refresh()
        let result = try #require(model.results.first)
        #expect(result.plugin == nil)

        model.requestDelete(fileURL: result.fileURL, plugin: nil)
        #expect(model.pendingDelete?.fileURL.resolvingSymlinksInPath() == file.resolvingSymlinksInPath())
        #expect(FileManager.default.fileExists(atPath: file.path))

        model.confirmDelete()
        #expect(model.pendingDelete == nil)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(model.results.isEmpty)
        #expect(model.operationError == nil)
    }

    @Test
    func `cancelling a plugin delete keeps the file and the plugin`() throws {
        let fixture = try PluginsSettingsFixture()
        defer { fixture.remove() }
        let file = try fixture.write(name: "acme.js", source: PluginsSettingsFixture.activeSource)
        let model = fixture.model(suite: "PluginsDelete-cancel")
        model.refresh()
        let plugin = try #require(model.results.first?.plugin)

        model.requestDelete(fileURL: plugin.fileURL, plugin: plugin)
        #expect(model.pendingDelete?.plugin?.manifest.id == plugin.manifest.id)
        model.cancelDelete()
        model.confirmDelete()

        #expect(model.pendingDelete == nil)
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(model.results.count == 1)
    }

    @Test
    func `status reads the approval store and the enabled state`() throws {
        let fixture = try PluginsSettingsFixture()
        defer { fixture.remove() }
        _ = try fixture.write(name: "acme.js", source: PluginsSettingsFixture.activeSource)
        var enabled = true
        let model = fixture.model(suite: "PluginsStatus", isEnabled: { _ in enabled })
        model.refresh()
        let plugin = try #require(model.results.first?.plugin)

        #expect(model.status(of: plugin) == .needsApproval)
        try fixture.approvals.record(plugin.approvalBinding(settings: [:]))
        #expect(model.status(of: plugin) == .active)
        enabled = false
        #expect(model.status(of: plugin) == .disabled)
    }
}

/// A plugins directory, cache and approval store in a temporary folder. Nothing touches the shared plugin
/// registry, the real plugins directory or the Keychain.
@MainActor
struct PluginsSettingsFixture {
    let root: URL
    let providers: URL
    let approvals: ProviderPluginApprovalStore

    init() throws {
        self.root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PluginsSettings-\(UUID().uuidString)", isDirectory: true)
        self.providers = self.root.appendingPathComponent("providers", isDirectory: true)
        self.approvals = ProviderPluginApprovalStore(fileURL: self.root.appendingPathComponent("approvals.json"))
        try FileManager.default.createDirectory(at: self.providers, withIntermediateDirectories: true)
    }

    var loader: UserProviderPluginLoader {
        UserProviderPluginLoader(
            providersDirectory: self.providers,
            cacheDirectory: self.root.appendingPathComponent("cache", isDirectory: true),
            storageDirectory: self.root.appendingPathComponent("storage", isDirectory: true))
    }

    func write(name: String, source: String) throws -> URL {
        let url = self.providers.appendingPathComponent(name)
        try Data(source.utf8).write(to: url, options: .atomic)
        return url
    }

    func model(
        suite: String,
        settings: SettingsStore? = nil,
        store: UsageStore? = nil,
        isEnabled: (@MainActor (ProviderInstanceID) -> Bool)? = nil) -> PluginsSettingsModel
    {
        let settings = settings ?? IntegrationsSettingsFixtures.settingsStore(suite: suite)
        let store = store ?? IntegrationsSettingsFixtures.usageStore(settings: settings, approvals: self.approvals)
        let loader = self.loader
        return PluginsSettingsModel(
            settings: settings,
            store: store,
            discover: { loader.discover() },
            isEnabled: isEnabled)
    }

    func remove() {
        try? FileManager.default.removeItem(at: self.root)
    }

    /// A plugin with a fixed HTTPS origin, a secret, a plain setting and cookie access.
    static let activeSource = """
    defineProvider({
      id: "acme-meter",
      name: "Acme Meter",
      icon: { monogram: "AM", tint: "#336699" },
      endpoints: ["https://api.acme-usage-reporting.example.com"],
      auth: { type: "bearer", secret: "TOKEN" },
      capabilities: ["browser-cookies", "http-status"],
      cookieDomains: ["acme-usage-reporting.example.com"],
      settings: [
        { key: "TOKEN", title: "API token", type: "secure" },
        { key: "TEAM", title: "Team", type: "plain", subtitle: "The team slug from your Acme workspace URL." },
      ],
      fetchUsage() { return { primary: { usedPercent: 42 } }; },
    });
    """

    /// A plugin whose origin comes from a setting on this Mac's loopback, so it needs typed approval.
    static let localSource = """
    defineProvider({
      id: "local-meter",
      name: "Local Model Gateway",
      endpoints: [{ setting: "BASE_URL", policy: "https-or-loopback-http" }],
      settings: [{ key: "BASE_URL", title: "Base URL", type: "plain", subtitle: "Where the gateway listens." }],
      fetchUsage() { return { primary: { usedPercent: 1 } }; },
    });
    """

    static let brokenSource = "defineProvider({id: 'Bad ID'});"
}
#endif
