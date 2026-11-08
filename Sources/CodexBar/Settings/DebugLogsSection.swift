import AppKit
import CodexBarCore
import InternalUI
import SwiftUI

/// Where the Debug pane's log viewer reads from.
enum DebugLogSource: Hashable, CaseIterable {
    /// A provider's latest probe output, fetched on demand.
    case probe
    /// The last OpenAI cookie import and WebKit scrape. Hidden while Keychain access is disabled.
    case openAICookies
}

/// Debug's Logs section: one viewer with a source picker and one provider picker. A probe log is fetched, copied,
/// saved to a file, swapped for Claude's parse dump, or refetched after re-running provider detection; the OpenAI
/// cookie log can be copied.
@MainActor
struct DebugLogsSection: View {
    @Bindable var settings: SettingsStore
    @Bindable var store: UsageStore
    @State private var source: DebugLogSource = .probe
    // Provider-specific by design: the debug probe picker historically starts on Codex.
    @State private var provider: UsageProvider = .codex
    @State private var isLoadingLog = false
    @State private var logText: String

    init(settings: SettingsStore, store: UsageStore, logText: String = "") {
        self.settings = settings
        self.store = store
        self._logText = State(initialValue: logText)
    }

    static let probeLogProviders = DebugSettingsPage.providers { $0.probeLogOrder }

    var body: some View {
        MacSettingsSection(
            L("section_logs"),
            footer: self.shownSource == .probe ? L("probe_logs_caption") : L("openai_cookies_caption"))
        {
            if self.cookiesAvailable {
                MacSettingsRow(L("debug_log_source")) {
                    MacSegmentedControl(
                        [
                            (DebugLogSource.probe, L("section_probe_logs")),
                            (.openAICookies, L("section_openai_cookies")),
                        ],
                        selection: self.$source)
                }
            }
            if self.shownSource == .probe {
                MacSettingsRow(L("Provider")) {
                    MacPopUpButton(
                        Self.probeLogProviders.map { ($0, DebugSettingsPage.displayName(of: $0)) },
                        selection: self.$provider)
                }
            }
            DebugTextRow(
                text: self.displayedText,
                height: MacSize.settingsRow * 4,
                isLoading: self.shownSource == .probe && self.isLoadingLog)
            DebugActionsRow {
                self.actions
            }
        }
    }

    /// The OpenAI cookie log comes from a Keychain-backed import, so it is offered only while Keychain access is on.
    private var cookiesAvailable: Bool {
        !self.settings.debugDisableKeychainAccess
    }

    private var shownSource: DebugLogSource {
        self.cookiesAvailable ? self.source : .probe
    }

    private var cookieLog: String {
        self.store.openAIDashboardCookieImportDebugLog ?? ""
    }

    private var displayedText: String {
        switch self.shownSource {
        case .probe:
            if self.logText.isEmpty {
                return self.isLoadingLog ? L("loading") : L("no_log_yet_fetch")
            }
            return self.logText
        case .openAICookies:
            return self.cookieLog.isEmpty ? L("no_log_yet") : self.cookieLog
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch self.shownSource {
        case .probe:
            Button { self.loadLog(self.provider) } label: {
                Label(L("fetch_log"), systemImage: "arrow.clockwise")
            }
            .disabled(self.isLoadingLog)

            Button { Self.copyToPasteboard(self.logText) } label: {
                Label(L("copy"), systemImage: "doc.on.doc")
            }
            .disabled(self.logText.isEmpty)

            Button { self.saveLog(self.provider) } label: {
                Label(L("save_to_file"), systemImage: "externaldrive.badge.plus")
            }
            .disabled(self.isLoadingLog && self.logText.isEmpty)

            // Provider-specific by design: only Claude exposes the raw parser dump diagnostic.
            if self.provider == .claude {
                Button { self.loadClaudeDump() } label: {
                    Label(L("load_parse_dump"), systemImage: "doc.text.magnifyingglass")
                }
                .disabled(self.isLoadingLog)
            }

            Button {
                self.settings.rerunProviderDetection()
                self.loadLog(self.provider)
            } label: {
                Label(L("rerun_provider_autodetect"), systemImage: "dot.radiowaves.left.and.right")
            }
        case .openAICookies:
            Button { Self.copyToPasteboard(self.cookieLog) } label: {
                Label(L("copy"), systemImage: "doc.on.doc")
            }
            .disabled(self.cookieLog.isEmpty)
        }
    }

    private func loadLog(_ provider: UsageProvider) {
        self.isLoadingLog = true
        Task {
            let text = await ProviderInteractionContext.$current.withValue(.userInitiated) {
                await ProviderRefreshContext.$current.withValue(.regular) {
                    await self.store.debugLog(for: provider)
                }
            }
            self.logText = text
            self.isLoadingLog = false
        }
    }

    private func saveLog(_ provider: UsageProvider) {
        Task {
            if self.logText.isEmpty {
                self.isLoadingLog = true
                let text = await ProviderInteractionContext.$current.withValue(.userInitiated) {
                    await ProviderRefreshContext.$current.withValue(.regular) {
                        await self.store.debugLog(for: provider)
                    }
                }
                self.logText = text
                self.isLoadingLog = false
            }
            _ = await ProviderInteractionContext.$current.withValue(.userInitiated) {
                await ProviderRefreshContext.$current.withValue(.regular) {
                    await self.store.dumpLog(toFileFor: provider)
                }
            }
        }
    }

    private func loadClaudeDump() {
        self.isLoadingLog = true
        Task {
            let text = await self.store.debugClaudeDump()
            self.logText = text
            self.isLoadingLog = false
        }
    }

    static func copyToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

/// Read-only monospaced text in a settings row: a log or a list of attempts, in a well that scrolls inside a fixed
/// height when given one, with a spinner over it while it loads.
@MainActor
struct DebugTextRow: View {
    var title: String?
    let text: String
    /// Nil sizes the well to its text; a height scrolls longer text inside it.
    var height: CGFloat?
    var isLoading = false

    var body: some View {
        VStack(alignment: .leading, spacing: MacSpace.unit * 2) {
            if let title {
                MacText(title)
            }
            Group {
                if let height {
                    ScrollView {
                        self.textBody
                    }
                    .frame(height: height)
                    .macSlimScrollers()
                } else {
                    self.textBody
                }
            }
            .macWell(radius: MacRadius.row)
            .overlay {
                if self.isLoading {
                    ProgressView().controlSize(.small)
                }
            }
        }
        .padding(.horizontal, MacSpace.settingsRowPaddingX)
        .padding(.vertical, MacSpace.settingsRowPaddingY)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var textBody: some View {
        Text(self.text)
            .font(MacTextRole.caption.font)
            .monospaced()
            .foregroundStyle(MacColor.primary)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(MacSpace.panelPadding)
            // Logs and paths read left to right in every language.
            .environment(\.layoutDirection, .leftToRight)
    }
}

/// A settings row of action buttons. They sit on one line when they fit and wrap onto a second line otherwise.
@MainActor
struct DebugActionsRow<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: MacSpace.unit * 2) {
                self.content
            }
            VStack(alignment: .leading, spacing: MacSpace.unit * 2) {
                self.content
            }
        }
        .buttonStyle(.mac())
        .padding(.horizontal, MacSpace.settingsRowPaddingX)
        .padding(.vertical, MacSpace.settingsRowPaddingY)
        .frame(maxWidth: .infinity, minHeight: MacSize.settingsRow, alignment: .leading)
    }
}
