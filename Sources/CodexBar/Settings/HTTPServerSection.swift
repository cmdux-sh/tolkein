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

/// The server status as a `MacStatusLabel`: the controller's lifecycle states in the app language, and
/// its error messages as they are.
struct HTTPServerStatusPresentation: Equatable {
    let text: String
    let tone: MacStatusTone
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

    private init(text: String, tone: MacStatusTone, systemImage: String?) {
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
        VStack(alignment: .leading, spacing: MacSpace.settingsHeaderGap) {
            MacSettingsSection(L("http_server_title"), footer: L("http_server_footer")) {
                self.settingRows
                self.exposureRows
                self.statusRows
            }
            self.applyBar
        }
    }

    @ViewBuilder
    private var settingRows: some View {
        MacSettingsToggleRow(L("http_server_enable"), isOn: self.$draft.enabled)
            .settingsAnchor(IntegrationsSettingsPane.anchor(.httpServer))
        MacSettingsRow(L("http_server_bind")) {
            MacTextField(L("http_server_bind"), text: self.$draft.host)
                .frame(width: MacSize.settingsField)
        }
        .settingsAnchor(IntegrationsSettingsPane.anchor(.httpServerBind))
        MacSettingsRow(L("http_server_port")) {
            SettingsFieldWell { focus in
                TextField(L("http_server_port"), value: self.$draft.port, format: .number.grouping(.never))
                    .focused(focus)
            }
            .frame(width: MacSize.settingsField)
        }
        .settingsAnchor(IntegrationsSettingsPane.anchor(.httpServerPort))
        MacSettingsRow(L("http_server_token")) {
            HStack(spacing: MacSpace.unit * 2) {
                SettingsSecureField(
                    placeholder: L("http_server_token"),
                    text: self.$draft.token,
                    isRevealed: self.$showsToken)
                    .frame(width: MacSize.settingsField)
                Button(L("http_server_generate")) { self.draft.token = HTTPServerConfiguration.generateToken() }
                    .buttonStyle(.mac())
                Button(L("copy")) { Self.copy(self.draft.token) }
                    .buttonStyle(.mac())
                    .disabled(self.draft.token.isEmpty)
            }
        }
        .settingsAnchor(IntegrationsSettingsPane.anchor(.httpServerToken))
        MacSettingsRow(L("http_server_cache")) {
            SettingsFieldWell { focus in
                TextField(L("http_server_cache"), value: self.$draft.refreshInterval, format: .number)
                    .focused(focus)
            }
            .frame(width: MacSize.settingsField)
        }
        .settingsAnchor(IntegrationsSettingsPane.anchor(.httpServerCache))
        MacSettingsRow(L("http_server_timeout")) {
            SettingsFieldWell { focus in
                TextField(L("http_server_timeout"), value: self.$draft.requestTimeout, format: .number)
                    .focused(focus)
            }
            .frame(width: MacSize.settingsField)
        }
        .settingsAnchor(IntegrationsSettingsPane.anchor(.httpServerTimeout))
        MacSettingsToggleRow(L("http_server_all_accounts"), isOn: self.$draft.allAccounts)
            .settingsAnchor(IntegrationsSettingsPane.anchor(.httpServerAllAccounts))
        MacSettingsRow(L("http_server_identity")) {
            MacPopUpButton(
                [("redacted", L("http_server_redacted")), ("full", L("full").localizedCapitalized)],
                selection: self.$draft.identity)
        }
        .settingsAnchor(IntegrationsSettingsPane.anchor(.httpServerIdentity))
    }

    /// Listening outside this Mac: what it exposes, and the opt-in to plain HTTP that it needs.
    @ViewBuilder
    private var exposureRows: some View {
        if !self.draft.isLoopback {
            MacSettingsRow(L("Network access"), subtitle: L("http_server_warning")) {
                MacStatusLabel(L("Other devices can connect"), tone: .warning)
            }
            MacSettingsToggleRow(L("http_server_plain_http"), isOn: self.$draft.allowPlainHTTP)
        }
    }

    @ViewBuilder
    private var statusRows: some View {
        let status = HTTPServerStatusPresentation(
            status: self.server.status,
            validationErrors: [self.draft.validationError, self.server.configuration.validationError])
        MacSettingsRow(L("Status")) {
            MacStatusLabel(status.text, tone: status.tone, systemImage: status.systemImage)
        }
        if let url = self.server.runningURL {
            let isWildcard = self.server.configuration.bindHost == "0.0.0.0"
            MacSettingsRow(L("http_server_dashboard"), subtitle: isWildcard ? L("http_server_wildcard") : nil) {
                HStack(spacing: MacSpace.unit * 2) {
                    MacText(url, muted: true)
                        .textSelection(.enabled)
                    Button(L("copy")) { Self.copy(url) }
                        .buttonStyle(.mac())
                }
            }
        }
    }

    /// Apply saves the draft and restarts the server; it stays available without edits, to restart it.
    private var applyBar: some View {
        HStack(spacing: MacSpace.unit * 2) {
            if self.hasUnappliedChanges {
                MacStatusLabel(L("Unapplied changes"), tone: .warning)
            }
            Spacer(minLength: MacSpace.panelPadding)
            if self.hasUnappliedChanges {
                Button(L("Discard"), action: self.onDiscard)
                    .buttonStyle(.mac())
            }
            Button(L("apply"), action: self.onApply)
                .buttonStyle(.mac(self.hasUnappliedChanges ? .primary : .standard))
                .disabled(self.server.isTransitioning)
        }
        .macControlSize(.large)
        .padding(.horizontal, MacSpace.settingsRowPaddingX)
    }

    private static func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}
