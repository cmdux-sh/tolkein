import Foundation

/// Presentation math for the wide usage board. This does not fetch providers or change stored usage.
package enum UsageBoardAttention: String, Equatable, Sendable {
    case ready
    case loading
    case needsSignIn
    case error
}

package enum UsageBoardLayout {
    /// Matches `StatusItemController.menuCardBaseWidth`. The board is three times that column.
    package static let classicMenuWidth = 310.0
    package static let widthScale = 3.0
    package static let sidebarWidth = 248.0
    package static let preferredHeight = 640.0

    package static var preferredWidth: Double {
        self.classicMenuWidth * self.widthScale
    }

    /// Uses the full 3× width when the screen can hold it, and shrinks to the visible area otherwise.
    package static func fittedWidth(_ availableWidth: Double) -> Double {
        let room = max(360, availableWidth - 16)
        return min(self.preferredWidth, room)
    }

    package static func fittedHeight(_ availableHeight: Double) -> Double {
        let room = max(420, availableHeight - 16)
        return min(self.preferredHeight, room)
    }

    /// How many window cards fit beside each other in the detail pane.
    package static func metricColumnCount(detailWidth: Double, itemCount: Int) -> Int {
        guard itemCount > 1 else { return 1 }
        if detailWidth >= 620, itemCount >= 3 {
            return min(3, itemCount)
        }
        if detailWidth >= 400 {
            return min(2, itemCount)
        }
        return 1
    }

    package static func attention(
        isLoading: Bool,
        isError: Bool,
        subtitle: String,
        hasContent: Bool) -> UsageBoardAttention
    {
        if self.mentionsSignIn(subtitle), isError || !hasContent {
            return .needsSignIn
        }
        if isLoading, !hasContent {
            return .loading
        }
        if isError {
            return .error
        }
        return .ready
    }

    package static func mentionsSignIn(_ subtitle: String) -> Bool {
        let folded = self.fold(subtitle)
        let needles = ["sign in", "sign-in", "log in", "login", "re-login", "signed out"]
        return needles.contains { folded.contains($0) }
    }

    package static func monogram(for name: String) -> String {
        let parts = name.split { $0 == " " || $0 == "-" || $0 == "·" }
        if parts.count >= 2 {
            let letters = parts.prefix(2).compactMap(\.first)
            return String(letters).uppercased()
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "?" }
        return String(trimmed.prefix(2)).uppercased()
    }

    package static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
}

package struct UsageBoardMetric: Equatable, Sendable, Identifiable {
    package let id: String
    package let title: String
    package let percent: Double?
    package let percentText: String
    package let resetText: String?
    package let detailText: String?
    package let pacePercent: Double?
    package let showsBar: Bool
    package let accessibilitySummary: String

    package init(
        id: String,
        title: String,
        percent: Double?,
        percentText: String,
        resetText: String?,
        detailText: String?,
        pacePercent: Double? = nil,
        showsBar: Bool,
        accessibilitySummary: String? = nil)
    {
        self.id = id
        self.title = title
        self.percent = percent
        self.percentText = percentText
        self.resetText = Self.cleaned(resetText)
        self.detailText = Self.cleaned(detailText)
        self.pacePercent = pacePercent
        self.showsBar = showsBar
        if let accessibilitySummary, !accessibilitySummary.isEmpty {
            self.accessibilitySummary = accessibilitySummary
        } else {
            self.accessibilitySummary = Self.summary(
                title: title,
                percentText: percentText,
                resetText: self.resetText,
                detailText: self.detailText)
        }
    }

    package static func summary(
        title: String,
        percentText: String,
        resetText: String?,
        detailText: String?) -> String
    {
        [title, percentText, resetText, detailText]
            .compactMap(self.cleaned)
            .joined(separator: ", ")
    }

    private static func cleaned(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

package struct UsageBoardDetailLine: Equatable, Sendable, Identifiable {
    package let id: String
    package let label: String
    package let value: String

    package init(id: String, label: String, value: String) {
        self.id = id
        self.label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        self.value = value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

package struct UsageBoardProvider: Equatable, Sendable, Identifiable {
    package let id: String
    package let name: String
    package let planText: String?
    package let email: String
    package let subtitle: String
    package let attention: UsageBoardAttention
    package let headlinePercentText: String?
    package let headlineCaption: String?
    package let metrics: [UsageBoardMetric]
    package let lines: [UsageBoardDetailLine]
    package let notes: [String]
    package let monogram: String

    package init(
        id: String,
        name: String,
        planText: String?,
        email: String,
        subtitle: String,
        attention: UsageBoardAttention,
        headlinePercentText: String?,
        headlineCaption: String?,
        metrics: [UsageBoardMetric],
        lines: [UsageBoardDetailLine],
        notes: [String],
        monogram: String)
    {
        self.id = id
        self.name = name
        self.planText = planText
        self.email = email
        self.subtitle = subtitle
        self.attention = attention
        self.headlinePercentText = headlinePercentText
        self.headlineCaption = headlineCaption
        self.metrics = metrics
        self.lines = lines
        self.notes = notes
        self.monogram = monogram
    }
}

package enum UsageBoardProviderBuilder {
    package static func make(
        id: String,
        name: String,
        planText: String?,
        email: String,
        subtitle: String,
        isLoading: Bool,
        isError: Bool,
        metrics: [UsageBoardMetric],
        lines: [UsageBoardDetailLine],
        notes: [String]) -> UsageBoardProvider
    {
        let cleanedNotes = notes.compactMap(Self.cleaned)
        let visibleLines = self.lines(lines, beside: metrics)
        let hasContent = !metrics.isEmpty || !visibleLines.isEmpty || !cleanedNotes.isEmpty
        let attention = UsageBoardLayout.attention(
            isLoading: isLoading,
            isError: isError,
            subtitle: subtitle,
            hasContent: hasContent)
        let headline = metrics.first(where: \.showsBar) ?? metrics.first
        let captionParts = [headline?.title, headline?.resetText].compactMap(Self.cleaned)
        return UsageBoardProvider(
            id: id,
            name: name,
            planText: Self.cleaned(planText),
            email: email.trimmingCharacters(in: .whitespacesAndNewlines),
            subtitle: subtitle.trimmingCharacters(in: .whitespacesAndNewlines),
            attention: attention,
            headlinePercentText: Self.cleaned(headline?.percentText),
            headlineCaption: captionParts.isEmpty ? nil : captionParts.joined(separator: " · "),
            metrics: metrics,
            lines: visibleLines,
            notes: cleanedNotes,
            monogram: UsageBoardLayout.monogram(for: name))
    }

    /// Drops a detail row that repeats a window already shown as a metric tile.
    package static func lines(
        _ lines: [UsageBoardDetailLine],
        beside metrics: [UsageBoardMetric]) -> [UsageBoardDetailLine]
    {
        lines.filter { line in
            guard !line.label.isEmpty || !line.value.isEmpty else { return false }
            let label = UsageBoardLayout.fold(line.label)
            let value = UsageBoardLayout.fold(line.value)
            let duplicatesMetric = metrics.contains { metric in
                guard UsageBoardLayout.fold(metric.title) == label else { return false }
                let known = [metric.percentText, metric.resetText, metric.detailText]
                    .compactMap(\.self)
                    .map(UsageBoardLayout.fold)
                return known.contains(value) || value.isEmpty
            }
            return !duplicatesMetric
        }
    }

    private static func cleaned(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
