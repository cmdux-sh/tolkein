import Foundation
import SwiftUI

/// Presentation math for the wide usage board. This does not fetch providers or change stored usage.
package enum UsageBoardAttention: String, Equatable, Sendable {
    case ready
    case loading
    case needsSignIn
    case error
}

package struct UsageBoardMasonryPlacement: Equatable, Sendable {
    package let index: Int
    package let column: Int
    package let x: Double
    package let y: Double
    package let width: Double
    package let height: Double
}

package enum UsageBoardLayout {
    /// Matches `StatusItemController.menuCardBaseWidth`. The board is at least three times that column.
    package static let classicMenuWidth = 310.0
    package static let widthScale = 3.0
    package static let sidebarWidth = 200.0
    /// Floor is the original 3× column. The board then grows toward the visible screen.
    package static let minimumWidth = 560.0
    package static let maximumWidth = 780.0
    package static let preferredWidth = 780.0
    package static let preferredHeight = 460.0
    package static let maximumHeight = 520.0
    /// Overview cards stay wide enough for a name plus two bars, then narrow only to fit the height.
    package static let overviewMinimumColumnWidth = 220.0

    /// Uses the visible width, capped so an ultrawide does not stretch the board edge to edge.
    /// A display narrower than the floor keeps the board on screen.
    package static func fittedWidth(_ availableWidth: Double) -> Double {
        let room = max(360, availableWidth - 16)
        if room < self.minimumWidth {
            return room
        }
        return min(self.maximumWidth, room)
    }

    package static func fittedHeight(_ availableHeight: Double) -> Double {
        let room = max(420, availableHeight - 16)
        return min(self.maximumHeight, room)
    }

    /// One session-style window and one weekly or limit window, for the glanceable overview.
    /// Credits, extra usage, and other tiles stay on the single-provider detail.
    package static func glanceMetrics(_ metrics: [UsageBoardMetric]) -> [UsageBoardMetric] {
        let bars = metrics.filter(\.showsBar)
        let pool = bars.isEmpty ? metrics : bars
        var picked: [UsageBoardMetric] = []
        if let session = pool.first(where: { self.glanceKind($0) == .session }) {
            picked.append(session)
        }
        if let weekly = pool.first(where: { self.glanceKind($0) == .weekly && !self.containsMetric($0, in: picked) }) {
            picked.append(weekly)
        }
        if picked.count < 2 {
            for metric in pool where picked.count < 2 && !self.containsMetric(metric, in: picked) {
                picked.append(metric)
            }
        }
        return Array(picked.prefix(2))
    }

    /// "42% used" becomes "42%". Text without a leading percent is left as written.
    package static func shortPercent(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let percentIndex = trimmed.firstIndex(of: "%") else { return trimmed }
        let head = trimmed[..<trimmed.index(after: percentIndex)]
        let digits = head.dropLast()
        guard !digits.isEmpty, digits.allSatisfy({ $0.isNumber || $0 == "." }) else { return trimmed }
        return String(head)
    }

    /// Keeps a short countdown and drops deficit, reserve, and "lasts until" sentences.
    package static func shortReset(_ text: String?) -> String? {
        guard let text else { return nil }
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let separator = trimmed.range(of: " · ") {
            trimmed = String(trimmed[..<separator.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let folded = self.fold(trimmed)
        if folded.contains("deficit") || folded.contains("reserve") || folded.contains("lasts until") {
            return nil
        }
        let prefixes = ["resets in ", "resets ", "reset in ", "reset "]
        let lowered = trimmed.lowercased()
        for prefix in prefixes where lowered.hasPrefix(prefix) {
            let rest = String(trimmed.dropFirst(prefix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return rest.isEmpty ? nil : rest
        }
        return trimmed.isEmpty ? nil : trimmed
    }

    /// How many overview columns fit. Wider boards get more columns, which also shortens the stack.
    package static func masonryColumnCount(
        itemCount: Int,
        availableWidth: Double,
        minimumColumnWidth: Double,
        spacing: Double) -> Int
    {
        guard itemCount > 1 else { return 1 }
        let minWidth = max(1, minimumColumnWidth)
        let gap = max(0, spacing)
        let slots = Int((max(0, availableWidth) + gap) / (minWidth + gap))
        return min(itemCount, max(1, slots))
    }

    package static func masonryColumnWidth(
        availableWidth: Double,
        columnCount: Int,
        spacing: Double) -> Double
    {
        let columns = max(1, columnCount)
        let gap = max(0, spacing)
        let gaps = gap * Double(columns - 1)
        return max(0, (availableWidth - gaps) / Double(columns))
    }

    /// Places each item in the currently shortest column. Equal heights go to the leftmost column.
    package static func masonryPlacements(
        itemHeights: [Double],
        columnCount: Int,
        columnWidth: Double,
        spacing: Double) -> [UsageBoardMasonryPlacement]
    {
        guard !itemHeights.isEmpty else { return [] }
        let columns = max(1, min(columnCount, itemHeights.count))
        let width = max(0, columnWidth)
        let gap = max(0, spacing)
        var columnHeights = Array(repeating: 0.0, count: columns)
        var placements: [UsageBoardMasonryPlacement] = []
        placements.reserveCapacity(itemHeights.count)
        for (index, rawHeight) in itemHeights.enumerated() {
            let height = max(0, rawHeight)
            let column = columnHeights.enumerated().min { lhs, rhs in
                if lhs.element == rhs.element {
                    return lhs.offset < rhs.offset
                }
                return lhs.element < rhs.element
            }?.offset ?? 0
            let y = columnHeights[column]
            placements.append(UsageBoardMasonryPlacement(
                index: index,
                column: column,
                x: Double(column) * (width + gap),
                y: y,
                width: width,
                height: height))
            columnHeights[column] = y + height + gap
        }
        return placements
    }

    package static func masonryContentHeight(of placements: [UsageBoardMasonryPlacement]) -> Double {
        placements.map { $0.y + $0.height }.max() ?? 0
    }

    /// Starts from the widest columns that still meet `minimumColumnWidth`.
    /// Adds columns when that stack is taller than `availableHeight`.
    /// Stops before a column would be narrower than `narrowestColumnWidth`.
    package static func masonryColumnCountFitting(
        itemHeights: [Double],
        availableWidth: Double,
        availableHeight: Double?,
        minimumColumnWidth: Double,
        spacing: Double,
        narrowestColumnWidth: Double = 160) -> Int
    {
        let count = itemHeights.count
        var columns = self.masonryColumnCount(
            itemCount: count,
            availableWidth: availableWidth,
            minimumColumnWidth: minimumColumnWidth,
            spacing: spacing)
        guard let availableHeight, availableHeight > 0, count > 1 else { return columns }
        let floorWidth = max(1, narrowestColumnWidth)
        while columns < count {
            let width = self.masonryColumnWidth(
                availableWidth: availableWidth,
                columnCount: columns,
                spacing: spacing)
            let placements = self.masonryPlacements(
                itemHeights: itemHeights,
                columnCount: columns,
                columnWidth: width,
                spacing: spacing)
            if self.masonryContentHeight(of: placements) <= availableHeight {
                return columns
            }
            let nextWidth = self.masonryColumnWidth(
                availableWidth: availableWidth,
                columnCount: columns + 1,
                spacing: spacing)
            if nextWidth < floorWidth {
                return columns
            }
            columns += 1
        }
        return columns
    }

    private enum GlanceKind {
        case session
        case weekly
        case other
    }

    private static func glanceKind(_ metric: UsageBoardMetric) -> GlanceKind {
        let text = self.fold(metric.id + " " + metric.title)
        if text.contains("session") || text.contains("5-hour") || text.contains("5 hour") || text.contains("primary") {
            return .session
        }
        if text.contains("week") || text.contains("secondary") || text.contains("limit") {
            return .weekly
        }
        return .other
    }

    private static func containsMetric(_ metric: UsageBoardMetric, in metrics: [UsageBoardMetric]) -> Bool {
        metrics.contains { $0.id == metric.id }
    }

    /// How many compact stat tiles share a row in the provider detail.
    /// A wide pane uses three columns even for a single tile, so one value does not stretch across the pane.
    package static func metricColumnCount(detailWidth: Double, itemCount: Int) -> Int {
        guard itemCount > 0 else { return 1 }
        if detailWidth >= 640 {
            return 3
        }
        if detailWidth >= 400 {
            return 2
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

    /// Color follows how much allowance is left, not the labeled number.
    /// Above 50 is healthy, 25 through 50 is warning, 1 through 24 is critical, and 0 is empty.
    package static func barTone(percentLeft: Double) -> UsageBoardBarTone {
        let left = min(100, max(0, percentLeft))
        if left <= 0 { return .empty }
        if left < 25 { return .critical }
        if left <= 50 { return .warning }
        return .healthy
    }

    /// `displayedPercent` is the number in the label. `showsUsed` says whether that number is consumed or remaining.
    package static func percentLeft(displayedPercent: Double, showsUsed: Bool) -> Double {
        let displayed = min(100, max(0, displayedPercent))
        if showsUsed { return min(100, max(0, 100 - displayed)) }
        return displayed
    }

    /// Keeps the percent and its used/left word, and drops the rest of a long label.
    package static func explicitPercent(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let percentIndex = trimmed.firstIndex(of: "%") else { return trimmed }
        let after = trimmed.index(after: percentIndex)
        let rest = trimmed[after...].drop { $0 == " " }
        guard let wordEnd = rest.firstIndex(where: \.isWhitespace) else {
            return rest.isEmpty ? String(trimmed[..<after]) : String(trimmed[..<after]) + " " + rest
        }
        let word = rest[..<wordEnd]
        guard word.count <= 16 else { return String(trimmed[..<after]) }
        return String(trimmed[..<after]) + " " + word
    }
}

package enum UsageBoardBarTone: String, Equatable, Sendable {
    case healthy
    case warning
    case critical
    case empty
}

package struct UsageBoardMetric: Equatable, Sendable, Identifiable {
    package let id: String
    package let title: String
    package let percent: Double?
    package let percentText: String
    package let resetText: String?
    package let detailText: String?
    package let pacePercent: Double?
    /// Percent of the allowance still remaining. The bar fill and color use this, not the label.
    package let percentLeft: Double?
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
        percentLeft: Double? = nil,
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
        self.percentLeft = percentLeft
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
    // swiftlint:disable:next function_parameter_count
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

/// SwiftUI adapter for `UsageBoardLayout.masonryPlacements`. Packing math stays testable without SwiftUI.
package struct UsageBoardMasonryLayout: Layout {
    package var minimumColumnWidth: CGFloat
    package var spacing: CGFloat
    /// Above zero, the overview adds columns until the packed stack fits this height.
    package var maximumHeight: CGFloat

    package init(minimumColumnWidth: CGFloat, spacing: CGFloat, maximumHeight: CGFloat = 0) {
        self.minimumColumnWidth = minimumColumnWidth
        self.spacing = spacing
        self.maximumHeight = maximumHeight
    }

    package func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void) -> CGSize
    {
        let width = proposal.width ?? 0
        let plan = self.plan(width: width, subviews: subviews)
        return CGSize(width: max(width, plan.width), height: plan.height)
    }

    package func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void)
    {
        let width = bounds.width > 0 ? bounds.width : (proposal.width ?? 0)
        let plan = self.plan(width: width, subviews: subviews)
        for index in subviews.indices {
            let offset = subviews.distance(from: subviews.startIndex, to: index)
            guard plan.placements.indices.contains(offset) else { continue }
            let placement = plan.placements[offset]
            subviews[index].place(
                at: CGPoint(
                    x: bounds.minX + CGFloat(placement.x),
                    y: bounds.minY + CGFloat(placement.y)),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: CGFloat(placement.width), height: CGFloat(placement.height)))
        }
    }

    private func plan(
        width: CGFloat,
        subviews: Subviews) -> (placements: [UsageBoardMasonryPlacement], width: CGFloat, height: CGFloat)
    {
        let gap = max(0, self.spacing)
        let available = max(0, width)
        let count = subviews.count
        guard count > 0, available > 0 else {
            return ([], available, 0)
        }
        let seedColumns = UsageBoardLayout.masonryColumnCount(
            itemCount: count,
            availableWidth: Double(available),
            minimumColumnWidth: Double(self.minimumColumnWidth),
            spacing: Double(gap))
        let seedWidth = UsageBoardLayout.masonryColumnWidth(
            availableWidth: Double(available),
            columnCount: seedColumns,
            spacing: Double(gap))
        let seedHeights = self.heights(subviews: subviews, columnWidth: seedWidth)
        let columns = UsageBoardLayout.masonryColumnCountFitting(
            itemHeights: seedHeights,
            availableWidth: Double(available),
            availableHeight: self.maximumHeight > 0 ? Double(self.maximumHeight) : nil,
            minimumColumnWidth: Double(self.minimumColumnWidth),
            spacing: Double(gap))
        let columnWidth = UsageBoardLayout.masonryColumnWidth(
            availableWidth: Double(available),
            columnCount: columns,
            spacing: Double(gap))
        let heights = self.heights(subviews: subviews, columnWidth: columnWidth)
        let placements = UsageBoardLayout.masonryPlacements(
            itemHeights: heights,
            columnCount: columns,
            columnWidth: columnWidth,
            spacing: Double(gap))
        let height = UsageBoardLayout.masonryContentHeight(of: placements)
        let usedWidth = placements.map { $0.x + $0.width }.max() ?? Double(available)
        return (placements, CGFloat(usedWidth), CGFloat(height))
    }

    private func heights(subviews: Subviews, columnWidth: Double) -> [Double] {
        let proposal = ProposedViewSize(width: CGFloat(columnWidth), height: nil)
        return subviews.map { subview in
            Double(subview.sizeThatFits(proposal).height)
        }
    }
}
