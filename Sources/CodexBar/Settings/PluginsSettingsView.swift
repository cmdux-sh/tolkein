#if canImport(JavaScriptCore)
import AppKit
import CodexBarCore
import InternalUI
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// Where a plugin stands, as the Plugins page shows it.
enum PluginStatus: Equatable {
    case active
    case needsApproval
    case disabled
    /// The file did not load as a plugin.
    case error

    /// A loaded plugin: disabled wins, then approval decides.
    init(enabled: Bool, approved: Bool) {
        self = if !enabled {
            .disabled
        } else if approved {
            .active
        } else {
            .needsApproval
        }
    }

    var title: String {
        switch self {
        case .active: L("Active")
        case .needsApproval: L("Needs approval")
        case .disabled: L("Disabled")
        case .error: L("Error")
        }
    }

    var tone: IUStatusTone {
        switch self {
        case .active, .disabled: .neutral
        case .needsApproval: .warning
        case .error: .error
        }
    }

    var systemImage: String? {
        switch self {
        case .active: "checkmark.circle.fill"
        case .disabled: "pause.circle"
        case .needsApproval, .error: nil
        }
    }
}

/// A plugin waiting for the approval sheet: a plugin already in the directory, or a file being installed.
struct PendingPluginApproval: Identifiable {
    let id = UUID()
    let plugin: UserProviderPlugin
    let sourceURL: URL?
    let initialSettings: [String: String]
}

/// A plugin file waiting for Delete to be confirmed. `plugin` is nil for a file that did not load.
struct PluginDeleteRequest {
    let fileURL: URL
    let plugin: UserProviderPlugin?
}

/// The Plugins page's state and actions: discovery, approval, enabling and deletion.
@MainActor
@Observable
final class PluginsSettingsModel {
    let settings: SettingsStore
    let store: UsageStore
    private(set) var results: [UserProviderPluginLoadResult] = []
    var pendingApproval: PendingPluginApproval?
    private(set) var pendingDelete: PluginDeleteRequest?
    private(set) var operationError: String?

    @ObservationIgnored private let discover: @MainActor () -> [UserProviderPluginLoadResult]
    @ObservationIgnored private let isEnabledOverride: (@MainActor (ProviderInstanceID) -> Bool)?

    /// - Parameters:
    ///   - discover: reads the plugins directory. By default it refreshes the store's plugin registry.
    ///   - isEnabled: whether a plugin is on, instead of the settings store; snapshot tests use it for
    ///     plugins that are not in the shared registry.
    init(
        settings: SettingsStore,
        store: UsageStore,
        discover: (@MainActor () -> [UserProviderPluginLoadResult])? = nil,
        isEnabled: (@MainActor (ProviderInstanceID) -> Bool)? = nil)
    {
        self.settings = settings
        self.store = store
        self.discover = discover ?? {
            store.refreshUserPluginDiscovery()
            return UserProviderPluginRegistry.allResults
        }
        self.isEnabledOverride = isEnabled
    }

    func refresh() {
        self.results = self.discover()
    }

    func isEnabled(_ instanceID: ProviderInstanceID) -> Bool {
        self.isEnabledOverride?(instanceID) ?? self.settings.isPluginEnabled(instanceID)
    }

    func setEnabled(_ instanceID: ProviderInstanceID, _ enabled: Bool) {
        self.settings.setPluginEnabled(instanceID, enabled: enabled)
    }

    func approvalBinding(for plugin: UserProviderPlugin) -> ProviderPluginApprovalBinding? {
        try? plugin.approvalBinding(settings: self.settings.pluginConfig(plugin.manifest.id)?.pluginSettings ?? [:])
    }

    func status(of plugin: UserProviderPlugin) -> PluginStatus {
        let approved = self.approvalBinding(for: plugin).map(self.store.pluginApprovalStore.isApproved) == true
        return PluginStatus(enabled: self.isEnabled(plugin.manifest.id), approved: approved)
    }

    // MARK: Install and approve

    func choosePlugin() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = ["js", "ts"].compactMap { UTType(filenameExtension: $0) }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let plugin = try UserProviderPluginLoader().load(fileURL: url)
            if plugin.manifest.id.firstPartyProvider != nil ||
                UserProviderPluginRegistry.plugin(for: plugin.manifest.id) != nil
            {
                throw ProviderPluginError.invalidManifest(
                    "provider id '\(plugin.manifest.id.rawValue)' collides with another provider")
            }
            self.requestApproval(plugin: plugin, sourceURL: url)
        } catch {
            self.operationError = error.localizedDescription
        }
    }

    func requestApproval(plugin: UserProviderPlugin, sourceURL: URL?) {
        let config = self.settings.pluginConfig(plugin.manifest.id)
        self.pendingApproval = PendingPluginApproval(
            plugin: plugin,
            sourceURL: sourceURL,
            initialSettings: config?.pluginSettings ?? [:])
    }

    func completeApproval(
        _ pending: PendingPluginApproval,
        confirmations: [String: String],
        settings: [String: String])
    {
        do {
            let binding = try pending.plugin.approvalBinding(settings: settings)
            guard binding.typedConfirmationOrigins.allSatisfy({ confirmations[$0] == $0 }) else { return }
            let plugin: UserProviderPlugin = if let sourceURL = pending.sourceURL {
                try UserProviderPluginLoader().install(fileURL: sourceURL)
            } else {
                pending.plugin
            }
            let installedBinding = try plugin.approvalBinding(settings: settings)
            guard installedBinding == binding else {
                throw ProviderPluginError.load("plugin authority changed during installation; review it again")
            }
            self.settings.updatePluginConfig(instanceID: plugin.manifest.id) {
                $0.enabled = true
                $0.pluginSettings = settings
            }
            try self.store.pluginApprovalStore.record(installedBinding)
            self.pendingApproval = nil
            self.refresh()
            Task { await self.store.refreshUserPlugin(plugin.manifest.id) }
        } catch {
            self.pendingApproval = nil
            self.operationError = error.localizedDescription
        }
    }

    // MARK: Delete

    /// Asks before deleting: nothing is removed until `confirmDelete()`.
    func requestDelete(fileURL: URL, plugin: UserProviderPlugin?) {
        self.pendingDelete = PluginDeleteRequest(fileURL: fileURL, plugin: plugin)
    }

    func cancelDelete() {
        self.pendingDelete = nil
    }

    func confirmDelete() {
        guard let request = self.pendingDelete else { return }
        do {
            if let plugin = request.plugin {
                try self.store.deleteUserPlugin(plugin)
                self.settings.removeMenuBarLayoutOverride(forInstanceID: plugin.manifest.id)
            } else if FileManager.default.fileExists(atPath: request.fileURL.path) {
                try FileManager.default.removeItem(at: request.fileURL)
            }
            self.pendingDelete = nil
            self.refresh()
        } catch {
            self.pendingDelete = nil
            self.operationError = error.localizedDescription
        }
    }

    func dismissError() {
        self.operationError = nil
    }

    // MARK: Plugin settings

    func settingBinding(_ instanceID: ProviderInstanceID, setting: ProviderPluginSetting) -> Binding<String> {
        Binding(
            get: {
                let config = self.settings.pluginConfig(instanceID)
                return setting.kind == .secure
                    ? config?.pluginSecrets?[setting.key] ?? ""
                    : config?.pluginSettings?[setting.key] ?? ""
            },
            set: { value in
                self.settings.updatePluginConfig(instanceID: instanceID) { config in
                    if setting.kind == .secure {
                        var values = config.pluginSecrets ?? [:]
                        values[setting.key] = value
                        config.pluginSecrets = values
                    } else {
                        var values = config.pluginSettings ?? [:]
                        values[setting.key] = value
                        config.pluginSettings = values
                    }
                }
            })
    }
}

/// The Plugins page: install and the plugins directory, then one section per plugin file.
@MainActor
struct PluginsSettingsView: View {
    @Bindable var model: PluginsSettingsModel

    var body: some View {
        IUSettingsPage(
            SettingsPane.plugins.title,
            subtitle: L(
                "Plugins are local JavaScript or TypeScript files. Network and cookie access require approval."))
        {
            IUSettingsSection(L("Provider Plugins")) {
                IUSettingsRow(
                    L("Install plugin"),
                    subtitle: L("Copies a JavaScript or TypeScript file into the plugins directory."))
                {
                    Button(L("Install…")) { self.model.choosePlugin() }
                        .buttonStyle(.iu())
                }
                .settingsAnchor(PluginsSettingsPane.anchor(.install))
                IUSettingsRow(
                    L("Plugins directory"),
                    subtitle: Self.displayPath(UserProviderPluginLoader.defaultProvidersDirectory))
                {
                    HStack(spacing: IUSpace.unit * 2) {
                        Button(L("Refresh")) { self.model.refresh() }
                            .buttonStyle(.iu())
                        Button(L("Show in Finder")) { Self.revealPluginsDirectory() }
                            .buttonStyle(.iu())
                    }
                }
                .textSelection(.enabled)
                .settingsAnchor(PluginsSettingsPane.anchor(.directory))
            }

            if self.model.results.isEmpty {
                IUSettingsSection {
                    IUEmptyState(
                        L("No Plugins Installed"),
                        systemImage: "puzzlepiece.extension",
                        message: L("Drop a .js or .ts file into the plugins directory, or choose Install…"))
                }
            }

            ForEach(self.model.results, id: \.fileURL) { result in
                if let plugin = result.plugin {
                    PluginSection(model: self.model, plugin: plugin)
                } else {
                    InvalidPluginSection(model: self.model, result: result)
                }
            }
        }
        .settingsAlertOverlay(isPresented: self.model.pendingDelete != nil || self.model.operationError != nil) {
            if self.model.pendingDelete != nil {
                IUAlert(
                    L("Delete Plugin?"),
                    message: L(
                        "This removes the plugin file, transpile cache, approval, " +
                            "saved settings and secrets, and history."),
                    systemImage: "trash.fill",
                    primary: (L("Delete"), { self.model.confirmDelete() }),
                    secondary: (L("Cancel"), { self.model.cancelDelete() }))
            } else if let error = self.model.operationError {
                IUAlert(
                    L("Plugin Error"),
                    message: error,
                    primary: (L("OK"), { self.model.dismissError() }))
            }
        }
        .onAppear { self.model.refresh() }
        .sheet(item: self.$model.pendingApproval) { pending in
            PluginApprovalSheet(
                pending: pending,
                onCancel: { self.model.pendingApproval = nil },
                onApprove: { confirmations, settings in
                    self.model.completeApproval(pending, confirmations: confirmations, settings: settings)
                })
        }
    }

    static func displayPath(_ url: URL) -> String {
        (url.path as NSString).abbreviatingWithTildeInPath
    }

    private static func revealPluginsDirectory() {
        let directory = UserProviderPluginLoader.defaultProvidersDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(directory)
    }
}

/// One loaded plugin: on or off, its status and actions, what it may reach, its settings and its menu bar metric.
@MainActor
private struct PluginSection: View {
    let model: PluginsSettingsModel
    let plugin: UserProviderPlugin
    @State private var revealedSecrets: Set<String> = []

    var body: some View {
        let manifest = self.plugin.manifest
        let binding = self.model.approvalBinding(for: self.plugin)
        let approved = binding.map(self.model.store.pluginApprovalStore.isApproved) == true
        let status = PluginStatus(enabled: self.model.isEnabled(manifest.id), approved: approved)
        IUSettingsSection(manifest.name) {
            IUSettingsToggleRow(L("Enabled"), isOn: Binding(
                get: { self.model.isEnabled(manifest.id) },
                set: { self.model.setEnabled(manifest.id, $0) }))
            IUSettingsRow(L("Status")) {
                HStack(spacing: IUSpace.unit * 2) {
                    IUStatusLabel(status.title, tone: status.tone, systemImage: status.systemImage)
                    if !approved {
                        Button(L("Approve…")) { self.model.requestApproval(plugin: self.plugin, sourceURL: nil) }
                            .buttonStyle(.iu(.primary))
                    }
                    Button(L("Refresh")) {
                        Task { await self.model.store.refreshUserPlugin(manifest.id) }
                    }
                    .buttonStyle(.iu())
                }
            }
            IUSettingsRow(L("File"), subtitle: PluginsSettingsView.displayPath(self.plugin.fileURL)) {
                Button(L("Delete…")) {
                    self.model.requestDelete(fileURL: self.plugin.fileURL, plugin: self.plugin)
                }
                .buttonStyle(.iu())
            }
            .textSelection(.enabled)
            IUSettingsValueRow(
                L("Origins"),
                value: binding?.origins.joined(separator: ", ") ?? L("Configure endpoint settings"))
            IUSettingsValueRow(
                L("Capabilities"),
                value: manifest.capabilities.map(\.rawValue).sorted().joined(separator: ", ").nilIfEmpty
                    ?? L("Network"))
            if !manifest.cookieDomains.isEmpty {
                IUSettingsValueRow(L("Cookie domains"), value: manifest.cookieDomains.sorted().joined(separator: ", "))
            }
            ForEach(manifest.settings, id: \.key) { setting in
                IUSettingsRow(setting.title, subtitle: setting.subtitle) {
                    if setting.kind == .secure {
                        SettingsSecureField(
                            placeholder: setting.title,
                            text: self.model.settingBinding(manifest.id, setting: setting),
                            isRevealed: self.revealBinding(setting.key))
                            .frame(width: IUSize.settingsField)
                    } else {
                        IUTextField(setting.title, text: self.model.settingBinding(manifest.id, setting: setting))
                            .frame(width: IUSize.settingsField)
                    }
                }
            }
            // Draws its own settings row (title, subtitle and picker).
            ProviderMenuBarPercentWindowSettingsView(
                instanceID: manifest.id,
                settings: self.model.settings,
                snapshot: self.model.store.snapshot(for: manifest.id))
            if let error = self.model.store.errors[manifest.id] {
                IUSettingsRow(L("Error"), subtitle: error) {
                    Image(systemName: IUStatusTone.error.systemImage)
                        .foregroundStyle(IUStatusTone.error.color)
                        .accessibilityHidden(true)
                }
                .textSelection(.enabled)
            }
        }
    }

    private func revealBinding(_ key: String) -> Binding<Bool> {
        Binding(
            get: { self.revealedSecrets.contains(key) },
            set: { revealed in
                if revealed {
                    self.revealedSecrets.insert(key)
                } else {
                    self.revealedSecrets.remove(key)
                }
            })
    }
}

/// A file in the plugins directory that did not load: the reason, and Delete.
@MainActor
private struct InvalidPluginSection: View {
    let model: PluginsSettingsModel
    let result: UserProviderPluginLoadResult

    var body: some View {
        IUSettingsSection(self.result.fileURL.deletingPathExtension().lastPathComponent) {
            IUSettingsRow(L("Status"), subtitle: self.result.error ?? L("Unknown validation error")) {
                IUStatusLabel(PluginStatus.error.title, tone: PluginStatus.error.tone)
            }
            .textSelection(.enabled)
            IUSettingsRow(L("File"), subtitle: PluginsSettingsView.displayPath(self.result.fileURL)) {
                Button(L("Delete…")) {
                    self.model.requestDelete(fileURL: self.result.fileURL, plugin: nil)
                }
                .buttonStyle(.iu())
            }
            .textSelection(.enabled)
        }
    }
}

/// Reviews what a plugin may reach before it runs: its endpoint settings, the exact origins and authority,
/// and a typed confirmation for every local or private-network origin. Approve stays off until each
/// origin is typed exactly.
@MainActor
struct PluginApprovalSheet: View {
    let pending: PendingPluginApproval
    let onCancel: () -> Void
    let onApprove: ([String: String], [String: String]) -> Void
    @State private var confirmations: [String: String]
    @State private var settings: [String: String]

    init(
        pending: PendingPluginApproval,
        confirmations: [String: String] = [:],
        onCancel: @escaping () -> Void,
        onApprove: @escaping ([String: String], [String: String]) -> Void)
    {
        self.pending = pending
        self.onCancel = onCancel
        self.onApprove = onApprove
        self._confirmations = State(initialValue: confirmations)
        self._settings = State(initialValue: pending.initialSettings)
    }

    var body: some View {
        let plainSettings = self.pending.plugin.manifest.settings.filter { $0.kind == .plain }
        let binding = self.binding
        let missingEndpoints = L("Enter every endpoint setting to review the exact network origins.")
        VStack(alignment: .leading, spacing: IUSpace.settingsSectionGap) {
            VStack(alignment: .leading, spacing: IUSpace.unit) {
                IUText(
                    self.pending.sourceURL == nil ? L("Approve Plugin") : L("Install and Approve Plugin"),
                    role: .title)
                IUText(self.pending.plugin.manifest.name, muted: true)
            }

            if !plainSettings.isEmpty {
                IUSettingsSection(footer: binding == nil ? missingEndpoints : nil) {
                    ForEach(plainSettings, id: \.key) { setting in
                        IUSettingsRow(setting.title, subtitle: setting.subtitle) {
                            IUTextField(setting.title, text: Binding(
                                get: { self.settings[setting.key] ?? "" },
                                set: { self.settings[setting.key] = $0 }))
                                .frame(width: IUSize.settingsField)
                        }
                    }
                }
            } else if binding == nil {
                IUText(missingEndpoints, role: .caption, muted: true)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let binding {
                IUSettingsSection(L("Network authority")) {
                    ForEach(binding.origins, id: \.self) { origin in
                        IUSettingsRow(origin) { EmptyView() }
                    }
                    if let dashboardURL = binding.dashboardURL {
                        IUSettingsRow(L("Usage Dashboard"), subtitle: dashboardURL) { EmptyView() }
                    }
                    IUSettingsRow(L("Auth: %@", binding.authMode)) { EmptyView() }
                    IUSettingsRow(L(
                        "Capabilities: %@",
                        binding.capabilities.joined(separator: ", ").nilIfEmpty ?? L("network"))) { EmptyView() }
                    IUSettingsRow(L(
                        "Secrets: %@",
                        binding.secretNames.joined(separator: ", ").nilIfEmpty ?? L("none"))) { EmptyView() }
                    if !binding.cookieDomains.isEmpty {
                        IUSettingsRow(L("Cookie domains: %@", binding.cookieDomains.joined(separator: ", "))) {
                            EmptyView()
                        }
                    }
                }
                .textSelection(.enabled)

                if !binding.typedConfirmationOrigins.isEmpty {
                    IUSettingsSection {
                        ForEach(binding.typedConfirmationOrigins, id: \.self) { origin in
                            IUSettingsRow(L("Type %@ to confirm", origin)) {
                                IUTextField(origin, text: Binding(
                                    get: { self.confirmations[origin] ?? "" },
                                    set: { self.confirmations[origin] = $0 }))
                                    .frame(width: IUSize.settingsField)
                            }
                        }
                    }
                }
            }

            HStack(spacing: IUSpace.unit * 2) {
                Spacer()
                Button(L("Cancel"), role: .cancel, action: self.onCancel)
                    .buttonStyle(.iu())
                    .keyboardShortcut(.cancelAction)
                Button(self.pending.sourceURL == nil ? L("Approve") : L("Install")) {
                    self.onApprove(self.confirmations, self.settings)
                }
                .buttonStyle(.iu(.primary))
                .keyboardShortcut(.defaultAction)
                .disabled(!self.canApprove)
            }
            .iuControlSize(.large)
        }
        .padding(IUSpace.settingsPagePadding)
        .frame(width: Self.width)
        .background(IUColor.window)
    }

    /// Wide enough for a settings field beside a typed-confirmation prompt.
    static let width = IUSize.settingsContentWidth - IUSize.settingsField / 2

    private var canApprove: Bool {
        guard let binding = self.binding else { return false }
        return binding.typedConfirmationOrigins.allSatisfy { self.confirmations[$0] == $0 }
    }

    private var binding: ProviderPluginApprovalBinding? {
        try? self.pending.plugin.approvalBinding(settings: self.settings)
    }
}

extension String {
    fileprivate var nilIfEmpty: String? {
        self.isEmpty ? nil : self
    }
}
#endif
