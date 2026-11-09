import CodexBarCore
import InternalUI
import SwiftUI

// MARK: - Status

/// Source, version, updated, status, account, auth and plan, then the last fetch error if there is one.
@MainActor
struct ProviderStatusSection: View {
    let facts: [IUKeyValueList.Row]
    let errorDisplay: ProviderErrorDisplay?
    @Binding var isErrorExpanded: Bool
    let onCopyError: (String) -> Void

    var body: some View {
        IUSettingsSection(ProviderSettingsPageSection.status.title) {
            if !self.facts.isEmpty {
                ProviderFactsRow(facts: self.facts)
            }
            if let errorDisplay {
                ProviderErrorRow(
                    display: errorDisplay,
                    isExpanded: self.$isErrorExpanded,
                    onCopy: { self.onCopyError(errorDisplay.full) })
            }
        }
    }
}

/// Read-only facts as one row of a section.
struct ProviderFactsRow: View {
    let facts: [IUKeyValueList.Row]

    var body: some View {
        IUKeyValueList(self.facts)
            .padding(.horizontal, IUSpace.settingsRowPaddingX)
            .padding(.vertical, IUSpace.unit)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The last fetch error: a one-line error status, the short message, and Show details / Copy error.
struct ProviderErrorRow: View {
    let display: ProviderErrorDisplay
    @Binding var isExpanded: Bool
    let onCopy: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: IUSpace.unit * 2) {
            IUStatusLabel(self.display.title, tone: .error)
            IUText(self.display.preview, role: .caption, muted: true)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            if self.isExpanded {
                IUText(self.display.full, role: .caption)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            HStack(spacing: IUSpace.unit * 2) {
                if self.display.preview != self.display.full {
                    Button(self.isExpanded ? L("Hide details") : L("Show details")) {
                        self.isExpanded.toggle()
                    }
                    .buttonStyle(.iu())
                }
                Button(L("Copy error"), action: self.onCopy)
                    .buttonStyle(.iu())
            }
        }
        .providerSettingsRow()
    }
}

// MARK: - Usage

/// The Usage group: the provider's usage (or Codex's per-account overview and local usage), Codex's OpenCode
/// history opt-in, and the visible usage items.
@MainActor
struct ProviderUsageSections: View {
    let content: ProviderSettingsPageContent
    @Bindable var settings: SettingsStore
    let isEnabled: Bool
    let isRefreshing: Bool

    var body: some View {
        if let overview = self.content.accountUsageOverview {
            ProviderAccountOverviewSections(
                provider: self.content.provider,
                overview: overview,
                isEnabled: self.isEnabled)
            if let tokenUsage = self.content.model.tokenUsage {
                let ledger = self.settings.codexLocalSessionCostLedgerEnabled
                IUSettingsSection(
                    L(ledger ? "This Mac" : "Local usage"),
                    footer: L(ledger
                        ? "Local usage is shared across accounts on this Mac."
                        : "Local usage comes from the current Codex profile."))
                {
                    ProviderTokenUsageRow(
                        usage: ProviderSettingsUsagePresentation.tokenUsage(
                            tokenUsage,
                            provider: self.content.provider))
                }
            }
        } else {
            IUSettingsSection(ProviderSettingsPageSection.usage.title) {
                ProviderUsageRows(rows: ProviderSettingsUsagePresentation.rows(
                    provider: self.content.provider,
                    model: self.content.model,
                    openAIWebDiagnostic: self.content.usageDiagnostic,
                    isEnabled: self.isEnabled,
                    isRefreshing: self.isRefreshing))
            }
        }

        // Provider-specific by design: this opt-in augments only the ambient Codex cost ledger.
        if self.content.provider == .codex {
            IUSettingsSection(footer: L(
                // swiftlint:disable:next line_length
                "Show this Mac's recorded OpenCode usage in Codex history. Off by default; scoped or alternate CODEX_HOME locations always stay excluded."))
            {
                IUSettingsToggleRow(L("OpenCode local history"), isOn: self.$settings.openCodeLocalHistoryEnabled)
            }
        }

        if !self.content.usageItems.isEmpty {
            ProviderUsageItemVisibilitySection(
                provider: self.content.provider,
                settings: self.settings,
                items: self.content.usageItems)
        }
    }
}

/// The rows of one usage block: a meter per window, then facts, token usage, the diagnostic and notes, or the
/// placeholder when there is nothing yet.
struct ProviderUsageRows: View {
    let rows: ProviderSettingsUsagePresentation.Rows

    var body: some View {
        if let placeholder = self.rows.placeholder {
            ProviderSettingsCaptionRow(placeholder)
        }
        ForEach(self.rows.meters) { metric in
            ProviderUsageMeterRow(metric: metric)
        }
        if !self.rows.facts.isEmpty {
            ProviderFactsRow(facts: self.rows.facts)
        }
        if let tokenUsage = self.rows.tokenUsage {
            ProviderTokenUsageRow(usage: tokenUsage)
        }
        if let diagnostic = self.rows.diagnostic {
            IUSettingsRow(L("OpenAI web extras"), subtitle: diagnostic) { EmptyView() }
        }
        if !self.rows.notes.isEmpty {
            ProviderSettingsCaptionRow(self.rows.notes.joined(separator: "\n"))
        }
    }
}

/// One usage window, as on the Usage Board's provider detail: its name and value on a line, the meter under it
/// (filled with what is left, with the pace marker), then its reset and detail lines.
struct ProviderUsageMeterRow: View {
    let metric: UsageBoardMetric

    var body: some View {
        VStack(alignment: .leading, spacing: IUSpace.unit * 1.5) {
            HStack(alignment: .firstTextBaseline, spacing: IUSpace.unit * 2) {
                IUText(self.metric.title, role: .caption, muted: true)
                    .lineLimit(1)
                Spacer(minLength: IUSpace.unit)
                Text(self.metric.percentText)
                    .font(IUTextRole.subtitle.font)
                    .monospacedDigit()
                    .foregroundStyle(IUColor.primary)
                    .lineLimit(1)
            }
            if self.metric.showsBar, let left = self.metric.percentLeft {
                IUMeter(
                    self.metric.title,
                    fraction: left / 100,
                    tone: UsageBoardStatus.meterTone(percentLeft: left),
                    marker: self.metric.pacePercent.map { $0 / 100 },
                    valueText: self.metric.percentText)
            }
            // One line each, so a long caption never breaks mid-phrase.
            ForEach([self.metric.resetText, self.metric.detailText].compactMap(\.self), id: \.self) { line in
                IUText(line, role: .caption, muted: true)
                    .lineLimit(1)
                    .help(line)
            }
        }
        .providerSettingsRow()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(UsageBoardStatus.accessibilitySummary(self.metric))
    }
}

/// Token usage: its heading, with the session, month and hint lines under it.
struct ProviderTokenUsageRow: View {
    let usage: ProviderSettingsUsagePresentation.TokenUsage

    var body: some View {
        IUSettingsRow(
            self.usage.title,
            subtitle: self.usage.lines.isEmpty ? nil : self.usage.lines.joined(separator: "\n"))
        {
            EmptyView()
        }
    }
}

// MARK: - Codex account overview

/// Codex's per-account usage: a refresh-all row, then one card per account with its facts, meters and error.
/// Account rows are inventory-owned; a failed or missing fetch must not remove an account.
@MainActor
struct ProviderAccountOverviewSections: View {
    let provider: UsageProvider
    let overview: ProviderAccountUsageOverview
    let isEnabled: Bool

    var body: some View {
        IUSettingsSection(L("All accounts"), footer: self.footer) {
            IUSettingsRow(L("Refresh all accounts")) {
                IUToolButton(L("Refresh all accounts"), systemImage: "arrow.clockwise") {
                    self.overview.onRefresh(Set(self.overview.rows.map(\.id)))
                }
                .disabled(!self.overview.canRefresh)
            }
        }

        ForEach(self.overview.rows) { row in
            IUSettingsSection {
                IUSettingsRow(row.title, subtitle: Self.roles(row)) {
                    IUToolButton(L("Refresh") + " " + row.title, systemImage: "arrow.clockwise", help: L("Refresh")) {
                        self.overview.onRefresh([row.id])
                    }
                    .disabled(!self.overview.canRefresh)
                }
                ProviderFactsRow(facts: Self.facts(row))
                ProviderUsageRows(rows: ProviderSettingsUsagePresentation.rows(
                    provider: self.provider,
                    model: row.model,
                    openAIWebDiagnostic: nil,
                    isEnabled: self.isEnabled,
                    isRefreshing: row.isRefreshing))
                if let error = row.error {
                    VStack(alignment: .leading, spacing: IUSpace.unit) {
                        IUStatusLabel(L("Couldn't load usage"), tone: .error)
                        IUText(error, role: .caption, muted: true)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                    .providerSettingsRow()
                }
            }
        }
    }

    private var footer: String {
        self.overview.rows.count > self.overview.refreshLimit
            ? L("Refreshes up to %@ accounts at a time.", String(self.overview.refreshLimit))
            : L("Each account has its own limits. Viewing usage does not switch accounts.")
    }

    static func roles(_ row: ProviderAccountUsageOverview.Row) -> String? {
        let roles = [row.isFollowed ? L("Tolkein follows") : nil, row.isSystem ? L("System") : nil]
            .compactMap(\.self)
        return roles.isEmpty ? nil : roles.joined(separator: " · ")
    }

    static func facts(_ row: ProviderAccountUsageOverview.Row) -> [IUKeyValueList.Row] {
        var facts: [IUKeyValueList.Row] = []
        if let plan = row.model.planText, !plan.isEmpty {
            facts.append(.init(L("Plan"), plan, id: "plan"))
        }
        facts.append(.init(
            L("Updated"),
            row.isRefreshing ? L("Refreshing")
                : row.updatedAt.map { UsageFormatter.updatedString(from: $0) } ?? L("Not fetched yet"),
            id: "updated"))
        if let source = row.sourceLabel {
            facts.append(.init(L("Source"), source, id: "source"))
        }
        return facts
    }
}

// MARK: - Visible usage items

/// Which usage rows appear in the provider's menu, Settings and Overview, with Restore Defaults.
@MainActor
struct ProviderUsageItemVisibilitySection: View {
    let provider: UsageProvider
    @Bindable var settings: SettingsStore
    let items: [ProviderUsageItemDescriptor]

    var body: some View {
        IUSettingsSection(
            L("Visible usage items"),
            footer: L("Choose which usage rows appear in this provider's menu, Settings preview, and Overview."))
        {
            ForEach(self.items) { item in
                IUSettingsRow(item.title, subtitle: self.hint(for: item)) {
                    Toggle(item.title, isOn: Binding(
                        get: { self.settings.isUsageItemVisible(item.id, for: self.provider) },
                        set: { isVisible in
                            self.settings.setUsageItemVisible(isVisible, itemID: item.id, for: self.provider)
                        }))
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                }
            }
            ProviderSettingsTrailingButtonsRow {
                Button(L("Restore Defaults")) {
                    self.settings.restoreDefaultUsageItemVisibility(for: self.provider)
                }
                .buttonStyle(.iu())
                .disabled(!self.settings.hasCustomUsageItemVisibility(for: self.provider))
            }
        }
    }

    private func hint(for item: ProviderUsageItemDescriptor) -> String? {
        guard item.requiresOptionalUsage, !self.settings.showOptionalCreditsAndExtraUsage else { return nil }
        return L("Hidden by the global optional credits, spending & billing setting.")
    }
}
