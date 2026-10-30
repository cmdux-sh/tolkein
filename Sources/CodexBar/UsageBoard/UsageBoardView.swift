import AppKit
import SwiftUI

// Layout, at the classic menu's 310pt column × 3 = 930pt:
//
// ┌ Sidebar 248 ┬ Detail ──────────────────────────────────────────┐
// │ All         │ Claude · Pro                          email      │
// │ Claude  42% │ ┌ Session ────┐ ┌ Weekly ─────┐ ┌ Credits ────┐ │
// │ Codex   18% │ │ 42%  2h 14m │ │ 61%  Mon 9a │ │ $12.40 left │ │
// │ Cursor  Sign│ └─────────────┘ └─────────────┘ └─────────────┘ │
// │ Gemini      │ notes, model lanes, and cost lines (scroll)     │
// └─────────────┴──────────────────────────────────────────────────┘
// Footer: classic menu (charts, accounts, agent sessions) · refresh · settings

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
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("CodexBar")
                    .font(UsageBoardTheme.titleFont)
                Text(self.headerCaption)
                    .font(UsageBoardTheme.captionFont)
                    .foregroundStyle(UsageBoardTheme.secondaryText)
            }
            Spacer(minLength: 12)
            if self.session.isRefreshing {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(L("Refreshing"))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var headerCaption: String {
        if let provider = self.session.selectedProvider {
            return provider.name
        }
        if self.session.providers.isEmpty {
            return L("No usage configured.")
        }
        return L("All providers")
    }

    private var footer: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(L("Up and down move between providers. Command-R refreshes. Escape closes."))
                .font(UsageBoardTheme.captionFont)
                .foregroundStyle(UsageBoardTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
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
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var separator: some View {
        Rectangle()
            .fill(UsageBoardTheme.separator)
            .frame(height: 1)
            .accessibilityHidden(true)
    }

    private var separatorVertical: some View {
        Rectangle()
            .fill(UsageBoardTheme.separator)
            .frame(width: 1)
            .accessibilityHidden(true)
    }
}

private struct UsageBoardSidebar: View {
    @Bindable var session: UsageBoardSession

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                UsageBoardSidebarRow(
                    title: L("All providers"),
                    caption: nil,
                    percentText: nil,
                    percent: nil,
                    attention: .ready,
                    monogram: "∗",
                    icon: nil,
                    isSelected: self.session.selectionID == nil,
                    accessibilitySummary: L("All providers"))
                {
                    self.session.select(nil)
                }
                ForEach(self.session.providers) { provider in
                    UsageBoardSidebarRow(
                        title: provider.name,
                        caption: provider.headlineCaption,
                        percentText: provider.headlinePercentText,
                        percent: provider.metrics.first(where: \.showsBar)?.percent,
                        attention: provider.attention,
                        monogram: provider.monogram,
                        icon: self.session.icon(provider.id),
                        isSelected: self.session.selectionID == provider.id,
                        accessibilitySummary: self.accessibilitySummary(for: provider))
                    {
                        self.session.select(provider.id)
                    }
                }
            }
            .padding(8)
        }
        .background(UsageBoardTheme.sidebar)
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
    let title: String
    let caption: String?
    let percentText: String?
    let percent: Double?
    let attention: UsageBoardAttention
    let monogram: String
    let icon: NSImage?
    let isSelected: Bool
    let accessibilitySummary: String
    let action: () -> Void

    var body: some View {
        Button(action: self.action) {
            HStack(alignment: .center, spacing: 8) {
                UsageBoardIconBadge(monogram: self.monogram, icon: self.icon)
                VStack(alignment: .leading, spacing: 2) {
                    Text(self.title)
                        .font(UsageBoardTheme.bodyFont)
                        .fontWeight(.semibold)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let caption, !caption.isEmpty {
                        Text(caption)
                            .font(UsageBoardTheme.captionFont)
                            .foregroundStyle(UsageBoardTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let status = UsageBoardStatusText.label(for: self.attention) {
                        UsageBoardStatusBadge(text: status, attention: self.attention)
                    }
                }
                Spacer(minLength: 6)
                if let percentText {
                    Text(percentText)
                        .font(UsageBoardTheme.percentCompactFont)
                        .foregroundStyle(UsageBoardTheme.percentColor(for: self.percent))
                        .multilineTextAlignment(.trailing)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(self.isSelected ? UsageBoardTheme.selectedRow : Color.clear))
            .overlay(alignment: .leading) {
                if self.isSelected {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(UsageBoardTheme.accent)
                        .frame(width: 3)
                        .padding(.vertical, 8)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(self.accessibilitySummary)
        .accessibilityAddTraits(self.isSelected ? AccessibilityTraits.isSelected : AccessibilityTraits())
    }
}

private struct UsageBoardDetail: View {
    @Bindable var session: UsageBoardSession

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let provider = self.session.selectedProvider {
                        self.focused(provider, width: proxy.size.width)
                    } else if self.session.providers.isEmpty {
                        Text(L("No usage configured."))
                            .font(UsageBoardTheme.bodyFont)
                            .foregroundStyle(UsageBoardTheme.secondaryText)
                    } else {
                        self.overview(width: proxy.size.width)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    private func overview(width: CGFloat) -> some View {
        let contentWidth = max(0, width - 32)
        let columnCount = UsageBoardLayout.metricColumnCount(
            detailWidth: Double(contentWidth),
            itemCount: self.session.providers.count)
        let columnWidth = (contentWidth - 10 * CGFloat(max(0, columnCount - 1))) / CGFloat(columnCount)
        let columns = Array(
            repeating: GridItem(.flexible(minimum: 180), spacing: 10, alignment: .top),
            count: columnCount)
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            ForEach(self.session.providers) { provider in
                Button {
                    self.session.select(provider.id)
                } label: {
                    UsageBoardProviderCard(
                        provider: provider,
                        icon: self.session.icon(provider.id),
                        metricWidth: max(0, columnWidth - 28),
                        commands: [],
                        showsClassicHint: false,
                        onCommand: { _ in })
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func focused(_ provider: UsageBoardProvider, width: CGFloat) -> some View {
        UsageBoardProviderCard(
            provider: provider,
            icon: self.session.icon(provider.id),
            metricWidth: max(0, width - 32 - 28),
            commands: self.session.providerCommands,
            showsClassicHint: true,
            onCommand: self.session.onCommand)
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
        VStack(alignment: .leading, spacing: 12) {
            self.header
            if let status = UsageBoardStatusText.label(for: self.provider.attention) {
                UsageBoardStatusBanner(
                    text: status,
                    detail: self.provider.subtitle,
                    attention: self.provider.attention)
            } else if !self.provider.subtitle.isEmpty {
                Text(self.provider.subtitle)
                    .font(UsageBoardTheme.captionFont)
                    .foregroundStyle(UsageBoardTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            if !self.commands.isEmpty {
                self.commandRow
            }
            if self.provider.metrics.isEmpty {
                Text(L("No windows reported yet."))
                    .font(UsageBoardTheme.bodyFont)
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
                            .font(UsageBoardTheme.captionFont)
                            .foregroundStyle(UsageBoardTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
            }
            if self.showsClassicHint {
                Text(L("Charts, accounts, and history stay in the classic menu."))
                    .font(UsageBoardTheme.captionFont)
                    .foregroundStyle(UsageBoardTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: UsageBoardTheme.cardRadius, style: .continuous)
                .fill(UsageBoardTheme.card))
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            UsageBoardIconBadge(monogram: self.provider.monogram, icon: self.icon)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(self.provider.name)
                        .font(UsageBoardTheme.titleFont)
                    if let plan = self.provider.planText {
                        Text(plan)
                            .font(UsageBoardTheme.captionFont)
                            .foregroundStyle(UsageBoardTheme.secondaryText)
                    }
                }
                if !self.provider.email.isEmpty {
                    Text(self.provider.email)
                        .font(UsageBoardTheme.captionFont)
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
        LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
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
            repeating: GridItem(.flexible(minimum: 150), spacing: 10, alignment: .top),
            count: count)
    }
}

private struct UsageBoardMetricCard: View {
    let metric: UsageBoardMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(self.metric.title)
                .font(UsageBoardTheme.labelFont)
                .foregroundStyle(UsageBoardTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text(self.metric.percentText)
                .font(UsageBoardTheme.percentFont)
                .foregroundStyle(UsageBoardTheme.percentColor(for: self.metric.showsBar ? self.metric.percent : nil))
                .fixedSize(horizontal: false, vertical: true)
            if self.metric.showsBar, let percent = self.metric.percent {
                UsageBoardProgressBar(percent: percent, pacePercent: self.metric.pacePercent)
            }
            if let reset = self.metric.resetText {
                Text(reset)
                    .font(UsageBoardTheme.captionFont)
                    .foregroundStyle(UsageBoardTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let detail = self.metric.detailText {
                Text(detail)
                    .font(UsageBoardTheme.captionFont)
                    .foregroundStyle(UsageBoardTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(UsageBoardTheme.cardRaised))
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
                    .fill(UsageBoardTheme.fill(for: clamped))
                    .frame(width: max(0, width * clamped / 100))
                if let pacePercent {
                    let pace = min(100, max(0, pacePercent))
                    Capsule()
                        .fill(UsageBoardTheme.primaryText)
                        .frame(width: 2, height: 10)
                        .offset(x: max(0, width * pace / 100 - 1))
                }
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }
}

private struct UsageBoardLineList: View {
    let lines: [UsageBoardDetailLine]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(self.lines) { line in
                if line.value.isEmpty {
                    Text(line.label)
                        .font(UsageBoardTheme.bodyFont)
                        .foregroundStyle(UsageBoardTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(line.label)
                            .font(UsageBoardTheme.labelFont)
                            .foregroundStyle(UsageBoardTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(line.value)
                            .font(UsageBoardTheme.bodyFont.monospacedDigit())
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
                    .font(UsageBoardTheme.bodyFont)
                    .foregroundStyle(UsageBoardTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(UsageBoardStatusText.fill(for: self.attention)))
    }
}

private struct UsageBoardStatusBadge: View {
    let text: String
    let attention: UsageBoardAttention

    var body: some View {
        Text(self.text)
            .font(UsageBoardTheme.labelFont)
            .foregroundStyle(UsageBoardStatusText.foreground(for: self.attention))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
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
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(UsageBoardTheme.cardRaised)
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .renderingMode(icon.isTemplate ? .template : .original)
                    .scaledToFit()
                    .padding(4)
                    .foregroundStyle(UsageBoardTheme.primaryText)
            } else {
                Text(self.monogram)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(UsageBoardTheme.primaryText)
            }
        }
        .frame(width: 28, height: 28)
        .accessibilityHidden(true)
    }
}

struct UsageBoardCommandButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: self.action) {
            HStack(spacing: 4) {
                Image(systemName: self.systemImage)
                Text(self.title)
                    .font(UsageBoardTheme.captionFont)
            }
            .foregroundStyle(UsageBoardTheme.primaryText)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(UsageBoardTheme.cardRaised))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(self.title)
    }
}

#if DEBUG
#Preview("Usage board") {
    UsageBoardView(session: UsageBoardPreviewData.session())
        .frame(width: 930, height: 640)
}
#endif
