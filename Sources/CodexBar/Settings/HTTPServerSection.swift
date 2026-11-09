import AppKit
import InternalUI
import Observation
import SwiftUI

/// What the HTTP server section reads from and asks of the server. `HTTPServerController` is the real one;
/// snapshot tests pass a stub so no helper process starts.
@MainActor
protocol HTTPServerControlling: AnyObject, Observable {
    var configuration: HTTPServerConfiguration { get }
    var status: String { get }
    var isTransitioning: Bool { get }
    var runningURL: String? { get }
    func apply(_ configuration: HTTPServerConfiguration) async
}

extension HTTPServerController: HTTPServerControlling {}

/// Keeps unapplied HTTP server edits for the rest of the app session, so leaving the Integrations pane or
/// closing Settings no longer drops them. The pane warns when it opens again with edits still unapplied.
@MainActor
@Observable
final class HTTPServerDraftStore {
    static let shared = HTTPServerDraftStore()

    /// Edits the pane left behind that differ from the applied configuration.
    private(set) var keptDraft: HTTPServerConfiguration?

    /// The draft the pane starts from, and whether it holds edits that were never applied. A kept draft that
    /// now matches the applied configuration (applied elsewhere, or edited back) is dropped.
    func open(applied: HTTPServerConfiguration) -> (draft: HTTPServerConfiguration, hasUnappliedChanges: Bool) {
        guard let kept = self.keptDraft, kept != applied else {
            self.keptDraft = nil
            return (applied, false)
        }
        return (kept, true)
    }

    /// Records the draft as the pane closes. Only edits that differ from the applied configuration are kept.
    func close(draft: HTTPServerConfiguration, applied: HTTPServerConfiguration) {
        self.keptDraft = draft == applied ? nil : draft
    }

    func discard() {
        self.keptDraft = nil
    }
}

/// The server status as a `IUStatusLabel`: the controller's lifecycle states in the app language, and
/// its error messages as they are.
struct HTTPServerStatusPresentation: Equatable {
    let text: String
    let tone: IUStatusTone
    let systemImage: String?

    /// - Parameter validationErrors: messages that come from the settings themselves; they show as warnings
    ///   (fix a field), while launch and exit failures show as errors.
    init(status: String, validationErrors: [String?]) {
        switch status {
        case "Running":
            self.init(text: L("Running"), tone: .neutral, systemImage: "checkmark.circle.fill")
        case "Stopped":
            self.init(text: L("Stopped"), tone: .neutral, systemImage: "stop.circle")
        case "Starting…":
            self.init(text: L("Starting…"), tone: .busy, systemImage: nil)
        case "Stopping…":
            self.init(text: L("Stopping…"), tone: .busy, systemImage: nil)
        default:
            let isValidation = validationErrors.contains { $0 == status }
            self.init(text: status, tone: isValidation ? .warning : .error, systemImage: nil)
        }
    }

    private init(text: String, tone: IUStatusTone, systemImage: String?) {
        self.text = text
        self.tone = tone
        self.systemImage = systemImage
    }
}

/// The local HTTP server: its settings as a draft that Apply saves and restarts the server with, the
/// server status, and the dashboard URL while it runs.
@MainActor
struct HTTPServerSection: View {
    let server: any HTTPServerControlling
    @Binding var draft: HTTPServerConfiguration
    let onApply: () -> Void
    let onDiscard: () -> Void
    @State private var showsToken = false

    private var hasUnappliedChanges: Bool {
        self.draft != self.server.configuration
    }

    var body: some View {
        VStack(alignment: .leading, spacing: IUSpace.settingsHeaderGap) {
            IUSettingsSection(L("http_server_title"), footer: L("http_server_footer")) {
                self.settingRows
                self.exposureRows
                self.statusRows
            }
            self.applyBar
        }
    }

    @ViewBuilder
    private var settingRows: some View {
        IUSettingsToggleRow(L("http_server_enable"), isOn: self.$draft.enabled)
            .settingsAnchor(IntegrationsSettingsPane.anchor(.httpServer))
        IUSettingsRow(L("http_server_bind")) {
            IUTextField(L("http_server_bind"), text: self.$draft.host)
                .frame(width: IUSize.settingsField)
        }
        .settingsAnchor(IntegrationsSettingsPane.anchor(.httpServerBind))
        IUSettingsRow(L("http_server_port")) {
            SettingsFieldWell { focus in
                TextField(L("http_server_port"), value: self.$draft.port, format: .number.grouping(.never))
                    .focused(focus)
            }
            .frame(width: IUSize.settingsField)
        }
        .settingsAnchor(IntegrationsSettingsPane.anchor(.httpServerPort))
        IUSettingsRow(L("http_server_token")) {
            HStack(spacing: IUSpace.unit * 2) {
                SettingsSecureField(
                    placeholder: L("http_server_token"),
                    text: self.$draft.token,
                    isRevealed: self.$showsToken)
                    .frame(width: IUSize.settingsField)
                Button(L("http_server_generate")) { self.draft.token = HTTPServerConfiguration.generateToken() }
                    .buttonStyle(.iu())
                Button(L("copy")) { Self.copy(self.draft.token) }
                    .buttonStyle(.iu())
                    .disabled(self.draft.token.isEmpty)
            }
        }
        .settingsAnchor(IntegrationsSettingsPane.anchor(.httpServerToken))
        IUSettingsRow(L("http_server_cache")) {
            SettingsFieldWell { focus in
                TextField(L("http_server_cache"), value: self.$draft.refreshInterval, format: .number)
                    .focused(focus)
            }
            .frame(width: IUSize.settingsField)
        }
        .settingsAnchor(IntegrationsSettingsPane.anchor(.httpServerCache))
        IUSettingsRow(L("http_server_timeout")) {
            SettingsFieldWell { focus in
                TextField(L("http_server_timeout"), value: self.$draft.requestTimeout, format: .number)
                    .focused(focus)
            }
            .frame(width: IUSize.settingsField)
        }
        .settingsAnchor(IntegrationsSettingsPane.anchor(.httpServerTimeout))
        IUSettingsToggleRow(L("http_server_all_accounts"), isOn: self.$draft.allAccounts)
            .settingsAnchor(IntegrationsSettingsPane.anchor(.httpServerAllAccounts))
        IUSettingsRow(L("http_server_identity")) {
            IUPopUpButton(
                [("redacted", L("http_server_redacted")), ("full", L("full").localizedCapitalized)],
                selection: self.$draft.identity)
        }
        .settingsAnchor(IntegrationsSettingsPane.anchor(.httpServerIdentity))
    }

    /// Listening outside this Mac: what it exposes, and the opt-in to plain HTTP that it needs.
    @ViewBuilder
    private var exposureRows: some View {
        if !self.draft.isLoopback {
            IUSettingsRow(L("Network access"), subtitle: L("http_server_warning")) {
                IUStatusLabel(L("Other devices can connect"), tone: .warning)
            }
            IUSettingsToggleRow(L("http_server_plain_http"), isOn: self.$draft.allowPlainHTTP)
        }
    }

    @ViewBuilder
    private var statusRows: some View {
        let status = HTTPServerStatusPresentation(
            status: self.server.status,
            validationErrors: [self.draft.validationError, self.server.configuration.validationError])
        IUSettingsRow(L("Status")) {
            IUStatusLabel(status.text, tone: status.tone, systemImage: status.systemImage)
        }
        if let url = self.server.runningURL {
            let isWildcard = self.server.configuration.bindHost == "0.0.0.0"
            IUSettingsRow(L("http_server_dashboard"), subtitle: isWildcard ? L("http_server_wildcard") : nil) {
                HStack(spacing: IUSpace.unit * 2) {
                    IUText(url, muted: true)
                        .textSelection(.enabled)
                    Button(L("copy")) { Self.copy(url) }
                        .buttonStyle(.iu())
                }
            }
        }
    }

    /// Apply saves the draft and restarts the server; it stays available without edits, to restart it.
    private var applyBar: some View {
        HStack(spacing: IUSpace.unit * 2) {
            if self.hasUnappliedChanges {
                IUStatusLabel(L("Unapplied changes"), tone: .warning)
            }
            Spacer(minLength: IUSpace.panelPadding)
            if self.hasUnappliedChanges {
                Button(L("Discard"), action: self.onDiscard)
                    .buttonStyle(.iu())
            }
            Button(L("apply"), action: self.onApply)
                .buttonStyle(.iu(self.hasUnappliedChanges ? .primary : .standard))
                .disabled(self.server.isTransitioning)
        }
        .iuControlSize(.large)
        .padding(.horizontal, IUSpace.settingsRowPaddingX)
    }

    private static func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}
