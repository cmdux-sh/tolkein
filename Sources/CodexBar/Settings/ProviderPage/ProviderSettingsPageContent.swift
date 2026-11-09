import CodexBarCore
import InternalUI
import SwiftUI

/// The fixed sections of a provider page, in page order. The title row (brand, name, Refresh and the Enabled
/// switch) sits above them; a section with nothing to show for a provider is left out.
enum ProviderSettingsPageSection: String, CaseIterable, Identifiable {
    case status
    case usage
    case connection
    case display
    case alerts
    case options

    var id: String {
        self.rawValue
    }

    var title: String {
        switch self {
        case .status: L("Status")
        case .usage: L("Usage")
        case .connection: L("Sign-in & connection")
        case .display: L("Display")
        case .alerts: L("tab_alerts")
        case .options: L("Options")
        }
    }

    /// The search entry id for this section on `provider`'s page, or nil for sections search does not list.
    func searchEntryID(for provider: UsageProvider) -> String? {
        switch self {
        case .status, .usage: nil
        case .connection, .display, .alerts, .options:
            "\(SettingsPane.provider(provider.instanceID).persistenceToken)/\(self.rawValue)"
        }
    }

    /// The sections search lists on every provider page.
    static let searchable: [ProviderSettingsPageSection] = [.connection, .display, .alerts, .options]
}

/// One provider page's content, read from the stores and the provider's settings descriptors on each render.
@MainActor
struct ProviderSettingsPageContent {
    let provider: UsageProvider
    let displayName: String
    /// Two lines: the provider's detail line, then when usage was last fetched.
    let subtitle: String
    /// The menu-card model with the provider's hidden usage items removed.
    let model: UsageMenuCardView.Model
    /// Codex's per-account overview, which replaces the single usage section.
    let accountUsageOverview: ProviderAccountUsageOverview?
    let usageItems: [ProviderUsageItemDescriptor]
    let statusFacts: [IUKeyValueList.Row]
    let errorDisplay: ProviderErrorDisplay?
    let openAIWebDiagnostic: String?
    let pickers: [ProviderSettingsPickerDescriptor]
    let toggles: [ProviderSettingsToggleDescriptor]
    let fields: [ProviderSettingsFieldDescriptor]
    let directoryLists: [ProviderSettingsDirectoryListDescriptor]
    let modelLimits: [ProviderSettingsModelLimitsDescriptor]
    let actions: [ProviderSettingsActionsDescriptor]
    /// Present only while the provider shows token accounts.
    let tokenAccounts: ProviderSettingsTokenAccountsDescriptor?
    let organizations: ProviderSettingsOrganizationsDescriptor?
    let codexAccounts: CodexAccountsSectionState?
    let showsMenuBarMetric: Bool

    var menuBarPickers: [ProviderSettingsPickerDescriptor] {
        self.pickers.filter { $0.placement == .menuBar }
    }

    var connectionPickers: [ProviderSettingsPickerDescriptor] {
        self.pickers.filter { $0.placement == .connection }
    }

    /// The OpenAI web diagnostic moves to Sign-in & connection when the account overview replaces the usage rows.
    var connectionDiagnostic: String? {
        self.accountUsageOverview == nil ? nil : self.openAIWebDiagnostic
    }

    /// The diagnostic shown with the usage rows, when there is no account overview.
    var usageDiagnostic: String? {
        self.accountUsageOverview == nil ? self.openAIWebDiagnostic : nil
    }

    var hasConnectionContent: Bool {
        !self.connectionPickers.isEmpty
            || !self.actions.isEmpty
            || self.tokenAccounts != nil
            || !self.fields.isEmpty
            || !self.directoryLists.isEmpty
            || !self.modelLimits.isEmpty
            || self.organizations != nil
            || self.codexAccounts != nil
            || self.connectionDiagnostic != nil
    }

    /// The sections this provider's page shows, in order. Usage always shows (at least a placeholder line), and so do
    /// Display (the accent colour) and Alerts (the quota-warning override); the rest appear only with content.
    var sections: [ProviderSettingsPageSection] {
        ProviderSettingsPageSection.allCases.filter { section in
            switch section {
            case .status: !self.statusFacts.isEmpty || self.errorDisplay != nil
            case .usage, .display, .alerts: true
            case .connection: self.hasConnectionContent
            case .options: !self.toggles.isEmpty
            }
        }
    }
}

// MARK: - Status facts

/// The read-only facts in a provider page's Status section.
@MainActor
enum ProviderStatusFacts {
    static func rows(
        provider: UsageProvider,
        store: UsageStore,
        model: UsageMenuCardView.Model,
        showsAccountInfo: Bool) -> [IUKeyValueList.Row]
    {
        var rows: [IUKeyValueList.Row] = []
        if showsAccountInfo {
            rows.append(.init(L("Source"), store.sourceLabel(for: provider), id: "source"))
        }
        if let version = self.versionText(provider: provider, store: store) {
            rows.append(.init(L("Version"), version, id: "version"))
        }
        if showsAccountInfo {
            rows.append(.init(L("Updated"), self.updatedText(provider: provider, store: store), id: "updated"))
        }
        if let status = store.status(for: provider) {
            rows.append(.init(L("Status"), status.description ?? status.indicator.label, id: "status"))
        }
        if showsAccountInfo, !model.email.isEmpty {
            rows.append(.init(L("Account"), model.email, id: "account"))
        }
        // Provider-specific by design: Kiro reports an auth method as a separate identity field, not a plan.
        if provider == .kiro,
           let authMethod = store.snapshot(for: provider.instanceID)?.loginMethod(for: .kiro),
           !authMethod.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            rows.append(.init(L("Auth"), authMethod, id: "auth"))
        }
        if showsAccountInfo, let plan = self.planRow(provider: provider, planText: model.planText) {
            rows.append(.init(plan.label, plan.value, id: "plan"))
        }
        return rows
    }

    static func versionText(provider: UsageProvider, store: UsageStore) -> String? {
        let context = ProviderPresentationContext(
            provider: provider,
            settings: store.settings,
            store: store,
            metadata: store.metadata(for: provider))
        let presentation = ProviderCatalog.implementation(for: provider)?.presentation(context: context)
            ?? ProviderPresentation(detailLine: ProviderPresentation.standardDetailLine)
        guard presentation.showsVersionInSettings else { return nil }
        return store.version(for: provider) ?? L("not detected")
    }

    static func planRow(provider: UsageProvider, planText: String?) -> (label: String, value: String)? {
        guard let rawPlan = planText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawPlan.isEmpty
        else {
            return nil
        }
        let presentation = ProviderDescriptorRegistry.descriptor(for: provider).presentation.planRow
        if presentation.stripsBalancePrefix,
           let value = MenuBarDisplayText.prefixedValue(from: rawPlan, prefix: "Balance:")
        {
            return (label: L(presentation.balancePrefixedLabel), value: value)
        }
        return (label: L(presentation.label), value: rawPlan)
    }

    static func updatedText(provider: UsageProvider, store: UsageStore) -> String {
        if let updated = store.snapshot(for: provider.instanceID)?.updatedAt {
            return UsageFormatter.updatedString(from: updated)
        }
        if store.refreshingProviders.contains(provider.instanceID) {
            return L("Refreshing")
        }
        if store.unavailableMessage(for: provider) != nil {
            return L("Unavailable")
        }
        return L("Not fetched yet")
    }
}

// MARK: - Usage presentation

enum ProviderMetricInlinePresentation: Equatable {
    case progress
    case status(String)
}

/// How a menu-card model reads in a provider page's Usage section: meters for every window with a level (as on the
/// Usage Board), facts for credits and costs, the token-usage lines, notes, and a placeholder when there is nothing.
@MainActor
enum ProviderSettingsUsagePresentation {
    struct InfoRow: Identifiable, Equatable {
        enum ID: Hashable {
            case credits
            case openAIWeb
        }

        let id: ID
        let label: String
        let value: String
    }

    struct ContentState: Equatable {
        let hasMetrics: Bool
        let hasUsageNotes: Bool
        let hasProviderCost: Bool
        let hasInfoRows: Bool
        let hasTokenUsage: Bool
        let hasResetCredits: Bool
        let hasCloudCredits: Bool
        let hasProviderDetails: Bool

        init(model: UsageMenuCardView.Model, infoRows: [InfoRow]) {
            self.hasMetrics = !model.metrics.isEmpty
            self.hasUsageNotes = !model.usageNotes.isEmpty
            self.hasProviderCost = model.providerCost?.showsInProviderDetails == true
            self.hasInfoRows = !infoRows.isEmpty
            self.hasTokenUsage = model.tokenUsage != nil
            self.hasResetCredits = model.limitResetCredits != nil
            self.hasCloudCredits = model.cloudCredits != nil
            self.hasProviderDetails = !model.providerDetails.isEmpty
        }

        var showsPlaceholder: Bool {
            !self.hasMetrics &&
                !self.hasUsageNotes &&
                !self.hasProviderCost &&
                !self.hasInfoRows &&
                !self.hasTokenUsage &&
                !self.hasResetCredits &&
                !self.hasCloudCredits &&
                !self.hasProviderDetails
        }
    }

    /// One usage row: the meters and facts it shows, then the token usage and notes.
    struct Rows {
        let meters: [UsageBoardMetric]
        let facts: [IUKeyValueList.Row]
        let tokenUsage: TokenUsage?
        let diagnostic: String?
        let notes: [String]
        let placeholder: String?
    }

    struct TokenUsage: Equatable {
        let title: String
        let lines: [String]
    }

    static func infoRows(
        for model: UsageMenuCardView.Model,
        openAIWebDiagnostic: String?) -> [InfoRow]
    {
        var rows: [InfoRow] = []
        if let credits = model.creditsText {
            rows.append(InfoRow(id: .credits, label: L("Credits"), value: credits))
        }
        if let diagnostic = openAIWebDiagnostic {
            rows.append(InfoRow(id: .openAIWeb, label: L("OpenAI web extras"), value: diagnostic))
        }
        return rows
    }

    static func placeholderText(
        isEnabled: Bool,
        isRefreshing: Bool,
        modelPlaceholder: String?) -> String
    {
        if !isEnabled {
            return L("Disabled — no recent data")
        }
        if isRefreshing {
            return L("Refreshing")
        }
        return modelPlaceholder.map(L) ?? L("No usage yet")
    }

    static func metricTitle(provider: UsageProvider, metric: UsageMenuCardView.Model.Metric) -> String {
        L(UsageMenuCardView.popupMetricTitle(provider: provider, metric: metric))
    }

    static func metricInlinePresentation(
        _ metric: UsageMenuCardView.Model.Metric) -> ProviderMetricInlinePresentation
    {
        if let statusText = metric.statusText {
            return .status(statusText)
        }
        return .progress
    }

    static func rows(
        provider: UsageProvider,
        model: UsageMenuCardView.Model,
        openAIWebDiagnostic: String?,
        isEnabled: Bool,
        isRefreshing: Bool) -> Rows
    {
        let infoRows = self.infoRows(for: model, openAIWebDiagnostic: openAIWebDiagnostic)
        let state = ContentState(model: model, infoRows: infoRows)
        guard !state.showsPlaceholder else {
            return Rows(
                meters: [],
                facts: [],
                tokenUsage: nil,
                diagnostic: nil,
                notes: [],
                placeholder: self.placeholderText(
                    isEnabled: isEnabled,
                    isRefreshing: isRefreshing,
                    modelPlaceholder: model.placeholder))
        }

        var meters = model.metrics.map { self.meter(for: $0, provider: provider) }
        var facts: [IUKeyValueList.Row] = infoRows
            .filter { $0.id == .credits }
            .map { IUKeyValueList.Row($0.label, $0.value, id: "credits") }
        if let resetCredits = model.limitResetCredits {
            facts.append(.init(
                L("Limit Reset Credits"),
                [resetCredits.text, resetCredits.expirySummaryText].joined(separator: " · "),
                id: "limit-reset-credits"))
        }
        self.appendCost(model.cloudCredits, id: "cloud-credits", meters: &meters, facts: &facts)
        if let cost = model.providerCost, cost.showsInProviderDetails {
            self.appendCost(cost, id: "provider-cost", meters: &meters, facts: &facts)
        }
        var detailMeters: [UsageBoardMetric] = []
        var detailLines: [UsageBoardDetailLine] = []
        UsageBoardCardProjection.appendDetails(model.providerDetails, metrics: &detailMeters, lines: &detailLines)
        meters += detailMeters
        facts += detailLines.map { IUKeyValueList.Row($0.label, $0.value, id: $0.id) }

        return Rows(
            meters: meters,
            facts: facts,
            tokenUsage: model.tokenUsage.map { self.tokenUsage($0, provider: provider) },
            diagnostic: infoRows.first { $0.id == .openAIWeb }?.value,
            notes: model.usageNotes,
            placeholder: nil)
    }

    static func meter(for metric: UsageMenuCardView.Model.Metric, provider: UsageProvider) -> UsageBoardMetric {
        let title = self.metricTitle(provider: provider, metric: metric)
        switch self.metricInlinePresentation(metric) {
        case let .status(statusText):
            return UsageBoardMetric(
                id: metric.id,
                title: title,
                percent: nil,
                percentText: statusText,
                resetText: metric.resetText,
                detailText: metric.detailText,
                showsBar: false)
        case .progress:
            let presentation = metric.linePresentation(title: title)
            let detail = [presentation.metaText, metric.detailText, metric.dailyTargetText]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " · ")
            return UsageBoardMetric(
                id: metric.id,
                title: title,
                percent: metric.percent,
                percentText: metric.percentLabel,
                resetText: presentation.resetText,
                detailText: detail,
                pacePercent: metric.pacePercent,
                percentLeft: UsageBoardLayout.percentLeft(
                    displayedPercent: metric.percent,
                    showsUsed: metric.percentStyle == .used),
                showsBar: true)
        }
    }

    static func tokenUsage(
        _ section: UsageMenuCardView.Model.TokenUsageSection,
        provider: UsageProvider) -> TokenUsage
    {
        var lines = [section.sessionLine, section.monthLine]
        if ProviderDescriptorRegistry.descriptor(for: provider).tokenCost.showsHintInProviderDetails,
           let hint = section.hintLine, !hint.isEmpty
        {
            lines.append(hint)
        }
        return TokenUsage(
            title: UsageMenuCardView.Model.tokenUsageHeader(provider: provider),
            lines: lines.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    }

    private static func appendCost(
        _ cost: UsageMenuCardView.Model.ProviderCostSection?,
        id: String,
        meters: inout [UsageBoardMetric],
        facts: inout [IUKeyValueList.Row])
    {
        guard let cost else { return }
        guard let consumed = cost.percentUsed else {
            facts.append(.init(cost.title, cost.spendLine, id: id))
            return
        }
        let showsUsed = cost.percentStyle == .used
        let displayed = min(100, max(0, cost.displayPercent ?? consumed))
        let suffix = showsUsed ? L("usage_percent_suffix_used") : L("usage_percent_suffix_left")
        meters.append(UsageBoardMetric(
            id: id,
            title: cost.title,
            percent: displayed,
            percentText: cost.percentLine ?? UsageFormatter.percentText(displayed, suffix: suffix),
            resetText: nil,
            detailText: cost.spendLine,
            percentLeft: showsUsed ? min(100, max(0, 100 - consumed)) : displayed,
            showsBar: true))
    }
}
