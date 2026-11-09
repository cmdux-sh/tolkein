import CodexBarCore
import InternalUI
import SwiftUI

/// Costs: whether Tolkein tracks local estimated spend, which sources count, the statistics time zone, the JSON
/// and share exports, and the way into the Spend window, which holds the dashboard itself.
@MainActor
struct CostsSettingsPane: View {
    /// The pane's sections, top to bottom. With cost tracking off the pane shows only `.off`, an empty state
    /// that turns it on.
    enum Section: String, CaseIterable, Identifiable {
        case off
        case tracking
        case spend
        case sources
        case timeZone
        case export

        var id: Self {
            self
        }
    }

    /// The search entry ids that rows anchor to (see `searchEntries`).
    enum Anchor {
        static let trackCosts = "costs/trackCosts"
        static let openCodexLogs = "costs/openCodexLogs"
        static let hideNativeCodex = "costs/hideNativeCodex"
        static let spendWindow = "costs/spendWindow"
        static let sources = "costs/sources"
        static let timeZone = "costs/timeZone"
        static let useCurrentTimeZone = "costs/useCurrentTimeZone"
        static let copyJSON = "costs/copyJSON"
        static let exportJSON = "costs/exportJSON"
        static let shareStats = "costs/shareStats"
    }

    let context: SettingsPaneContext
    @Bindable private var settings: SettingsStore
    private let store: UsageStore
    private let openSpendWindow: SpendWindowOpening

    /// - Parameter openSpendWindow: opens the Spend window; defaults to the app's shared window.
    init(context: SettingsPaneContext, openSpendWindow: SpendWindowOpening? = nil) {
        self.context = context
        self.settings = context.settings
        self.store = context.store
        self.openSpendWindow = openSpendWindow
            ?? SpendWindowController.opener(settings: context.settings, store: context.store)
    }

    static func sections(costUsageEnabled: Bool) -> [Section] {
        costUsageEnabled ? [.tracking, .spend, .sources, .timeZone, .export] : [.off, .timeZone]
    }

    var sections: [Section] {
        Self.sections(costUsageEnabled: self.settings.costUsageEnabled)
    }

    var body: some View {
        IUSettingsPage(
            SettingsPane.costs.title,
            subtitle: L("Local estimated cost history across supported providers."))
        {
            ForEach(self.sections) { section in
                self.section(section)
            }
        }
    }

    @ViewBuilder
    private func section(_ section: Section) -> some View {
        switch section {
        case .off: self.offSection
        case .tracking: self.trackingSection
        case .spend: self.spendSection
        case .sources: self.sourcesSection
        case .timeZone: self.timeZoneSection
        case .export: self.exportSection
        }
    }

    // MARK: - Sections

    private var offSection: some View {
        IUSettingsSection {
            IUEmptyState.firstUse(
                L("Cost tracking is off"),
                systemImage: "chart.bar.xaxis",
                message: L("Turn on Track costs to build local estimates."),
                primary: IUEmptyStateAction(L("Turn On")) {
                    self.settings.costUsageEnabled = true
                })
        }
        .settingsAnchor(Anchor.trackCosts)
    }

    private var trackingSection: some View {
        IUSettingsSection(L("Tracking")) {
            IUSettingsToggleRow(L("Track costs"), isOn: self.$settings.costUsageEnabled)
                .settingsAnchor(Anchor.trackCosts)
            IUSettingsToggleRow(
                L("Include OpenCodex usage logs"),
                isOn: self.$settings.openCodexUsageLogsEnabled)
                .settingsAnchor(Anchor.openCodexLogs)
            IUSettingsToggleRow(
                L("Hide native Codex when OpenCodex is present"),
                disabledReason: self.hideNativeCodexDisabledReason,
                isOn: self.$settings.hideNativeCodexCostWhenOpenCodexPresent)
                .disabled(self.hideNativeCodexDisabledReason != nil)
                .settingsAnchor(Anchor.hideNativeCodex)
        }
    }

    /// Hiding native Codex only means something while OpenCodex logs are included.
    var hideNativeCodexDisabledReason: String? {
        self.settings.openCodexUsageLogsEnabled ? nil : L("Requires OpenCodex usage logs.")
    }

    private var spendSection: some View {
        IUSettingsSection(L("Spend")) {
            IUSettingsLinkRow(
                L("Open Spend window"),
                subtitle: L("Local estimated cost history"),
                systemImage: "chart.bar.xaxis")
            {
                self.openSpendWindowFromLink()
            }
            .settingsAnchor(Anchor.spendWindow)
            IUKeyValueList(Self.summaryRows(
                model: self.controller.model,
                period: self.controller.selectedPeriod,
                isRefreshing: self.controller.isRefreshing))
                .padding(.horizontal, IUSpace.settingsRowPaddingX)
                .padding(.vertical, IUSpace.settingsRowPaddingY)
        }
    }

    /// The link row's action: the Spend window on its dashboard.
    func openSpendWindowFromLink() {
        self.openSpendWindow(.dashboard)
    }

    private var sourcesSection: some View {
        let sources = self.controller.model.availableSources
        return IUSettingsSection(L("Sources")) {
            if sources.isEmpty {
                let emptyState = SpendDashboardEmptyState.make(isRefreshing: self.controller.isRefreshing)
                IUSettingsRow(emptyState.title, subtitle: emptyState.message) {
                    EmptyView()
                }
            } else {
                ForEach(sources) { source in
                    IUSettingsRow(source.displayName) {
                        Toggle(source.displayName, isOn: self.sourceVisibility(source.id))
                            .toggleStyle(.checkbox)
                            .labelsHidden()
                            .accessibilityLabel(source.displayName)
                    }
                }
            }
        }
        .settingsAnchor(Anchor.sources)
    }

    private var timeZoneSection: some View {
        IUSettingsSection(L("Time zone")) {
            SpendTimeZoneControls(settings: self.settings)
        }
    }

    private var exportSection: some View {
        IUSettingsSection(L("Export"), footer: L("List-price equivalent — not a billing receipt.")) {
            IUSettingsRow(
                L("Estimated spend"),
                subtitle: spendDashboardPeriodText(self.controller.selectedPeriod))
            {
                HStack(spacing: IUSpace.chromeGap) {
                    Button {
                        self.copyJSON()
                    } label: {
                        Label(L("Copy JSON"), systemImage: "doc.on.doc")
                    }
                    .disabled(self.controller.model.groups.isEmpty)
                    .settingsAnchor(Anchor.copyJSON)
                    Button {
                        self.exportJSON()
                    } label: {
                        Label(L("Export JSON"), systemImage: "square.and.arrow.down")
                    }
                    .disabled(self.controller.model.groups.isEmpty)
                    .settingsAnchor(Anchor.exportJSON)
                    Button {
                        guard let payload = self.sharePayload else { return }
                        ShareStatsPresenter.shared.present(payload: payload)
                    } label: {
                        Label(L("Share Stats…"), systemImage: "square.and.arrow.up")
                    }
                    .disabled(self.sharePayload == nil)
                    .settingsAnchor(Anchor.shareStats)
                }
                .buttonStyle(.iu())
            }
        }
    }

    // MARK: - Data

    private var controller: SpendDashboardController {
        self.store.sharedSpendDashboardController()
    }

    /// The compact summary under the link row: the dashboard's selected range and its totals, per currency.
    static func summaryRows(
        model: SpendDashboardModel,
        period: CostReportingPeriod,
        isRefreshing: Bool) -> [IUKeyValueList.Row]
    {
        var rows = [IUKeyValueList.Row(L("Time range"), spendDashboardPeriodText(period))]
        guard !model.groups.isEmpty else {
            let emptyState = SpendDashboardEmptyState.make(isRefreshing: isRefreshing)
            rows.append(.init(L("Estimated spend"), emptyState.title))
            return rows
        }
        rows.append(.init(L("Estimated spend"), model.groups.map(spendDashboardGroupCostText).joined(separator: " · ")))
        rows.append(.init(L("Tracked tokens"), model.groups.map(spendDashboardGroupTokenText).joined(separator: " · ")))
        let coveredDays = model.groups.map(\.coveredDayCount).min() ?? 0
        rows.append(.init(
            L("Coverage"),
            "\(codexBarLocalizedInteger(coveredDays)) / \(codexBarLocalizedInteger(model.requestedDays))"))
        return rows
    }

    private func sourceVisibility(_ sourceID: String) -> Binding<Bool> {
        Binding(
            get: { !self.settings.spendDashboardHiddenSourceIDs.contains(sourceID) },
            set: { isVisible in
                var hidden = Set(self.settings.spendDashboardHiddenSourceIDs)
                if isVisible {
                    hidden.remove(sourceID)
                } else {
                    hidden.insert(sourceID)
                }
                self.settings.spendDashboardHiddenSourceIDs = Array(hidden)
            })
    }

    private func copyJSON() {
        _ = SpendDashboardJSONExporter.copyToPasteboard(
            model: self.controller.model,
            hiddenSourceIDs: self.settings.spendDashboardHiddenSourceIDs)
    }

    private func exportJSON() {
        _ = SpendDashboardJSONExporter.save(
            model: self.controller.model,
            hiddenSourceIDs: self.settings.spendDashboardHiddenSourceIDs)
    }

    private var sharePayload: ShareStatsPayload? {
        ShareStatsPayloadFactory.make(model: self.controller.model, store: self.store)
    }
}

extension CostsSettingsPane {
    static var searchEntries: [SettingsSearchEntry] {
        let pane = SettingsPane.costs
        let usageAndSpend = L("tab_usage_spend")
        let tracking = L("Tracking")
        let export = L("Export")
        let timeZone = L("Time zone")
        return [
            .paneTitle(pane, keywords: usageAndSpend),
            pane.searchEntry("trackCosts", L("Track costs"), keywords: tracking, L("Cost tracking is off")),
            pane.searchEntry("openCodexLogs", L("Include OpenCodex usage logs"), keywords: tracking),
            pane.searchEntry("hideNativeCodex", L("Hide native Codex when OpenCodex is present"), keywords: tracking),
            pane.searchEntry(
                "spendWindow",
                L("Open Spend window"),
                keywords: L("Spend"),
                usageAndSpend,
                L("Daily estimated spend"),
                L("Sessions"),
                L("Local estimated cost history")),
            pane.searchEntry("sources", L("Sources"), keywords: L("Spend")),
            pane.searchEntry(
                "timeZone",
                L("Statistics time zone"),
                keywords: timeZone,
                L("Daily usage uses a fixed time zone. Changing it may move usage to a different day.")),
            pane.searchEntry("useCurrentTimeZone", L("Use Mac's current time zone"), keywords: timeZone),
            pane.searchEntry("copyJSON", L("Copy JSON"), keywords: export),
            pane.searchEntry("exportJSON", L("Export JSON"), keywords: export),
            pane.searchEntry("shareStats", L("Share Stats…"), keywords: export),
        ]
    }
}
