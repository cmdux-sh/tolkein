import AppKit
import CodexBarCore
import SwiftUI

// The board grows toward the visible screen (floor 930, cap 1560):
//
// ┌ Sidebar 248 ┬ Detail, masonry, no scroll on All ──────────────┐
// │ All         │ Claude   Session ████ 42%  2h    Weekly ██ 61%  │
// │ Claude  42% │ Codex    Session ██ 18%  4h      Weekly █ 12%   │
// │ Codex   18% │ Cursor   Needs sign-in                          │
// │ Cursor  Sign│ Gemini   Session ████ 70%  1d                   │
// └─────────────┴──────────────────────────────────────────────────┘
// One provider still scrolls and keeps credits, notes, and commands.

struct UsageBoardView: View {
    @Bindable var session: UsageBoardSession

    var body: some View {
        VStack(spacing: 0) {
            self.header
            self.separator
            HStack(spacing: 0) {
                UsageBoardSidebar(session: self.session)
                    .frame(width: UsageBoardTheme.sidebarWidth)
                self.separatorVertical
                UsageBoardDetail(session: self.session)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            self.separator
            self.footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(UsageBoardTheme.canvas)
        .foregroundStyle(UsageBoardTheme.primaryText)
        .environment(\.colorScheme, .dark)
        .preferredColorScheme(.dark)
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: UsageBoardMetrics.gapComfortable) {
            VStack(alignment: .leading, spacing: UsageBoardMetrics.gap) {
                Text("CodexBar")
                    .boardFont(.title)
                Text(self.headerCaption)
                    .boardFont(.caption)
                    .foregroundStyle(UsageBoardTheme.secondaryText)
            }
            Spacer(minLength: 12)
            if self.session.isRefreshing {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(L("Refreshing"))
            }
        }
        .padding(.horizontal, UsageBoardMetrics.windowPad)
        .padding(.vertical, UsageBoardMetrics.pad)
    }

    private var headerCaption: String {
        if let provider = self.session.selectedProvider {
            return provider.name
        }
        if self.session.isShowingSkeleton, self.session.providers.isEmpty {
            return L("Refreshing")
        }
        if self.session.providers.isEmpty {
            return L("No usage configured.")
        }
        return L("All providers")
    }

    private var footer: some View {
        HStack(alignment: .center, spacing: UsageBoardMetrics.gap) {
            Text(L("Up and down move between providers. Command-R refreshes. Escape closes."))
                .boardFont(.caption)
                .foregroundStyle(UsageBoardTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: UsageBoardMetrics.gapComfortable)
            UsageBoardCommandButton(
                title: L("Classic menu"),
                systemImage: "list.bullet.rectangle",
                action: { self.session.onCommand(.classicMenu) })
            UsageBoardCommandButton(
                title: L("Refresh"),
                systemImage: "arrow.clockwise",
                action: { self.session.onCommand(.refresh) })
            UsageBoardCommandButton(
                title: L("Settings..."),
                systemImage: "gearshape",
                action: { self.session.onCommand(.settings) })
            UsageBoardCommandButton(
                title: L("Quit"),
                systemImage: "xmark.rectangle",
                action: { self.session.onCommand(.quit) })
        }
        .padding(.horizontal, UsageBoardMetrics.windowPad)
        .padding(.vertical, UsageBoardMetrics.pad)
    }

    private var separator: some View {
        Rectangle()
            .fill(UsageBoardTheme.hairline)
            .frame(height: 1)
            .accessibilityHidden(true)
    }

    private var separatorVertical: some View {
        Rectangle()
            .fill(UsageBoardTheme.hairline)
            .frame(width: 1)
            .accessibilityHidden(true)
    }
}

private struct UsageBoardSidebar: View {
    @Bindable var session: UsageBoardSession
    @State private var hoveredID: String?
    @State private var frames: [String: CGRect] = [:]
    @State private var restingFrame: CGRect = .zero
    @FocusState private var focusedID: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            ZStack(alignment: .topLeading) {
                self.hoverHighlight
                VStack(alignment: .leading, spacing: 0) {
                    self.allRow
                    if self.session.isShowingSkeleton, self.session.providers.isEmpty {
                        ForEach(0..<4, id: \.self) { _ in
                            UsageBoardSkeletonRow()
                        }
                    }
                    ForEach(self.session.providers) { provider in
                        self.providerRow(provider)
                    }
                }
            }
            .coordinateSpace(name: "usageBoardSidebar")
            .padding(UsageBoardMetrics.pad)
            .onPreferenceChange(UsageBoardRowFramesKey.self) { frames in
                guard frames != self.frames else { return }
                self.frames = frames
                if let hoveredID, let frame = frames[hoveredID] {
                    self.restingFrame = frame
                }
            }
        }
        .background(UsageBoardTheme.surface)
    }

    private var hoverHighlight: some View {
        let frame = self.frames[self.hoveredID ?? ""] ?? self.restingFrame
        let visible = self.hoveredID != nil && frame != .zero
        return RoundedRectangle(cornerRadius: UsageBoardMetrics.radiusItem, style: .continuous)
            .fill(UsageBoardTheme.hover)
            .frame(width: frame.width, height: frame.height)
            .offset(x: frame.minX, y: frame.minY)
            .opacity(visible ? 1 : 0)
            .allowsHitTesting(false)
            .animation(self.reduceMotion ? nil : UsageBoardMotion.fastSpring, value: frame)
            .animation(UsageBoardMotion.fastExitTween, value: visible)
    }

    private var allRow: some View {
        UsageBoardSidebarRow(
            id: "all",
            title: L("All providers"),
            caption: nil,
            percentText: nil,
            attention: .ready,
            monogram: "∗",
            icon: nil,
            isSelected: self.session.selectionID == nil,
            isFocused: self.focusedID == "all",
            accessibilitySummary: L("All providers"),
            focus: self.$focusedID)
        {
            self.session.select(nil)
        }
        .onHover { inside in
            self.hoveredID = inside ? "all" : (self.hoveredID == "all" ? nil : self.hoveredID)
        }
    }

    private func providerRow(_ provider: UsageBoardProvider) -> some View {
        UsageBoardSidebarRow(
            id: provider.id,
            title: provider.name,
            caption: provider.headlineCaption,
            percentText: provider.headlinePercentText,
            attention: provider.attention,
            monogram: provider.monogram,
            icon: self.session.icon(provider.id),
            isSelected: self.session.selectionID == provider.id,
            isFocused: self.focusedID == provider.id,
            accessibilitySummary: self.accessibilitySummary(for: provider),
            focus: self.$focusedID)
        {
            self.session.select(provider.id)
        }
        .onHover { inside in
            self.hoveredID = inside ? provider.id : (self.hoveredID == provider.id ? nil : self.hoveredID)
        }
    }

    private func accessibilitySummary(for provider: UsageBoardProvider) -> String {
        var parts = [provider.name]
        if let status = UsageBoardStatusText.label(for: provider.attention) {
            parts.append(status)
        }
        if let headline = provider.headlinePercentText {
            parts.append(headline)
        }
        if let caption = provider.headlineCaption {
            parts.append(caption)
        }
        if provider.attention != .ready, !provider.subtitle.isEmpty {
            parts.append(provider.subtitle)
        }
        return parts.joined(separator: ", ")
    }
}

private struct UsageBoardSidebarRow: View {
    let id: String
    let title: String
    let caption: String?
    let percentText: String?
    let attention: UsageBoardAttention
    let monogram: String
    let icon: NSImage?
    let isSelected: Bool
    let isFocused: Bool
    let accessibilitySummary: String
    var focus: FocusState<String?>.Binding
    let action: () -> Void

    var body: some View {
        Button(action: self.action) {
            HStack(alignment: .center, spacing: UsageBoardMetrics.gapComfortable) {
                UsageBoardIconBadge(monogram: self.monogram, icon: self.icon)
                VStack(alignment: .leading, spacing: 0) {
                    Text(self.title)
                        .boardFont(.subtitle, weight: self.isSelected ? .semibold : .regular)
                        .lineLimit(1)
                        .multilineTextAlignment(.leading)
                    if let caption, !caption.isEmpty {
                        Text(caption)
                            .boardFont(.micro)
                            .foregroundStyle(UsageBoardTheme.secondaryText)
                            .lineLimit(1)
                    }
                    if let status = UsageBoardStatusText.label(for: self.attention) {
                        UsageBoardStatusBadge(text: status, attention: self.attention)
                    }
                }
                Spacer(minLength: UsageBoardMetrics.gap)
                if let percentText {
                    Text(percentText)
                        .boardFont(.caption, weight: .semibold)
                        .foregroundStyle(UsageBoardTheme.primaryText)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, UsageBoardMetrics.padComfortable)
            .padding(.vertical, UsageBoardMetrics.pad)
            .frame(maxWidth: .infinity, minHeight: UsageBoardMetrics.control, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: UsageBoardMetrics.radiusItem, style: .continuous)
                    .fill(self.isSelected ? UsageBoardTheme.selectionFill : Color.clear))
            .overlay {
                if self.isFocused {
                    RoundedRectangle(cornerRadius: UsageBoardMetrics.radiusItem, style: .continuous)
                        .strokeBorder(UsageBoardTheme.accent, lineWidth: UsageBoardMetrics.focusRing)
                }
            }
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .preference(
                            key: UsageBoardRowFramesKey.self,
                            value: [self.id: proxy.frame(in: .named("usageBoardSidebar"))])
                        .allowsHitTesting(false)
                }
                .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(UsageBoardHitButtonStyle())
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .focused(self.focus, equals: self.id)
        .accessibilityLabel(self.accessibilitySummary)
        .accessibilityAddTraits(self.isSelected ? AccessibilityTraits.isSelected : AccessibilityTraits())
    }
}

private struct UsageBoardDetail: View {
    @Bindable var session: UsageBoardSession

    var body: some View {
        GeometryReader { proxy in
            if let provider = self.session.selectedProvider {
                ScrollView {
                    self.selectedProviderDetail(provider, width: proxy.size.width)
                        .padding(UsageBoardMetrics.windowPad)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            } else if self.session.isShowingSkeleton, self.session.providers.isEmpty {
                UsageBoardSkeletonDetail()
                    .padding(UsageBoardMetrics.windowPad)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .accessibilityLabel(L("Refreshing"))
            } else if self.session.providers.isEmpty {
                Text(L("No usage configured."))
                    .boardFont(.body)
                    .foregroundStyle(UsageBoardTheme.secondaryText)
                    .padding(UsageBoardMetrics.windowPad)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                self.overview(size: proxy.size)
            }
        }
    }

    private func overview(size: CGSize) -> some View {
        let inset = UsageBoardMetrics.windowPad
        let contentWidth = max(0, size.width - inset * 2)
        let contentHeight = max(0, size.height - inset * 2)
        return UsageBoardMasonryLayout(
            minimumColumnWidth: CGFloat(UsageBoardLayout.overviewMinimumColumnWidth),
            spacing: UsageBoardMetrics.gap,
            maximumHeight: contentHeight)
        {
            ForEach(self.session.providers) { provider in
                UsageBoardOverviewCard(
                    provider: provider,
                    icon: self.session.icon(provider.id))
                {
                    self.session.select(provider.id)
                }
            }
        }
        .frame(width: contentWidth, height: contentHeight, alignment: .topLeading)
        .clipped()
        .padding(inset)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    private func selectedProviderDetail(_ provider: UsageBoardProvider, width: CGFloat) -> some View {
        UsageBoardProviderCard(
            provider: provider,
            icon: self.session.icon(provider.id),
            metricWidth: max(0, width - UsageBoardMetrics.windowPad * 2 - UsageBoardMetrics.pad * 2),
            commands: self.session.providerCommands,
            showsClassicHint: true,
            onCommand: self.session.onCommand)
    }
}

private struct UsageBoardOverviewCard: View {
    let provider: UsageBoardProvider
    let icon: NSImage?
    let action: () -> Void

    var body: some View {
        Button(action: self.action) {
            VStack(alignment: .leading, spacing: UsageBoardMetrics.gap) {
                self.header
                let glance = UsageBoardLayout.glanceMetrics(self.provider.metrics)
                if glance.isEmpty, self.provider.attention == .ready {
                    Text(L("No windows reported yet."))
                        .boardFont(.micro)
                        .foregroundStyle(UsageBoardTheme.secondaryText)
                        .lineLimit(1)
                } else {
                    ForEach(glance) { metric in
                        UsageBoardGlanceMetric(metric: metric)
                    }
                }
            }
            .padding(UsageBoardMetrics.pad)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: UsageBoardMetrics.radiusCard, style: .continuous)
                    .fill(UsageBoardTheme.card))
            .boardHairline(radius: UsageBoardMetrics.radiusCard)
            .contentShape(RoundedRectangle(cornerRadius: UsageBoardMetrics.radiusCard, style: .continuous))
        }
        .buttonStyle(UsageBoardHitButtonStyle())
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: UsageBoardMetrics.radiusCard, style: .continuous))
        .accessibilityLabel(self.accessibilitySummary)
    }

    private var header: some View {
        HStack(spacing: UsageBoardMetrics.gap) {
            UsageBoardIconBadge(monogram: self.provider.monogram, icon: self.icon)
            Text(self.provider.name)
                .boardFont(.subtitle, weight: .semibold)
                .lineLimit(1)
            Spacer(minLength: UsageBoardMetrics.gap)
            if self.provider.attention != .ready,
               let status = UsageBoardStatusText.label(for: self.provider.attention)
            {
                UsageBoardStatusBadge(text: status, attention: self.provider.attention)
            } else if let plan = self.provider.planText, !plan.isEmpty {
                Text(plan)
                    .boardFont(.micro)
                    .foregroundStyle(UsageBoardTheme.secondaryText)
                    .lineLimit(1)
            }
        }
    }

    private var accessibilitySummary: String {
        var parts = [self.provider.name]
        if let status = UsageBoardStatusText.label(for: self.provider.attention) {
            parts.append(status)
        }
        let glance = UsageBoardLayout.glanceMetrics(self.provider.metrics)
        parts.append(contentsOf: glance.map(\.accessibilitySummary))
        return parts.joined(separator: ", ")
    }
}

private struct UsageBoardGlanceMetric: View {
    let metric: UsageBoardMetric

    var body: some View {
        VStack(alignment: .leading, spacing: UsageBoardMetrics.gap) {
            HStack(spacing: UsageBoardMetrics.gap) {
                Text(self.metric.title)
                    .boardFont(.micro)
                    .foregroundStyle(UsageBoardTheme.secondaryText)
                    .lineLimit(1)
                Spacer(minLength: UsageBoardMetrics.gap)
                Text(UsageBoardLayout.shortPercent(self.metric.percentText))
                    .boardFont(.caption, weight: .semibold, digits: true)
                    .foregroundStyle(UsageBoardTheme.primaryText)
                    .lineLimit(1)
                if let reset = UsageBoardLayout.shortReset(self.metric.resetText) {
                    Text(reset)
                        .boardFont(.micro, digits: true)
                        .foregroundStyle(UsageBoardTheme.secondaryText)
                        .lineLimit(1)
                }
            }
            if self.metric.showsBar, let percent = self.metric.percent {
                UsageBoardProgressBar(percent: percent, pacePercent: nil)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct UsageBoardHitButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
    }
}

private struct UsageBoardProviderCard: View {
    let provider: UsageBoardProvider
    let icon: NSImage?
    let metricWidth: CGFloat
    let commands: [UsageBoardCommand]
    let showsClassicHint: Bool
    let onCommand: (UsageBoardCommand.Action) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: UsageBoardMetrics.gapComfortable) {
            self.header
            if let status = UsageBoardStatusText.label(for: self.provider.attention) {
                UsageBoardStatusBanner(
                    text: status,
                    detail: self.provider.subtitle,
                    attention: self.provider.attention)
            } else if !self.provider.subtitle.isEmpty {
                Text(self.provider.subtitle)
                    .boardFont(.caption)
                    .foregroundStyle(UsageBoardTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            if !self.commands.isEmpty {
                self.commandRow
            }
            if self.provider.metrics.isEmpty {
                Text(L("No windows reported yet."))
                    .boardFont(.body)
                    .foregroundStyle(UsageBoardTheme.secondaryText)
            } else {
                UsageBoardMetricGrid(metrics: self.provider.metrics, width: self.metricWidth)
            }
            if !self.provider.lines.isEmpty {
                UsageBoardLineList(lines: self.provider.lines)
            }
            if !self.provider.notes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(self.provider.notes.enumerated()), id: \.offset) { _, note in
                        Text(note)
                            .boardFont(.caption)
                            .foregroundStyle(UsageBoardTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
            }
            if self.showsClassicHint {
                Text(L("Charts, accounts, and history stay in the classic menu."))
                    .boardFont(.caption)
                    .foregroundStyle(UsageBoardTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(UsageBoardMetrics.pad)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: UsageBoardMetrics.radiusCard, style: .continuous)
                .fill(UsageBoardTheme.card))
        .boardHairline(radius: UsageBoardMetrics.radiusCard)
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: UsageBoardMetrics.gapComfortable) {
            UsageBoardIconBadge(monogram: self.provider.monogram, icon: self.icon)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: UsageBoardMetrics.gapComfortable) {
                    Text(self.provider.name)
                        .boardFont(.title)
                    if let plan = self.provider.planText {
                        Text(plan)
                            .boardFont(.caption)
                            .foregroundStyle(UsageBoardTheme.secondaryText)
                    }
                }
                if !self.provider.email.isEmpty {
                    Text(self.provider.email)
                        .boardFont(.caption)
                        .foregroundStyle(UsageBoardTheme.secondaryText)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
        }
    }

    private var commandRow: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 148), spacing: 6, alignment: .leading)],
            alignment: .leading,
            spacing: 6)
        {
            ForEach(self.commands) { command in
                UsageBoardCommandButton(
                    title: command.title,
                    systemImage: command.systemImage)
                {
                    self.onCommand(command.action)
                }
            }
        }
    }
}

private struct UsageBoardMetricGrid: View {
    let metrics: [UsageBoardMetric]
    let width: CGFloat

    var body: some View {
        let columns = self.columns
        LazyVGrid(columns: columns, alignment: .leading, spacing: UsageBoardMetrics.gap) {
            ForEach(self.metrics) { metric in
                UsageBoardMetricCard(metric: metric)
            }
        }
    }

    private var columns: [GridItem] {
        let count = UsageBoardLayout.metricColumnCount(
            detailWidth: Double(self.width),
            itemCount: self.metrics.count)
        return Array(
            repeating: GridItem(.flexible(minimum: 150), spacing: UsageBoardMetrics.gap, alignment: .top),
            count: count)
    }
}

private struct UsageBoardMetricCard: View {
    let metric: UsageBoardMetric

    var body: some View {
        VStack(alignment: .leading, spacing: UsageBoardMetrics.gap) {
            Text(self.metric.title)
                .boardFont(.micro)
                .foregroundStyle(UsageBoardTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text(self.metric.percentText)
                .boardFont(.percent)
                .foregroundStyle(UsageBoardTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            if self.metric.showsBar, let percent = self.metric.percent {
                UsageBoardProgressBar(percent: percent, pacePercent: self.metric.pacePercent)
            }
            if let reset = self.metric.resetText {
                Text(reset)
                    .boardFont(.caption)
                    .foregroundStyle(UsageBoardTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let detail = self.metric.detailText {
                Text(detail)
                    .boardFont(.micro)
                    .foregroundStyle(UsageBoardTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(UsageBoardMetrics.pad)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: UsageBoardMetrics.nestedRadius(
                outer: UsageBoardMetrics.radiusCard,
                pad: UsageBoardMetrics.pad), style: .continuous)
                .fill(UsageBoardTheme.cardRaised))
        .boardHairline(radius: UsageBoardMetrics.nestedRadius(
            outer: UsageBoardMetrics.radiusCard,
            pad: UsageBoardMetrics.pad))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(self.metric.accessibilitySummary)
    }
}

private struct UsageBoardProgressBar: View {
    let percent: Double
    let pacePercent: Double?

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let clamped = min(100, max(0, self.percent))
            ZStack(alignment: .leading) {
                Capsule().fill(UsageBoardTheme.track)
                Capsule()
                    .fill(UsageBoardTheme.barFill(for: clamped))
                    .frame(width: max(0, width * clamped / 100))
                if let pacePercent {
                    let pace = min(100, max(0, pacePercent))
                    Capsule()
                        .fill(UsageBoardTheme.primaryText)
                        .frame(width: 1, height: UsageBoardMetrics.progress + 4)
                        .offset(x: max(0, width * pace / 100 - 1))
                }
            }
        }
        .frame(height: UsageBoardMetrics.progress)
        .accessibilityHidden(true)
    }
}

private struct UsageBoardLineList: View {
    let lines: [UsageBoardDetailLine]

    var body: some View {
        VStack(alignment: .leading, spacing: UsageBoardMetrics.gap) {
            ForEach(self.lines) { line in
                if line.value.isEmpty {
                    Text(line.label)
                        .boardFont(.body)
                        .foregroundStyle(UsageBoardTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(line.label)
                            .boardFont(.micro)
                            .foregroundStyle(UsageBoardTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(line.value)
                            .boardFont(.body, digits: true)
                            .foregroundStyle(UsageBoardTheme.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

private struct UsageBoardStatusBanner: View {
    let text: String
    let detail: String
    let attention: UsageBoardAttention

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            UsageBoardStatusBadge(text: self.text, attention: self.attention)
            if !self.detail.isEmpty, self.detail != self.text {
                Text(self.detail)
                    .boardFont(.body)
                    .foregroundStyle(UsageBoardTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .padding(UsageBoardMetrics.pad)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: UsageBoardMetrics.radiusItem, style: .continuous)
                .fill(UsageBoardStatusText.fill(for: self.attention)))
        .boardHairline(radius: UsageBoardMetrics.radiusItem)
    }
}

private struct UsageBoardStatusBadge: View {
    let text: String
    let attention: UsageBoardAttention

    var body: some View {
        Text(self.text)
            .boardFont(.micro)
            .foregroundStyle(UsageBoardStatusText.foreground(for: self.attention))
            .padding(.horizontal, UsageBoardMetrics.pad)
            .padding(.vertical, 1)
            .background(Capsule().fill(UsageBoardStatusText.fill(for: self.attention)))
    }
}

private enum UsageBoardStatusText {
    static func label(for attention: UsageBoardAttention) -> String? {
        switch attention {
        case .needsSignIn:
            L("Needs sign-in")
        case .error:
            L("Couldn't load usage")
        case .loading:
            L("Refreshing")
        case .ready:
            nil
        }
    }

    static func fill(for attention: UsageBoardAttention) -> Color {
        switch attention {
        case .needsSignIn, .loading:
            UsageBoardTheme.signInFill
        case .error:
            UsageBoardTheme.errorFill
        case .ready:
            UsageBoardTheme.cardRaised
        }
    }

    static func foreground(for attention: UsageBoardAttention) -> Color {
        switch attention {
        case .needsSignIn, .loading:
            UsageBoardTheme.signInText
        case .error:
            UsageBoardTheme.errorText
        case .ready:
            UsageBoardTheme.secondaryText
        }
    }
}

private struct UsageBoardIconBadge: View {
    let monogram: String
    let icon: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(UsageBoardTheme.cardRaised)
                .boardHairline(radius: 4)
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .renderingMode(icon.isTemplate ? .template : .original)
                    .scaledToFit()
                    .padding(1)
                    .foregroundStyle(UsageBoardTheme.primaryText)
            } else {
                Text(self.monogram)
                    .boardFont(.micro, weight: .semibold)
                    .foregroundStyle(UsageBoardTheme.primaryText)
            }
        }
        .frame(width: UsageBoardMetrics.icon, height: UsageBoardMetrics.icon)
        .accessibilityHidden(true)
    }
}

struct UsageBoardCommandButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: self.action) {
            HStack(spacing: UsageBoardMetrics.gap) {
                Image(systemName: self.systemImage)
                    .font(.system(size: 14, weight: .regular))
                Text(self.title)
                    .boardFont(.caption)
            }
            .foregroundStyle(UsageBoardTheme.primaryText)
            .padding(.horizontal, 10)
            .frame(minHeight: UsageBoardMetrics.control)
            .background(
                RoundedRectangle(cornerRadius: UsageBoardMetrics.radiusItem, style: .continuous)
                    .fill(UsageBoardTheme.card))
            .boardHairline(radius: UsageBoardMetrics.radiusItem)
            .contentShape(Rectangle())
        }
        .buttonStyle(UsageBoardHitButtonStyle())
        .accessibilityLabel(self.title)
    }
}

private struct UsageBoardSkeletonRow: View {
    var body: some View {
        RoundedRectangle(cornerRadius: UsageBoardMetrics.radiusItem, style: .continuous)
            .fill(UsageBoardTheme.card)
            .frame(height: UsageBoardMetrics.control)
            .accessibilityHidden(true)
    }
}

private struct UsageBoardSkeletonDetail: View {
    var body: some View {
        VStack(alignment: .leading, spacing: UsageBoardMetrics.gap) {
            RoundedRectangle(cornerRadius: UsageBoardMetrics.radiusCard, style: .continuous)
                .fill(UsageBoardTheme.card)
                .frame(height: 36)
            HStack(spacing: UsageBoardMetrics.gap) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: UsageBoardMetrics.radiusItem, style: .continuous)
                        .fill(UsageBoardTheme.cardRaised)
                        .frame(height: 64)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("Usage board") {
    UsageBoardView(session: UsageBoardPreviewData.session())
        .frame(width: 1280, height: 860)
}
#endif
