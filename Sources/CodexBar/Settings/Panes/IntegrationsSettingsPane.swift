import CodexBarCore
import InternalUI
import Observation
import SwiftUI

/// Integrations: the local HTTP server, the command-line tool and Hooks.
@MainActor
struct IntegrationsSettingsPane: View {
    @Bindable private var settings: SettingsStore
    @State private var model: IntegrationsSettingsModel
    private let cliReport: CLIInstallReport?

    init(context: SettingsPaneContext) {
        self.init(settings: context.settings, server: context.settings.httpServer, drafts: .shared)
    }

    /// - Parameters:
    ///   - server: the HTTP server the section edits; tests pass a stub.
    ///   - drafts: where unapplied HTTP server edits wait while the pane is closed.
    ///   - cliReport: an install result to show from the start (snapshot tests).
    init(
        settings: SettingsStore,
        server: any HTTPServerControlling,
        drafts: HTTPServerDraftStore,
        cliReport: CLIInstallReport? = nil)
    {
        self.settings = settings
        self._model = State(initialValue: IntegrationsSettingsModel(server: server, drafts: drafts))
        self.cliReport = cliReport
    }

    var body: some View {
        IUSettingsPage(
            SettingsPane.integrations.title,
            subtitle: L("The local HTTP server, the command-line tool and hooks."))
        {
            HTTPServerSection(
                server: self.model.server,
                draft: self.$model.draft,
                onApply: { Task { await self.model.apply() } },
                onDiscard: { self.model.discardChanges() })
            CommandLineInstallSection(report: self.cliReport)
            HooksSections(settings: self.settings, requestDelete: { self.model.requestDelete($0) })
        }
        .settingsAlertOverlay(isPresented: self.model.confirmation != nil) {
            self.alert
        }
        .onAppear { self.model.paneAppeared() }
        .onDisappear { self.model.paneDisappeared() }
        .onChange(of: self.model.server.configuration) { self.model.serverConfigurationChanged() }
    }

    @ViewBuilder
    private var alert: some View {
        switch self.model.confirmation {
        case .none:
            EmptyView()
        case .unappliedHTTPServerChanges:
            IUAlert(
                L("Apply HTTP server changes?"),
                message: L("You left the HTTP server settings with changes that aren’t applied yet."),
                systemImage: "exclamationmark.triangle.fill",
                primary: (L("apply"), {
                    self.model.dismissConfirmation()
                    Task { await self.model.apply() }
                }),
                secondary: (L("Keep Editing"), { self.model.dismissConfirmation() }))
        case .deleteHookRule:
            IUAlert(
                L("Delete Rule?"),
                message: L("This rule is removed from Hooks. This can’t be undone."),
                systemImage: "trash.fill",
                primary: (L("Delete"), { self.model.confirmDelete(in: self.settings) }),
                secondary: (L("Cancel"), { self.model.dismissConfirmation() }))
        }
    }
}

/// What the Integrations page asks the user before going on. One at a time.
enum IntegrationsConfirmation: Equatable {
    /// The pane opened again with HTTP server edits that were never applied.
    case unappliedHTTPServerChanges
    case deleteHookRule(id: String)
}

/// The Integrations page's state: the HTTP server draft, and the confirmation it is showing.
@MainActor
@Observable
final class IntegrationsSettingsModel {
    let server: any HTTPServerControlling
    private let drafts: HTTPServerDraftStore
    var draft = HTTPServerConfiguration()
    private(set) var confirmation: IntegrationsConfirmation?
    /// The applied configuration the draft started from, to tell edits from a configuration that loaded late.
    private var base = HTTPServerConfiguration()

    init(server: any HTTPServerControlling, drafts: HTTPServerDraftStore) {
        self.server = server
        self.drafts = drafts
    }

    var hasUnappliedChanges: Bool {
        self.draft != self.server.configuration
    }

    /// Starts from the edits the pane left behind, if they are still unapplied, and asks about them.
    func paneAppeared() {
        let opened = self.drafts.open(applied: self.server.configuration)
        self.draft = opened.draft
        self.base = self.server.configuration
        if opened.hasUnappliedChanges {
            self.confirmation = .unappliedHTTPServerChanges
        }
    }

    /// The server's configuration changed (it loaded at launch, or Apply saved it). An untouched draft follows
    /// it, so a late load never reads as unapplied edits; a draft with edits keeps them.
    func serverConfigurationChanged() {
        if self.draft == self.base {
            self.draft = self.server.configuration
        }
        self.base = self.server.configuration
    }

    /// Keeps unapplied edits for the next time the pane opens.
    func paneDisappeared() {
        self.drafts.close(draft: self.draft, applied: self.server.configuration)
    }

    /// Saves the draft and restarts the server with it. The server rejects invalid settings and says why
    /// in its status; the draft then stays unapplied.
    func apply() async {
        await self.server.apply(self.draft)
    }

    func discardChanges() {
        self.draft = self.server.configuration
        self.base = self.server.configuration
        self.drafts.discard()
    }

    /// Asks before deleting: nothing is removed until `confirmDelete(in:)`.
    func requestDelete(_ rule: HookRule) {
        self.confirmation = .deleteHookRule(id: rule.id)
    }

    func confirmDelete(in settings: SettingsStore) {
        guard case let .deleteHookRule(id) = self.confirmation else { return }
        settings.removeHookRule(id: id)
        self.confirmation = nil
    }

    func dismissConfirmation() {
        self.confirmation = nil
    }
}

extension IntegrationsSettingsPane {
    /// The settings search can jump to. Each one marks its row with `.settingsAnchor(anchor(_:))`.
    enum SearchSetting: String {
        case httpServer
        case httpServerBind
        case httpServerPort
        case httpServerToken
        case httpServerCache
        case httpServerTimeout
        case httpServerAllAccounts
        case httpServerIdentity
        case installCLI
        case hooks
        case hookRules
    }

    static func anchor(_ setting: SearchSetting) -> String {
        "\(SettingsPane.integrations.persistenceToken)/\(setting.rawValue)"
    }

    static var searchEntries: [SettingsSearchEntry] {
        let pane = SettingsPane.integrations
        let httpServer = L("http_server_title")
        let hooks = L("tab_hooks")
        let commandLine = L("section_command_line")
        let cliSubtitle = L("install_cli_subtitle")
        let advanced = SettingsSearchEntry.formerAdvancedKeyword
        func entry(_ setting: SearchSetting, _ title: String, keywords: String...) -> SettingsSearchEntry {
            SettingsSearchEntry(id: self.anchor(setting), pane: pane, title: title, keywords: keywords)
        }
        return [
            .paneTitle(pane, keywords: advanced),
            entry(.httpServer, httpServer, keywords: L("http_server_enable"), advanced),
            entry(.httpServerBind, L("http_server_bind"), keywords: httpServer, advanced),
            entry(.httpServerPort, L("http_server_port"), keywords: httpServer, advanced),
            entry(.httpServerToken, L("http_server_token"), keywords: httpServer, advanced),
            entry(.httpServerCache, L("http_server_cache"), keywords: httpServer, advanced),
            entry(.httpServerTimeout, L("http_server_timeout"), keywords: httpServer, advanced),
            entry(.httpServerAllAccounts, L("http_server_all_accounts"), keywords: httpServer, advanced),
            entry(.httpServerIdentity, L("http_server_identity"), keywords: httpServer, advanced),
            entry(.installCLI, L("install_cli"), keywords: commandLine, cliSubtitle, advanced),
            entry(.hooks, L("hooks_enable_title"), keywords: hooks, L("hooks_enable_subtitle")),
            entry(.hookRules, L("hooks_rules_header"), keywords: hooks, L("hooks_add_rule")),
        ]
    }
}
