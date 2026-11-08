import CodexBarCore
import InternalUI
import SwiftUI

/// The Menu pane's cost summary section. While the summary is on, the footer lists each cost provider's fetch
/// status between the refresh note and the explanation of where the numbers come from.
@MainActor
struct CostSummarySettingsSection: View {
    @Bindable var settings: SettingsStore
    @Bindable var store: UsageStore

    var body: some View {
        MacSettingsSection(
            L("section_cost_summary"),
            footer: self.settings.costUsageEnabled ? self.footer(now: Date()) : nil)
        {
            MacSettingsRow(L("cost_summary_title"), subtitle: L("show_cost_summary_subtitle")) {
                MacPopUpButton(
                    MenuSettingsMenuOptions.costSummaries.map { ($0, $0.label) },
                    selection: self.$settings.costSummaryOption)
                    .accessibilityLabel(L("cost_summary_title"))
            }
            .settingsAnchor(MenuSettingsPane.SearchID.costSummary)

            if self.settings.costUsageEnabled {
                CostHistoryDaysEditor(settings: self.settings)

                MacSettingsToggleRow(
                    L("cost_comparison_periods_title"),
                    subtitle: L("cost_comparison_periods_subtitle"),
                    isOn: self.$settings.costComparisonPeriodsEnabled)
                    .settingsAnchor(MenuSettingsPane.SearchID.costComparison)
            }
        }
    }

    static func costDataExplanation() -> String {
        L("cost_data_explanation")
    }

    static var costStatusProviders: [UsageProvider] {
        ProviderDescriptorRegistry.all.compactMap { descriptor -> (UsageProvider, Int)? in
            guard let order = descriptor.tokenCost.settingsStatusOrder else { return nil }
            return (descriptor.id, order)
        }
        .sorted { $0.1 < $1.1 }
        .map(\.0)
    }

    /// The footer: the refresh note, one status line per cost provider, then where the numbers come from.
    func footer(now: Date) -> String {
        Self.footer(statusLines: Self.costStatusProviders.map { Self.statusLine(
            provider: $0,
            store: self.store,
            now: now) })
    }

    static func footer(statusLines: [String]) -> String {
        ([L("cost_auto_refresh_info")] + statusLines + [self.costDataExplanation()]).joined(separator: "\n")
    }

    /// One provider's cost fetch status: unsupported, fetching (with the time so far), its latest snapshot, its
    /// last error, when it was last tried, or no data yet.
    static func statusLine(provider: UsageProvider, store: UsageStore, now: Date) -> String {
        let descriptor = ProviderDescriptorRegistry.descriptor(for: provider)
        let name = descriptor.metadata.displayName

        guard descriptor.tokenCost.supportsTokenCost else {
            return String(format: L("cost_status_unsupported"), name)
        }

        if store.isTokenRefreshInFlight(for: provider) {
            let elapsed: String = {
                guard let startedAt = store.tokenLastAttemptAt(for: provider) else { return "" }
                let seconds = max(0, now.timeIntervalSince(startedAt))
                let formatter = DateComponentsFormatter()
                formatter.allowedUnits = seconds < 60 ? [.second] : [.minute, .second]
                formatter.unitsStyle = .abbreviated
                return formatter.string(from: seconds).map { " (\($0))" } ?? ""
            }()
            return String(format: L("cost_status_fetching"), name, elapsed)
        }
        if let snapshot = store.tokenSnapshot(for: provider) {
            let updated = UsageFormatter.updatedString(from: snapshot.updatedAt)
            let cost = snapshot.last30DaysCostUSD
                .map { UsageFormatter.currencyString($0, currencyCode: snapshot.currencyCode) } ?? "—"
            let window = snapshot.historyLabel ?? (snapshot.historyDays == 1 ? "today" : "\(snapshot.historyDays)d")
            return String(format: L("cost_status_snapshot"), name, updated, window, cost)
        }
        if let error = store.tokenError(for: provider), !error.isEmpty {
            let truncated = UsageFormatter.truncatedSingleLine(error, max: 120)
            return String(format: L("cost_status_error"), name, truncated)
        }
        if let lastAttempt = store.tokenLastAttemptAt(for: provider) {
            let rel = RelativeDateTimeFormatter()
            rel.locale = Locale(identifier: "en_US")
            rel.unitsStyle = .abbreviated
            let when = rel.localizedString(for: lastAttempt, relativeTo: now)
            return String(format: L("cost_status_last_attempt"), name, when)
        }
        return String(format: L("cost_status_no_data"), name)
    }
}

/// The cost history window and, for a rolling window, its number of days. The days are typed or stepped.
@MainActor
struct CostHistoryDaysEditor: View {
    @Bindable var settings: SettingsStore

    static let presetDays = [1, 7, 30, 90, 365]
    static let dayRange = 1...365

    static func title(days: Int) -> String {
        String(format: L("cost_history_days_title"), days)
    }

    /// Month to date, all time and the preset rolling windows, plus the current rolling window when it is not one
    /// of the presets.
    static func periodOptions(selection: CostReportingPeriod) -> [(CostReportingPeriod, String)] {
        let periods = [CostReportingPeriod.monthToDate, .allTime] + self.presetDays.map { .rolling(days: $0) }
        return MenuSettingsPopUpOptions.options(periods, selection: selection) { period in
            switch period {
            case .monthToDate: L("Month to date")
            case .allTime: L("All")
            case let .rolling(days): Self.title(days: days)
            }
        }
    }

    var body: some View {
        MacSettingsRow(L("cost_history_window_title"), subtitle: L("cost_history_window_help")) {
            MacPopUpButton(
                Self.periodOptions(selection: self.settings.costReportingPeriod),
                selection: self.$settings.costReportingPeriod)
                .accessibilityLabel(L("cost_history_window_title"))
        }
        .settingsAnchor(MenuSettingsPane.SearchID.costHistoryWindow)

        if case .rolling = self.settings.costReportingPeriod {
            MacSettingsRow(L("cost_history_rolling_days_title")) {
                HStack(spacing: MacSpace.unit * 2) {
                    MenuSettingsNumberField(
                        title: L("Time range"),
                        value: self.$settings.costUsageHistoryDays,
                        format: .number)
                    MacStepper(value: self.$settings.costUsageHistoryDays, in: Self.dayRange)
                        .accessibilityLabel(Self.title(days: self.settings.costUsageHistoryDays))
                }
            }
            .settingsAnchor(MenuSettingsPane.SearchID.costRollingDays)
        }
    }
}
