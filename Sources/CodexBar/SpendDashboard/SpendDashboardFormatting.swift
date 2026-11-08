import CodexBarCore
import Foundation

// Text and selection helpers shared by the Spend window, the Costs settings pane and the menu's spend card.

func spendDashboardLedgerDateText(_ day: Date, timeZone: TimeZone, accessibility: Bool = false) -> String {
    var format = accessibility
        ? Date.FormatStyle.dateTime.weekday(.wide).day().month(.wide).year()
        : Date.FormatStyle.dateTime.weekday(.abbreviated).day().month(.abbreviated)
    format.locale = codexBarLocalizedLocale()
    format.timeZone = timeZone
    return day.formatted(format)
}

func spendDashboardDayRangeText(_ days: Int) -> String {
    if days >= SpendDashboardSource.scanDays {
        return L("All")
    }
    guard let template = [7: L("7d"), 30: L("30d"), 90: L("90d")][days] else {
        return codexBarLocalizedInteger(days)
    }
    return template.replacingOccurrences(
        of: String(days),
        with: codexBarLocalizedInteger(days))
}

/// A reporting period as the Spend window's range control names it ("30d", "Month to date", "All").
func spendDashboardPeriodText(_ period: CostReportingPeriod) -> String {
    switch period {
    case let .rolling(days): spendDashboardDayRangeText(days)
    case .monthToDate: L("Month to date")
    case .allTime: L("All")
    }
}

func spendDashboardRankText(_ rank: Int) -> String {
    "#\(codexBarLocalizedInteger(rank))"
}

func spendDashboardRefreshFailureText(_ count: Int) -> String {
    "\(L("Refresh failures")): \(codexBarLocalizedInteger(count))"
}

func spendDashboardCoverageText(covered: Int, requested: Int) -> String {
    "\(L("Coverage")): \(codexBarLocalizedInteger(covered)) / \(codexBarLocalizedInteger(requested))"
}

func spendDashboardTokenMixValue(_ value: Int?) -> String {
    value.map(UsageFormatter.tokenCountString) ?? "—"
}

func spendDashboardMetricText(
    cost: Double?,
    tokens: Int?,
    currencyCode: String,
    incompleteRequestCount: Int = 0,
    costIsLowerBound: Bool = false,
    tokensAreLowerBound: Bool = false) -> String
{
    // A truncated scan or an unpriced request makes the subtotal a floor, not an exact value.
    // The row must say so with the same `≥` marker the header and menu card already use.
    let parts = [
        cost.map {
            spendDashboardLowerBoundText(
                UsageFormatter.currencyString($0, currencyCode: currencyCode), isLowerBound: costIsLowerBound)
        },
        tokens.map {
            spendDashboardLowerBoundText(
                L("%@ tokens", UsageFormatter.tokenCountString($0)), isLowerBound: tokensAreLowerBound)
        },
    ].compactMap(\.self)
    return (parts.isEmpty ? "—" : parts.joined(separator: " · "))
        + UsageFormatter.incompleteUsageSuffix(incompleteRequestCount)
}

func spendDashboardLowerBoundText(_ value: String, isLowerBound: Bool) -> String {
    isLowerBound ? "≥ \(value)" : value
}

func spendDashboardCoverageChipText(_ coverage: CostUsageCoverageCounts) -> String {
    "\(L("Priced")) \(codexBarLocalizedInteger(coverage.priced)) · "
        + "\(L("Unpriced")) \(codexBarLocalizedInteger(coverage.unpriced)) · "
        + "\(L("Unmetered")) \(codexBarLocalizedInteger(coverage.unmetered)) · "
        + "\(L("Estimated")) \(codexBarLocalizedInteger(coverage.estimated))"
}

func spendDashboardProvenanceText(_ provenance: CostProvenance) -> String {
    switch provenance {
    case .listPriceEstimate: L("List-price equivalent")
    case .vendorMetered: L("Plan metered")
    case .mixed: L("Metered and list-price")
    case .unknown: L("Spend unavailable")
    }
}

func spendDashboardHourlyChartAccessibilityValue(hourCount: Int, serviceCount: Int) -> String {
    switch (hourCount == 1, serviceCount == 1) {
    case (true, true):
        L("1 hour of usage data across 1 service")
    case (false, true):
        L("%d hours of usage data across 1 service", hourCount)
    case (true, false):
        L("1 hour of usage data across %d services", serviceCount)
    case (false, false):
        L("%d hours of usage data across %d services", hourCount, serviceCount)
    }
}

func codexCostCatchUpProgressText(_ activity: CodexCostCatchUpActivity) -> String {
    if activity.totalBytes > 0 {
        let processed = ByteCountFormatter.string(
            fromByteCount: activity.processedBytes,
            countStyle: .file)
        let total = ByteCountFormatter.string(
            fromByteCount: activity.totalBytes,
            countStyle: .file)
        return "\(processed) / \(total)"
    }
    if activity.totalFiles > 0 {
        return "\(codexBarLocalizedInteger(activity.completedFiles)) / "
            + codexBarLocalizedInteger(activity.totalFiles)
    }
    return L("Loading…")
}

struct SpendDashboardEmptyState: Equatable {
    let title: String
    let message: String

    static func make(isRefreshing: Bool) -> Self {
        if isRefreshing {
            return Self(
                title: L("Refreshing"),
                message: L("Local estimated cost history across supported providers."))
        }
        return Self(
            title: L("No local cost history yet"),
            message: L("Turn on cost tracking or refresh after using a supported provider."))
    }
}

enum SpendDashboardDetailSection: Hashable, Identifiable {
    case providers
    case projects
    case chats
    case sessions

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .providers: L("Providers")
        case .projects: L("Projects")
        case .chats: L("Independent chats")
        case .sessions: L("Sessions")
        }
    }
}

func spendDashboardCodexDetailPlaceholderCurrency(
    configuration: SpendDashboardConfiguration,
    currencyCodes: [String]) -> String?
{
    guard configuration.supportsCodexDetails else { return nil }
    let currency = configuration.preferredCurrencyCode == "auto" ? "USD" : configuration.preferredCurrencyCode
    return currencyCodes.contains("USD") || currencyCodes.contains(currency) ? nil : currency
}

func spendDashboardAvailableDetailSections(
    hasProjects: Bool,
    hasSessions: Bool,
    hasChats: Bool = false,
    supportsCodexDetails: Bool = false) -> [SpendDashboardDetailSection]
{
    var sections: [SpendDashboardDetailSection] = [.providers]
    if supportsCodexDetails || hasProjects {
        sections.append(.projects)
    }
    if supportsCodexDetails || hasChats {
        sections.append(.chats)
    }
    if supportsCodexDetails || hasSessions {
        sections.append(.sessions)
    }
    return sections
}

/// Filter for display without regrouping ledger paths or changing any amounts.
func spendDashboardProjectRows(
    _ rows: [SpendDashboardModel.ProjectRow],
    isProjectless: Bool) -> [SpendDashboardModel.ProjectRow]
{
    rows.filter { $0.isProjectless == isProjectless }.enumerated().map { index, row in
        var ranked = row
        ranked.rank = index + 1
        return ranked
    }
}

enum SpendDashboardTrendSection: Hashable, Identifiable {
    case daily
    case hourly

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .daily: L("Daily estimated spend")
        case .hourly: L("Hourly estimated spend")
        }
    }

    var pickerTitle: String {
        switch self {
        case .daily: L("Overview")
        case .hourly: L("Hour")
        }
    }
}

func spendDashboardHasTokenMix(_ group: SpendDashboardModel.CurrencyGroup) -> Bool {
    group.tokenMix.inputTokens != nil
        || group.tokenMix.outputTokens != nil
        || group.tokenMix.cacheReadTokens != nil
        || group.tokenMix.cacheCreationTokens != nil
        || group.tokenMix.reasoningTokens != nil
}

/// Bound initial ledger layout on long ranges; expansion still exposes the complete history.
func spendDailyLedgerVisibleSummaries(
    _ summaries: [SpendDashboardModel.DailySummary],
    showsAllRows: Bool,
    collapsedRowCount: Int) -> [SpendDashboardModel.DailySummary]
{
    Array(summaries.suffix(showsAllRows ? summaries.count : collapsedRowCount).reversed())
}

func spendDashboardGroupCostText(_ group: SpendDashboardModel.CurrencyGroup) -> String {
    guard let cost = group.totalCost else { return L("Spend unavailable") }
    let formatted = UsageFormatter.currencyString(cost, currencyCode: group.currencyCode)
    return group.hasPartialCost ? "~\(formatted)" : formatted
}

func spendDashboardLedgerCostText(_ summary: SpendDashboardModel.DailySummary, currencyCode: String) -> String {
    guard let cost = summary.totalCost else { return "—" }
    let formatted = UsageFormatter.currencyString(cost, currencyCode: currencyCode)
    return summary.hasPartialCost ? "~\(formatted)" : formatted
}

func spendDashboardLedgerTokenText(_ summary: SpendDashboardModel.DailySummary) -> String {
    spendDashboardLedgerCountText(
        summary.totalTokens,
        isLowerBound: summary.hasPartialCounts,
        format: UsageFormatter.tokenCountString)
}

func spendDashboardLedgerRequestText(_ summary: SpendDashboardModel.DailySummary) -> String {
    // A missing source count makes only the request total a floor. Token totals keep their own flag.
    spendDashboardLedgerCountText(
        summary.requestCount,
        isLowerBound: summary.hasPartialCounts || summary.requestsAreLowerBound,
        format: codexBarLocalizedInteger)
}

func spendDashboardLedgerCountText(
    _ count: Int?,
    isLowerBound: Bool,
    format: (Int) -> String) -> String
{
    guard let count else { return "—" }
    let text = format(count)
    return isLowerBound ? "≥\(text)" : text
}

func spendDashboardGroupTokenText(_ group: SpendDashboardModel.CurrencyGroup) -> String {
    guard let tokens = group.totalTokens else { return "—" }
    let formatted = UsageFormatter.tokenCountString(tokens)
    return group.hasPartialTokens ? "~\(formatted)" : formatted
}

private func spendDashboardIncludesLocalHistory(_ group: SpendDashboardModel.CurrencyGroup) -> Bool {
    group.providers.contains { $0.sourceKind == .localHistory }
}

func spendDashboardProviderCountTitle(_ group: SpendDashboardModel.CurrencyGroup) -> String {
    spendDashboardIncludesLocalHistory(group) ? L("Sources") : L("Subscriptions")
}

func spendDashboardPartialSourceCoverageText(_ group: SpendDashboardModel.CurrencyGroup) -> String {
    let template = spendDashboardIncludesLocalHistory(group)
        ? "%d of %d sources have spend" : "%d of %d subscriptions have spend"
    return L(template, group.pricedProviderCount, group.providers.count)
}

func spendDashboardHistoryCaption(
    _ group: SpendDashboardModel.CurrencyGroup,
    requestedDays: Int) -> String
{
    var parts: [String] = []
    if group.hasPartialCost || group.hasPartialTokens {
        parts.append(L("Partial estimate"))
        if group.hasUnpricedProviders {
            parts.append(spendDashboardPartialSourceCoverageText(group))
        }
    } else {
        parts.append(L("Local estimated history"))
    }
    parts.append(spendDashboardCoverageText(covered: group.coveredDayCount, requested: requestedDays))
    return parts.joined(separator: " · ")
}
