import CodexBarCore

/// Maps an existing menu-card model into the wide board. Reads the model only; it does not fetch.
enum UsageBoardCardProjection {
    static func provider(from model: UsageMenuCardView.Model) -> UsageBoardProvider {
        var metrics = model.metrics.map(self.metric)
        var lines: [UsageBoardDetailLine] = []
        self.appendCredits(from: model, metrics: &metrics, lines: &lines)
        self.appendCost(model.providerCost, id: "provider-cost", metrics: &metrics, lines: &lines)
        self.appendCost(model.cloudCredits, id: "cloud-credits", metrics: &metrics, lines: &lines)
        self.appendTokenUsage(model.tokenUsage, lines: &lines)
        self.appendLimitResetCredits(model.limitResetCredits, lines: &lines)
        self.appendDashboard(model.inlineUsageDashboard, lines: &lines)
        self.appendThroughput(model.throughput, lines: &lines)
        self.appendDetails(model.providerDetails, metrics: &metrics, lines: &lines)

        var notes = model.usageNotes + model.subscriptionNotes
        if let lastKnown = self.nonEmpty(model.lastKnownUsageText) {
            notes.append(lastKnown)
        }
        if metrics.isEmpty, let placeholder = self.nonEmpty(model.placeholder), placeholder != model.subtitleText {
            notes.append(placeholder)
        }

        return UsageBoardProviderBuilder.make(
            id: model.provider.rawValue,
            name: model.providerName,
            planText: model.planText,
            email: model.email,
            subtitle: model.subtitleText,
            isLoading: model.subtitleStyle == .loading,
            isError: model.subtitleStyle == .error,
            metrics: metrics,
            lines: lines,
            notes: notes)
    }

    private static func metric(_ metric: UsageMenuCardView.Model.Metric) -> UsageBoardMetric {
        let showsBar = metric.statusText == nil
        let detail = self.joined([
            metric.detailText,
            metric.detailLeftText,
            metric.detailRightText,
            metric.dailyTargetText,
        ])
        return UsageBoardMetric(
            id: metric.id,
            title: metric.title,
            percent: showsBar ? metric.percent : nil,
            percentText: showsBar ? metric.percentLabel : (metric.statusText ?? metric.percentLabel),
            resetText: metric.resetText,
            detailText: detail,
            pacePercent: metric.pacePercent,
            showsBar: showsBar)
    }

    private static func appendCredits(
        from model: UsageMenuCardView.Model,
        metrics: inout [UsageBoardMetric],
        lines: inout [UsageBoardDetailLine])
    {
        guard let credits = self.nonEmpty(model.creditsText) else { return }
        let creditsTitle = L("Credits")
        let alreadyShown = metrics.contains {
            $0.id == "credits" || $0.title.caseInsensitiveCompare(creditsTitle) == .orderedSame
        }
        guard !alreadyShown else { return }
        if model.creditsShowProgress, let percent = model.creditsProgressPercent {
            metrics.append(UsageBoardMetric(
                id: "credits",
                title: creditsTitle,
                percent: percent,
                percentText: UsageFormatter.percentText(percent, suffix: L("usage_percent_suffix_used")),
                resetText: self.nonEmpty(model.creditsHintText),
                detailText: self.joined([credits, model.creditsScaleText]),
                showsBar: true))
            return
        }
        lines.append(UsageBoardDetailLine(id: "credits", label: creditsTitle, value: credits))
        if let hint = self.nonEmpty(model.creditsHintText) {
            lines.append(UsageBoardDetailLine(id: "credits-hint", label: creditsTitle, value: hint))
        }
    }

    private static func appendCost(
        _ cost: UsageMenuCardView.Model.ProviderCostSection?,
        id: String,
        metrics: inout [UsageBoardMetric],
        lines: inout [UsageBoardDetailLine])
    {
        guard let cost else { return }
        let detail = self.joined([
            cost.spendLine,
            cost.balanceLine,
            cost.personalSpendLine,
            cost.dailyTargetText,
        ])
        if let percent = cost.percentUsed {
            metrics.append(UsageBoardMetric(
                id: id,
                title: cost.title,
                percent: percent,
                percentText: cost.percentLine ?? UsageFormatter.percentString(percent),
                resetText: nil,
                detailText: detail,
                showsBar: true))
            return
        }
        lines.append(UsageBoardDetailLine(
            id: id,
            label: cost.title,
            value: detail ?? cost.spendLine))
    }

    private static func appendTokenUsage(
        _ tokenUsage: UsageMenuCardView.Model.TokenUsageSection?,
        lines: inout [UsageBoardDetailLine])
    {
        guard let tokenUsage else { return }
        var sentences: [String?] = [
            tokenUsage.sessionLine,
            tokenUsage.monthLine,
            tokenUsage.meteredLine,
            tokenUsage.hintLine,
            tokenUsage.errorLine,
        ]
        sentences.append(contentsOf: tokenUsage.comparisonLines)
        for (index, sentence) in sentences.enumerated() {
            guard let sentence = self.nonEmpty(sentence) else { continue }
            lines.append(UsageBoardDetailLine(id: "token-\(index)", label: sentence, value: ""))
        }
    }

    private static func appendLimitResetCredits(
        _ credits: LimitResetCreditsPresentation?,
        lines: inout [UsageBoardDetailLine])
    {
        guard let credits else { return }
        let value = self.joined([credits.text, credits.expirySummaryText]) ?? credits.text
        lines.append(UsageBoardDetailLine(
            id: "limit-reset-credits",
            label: L("Limit Reset Credits"),
            value: value))
    }

    private static func appendDashboard(
        _ dashboard: InlineUsageDashboardModel?,
        lines: inout [UsageBoardDetailLine])
    {
        guard let dashboard else { return }
        for (index, kpi) in dashboard.kpis.enumerated() {
            guard self.nonEmpty(kpi.value) != nil else { continue }
            lines.append(UsageBoardDetailLine(id: "kpi-\(index)", label: kpi.title, value: kpi.value))
        }
    }

    private static func appendThroughput(
        _ throughput: ProviderThroughputSection?,
        lines: inout [UsageBoardDetailLine])
    {
        guard let throughput else { return }
        lines.append(UsageBoardDetailLine(
            id: "throughput",
            label: throughput.summaryLine,
            value: ""))
    }

    static func appendDetails(
        _ sections: [ProviderDetailSection],
        metrics: inout [UsageBoardMetric],
        lines: inout [UsageBoardDetailLine])
    {
        for (sectionIndex, section) in sections.enumerated() {
            for (rowIndex, row) in section.rows.enumerated() {
                let id = "detail-\(sectionIndex)-\(rowIndex)"
                if let progress = row.progress {
                    metrics.append(UsageBoardMetric(
                        id: id,
                        title: row.label,
                        percent: progress.usedPercent,
                        percentText: row.value,
                        resetText: row.secondaryValue,
                        detailText: nil,
                        pacePercent: progress.expectedUsedPercent,
                        showsBar: true))
                } else if self.nonEmpty(row.value) != nil || self.nonEmpty(row.secondaryValue) != nil {
                    lines.append(UsageBoardDetailLine(
                        id: id,
                        label: row.label,
                        value: self.joined([row.value, row.secondaryValue]) ?? row.value))
                }
            }
        }
    }

    private static func joined(_ parts: [String?]) -> String? {
        let values = parts.compactMap(self.nonEmpty)
        return values.isEmpty ? nil : values.joined(separator: " · ")
    }

    private static func nonEmpty(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
