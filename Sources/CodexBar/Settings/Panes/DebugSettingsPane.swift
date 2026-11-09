import AppKit
import CodexBarCore
import InternalUI
import SwiftUI

/// Debug: logging, logs, fetch attempts, simulations, caches, the command line and the plugin engine rollback.
/// Listed only while the debug-settings switch is on.
@MainActor
struct DebugSettingsPane: View {
    let context: SettingsPaneContext

    var body: some View {
        DebugSettingsPage(settings: self.context.settings, store: self.context.store)
    }
}

extension DebugSettingsPane {
    static var searchEntries: [SettingsSearchEntry] {
        let pane = SettingsPane.debug
        let logging = L("section_logging")
        let simulations = L("section_simulations")
        let caches = L("section_caches")
        let commandLine = L("section_command_line")
        var entries: [SettingsSearchEntry] = [
            .paneTitle(pane),
            pane.searchEntry("fileLogging", L("enable_file_logging"), keywords: logging),
            pane.searchEntry("verbosity", L("verbosity_title"), keywords: logging),
            pane.searchEntry("openLogFile", L("open_log_file"), keywords: logging),
            pane.searchEntry(
                "probeLogs",
                L("section_logs"),
                keywords: L("section_probe_logs"),
                L("section_openai_cookies"),
                L("fetch_log"),
                L("load_parse_dump"),
                L("rerun_provider_autodetect")),
            pane.searchEntry("fetchStrategy", L("section_fetch_strategy")),
            pane.searchEntry("forceAnimation", L("force_animation_next_refresh"), keywords: simulations),
            pane.searchEntry(
                "loadingAnimations",
                L("Animation pattern"),
                keywords: simulations,
                L("section_loading_animations"),
                L("replay_selected_animation"),
                L("blink_now")),
            pane.searchEntry(
                "notifications",
                L("section_notifications"),
                keywords: simulations,
                L("post_depleted"),
                L("post_restored")),
            pane.searchEntry("clearCostCache", L("clear_cost_cache"), keywords: caches),
            pane.searchEntry("clearCookieCache", L("clear_cookie_cache"), keywords: caches),
            pane.searchEntry(
                "cliSessions",
                L("keep_cli_sessions_alive"),
                keywords: commandLine,
                L("section_cli_sessions")),
            pane.searchEntry("resetCLISessions", L("reset_cli_sessions"), keywords: commandLine),
            pane.searchEntry("cliPaths", L("section_cli_paths"), keywords: commandLine, L("effective_path")),
            pane.searchEntry("pluginEngine", L("use_javascriptcore_plugin_engine"), keywords: L("Provider Plugins")),
        ]
        #if DEBUG
        entries.append(pane.searchEntry("errorSimulation", L("section_error_simulation"), keywords: simulations))
        #endif
        return entries
    }
}

@MainActor
struct DebugSettingsPage: View {
    @Bindable var settings: SettingsStore
    @Bindable var store: UsageStore
    /// Reads the CLI paths when the pane appears. Snapshots turn it off and set the paths themselves.
    var loadsPathInfo = true
    var initialLogText = ""
    @AppStorage("debugFileLoggingEnabled") private var debugFileLoggingEnabled = false
    @AppStorage(ProviderPluginRuntime.javaScriptCoreRollbackDefaultsKey)
    private var useJavaScriptCorePluginEngine = false
    // Provider-specific by design: the fetch, notification and error pickers historically start on Codex.
    @State private var fetchProvider: UsageProvider = .codex
    @State private var notificationProvider: UsageProvider = .codex
    @State private var isClearingCostCache = false
    @State private var costCacheStatus: String?
    @State private var cookieCacheStatus: String?
    @State private var confirmation: SettingsConfirmation?
    #if DEBUG
    @State private var errorProvider: UsageProvider = .codex
    @State private var simulatedErrorText: String = """
    Simulated error for testing layout.
    Second line.
    Third line.
    Fourth line.
    """
    #endif

    var body: some View {
        IUSettingsPage(L("tab_debug")) {
            self.loggingSection
            DebugLogsSection(settings: self.settings, store: self.store, logText: self.initialLogText)
                .settingsAnchor("debug/probeLogs")
            self.fetchStrategySection
            self.simulationsSection
            #if DEBUG
            self.errorSimulationSection
            #endif
            self.cachesSection
            self.commandLineSection
            IUSettingsSection(L("Provider Plugins")) {
                IUSettingsToggleRow(
                    L("use_javascriptcore_plugin_engine"),
                    subtitle: L("use_javascriptcore_plugin_engine_subtitle"),
                    isOn: self.$useJavaScriptCorePluginEngine)
                    .settingsAnchor("debug/pluginEngine")
            }
        }
        .settingsConfirmation(self.$confirmation)
        .task {
            guard self.loadsPathInfo else { return }
            await self.store.refreshPathDebugInfo()
        }
    }

    // MARK: Sections

    private var loggingSection: some View {
        IUSettingsSection(L("section_logging")) {
            IUSettingsToggleRow(
                L("enable_file_logging"),
                subtitle: String(format: L("enable_file_logging_subtitle"), CodexBarLog.fileLogURL.path),
                isOn: self.$debugFileLoggingEnabled)
                .settingsAnchor("debug/fileLogging")
                .onChange(of: self.debugFileLoggingEnabled) { _, newValue in
                    if self.settings.debugFileLoggingEnabled != newValue {
                        self.settings.debugFileLoggingEnabled = newValue
                    }
                }
            IUSettingsRow(L("verbosity_title"), subtitle: L("verbosity_subtitle")) {
                IUPopUpButton(
                    CodexBarLog.Level.allCases.map { ($0, $0.displayName) },
                    selection: self.$settings.debugLogLevel)
            }
            .settingsAnchor("debug/verbosity")
            IUSettingsLinkRow(L("open_log_file"), systemImage: "doc.text.magnifyingglass") {
                NSWorkspace.shared.open(CodexBarLog.fileLogURL)
            }
            .settingsAnchor("debug/openLogFile")
        }
    }

    private var fetchStrategySection: some View {
        IUSettingsSection(L("section_fetch_strategy"), footer: L("fetch_strategy_caption")) {
            IUSettingsRow(L("Provider")) {
                IUPopUpButton(
                    UsageProvider.allCases.map { ($0, $0.rawValue.capitalized) },
                    selection: self.$fetchProvider)
            }
            DebugTextRow(text: self.fetchAttemptsText(for: self.fetchProvider), height: IUSize.settingsRow * 3)
        }
        .settingsAnchor("debug/fetchStrategy")
    }

    private var simulationsSection: some View {
        IUSettingsSection(L("section_simulations"), footer: L("loading_animations_caption")) {
            IUSettingsToggleRow(
                L("force_animation_next_refresh"),
                subtitle: L("force_animation_next_refresh_subtitle"),
                isOn: self.$store.debugForceAnimation)
                .settingsAnchor("debug/forceAnimation")
            IUSettingsRow(L("Animation pattern")) {
                IUPopUpButton(
                    [(LoadingPattern?.none, L("animation_random_default"))]
                        + LoadingPattern.allCases.map { (Optional($0), $0.displayName) },
                    selection: self.$settings.debugLoadingPattern)
            }
            .settingsAnchor("debug/loadingAnimations")
            DebugActionsRow {
                Button(L("replay_selected_animation")) { self.replaySelectedAnimation() }
                    .keyboardShortcut(.defaultAction)
                Button {
                    NotificationCenter.default.post(name: .codexbarDebugBlinkNow, object: nil)
                } label: {
                    Label(L("blink_now"), systemImage: "eyes")
                }
            }
            IUSettingsRow(L("section_notifications"), subtitle: L("notifications_caption")) {
                IUSegmentedControl(
                    Self.notificationSimulationProviders.map { ($0, Self.displayName(of: $0)) },
                    selection: self.$notificationProvider)
            }
            .settingsAnchor("debug/notifications")
            DebugActionsRow {
                Button {
                    self.postSessionNotification(.depleted)
                } label: {
                    Label(L("post_depleted"), systemImage: "bell.badge")
                }
                Button {
                    self.postSessionNotification(.restored)
                } label: {
                    Label(L("post_restored"), systemImage: "bell")
                }
            }
        }
    }

    #if DEBUG
    private var errorSimulationSection: some View {
        // Provider-specific by design: only Codex/Claude expose scanner-owned token errors here.
        let supportsTokenError = self.errorProvider == .codex || self.errorProvider == .claude
        return IUSettingsSection(L("section_error_simulation"), footer: L("error_simulation_caption")) {
            IUSettingsRow(L("Provider")) {
                IUPopUpButton(
                    Self.errorSimulationProviders.map { ($0, Self.displayName(of: $0)) },
                    selection: self.$errorProvider)
            }
            .settingsAnchor("debug/errorSimulation")
            IUSettingsRow(L("Simulated error text")) {
                TextField(L("Simulated error text"), text: self.$simulatedErrorText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(IUTextRole.body.font)
                    .lineLimit(4, reservesSpace: true)
                    .padding(IUSpace.unit * 2)
                    .frame(width: IUSize.settingsField)
                    .iuWell(radius: IURadius.row)
            }
            IUSettingsRow(L("debug_menu_error_title")) {
                HStack(spacing: IUSpace.unit * 2) {
                    Button(L("set_menu_error")) {
                        self.store._setErrorForTesting(self.simulatedErrorText, provider: self.errorProvider)
                    }
                    Button(L("clear_menu_error")) {
                        self.store._setErrorForTesting(nil, provider: self.errorProvider)
                    }
                }
                .buttonStyle(.iu())
            }
            IUSettingsRow(L("debug_cost_error_title"), disabledReason: L("debug_cost_error_unsupported")) {
                HStack(spacing: IUSpace.unit * 2) {
                    Button(L("set_cost_error")) {
                        self.store._setTokenErrorForTesting(self.simulatedErrorText, provider: self.errorProvider)
                    }
                    Button(L("clear_cost_error")) {
                        self.store._setTokenErrorForTesting(nil, provider: self.errorProvider)
                    }
                }
                .buttonStyle(.iu())
            }
            .disabled(!supportsTokenError)
        }
    }
    #endif

    private var cachesSection: some View {
        // Provider-specific by design: cache activity currently tracks the Codex/Claude scanners.
        let isTokenRefreshActive = self.store.isTokenRefreshInFlight(for: .codex)
            || self.store.isTokenRefreshInFlight(for: .claude)
        return IUSettingsSection(L("section_caches"), footer: L("caches_caption")) {
            IUSettingsRow(
                L("clear_cost_cache"),
                subtitle: self.costCacheStatus,
                disabledReason: L("debug_cost_cache_busy"))
            {
                if self.isClearingCostCache {
                    ProgressView().controlSize(.small)
                } else {
                    Button(L("Clear")) { self.confirmClearCostCache() }
                        .buttonStyle(.iu())
                }
            }
            .disabled(isTokenRefreshActive)
            .settingsAnchor("debug/clearCostCache")
            IUSettingsRow(L("clear_cookie_cache"), subtitle: self.cookieCacheStatus) {
                Button(L("Clear")) { self.confirmClearCookieCache() }
                    .buttonStyle(.iu())
            }
            .settingsAnchor("debug/clearCookieCache")
        }
    }

    private var commandLineSection: some View {
        // Provider-specific by design: PathDebugInfo only records the Codex and Claude binaries.
        let paths = self.store.pathDebugInfo
        return IUSettingsSection(
            L("section_command_line"),
            footer: L("cli_sessions_caption") + " " + L("cli_paths_caption"))
        {
            IUSettingsToggleRow(
                L("keep_cli_sessions_alive"),
                subtitle: L("keep_cli_sessions_alive_subtitle"),
                isOn: self.$settings.debugKeepCLISessionsAlive)
                .settingsAnchor("debug/cliSessions")
            IUSettingsRow(L("reset_cli_sessions")) {
                Button(L("debug_reset_action")) { self.confirmResetCLISessions() }
                    .buttonStyle(.iu())
            }
            .settingsAnchor("debug/resetCLISessions")
            IUSettingsValueRow(L("codex_binary"), value: paths.codexBinary ?? L("not_found"))
                .settingsAnchor("debug/cliPaths")
            IUSettingsValueRow(L("claude_binary"), value: paths.claudeBinary ?? L("not_found"))
            DebugTextRow(
                title: L("effective_path"),
                text: paths.effectivePATH.isEmpty ? L("unavailable") : paths.effectivePATH)
            if let loginPATH = paths.loginShellPATH {
                DebugTextRow(title: L("login_shell_path"), text: loginPATH)
            }
        }
    }

    // MARK: Providers

    static let notificationSimulationProviders = Self.providers { $0.notificationSimulationOrder }
    #if DEBUG
    static let errorSimulationProviders = Self.providers { $0.errorSimulationOrder }
    #endif

    /// The providers a debug tool supports, in the order their descriptors give it.
    static func providers(order: (ProviderDebugPaneCapabilities) -> Int?) -> [UsageProvider] {
        ProviderDescriptorRegistry.all.compactMap { descriptor -> (UsageProvider, Int)? in
            guard let rank = order(descriptor.metadata.debugPane) else { return nil }
            return (descriptor.id, rank)
        }
        .sorted { $0.1 < $1.1 }
        .map(\.0)
    }

    static func displayName(of provider: UsageProvider) -> String {
        ProviderDescriptorRegistry.descriptor(for: provider).metadata.displayName
    }

    // MARK: Actions

    private func replaySelectedAnimation() {
        var userInfo: [AnyHashable: Any] = [:]
        if let pattern = self.settings.debugLoadingPattern {
            userInfo["pattern"] = pattern.rawValue
        }
        NotificationCenter.default.post(
            name: .codexbarDebugReplayAllAnimations,
            object: nil,
            userInfo: userInfo.isEmpty ? nil : userInfo)
        self.store.replayLoadingAnimation(duration: 4)
    }

    private func postSessionNotification(_ transition: SessionQuotaTransition) {
        SessionQuotaNotifier().post(transition: transition, provider: self.notificationProvider, badge: 1)
    }

    private func confirmClearCostCache() {
        self.confirmation = SettingsConfirmation(
            title: L("debug_clear_cost_cache_confirm_title"),
            message: L("debug_clear_cost_cache_confirm_message"),
            systemImage: "trash.fill",
            confirmTitle: L("Clear"),
            action: { Task { await self.clearCostCache() } })
    }

    private func confirmClearCookieCache() {
        self.confirmation = SettingsConfirmation(
            title: L("debug_clear_cookie_cache_confirm_title"),
            message: L("debug_clear_cookie_cache_confirm_message"),
            systemImage: "trash.fill",
            confirmTitle: L("Clear"),
            action: { self.cookieCacheStatus = DebugCacheStatus.cookieCache(CookieHeaderCache.clearAllDetailed()) })
    }

    private func confirmResetCLISessions() {
        self.confirmation = SettingsConfirmation(
            title: L("debug_reset_cli_sessions_confirm_title"),
            message: L("debug_reset_cli_sessions_confirm_message"),
            systemImage: "arrow.counterclockwise",
            confirmTitle: L("debug_reset_action"),
            action: { Task { await CLIProbeSessionResetter.resetAll() } })
    }

    private func clearCostCache() async {
        guard !self.isClearingCostCache else { return }
        self.isClearingCostCache = true
        self.costCacheStatus = nil
        defer { self.isClearingCostCache = false }
        self.costCacheStatus = await DebugCacheStatus.costCache(error: self.store.clearCostUsageCache())
    }

    private func fetchAttemptsText(for provider: UsageProvider) -> String {
        let attempts = self.store.fetchAttempts(for: provider)
        guard !attempts.isEmpty else { return L("no_fetch_attempts") }
        return attempts.map { attempt in
            let kind = ProviderDiagnosticFetchAttempt.kindLabel(attempt.kind)
            var line = "\(attempt.strategyID) (\(kind))"
            line += attempt.wasAvailable ? " available" : " unavailable"
            if let error = attempt.errorDescription, !error.isEmpty {
                line += " error=\(error)"
            }
            return line
        }.joined(separator: "\n")
    }
}

/// The status lines the Caches section shows after a clear.
enum DebugCacheStatus {
    static func costCache(error: String?) -> String {
        error.map { L("debug_cache_failed", $0) } ?? L("cleared")
    }

    static func cookieCache(_ summary: CookieHeaderCache.ClearSummary) -> String {
        if summary.failedCount > 0 {
            return summary.failedCount == 1
                ? L("debug_cookie_cache_failed_one")
                : L("debug_cookie_cache_failed_other", summary.failedCount)
        }
        if summary.clearedCount > 0 {
            return summary.clearedCount == 1
                ? L("debug_cookie_cache_cleared_one")
                : L("debug_cookie_cache_cleared_other", summary.clearedCount)
        }
        return L("debug_cookie_cache_empty")
    }
}
