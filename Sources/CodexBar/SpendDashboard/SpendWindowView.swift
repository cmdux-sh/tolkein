import AppKit
import CodexBarCore
import InternalUI
import SwiftUI

/// The Spend window: local estimated cost history across providers. A pinned title row with Refresh, then the
/// time range, the Codex catch-up panel, a section per currency, the activity heatmap and, when the menu asks for
/// it, the session browser. Everything reads the shared `SpendDashboardController`; the settings that shape it
/// (tracking, sources, time zone, export) live in Settings → Costs.
@MainActor
struct SpendWindowView: View {
    @Bindable var settings: SettingsStore
    @Bindable var store: UsageStore
    let chrome: MacWindowChrome
    @State private var navigation: SessionUsageNavigation
    @State private var isVisible = false
    @State private var userSelectedBackground = false
    @State private var detailSelections: [String: SpendDashboardDetailSection] = [:]

    /// - Parameters:
    ///   - navigation: carries a session browser request from the menu; the window shows it instead of the
    ///     dashboard until its back button clears it.
    ///   - chrome: `.system` in the real window; snapshots pass `.drawn` to see the title row.
    init(
        settings: SettingsStore,
        store: UsageStore,
        navigation: SessionUsageNavigation = .shared,
        chrome: MacWindowChrome = .system)
    {
        self.settings = settings
        self.store = store
        self.chrome = chrome
        self._navigation = State(initialValue: navigation)
    }

    var body: some View {
        MacWindow(L("Spend"), subtitle: L("Local estimated cost history"), chrome: self.chrome) {
            self.refreshButton
        } content: {
            ScrollView {
                VStack(alignment: .leading, spacing: MacSpace.chromeGap) {
                    if let request = self.navigation.request {
                        self.sessionBrowserHeader
                        SessionUsageBrowser(
                            context: request.context,
                            hidePersonalInfo: self.settings.hidePersonalInfo,
                            selectedSessionID: request.sessionID)
                            .id(request.id)
                            .frame(height: SpendDashboardPanelLayout.sessionBrowserHeight)
                            .macCard(padding: 0)
                    } else {
                        if self.settings.costUsageEnabled {
                            self.rangeBar
                        }
                        self.refreshStatus
                        self.codexCostCatchUpPanel
                        self.content
                    }
                }
                .padding(MacSpace.panelPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .macSlimScrollers()
            }
            .background(FocusResigningBackground())
        }
        .onAppear {
            self.isVisible = true
            self.controller.update(configuration: self.configuration)
            self.controller.refreshIfStale()
            if !self.controller.isRefreshing {
                self.synchronizeCodexCostCatchUp()
            }
        }
        .onChange(of: self.configuration) { _, configuration in
            self.controller.update(configuration: configuration)
        }
        .onChange(of: self.configuration.codexAccountIdentities) { _, _ in
            if self.isVisible, !self.controller.isRefreshing {
                self.synchronizeCodexCostCatchUp()
            }
        }
        .onChange(of: self.configuration.costUsageEnabled) { _, _ in
            if self.isVisible, !self.controller.isRefreshing {
                self.synchronizeCodexCostCatchUp()
            }
        }
        .onChange(of: self.controller.isRefreshing) { _, isRefreshing in
            if self.isVisible, !isRefreshing {
                self.synchronizeCodexCostCatchUp()
            }
        }
        .onDisappear {
            self.isVisible = false
            self.synchronizeCodexCostCatchUp()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            self.controller.refreshDateWindow()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
            self.controller.refreshDateWindow()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            self.controller.refreshDateWindow()
            self.controller.refreshIfStale()
        }
    }

    // MARK: - Chrome

    private var refreshButton: some View {
        MacToolButton(L("Refresh"), systemImage: "arrow.clockwise", help: L("Refresh") + " (⌘R)") {
            self.refresh()
        }
        .keyboardShortcut("r")
        .disabled(!self.canRefresh)
        .accessibilityIdentifier("spend-window-refresh")
    }

    /// Refresh is off while a load runs and while cost tracking is off, as in the old dashboard header.
    var canRefresh: Bool {
        !self.controller.isRefreshing && self.settings.costUsageEnabled
    }

    func refresh() {
        self.store.refreshSpendDashboard(accounts: self.codexSpendScanRequests)
    }

    private var sessionBrowserHeader: some View {
        HStack(spacing: MacSpace.tabContentGap) {
            Button {
                self.navigation.request = nil
            } label: {
                Label(L("Spend"), systemImage: "chevron.backward")
            }
            .buttonStyle(.mac())
            .accessibilityIdentifier("spend-window-sessions-back")
            MacText(L("Sessions"), role: .title)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, MacSpace.rowPaddingX)
    }

    // MARK: - Range and status

    private var rangeBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: MacSpace.tabContentGap) {
                self.rangePicker
                Spacer(minLength: 0)
                self.refreshingStatus
            }
            VStack(alignment: .leading, spacing: MacSpace.chromeGap) {
                self.rangePicker
                self.refreshingStatus
            }
        }
    }

    private var rangePicker: some View {
        MacSegmentedControl(Self.periodOptions(selected: self.controller.selectedPeriod), selection: self.periodBinding)
            .fixedSize()
            .accessibilityLabel(L("Time range"))
            .accessibilityIdentifier("spend-dashboard-range-picker")
    }

    @ViewBuilder
    private var refreshingStatus: some View {
        if self.controller.isRefreshing {
            MacStatusLabel(L("Refreshing"), tone: .busy)
        }
    }

    /// The range choices: 7, 30 and 90 days, month to date and all, plus a stored rolling range that is none of them.
    static func periodOptions(selected: CostReportingPeriod) -> [(CostReportingPeriod, String)] {
        var options: [(CostReportingPeriod, String)] = [
            (.rolling(days: 7), spendDashboardDayRangeText(7)),
            (.rolling(days: 30), spendDashboardDayRangeText(30)),
            (.rolling(days: 90), spendDashboardDayRangeText(90)),
            (.monthToDate, L("Month to date")),
            (.allTime, L("All")),
        ]
        if case let .rolling(days) = selected, ![7, 30, 90].contains(days) {
            options.append((selected, spendDashboardDayRangeText(days)))
        }
        return options
    }

    @ViewBuilder
    private var refreshStatus: some View {
        if self.controller.failedSourceCount > 0 {
            MacStatusLabel(
                spendDashboardRefreshFailureText(self.controller.failedSourceCount),
                tone: .warning)
                .padding(.horizontal, MacSpace.rowPaddingX)
        }
    }

    // MARK: - Codex catch-up

    @ViewBuilder
    private var codexCostCatchUpPanel: some View {
        if let activity = self.store.spendDashboardCodexCostCatchUpActivity,
           activity.phase != .complete
        {
            SpendDashboardPanel {
                VStack(alignment: .leading, spacing: MacSpace.panelPadding) {
                    HStack(spacing: MacSpace.chromeGap) {
                        Label(
                            self.codexCostCatchUpTitle(activity),
                            systemImage: activity.phase == .paused ? "pause.circle" : "externaldrive")
                            .font(MacTextRole.subtitle.font)
                            .foregroundStyle(MacColor.primary)
                        Spacer()
                        Text(codexCostCatchUpProgressText(activity))
                            .font(MacTextRole.caption.font.monospacedDigit())
                            .foregroundStyle(MacColor.muted)
                    }

                    if let progress = activity.fractionCompleted {
                        ProgressView(value: progress)
                    } else if activity.phase == .indexing {
                        ProgressView()
                            .controlSize(.small)
                    }

                    if let staleSnapshotUpdatedAt = activity.staleSnapshotUpdatedAt {
                        MacStatusLabel(
                            L("stale data") + " · " + L(
                                "Updated relative %@",
                                staleSnapshotUpdatedAt.relativeDescription()),
                            tone: .warning,
                            systemImage: "clock.badge.exclamationmark")
                    }

                    MacText(self.codexCostCatchUpDetail(activity), role: .caption, muted: true)

                    HStack(spacing: MacSpace.chromeGap) {
                        if activity.pauseReason == .user
                            || activity.pauseReason == .noProgress
                            || self.codexCostCatchUpHasError(activity)
                        {
                            Button(L("Refresh")) {
                                self.startCodexCostCatchUp(mode: .automatic)
                            }
                        } else if activity.mode == .automatic {
                            Button(L("Finish now")) {
                                self.startCodexCostCatchUp(mode: .accelerated)
                            }
                        } else {
                            Button(L("Continue in background")) {
                                self.userSelectedBackground = true
                                self.startCodexCostCatchUp(mode: .automatic)
                            }
                        }

                        if activity.pauseReason != .user,
                           activity.pauseReason != .noProgress,
                           !self.codexCostCatchUpHasError(activity)
                        {
                            Button(L("Cancel")) {
                                self.store.stopSpendDashboardCodexCostCatchUp()
                            }
                        }
                    }
                    .buttonStyle(.mac())
                    .macControlSize(.regular)
                }
            }
        }
    }

    private func codexCostCatchUpHasError(_ activity: CodexCostCatchUpActivity) -> Bool {
        if case .error = activity.pauseReason {
            return true
        }
        return false
    }

    private func synchronizeCodexCostCatchUp() {
        guard self.isVisible else {
            self.userSelectedBackground = false
            self.store.synchronizeSpendDashboardCodexCostCatchUp(
                accounts: self.codexSpendScanRequests,
                preferredMode: .automatic)
            return
        }
        let preferredMode: CodexCostCatchUpMode? = self.userSelectedBackground ? nil : .accelerated
        self.store.synchronizeSpendDashboardCodexCostCatchUp(
            accounts: self.codexSpendScanRequests,
            preferredMode: preferredMode)
    }

    private func startCodexCostCatchUp(mode: CodexCostCatchUpMode) {
        if mode == .accelerated {
            self.userSelectedBackground = false
        }
        self.store.startSpendDashboardCodexCostCatchUpIfNeeded(
            accounts: self.codexSpendScanRequests,
            mode: mode)
    }

    private var codexSpendScanRequests: [CodexSpendScanRequest] {
        guard self.configuration.costUsageEnabled,
              self.configuration.providerIDs.contains(UsageProvider.codex.rawValue)
        else { return [] }
        return SpendDashboardSource.codexRequests(settings: self.settings, store: self.store)
    }

    private func codexCostCatchUpTitle(_ activity: CodexCostCatchUpActivity) -> String {
        let prefix = L("Local estimated history")
        switch activity.phase {
        case .indexing:
            return "\(prefix) · \(L("Refreshing"))"
        case .paused:
            return "\(prefix) · \(L("Inactive"))"
        case .complete:
            return "\(prefix) · \(L("Done"))"
        }
    }

    private func codexCostCatchUpDetail(_ activity: CodexCostCatchUpActivity) -> String {
        switch activity.pauseReason {
        case .lowPower:
            L("Battery Saver")
        case .thermal, .user:
            L("Inactive")
        case .noProgress:
            L("Error")
        case let .error(message):
            L("cost_status_error", L("Cost"), message)
        case nil:
            L("Estimated from local Codex logs for the selected account.")
        }
    }

    // MARK: - Dashboard

    @ViewBuilder
    private var content: some View {
        if self.settings.costUsageEnabled,
           let configuration = self.controller.configuration,
           let currency = spendDashboardCodexDetailPlaceholderCurrency(
               configuration: configuration,
               currencyCodes: self.controller.model.groups.map(\.currencyCode))
        {
            SpendDashboardCurrencySection.placeholderDetailPanel(
                currencyCode: currency,
                timeZone: configuration.bucketCalendar.timeZone,
                hidePersonalInfo: self.settings.hidePersonalInfo,
                selection: self.detailSelection(for: currency))
        }
        if !self.settings.costUsageEnabled {
            SpendDashboardPanel {
                MacEmptyState.firstUse(
                    L("Cost tracking is off"),
                    systemImage: "chart.bar.xaxis",
                    message: L("Turn on Track costs to build local estimates."),
                    primary: MacEmptyStateAction(L("Turn On")) {
                        self.settings.costUsageEnabled = true
                    })
            }
        } else if self.controller.model.groups.isEmpty {
            let emptyState = SpendDashboardEmptyState.make(isRefreshing: self.controller.isRefreshing)
            SpendDashboardPanel {
                MacEmptyState(emptyState.title, systemImage: "chart.bar.xaxis", message: emptyState.message)
            }
        } else {
            ForEach(self.controller.model.groups) { group in
                SpendDashboardCurrencySection(
                    group: group,
                    requestedDays: self.controller.model.requestedDays,
                    hidePersonalInfo: self.settings.hidePersonalInfo,
                    detailSelection: self.detailSelection(for: group.id),
                    supportsCodexDetails: self.controller.configuration?.supportsCodexDetails == true
                        && (group.currencyCode == "USD" || group.currencyCode == self.detailCurrency),
                    onSelectDay: { self.controller.selectDay($0) },
                    onClearSelectedDay: {
                        self.controller.selectDay(nil)
                    })
            }
        }

        if self.settings.costUsageEnabled, !self.controller.model.tokenActivity.isEmpty {
            SpendDashboardPanel {
                SpendActivityHeatmapView(
                    points: self.controller.model.tokenActivity,
                    calendar: self.settings.costUsageBucketCalendar,
                    selectedDay: self.controller.selectedDay,
                    onSelectDay: { day in
                        self.controller.selectDay(day)
                    })
            }
        }
    }

    // MARK: - Model

    private var configuration: SpendDashboardConfiguration {
        SpendDashboardSource.configuration(settings: self.settings, store: self.store)
    }

    private var controller: SpendDashboardController {
        self.store.sharedSpendDashboardController()
    }

    private var detailCurrency: String {
        let preferred = self.controller.configuration?.preferredCurrencyCode ?? "auto"
        return preferred == "auto" ? "USD" : preferred
    }

    private func detailSelection(for currency: String) -> Binding<SpendDashboardDetailSection> {
        Binding(get: { self.detailSelections[currency] ?? .providers }, set: { self.detailSelections[currency] = $0 })
    }

    private var periodBinding: Binding<CostReportingPeriod> {
        Binding(
            get: { self.controller.selectedPeriod },
            set: { self.controller.selectPeriod($0) })
    }
}
