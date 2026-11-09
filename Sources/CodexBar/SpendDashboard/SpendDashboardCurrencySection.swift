import CodexBarCore
import InternalUI
import SwiftUI

struct SpendDashboardCurrencySection: View {
    let group: SpendDashboardModel.CurrencyGroup
    let requestedDays: Int
    let hidePersonalInfo: Bool
    let onClearSelectedDay: (() -> Void)?
    let onSelectDay: ((Date) -> Void)?
    let detailSelection: Binding<SpendDashboardDetailSection>?
    let supportsCodexDetails: Bool
    @State private var selectedDetailSection: SpendDashboardDetailSection
    @State private var selectedTrendSection: SpendDashboardTrendSection

    init(
        group: SpendDashboardModel.CurrencyGroup,
        requestedDays: Int,
        hidePersonalInfo: Bool = false,
        initialDetailSection: SpendDashboardDetailSection = .providers,
        initialTrendSection: SpendDashboardTrendSection? = nil,
        detailSelection: Binding<SpendDashboardDetailSection>? = nil,
        supportsCodexDetails: Bool = false,
        onSelectDay: ((Date) -> Void)? = nil,
        onClearSelectedDay: (() -> Void)? = nil)
    {
        self.group = group
        self.detailSelection = detailSelection
        self.supportsCodexDetails = supportsCodexDetails
        self.requestedDays = requestedDays
        self.hidePersonalInfo = hidePersonalInfo
        self.onClearSelectedDay = onClearSelectedDay
        self.onSelectDay = onSelectDay
        self._selectedDetailSection = State(initialValue: initialDetailSection)
        self._selectedTrendSection = State(
            initialValue: initialTrendSection
                ?? (group.selectedDay != nil && !group.hourlyPoints.isEmpty ? .hourly : .daily))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: IUSpace.chromeGap) {
            VStack(alignment: .leading, spacing: IUSpace.unit / 2) {
                IUText(self.group.currencyCode, role: .subtitle)
                IUText(
                    spendDashboardHistoryCaption(self.group, requestedDays: self.requestedDays),
                    role: .caption,
                    muted: true)
            }
            .padding(.horizontal, IUSpace.rowPaddingX)
            .padding(.top, IUSpace.chromeGap)

            SpendDashboardSummary(
                group: self.group,
                onClearSelectedDay: self.onClearSelectedDay)
            SpendDashboardDetailPanel(
                group: self.group,
                hidePersonalInfo: self.hidePersonalInfo,
                supportsCodexDetails: self.supportsCodexDetails,
                selection: self.detailSelection ?? self.$selectedDetailSection)
            SpendDashboardTrendPanel(
                group: self.group,
                selection: self.$selectedTrendSection,
                onSelectDay: self.onSelectDay,
                onClearSelectedDay: self.onClearSelectedDay)
            SpendDailyLedger(group: self.group)
        }
        .environment(\.timeZone, self.group.timeZone)
        .environment(\.calendar, self.group.calendar)
    }
}

extension SpendDashboardCurrencySection {
    /// The detail tabs alone, for local Codex details in a currency that has no spend group yet.
    static func placeholderDetailPanel(
        currencyCode: String,
        timeZone: TimeZone,
        hidePersonalInfo: Bool,
        selection: Binding<SpendDashboardDetailSection>) -> some View
    {
        SpendDashboardDetailPanel(
            group: .init(
                currencyCode: currencyCode,
                providers: [],
                models: [],
                dailyPoints: [],
                totalTokens: nil,
                totalCost: nil,
                coveredDayCount: 0,
                chartDomain: Date.distantPast...Date.distantPast,
                modelHistoryCompleteness: .incomplete,
                timeZone: timeZone),
            hidePersonalInfo: hidePersonalInfo,
            supportsCodexDetails: true,
            selection: selection)
    }
}

private struct SpendDashboardDetailPanel: View {
    let group: SpendDashboardModel.CurrencyGroup
    let hidePersonalInfo: Bool
    var supportsCodexDetails = false
    @Binding var selection: SpendDashboardDetailSection

    var body: some View {
        SpendDashboardPanel {
            VStack(alignment: .leading, spacing: IUSpace.panelPadding) {
                if self.availableSections.count > 1 {
                    Picker(L("Usage & Spend"), selection: self.normalizedSelection) {
                        ForEach(self.availableSections) { section in
                            Text(section.title).tag(section)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                    .frame(maxWidth: IUSize.settingsWidth, alignment: .leading)
                    .accessibilityIdentifier("spend-dashboard-detail-picker")
                }

                self.detailContent
                if self.activeSection != .providers {
                    if self.group.projects.isEmpty, self.group.sessions.isEmpty {
                        Text(L("No usage breakdown data available."))
                            .font(IUTextRole.caption.font).foregroundStyle(IUColor.muted)
                    }
                    if self.group.detailsExcludedFromTotals {
                        Text(L("Local Codex details; excluded from combined totals."))
                            .font(IUTextRole.caption.font).foregroundStyle(IUColor.muted)
                    }
                    if let updatedAt = self.group.retainedDetailUpdatedAt {
                        Text(L("Incomplete") + " · " + L(
                            "Updated %@",
                            spendDashboardLedgerDateText(updatedAt, timeZone: self.group.timeZone)))
                            .font(IUTextRole.caption.font).foregroundStyle(IUColor.muted)
                    }
                }
            }
        }
    }

    private var availableSections: [SpendDashboardDetailSection] {
        spendDashboardAvailableDetailSections(
            hasProjects: self.group.projects.contains { !$0.isProjectless },
            hasSessions: !self.group.sessions.isEmpty,
            hasChats: self.group.projects.contains(where: \.isProjectless),
            supportsCodexDetails: self.supportsCodexDetails)
    }

    private var activeSection: SpendDashboardDetailSection {
        self.availableSections.contains(self.selection) ? self.selection : self.availableSections[0]
    }

    private var normalizedSelection: Binding<SpendDashboardDetailSection> {
        Binding(
            get: { self.activeSection },
            set: { self.selection = $0 })
    }

    @ViewBuilder
    private var detailContent: some View {
        switch self.activeSection {
        case .providers:
            SpendProviderBreakdownRows(group: self.group)
        case .projects:
            SpendProjectRows(group: self.group, hidePersonalInfo: self.hidePersonalInfo, isProjectless: false)
        case .chats:
            SpendProjectRows(group: self.group, hidePersonalInfo: self.hidePersonalInfo, isProjectless: true)
        case .sessions:
            SpendSessionRows(group: self.group, hidePersonalInfo: self.hidePersonalInfo)
        }
    }
}

private struct SpendProjectRows: View {
    let group: SpendDashboardModel.CurrencyGroup
    let hidePersonalInfo: Bool
    let isProjectless: Bool
    @State private var showsAllRows = false

    private static let collapsedRowCount = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(self.visibleRows) { row in
                let identity = row.displayIdentity(hidePersonalInfo: self.hidePersonalInfo)
                if row.rank > 1 {
                    IUDivider()
                }
                HStack(spacing: IUSpace.panelPadding) {
                    Text(spendDashboardRankText(row.rank))
                        .font(IUTextRole.caption.font.monospacedDigit())
                        .foregroundStyle(IUColor.muted)
                        .frame(width: SpendDashboardRowLayout.rankWidth, alignment: .leading)
                    Image(systemName: row.isProjectless ? "bubble.left.and.bubble.right" : "folder")
                        .font(IUTextRole.caption.font)
                        .foregroundStyle(IUColor.muted)
                    VStack(alignment: .leading, spacing: IUSpace.keyCapGap) {
                        Text(identity.name)
                            .lineLimit(1)
                            .help(identity.path ?? identity.name)
                        Text(row.providerName)
                            .font(IUTextRole.caption.font)
                            .foregroundStyle(IUColor.muted)
                        if let path = identity.path,
                           row.needsPathDisambiguation(in: self.rows)
                        {
                            Text(path)
                                .font(IUTextRole.caption.font)
                                .foregroundStyle(IUColor.muted)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .help(path)
                        }
                    }
                    Spacer()
                    Text(spendDashboardMetricText(
                        cost: row.totalCost,
                        tokens: row.totalTokens,
                        currencyCode: self.group.currencyCode))
                        .monospacedDigit()
                }
                .padding(.vertical, SpendDashboardRowLayout.rowPaddingY)
            }
            SpendPanelExpandButton(
                rowCount: self.rows.count,
                collapsedRowCount: Self.collapsedRowCount,
                showsAllRows: self.$showsAllRows)
        }
    }

    private var visibleRows: ArraySlice<SpendDashboardModel.ProjectRow> {
        self.rows.prefix(self.showsAllRows ? self.rows.count : Self.collapsedRowCount)
    }

    private var rows: [SpendDashboardModel.ProjectRow] {
        spendDashboardProjectRows(self.group.projects, isProjectless: self.isProjectless)
    }
}

private struct SpendPanelExpandButton: View {
    let rowCount: Int
    let collapsedRowCount: Int
    @Binding var showsAllRows: Bool

    var body: some View {
        if self.rowCount > self.collapsedRowCount {
            Button {
                self.showsAllRows.toggle()
            } label: {
                Text(
                    self.showsAllRows
                        ? L("Show less")
                        : L("Show all (%d)", self.rowCount))
                    .font(IUTextRole.caption.font)
            }
            .buttonStyle(.borderless)
            .padding(.top, IUSpace.dividerInset)
        }
    }
}

/// Ranked project and chat rows: the rank column and the row's vertical padding, on the 4 pt grid.
private enum SpendDashboardRowLayout {
    static let rankWidth = IUSpace.unit * 7
    static let rowPaddingY = IUSpace.unit * 2
}

/// The ledger's columns, on the 4 pt grid. The table scrolls sideways below `minimumTableWidth`.
private enum SpendDailyLedgerLayout {
    static let dayWidth = IUSpace.unit * 28
    static let providerMinimumWidth = IUSpace.unit * 24
    static let trackedTokensWidth = IUSpace.unit * 23
    static let requestsWidth = IUSpace.unit * 18
    static let estimatedSpendWidth = IUSpace.unit * 29
    static let columnSpacing = IUSpace.tabContentGap
    static let horizontalPadding = IUSpace.rowPaddingX
    static let headerPaddingY = IUSpace.dividerInset
    static let rowPaddingY = IUSpace.panelPadding
    static let providerIconGap = IUSpace.unit
    static let minimumTableWidth: CGFloat =
        dayWidth
            + providerMinimumWidth
            + trackedTokensWidth
            + requestsWidth
            + estimatedSpendWidth
            + (columnSpacing * 4)
            + (horizontalPadding * 2)
}

private struct SpendDailyLedger: View {
    let group: SpendDashboardModel.CurrencyGroup
    @State private var showsAllRows = false

    static let collapsedRowCount = 30

    private var visibleSummaries: [SpendDashboardModel.DailySummary] {
        spendDailyLedgerVisibleSummaries(
            self.group.dailySummaries,
            showsAllRows: self.showsAllRows,
            collapsedRowCount: Self.collapsedRowCount)
    }

    var body: some View {
        SpendDashboardPanel {
            VStack(alignment: .leading, spacing: 0) {
                IUText(L("Daily estimated spend"), role: .subtitle)
                    .padding(.bottom, IUSpace.panelPadding)

                if self.group.dailySummaries.isEmpty {
                    IUEmptyState(L("Spend unavailable"), systemImage: "calendar.badge.exclamationmark", size: .compact)
                } else {
                    ScrollView(.horizontal, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: 0) {
                            self.header
                            IUDivider()
                            VStack(spacing: 0) {
                                ForEach(Array(self.visibleSummaries.enumerated()), id: \.element.id) { index, summary in
                                    if index > 0 {
                                        IUDivider()
                                    }
                                    SpendDailyLedgerRow(
                                        summary: summary,
                                        currencyCode: self.group.currencyCode,
                                        timeZone: self.group.timeZone)
                                }
                            }
                        }
                        .frame(minWidth: SpendDailyLedgerLayout.minimumTableWidth, alignment: .leading)
                    }
                    SpendPanelExpandButton(
                        rowCount: self.group.dailySummaries.count,
                        collapsedRowCount: Self.collapsedRowCount,
                        showsAllRows: self.$showsAllRows)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: SpendDailyLedgerLayout.columnSpacing) {
            Text(L("Day")).frame(width: SpendDailyLedgerLayout.dayWidth, alignment: .leading)
            Text(L("Providers")).frame(
                minWidth: SpendDailyLedgerLayout.providerMinimumWidth,
                maxWidth: .infinity,
                alignment: .leading)
            Text(L("Tracked tokens")).frame(
                width: SpendDailyLedgerLayout.trackedTokensWidth,
                alignment: .trailing)
            Text(L("Requests")).frame(
                width: SpendDailyLedgerLayout.requestsWidth,
                alignment: .trailing)
            Text(L("Estimated spend")).frame(
                width: SpendDailyLedgerLayout.estimatedSpendWidth,
                alignment: .trailing)
        }
        .font(IUTextRole.caption.font)
        .foregroundStyle(IUColor.muted)
        .padding(.horizontal, SpendDailyLedgerLayout.horizontalPadding)
        .padding(.vertical, SpendDailyLedgerLayout.headerPaddingY)
    }
}

private struct SpendDailyLedgerRow: View {
    let summary: SpendDashboardModel.DailySummary
    let currencyCode: String
    let timeZone: TimeZone

    var body: some View {
        HStack(spacing: SpendDailyLedgerLayout.columnSpacing) {
            Text(spendDashboardLedgerDateText(self.summary.day, timeZone: self.timeZone))
                .frame(width: SpendDailyLedgerLayout.dayWidth, alignment: .leading)
            self.providerMix
                .frame(
                    minWidth: SpendDailyLedgerLayout.providerMinimumWidth,
                    maxWidth: .infinity,
                    alignment: .leading)
            Text(self.tokensText)
                .frame(width: SpendDailyLedgerLayout.trackedTokensWidth, alignment: .trailing)
            Text(self.requestsText)
                .frame(width: SpendDailyLedgerLayout.requestsWidth, alignment: .trailing)
            Text(spendDashboardLedgerCostText(self.summary, currencyCode: self.currencyCode))
                .fontWeight(.medium)
                .frame(width: SpendDailyLedgerLayout.estimatedSpendWidth, alignment: .trailing)
        }
        .monospacedDigit()
        .padding(.horizontal, SpendDailyLedgerLayout.horizontalPadding)
        .padding(.vertical, SpendDailyLedgerLayout.rowPaddingY)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(self.accessibilityLabel)
    }

    @ViewBuilder
    private var providerMix: some View {
        if self.activeProviders.isEmpty {
            Text(L("No usage yet"))
                .font(IUTextRole.caption.font)
                .foregroundStyle(IUColor.muted)
        } else {
            HStack(spacing: SpendDailyLedgerLayout.providerIconGap) {
                ForEach(self.activeProviders.prefix(4)) { row in
                    SpendProviderIcon(provider: row.provider)
                }
                if self.activeProviders.count > 4 {
                    Text("+\(codexBarLocalizedInteger(self.activeProviders.count - 4))")
                        .font(IUTextRole.caption.font)
                        .foregroundStyle(IUColor.muted)
                }
            }
            .help(self.activeProviders.map(\.displayName).joined(separator: ", "))
        }
    }

    private var activeProviders: [SpendDashboardModel.DailyProviderRow] {
        self.summary.providers.filter { !$0.isKnownIdle }
    }

    private var tokensText: String {
        spendDashboardLedgerTokenText(self.summary)
    }

    private var requestsText: String {
        spendDashboardLedgerRequestText(self.summary)
    }

    private var accessibilityLabel: String {
        let day = spendDashboardLedgerDateText(self.summary.day, timeZone: self.timeZone, accessibility: true)
        let providers = self.activeProviders.isEmpty
            ? L("No usage yet")
            : self.activeProviders.map(\.displayName).joined(separator: ", ")
        let spend = spendDashboardLedgerCostText(self.summary, currencyCode: self.currencyCode)
        return "\(day), \(L("Providers")): \(providers), \(L("Tracked tokens")): \(self.tokensText), "
            + "\(L("Requests")): \(self.requestsText), \(L("Estimated spend")): \(spend)"
    }
}

struct SpendSessionRows: View {
    let group: SpendDashboardModel.CurrencyGroup
    let hidePersonalInfo: Bool
    @State private var selectedSourceID: String?

    private var sourceIDs: [String] {
        Array(Set(self.group.sessions.map(\.sourceID))).sorted()
    }

    private var sourceID: String? {
        self.selectedSourceID.flatMap { self.sourceIDs.contains($0) ? $0 : nil } ?? self.sourceIDs.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: IUSpace.tabContentGap) {
            if self.sourceIDs.count > 1 {
                Picker(L("Sources"), selection: Binding(
                    get: { self.sourceID ?? "" }, set: { self.selectedSourceID = $0 }))
                {
                    ForEach(self.sourceIDs, id: \.self) { id in
                        Text(self.sourceName(id)).tag(id)
                    }
                }
            }
            if let id = self.sourceID, let context = self.context(for: id) {
                SessionUsageBrowser(context: context, hidePersonalInfo: self.hidePersonalInfo)
                    .id(id)
                    .frame(height: SpendDashboardPanelLayout.sessionBrowserHeight)
            } else {
                IUText(L("No data available"), role: .body, muted: true)
            }
        }
    }

    private func sourceName(_ id: String) -> String {
        guard let row = self.group.sessions.first(where: { $0.sourceID == id }) else { return "" }
        let provider = ProviderDescriptorRegistry.descriptor(for: row.provider).metadata.displayName
        if self.hidePersonalInfo {
            let index = (self.sourceIDs.firstIndex(of: id) ?? 0) + 1
            return self.sourceIDs.count > 1 ? "\(provider) · \(codexBarLocalizedInteger(index))" : provider
        }
        return row.sourceName ?? provider
    }

    func context(for id: String) -> SessionUsageBrowserContext? {
        let rows = self.group.sessions.filter { $0.sourceID == id }
        guard let first = rows.first else { return nil }
        // Session totals belong to the source snapshot's reporting period, independent of chart day selection.
        let range = first.reportingRange ?? self.group.chartDomain.lowerBound..<self.group.chartDomain.upperBound
        let format = Date.FormatStyle(
            date: .abbreviated,
            time: .omitted,
            locale: codexBarLocalizedLocale(),
            calendar: self.group.calendar,
            timeZone: self.group.timeZone)
        let label = first.reportingPeriod == .allTime ? L("All")
            : range.lowerBound.formatted(format) + " – "
            + range.upperBound.addingTimeInterval(-0.001).formatted(format)
        return SessionUsageBrowserContext(
            providerName: self.sourceName(id),
            windowLabel: label,
            sessions: rows.map { row in
                row.usage ?? CostUsageSessionBreakdown(
                    sessionID: row.sessionID,
                    lastActivity: row.lastActivity,
                    inputTokens: nil,
                    cachedInputTokens: nil,
                    outputTokens: nil,
                    totalTokens: row.totalTokens,
                    requestCount: nil,
                    costUSD: row.totalCost.flatMap { cost in
                        row.costMultiplier > 0 ? cost / row.costMultiplier : nil
                    },
                    modelBreakdowns: [],
                    title: row.title)
            },
            currencyCode: self.group.currencyCode,
            costMultiplier: first.costMultiplier,
            timeZone: self.group.timeZone,
            activityRange: range)
    }
}

/// Shared sizes for the Spend window's cards.
enum SpendDashboardPanelLayout {
    /// The session browser's fixed height inside a card or the Spend window.
    static let sessionBrowserHeight = IUSize.chart * 3
}

/// One card of the Spend window: an Internal UI content card across the column's full width.
struct SpendDashboardPanel<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        self.content
            .frame(maxWidth: .infinity, alignment: .leading)
            .iuCard()
    }
}
