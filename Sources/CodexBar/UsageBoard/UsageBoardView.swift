import AppKit
import CodexBarCore
import InternalUI
import SwiftUI

// The usage board is a small window in Internal UI's panel chrome (see docs/decisions.md):
//
// ┌──────────────────┐  Claude                                   ↻  ⋯
// │ CodexBar         │  Ultra · Updated 4 mins ago
// │ Providers        │ ┌ Weekly ──── 31% left ┐ ┌ Fable weekly ─ 92% left ┐
// │   All providers  │ │ ▬▬▬▬▬▬──────────────  │ │ ▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬─  │
// │   Claude    31%  │ └──────────────────────┘ └─────────────────────────┘
// │   Codex      ⊗   │ ┌ Today ................................. $358.18 ┐
// │ Classic menu …   │ └ 30d cost ............................ $4,926.79 ┘
// └──────────────────┘

struct UsageBoardView: View {
    @Bindable var session: UsageBoardSession

    var body: some View {
        IUWindow(
            self.title,
            subtitle: self.subtitle,
            chrome: .panel,
            sidebarTitle: "Tolkein",
            sidebarWidth: CGFloat(UsageBoardLayout.sidebarWidth))
        {
            UsageBoardSidebar(session: self.session)
        } toolbar: {
            UsageBoardToolbar(session: self.session)
        } content: {
            UsageBoardDetail(session: self.session)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var title: String {
        self.session.selectedProvider?.name ?? L("All providers")
    }

    private var subtitle: String? {
        if let provider = self.session.selectedProvider {
            let freshness = provider.attention == .ready ? provider.subtitle : nil
            let parts = [provider.planText, freshness].compactMap(\.self).filter { !$0.isEmpty }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        }
        let attention = self.session.providers.filter { $0.attention != .ready }.count
        guard attention > 0 else { return nil }
        return "\(attention) \(L("Needs attention").lowercased())"
    }
}

// MARK: - Shared pieces

enum UsageBoardStatus {
    /// The library tone for a provider that needs attention, or nil when it is ready.
    static func tone(_ attention: UsageBoardAttention) -> IUStatusTone? {
        switch attention {
        case .ready: nil
        case .loading: .busy
        case .needsSignIn: .warning
        case .error: .error
        }
    }

    static func label(_ attention: UsageBoardAttention) -> String? {
        switch attention {
        case .ready: nil
        case .loading: L("Refreshing")
        case .needsSignIn: L("Needs sign-in")
        case .error: L("Couldn't load usage")
        }
    }

    static func meterTone(percentLeft: Double) -> IUMeter.Tone {
        switch UsageBoardLayout.barTone(percentLeft: percentLeft) {
        case .healthy: .accent
        case .warning: .warning
        case .critical, .empty: .critical
        }
    }

    static func accessibilitySummary(_ metric: UsageBoardMetric) -> String {
        guard let left = metric.percentLeft else { return metric.accessibilitySummary }
        let note = switch UsageBoardLayout.barTone(percentLeft: left) {
        case .healthy: L("More than half left")
        case .warning: L("Under half left")
        case .critical: L("Almost out")
        case .empty: L("None left")
        }
        return metric.accessibilitySummary + ", " + note
    }

    /// Notes that only restate facts already shown ("Today: $358.18 · 1B tokens" next to Today and Latest
    /// tokens) are dropped, so each fact appears once.
    static func distinctNotes(_ provider: UsageBoardProvider) -> [String] {
        let shown = provider.lines.flatMap { [$0.label, $0.value] } + provider.metrics.flatMap {
            [$0.percentText, $0.resetText, $0.detailText].compactMap(\.self)
        }
        let notes = provider.notes + provider.lines.filter(\.value.isEmpty).map(\.label)
        return notes.filter { note in
            let figures = self.figures(in: note)
            guard !figures.isEmpty else { return true }
            return !figures.allSatisfy { figure in shown.contains { $0.contains(figure) } }
        }
    }

    /// Money and amounts in a sentence: "$358.18", "1B", "15B".
    static func figures(in text: String) -> [String] {
        text.split(whereSeparator: { $0 == " " || $0 == "·" })
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ":;()")) }
            .filter { token in token.first.map { $0 == "$" || $0.isNumber } ?? false }
    }
}

/// A provider's logo, or its monogram when it has none. Sized like a sidebar icon.
private struct UsageBoardProviderIcon: View {
    let monogram: String
    let icon: NSImage?

    var body: some View {
        Group {
            if let icon {
                Image(nsImage: icon)
                    .renderingMode(icon.isTemplate ? .template : .original)
                    .resizable()
                    .scaledToFit()
            } else {
                IUText(self.monogram, role: .micro, muted: true)
            }
        }
        .frame(width: IUSize.sidebarIcon, height: IUSize.sidebarIcon)
        .foregroundStyle(IUColor.primary)
        .accessibilityHidden(true)
    }
}

// MARK: - Title row

/// The title row's actions: refresh, and the selected provider's other commands in an overflow menu.
private struct UsageBoardToolbar: View {
    let session: UsageBoardSession

    var body: some View {
        HStack(spacing: IUSpace.unit * 2) {
            if self.session.isRefreshing {
                ProgressView().controlSize(.small).accessibilityLabel(L("Refreshing"))
            } else {
                IUToolButton(L("Refresh"), systemImage: "arrow.clockwise", help: L("Refresh") + " (⌘R)") {
                    self.session.onCommand(self.refreshAction)
                }
            }
            let menuCommands = self.session.selectedProvider == nil
                ? [] : self.session.providerCommands.filter { !Self.isRefresh($0) }
            if !menuCommands.isEmpty {
                IUToolMenu(L("More")) {
                    ForEach(menuCommands) { command in
                        Button { self.session.onCommand(command.action) } label: {
                            Label(command.title, systemImage: command.systemImage)
                        }
                    }
                }
            }
        }
    }

    private var refreshAction: UsageBoardCommand.Action {
        if self.session.selectedProvider != nil,
           let refresh = self.session.providerCommands.first(where: Self.isRefresh)
        {
            return refresh.action
        }
        return .refresh
    }

    private static func isRefresh(_ command: UsageBoardCommand) -> Bool {
        switch command.action {
        case .refresh, .refreshProvider: true
        default: false
        }
    }
}

// MARK: - Sidebar

private struct UsageBoardSidebar: View {
    @Bindable var session: UsageBoardSession
    private static let allID = "all"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            IUSourceList([self.section], selection: self.selection)
                .frame(maxHeight: .infinity)
            IUDivider(inset: IUSpace.panelPadding)
            UsageBoardFooter(session: self.session)
        }
    }

    private var selection: Binding<String> {
        Binding(
            get: { self.session.selectionID ?? Self.allID },
            set: { self.session.select($0 == Self.allID ? nil : $0) })
    }

    private var section: IUSourceSection {
        let providers = self.session.providers.map { provider in
            let icon = self.session.icon(provider.id)
            return IUSourceItem(
                provider.id,
                provider.name,
                systemImage: "gauge.medium",
                image: icon.map { Image(nsImage: $0).renderingMode($0.isTemplate ? .template : .original) },
                imageID: icon.map { "\(provider.id)-\(ObjectIdentifier($0).hashValue)" },
                detail: provider.attention == .ready
                    ? provider.headlinePercentText.map(UsageBoardLayout.shortPercent) : nil,
                status: UsageBoardStatus.tone(provider.attention))
        }
        let all = IUSourceItem(Self.allID, L("All providers"), systemImage: "square.grid.2x2", detail: nil)
        return IUSourceSection(L("Providers"), items: [all] + providers)
    }
}

/// App commands: small plain buttons at the foot of the sidebar, not rows in the source list (it is for
/// places).
private struct UsageBoardFooter: View {
    let session: UsageBoardSession

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            self.command(L("Classic menu"), "list.bullet.rectangle", .classicMenu)
            self.command(L("Settings..."), "gearshape", .settings)
            self.command(L("Quit"), "xmark.rectangle", .quit)
        }
        .padding(IUSpace.panelPadding)
        .iuControlSize(.regular)
    }

    private func command(_ title: String, _ symbol: String, _ action: UsageBoardCommand.Action) -> some View {
        Button { self.session.onCommand(action) } label: {
            HStack(spacing: IUSpace.unit * 2) {
                Image(systemName: symbol)
                    .frame(width: IUSize.sidebarIcon)
                    .foregroundStyle(IUColor.muted)
                Text(title)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.iu(.plain))
        .accessibilityLabel(title)
    }
}

// MARK: - Content

private struct UsageBoardDetail: View {
    @Bindable var session: UsageBoardSession

    var body: some View {
        GeometryReader { proxy in
            if let provider = self.session.selectedProvider {
                ScrollView {
                    UsageBoardProviderDetail(
                        provider: provider,
                        width: proxy.size.width - IUSpace.panelPadding * 2)
                        .padding([.horizontal, .bottom], IUSpace.panelPadding)
                        .iuSlimScrollers()
                }
            } else if self.session.providers.isEmpty {
                Group {
                    if self.session.isShowingSkeleton {
                        IUStatusLabel(L("Refreshing"), tone: .busy)
                    } else {
                        IUText(L("No usage configured."), muted: true)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                UsageBoardOverview(session: self.session, size: proxy.size)
            }
        }
    }
}

/// Every provider at a glance. Ready providers get a card each; providers that need attention share one
/// card, so eight identical failures read as one problem.
private struct UsageBoardOverview: View {
    let session: UsageBoardSession
    let size: CGSize

    var body: some View {
        let inset = IUSpace.panelPadding
        let content = CGSize(width: max(0, self.size.width - inset * 2), height: max(0, self.size.height - inset))
        let ready = self.session.providers.filter { $0.attention == .ready }
        let attention = self.session.providers.filter { $0.attention != .ready }
        return UsageBoardMasonryLayout(
            minimumColumnWidth: CGFloat(UsageBoardLayout.overviewMinimumColumnWidth),
            spacing: IUSpace.chromeGap,
            maximumHeight: content.height)
        {
            ForEach(ready) { provider in
                UsageBoardOverviewCard(provider: provider, icon: self.session.icon(provider.id)) {
                    self.session.select(provider.id)
                }
            }
            if !attention.isEmpty {
                UsageBoardAttentionCard(providers: attention, icon: self.session.icon) { id in
                    self.session.select(id)
                }
            }
        }
        .frame(width: content.width, height: content.height, alignment: .topLeading)
        .padding([.horizontal, .bottom], inset)
        .clipped()
    }
}

private struct UsageBoardOverviewCard: View {
    let provider: UsageBoardProvider
    let icon: NSImage?
    let action: () -> Void

    var body: some View {
        Button(action: self.action) {
            VStack(alignment: .leading, spacing: IUSpace.chromeGap) {
                HStack(spacing: IUSpace.unit * 2) {
                    UsageBoardProviderIcon(monogram: self.provider.monogram, icon: self.icon)
                    IUText(self.provider.name, role: .subtitle)
                        .lineLimit(1)
                    Spacer(minLength: IUSpace.unit)
                    if let plan = self.provider.planText, !plan.isEmpty {
                        IUText(plan, role: .caption, muted: true)
                            .lineLimit(1)
                    }
                }
                let glance = UsageBoardLayout.glanceMetrics(self.provider.metrics)
                if glance.isEmpty {
                    IUText(L("No windows reported yet."), role: .caption, muted: true)
                } else {
                    ForEach(glance) { metric in
                        UsageBoardMetricRow(metric: metric, compact: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .iuCard(padding: IUSpace.panelPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(self.accessibilitySummary)
        .accessibilityAddTraits(.isButton)
    }

    private var accessibilitySummary: String {
        ([self.provider.name] + UsageBoardLayout.glanceMetrics(self.provider.metrics)
            .map(UsageBoardStatus.accessibilitySummary))
            .joined(separator: ", ")
    }
}

private struct UsageBoardAttentionCard: View {
    let providers: [UsageBoardProvider]
    let icon: @MainActor (String) -> NSImage?
    let select: (String) -> Void

    var body: some View {
        // When every provider has the same problem, say it once under the title and list the names.
        let labels = Set(self.providers.compactMap { UsageBoardStatus.label($0.attention) })
        let shared = labels.count == 1 ? self.providers.first : nil
        VStack(alignment: .leading, spacing: IUSpace.unit * 2) {
            VStack(alignment: .leading, spacing: IUSpace.unit) {
                IUText(L("Needs attention"), role: .subtitle)
                if let shared, let label = UsageBoardStatus.label(shared.attention),
                   let tone = UsageBoardStatus.tone(shared.attention)
                {
                    IUStatusLabel(label, tone: tone)
                }
            }
            ForEach(self.providers) { provider in
                Button { self.select(provider.id) } label: {
                    HStack(spacing: IUSpace.unit * 2) {
                        UsageBoardProviderIcon(monogram: provider.monogram, icon: self.icon(provider.id))
                        IUText(provider.name, role: .body)
                            .lineLimit(1)
                        Spacer(minLength: IUSpace.unit)
                        if shared == nil, let label = UsageBoardStatus.label(provider.attention),
                           let tone = UsageBoardStatus.tone(provider.attention)
                        {
                            IUStatusLabel(label, tone: tone)
                        }
                    }
                    .frame(
                        maxWidth: .infinity,
                        minHeight: IUControlMetrics.forSize(.regular).height,
                        alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel([provider.name, UsageBoardStatus.label(provider.attention)]
                    .compactMap(\.self).joined(separator: ", "))
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .iuCard(padding: IUSpace.panelPadding)
    }
}

/// One usage window: label and value on a line, the meter under it, then reset and detail lines.
private struct UsageBoardMetricRow: View {
    let metric: UsageBoardMetric
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: IUSpace.unit * 1.5) {
            HStack(alignment: .firstTextBaseline, spacing: IUSpace.unit * 2) {
                IUText(self.metric.title, role: .caption, muted: true)
                    .lineLimit(1)
                Spacer(minLength: IUSpace.unit)
                Text(self.compact ? UsageBoardLayout.explicitPercent(self.metric.percentText) : self.metric.percentText)
                    .font(IUTextRole.subtitle.font)
                    .monospacedDigit()
                    .foregroundStyle(IUColor.primary)
                    .lineLimit(1)
                if self.compact, let reset = UsageBoardLayout.shortReset(self.metric.resetText) {
                    Text(reset)
                        .font(IUTextRole.caption.font)
                        .monospacedDigit()
                        .foregroundStyle(IUColor.muted)
                        .lineLimit(1)
                }
            }
            if self.metric.showsBar, let left = self.metric.percentLeft {
                IUMeter(
                    self.metric.title,
                    fraction: left / 100,
                    tone: UsageBoardStatus.meterTone(percentLeft: left),
                    marker: self.compact ? nil : self.metric.pacePercent.map { $0 / 100 },
                    valueText: self.metric.percentText)
            }
            if !self.compact {
                // One line each, so a long caption never breaks mid-phrase.
                ForEach([self.metric.resetText, self.metric.detailText].compactMap(\.self), id: \.self) { line in
                    IUText(line, role: .caption, muted: true)
                        .lineLimit(1)
                        .help(line)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(UsageBoardStatus.accessibilitySummary(self.metric))
    }
}

// MARK: - Selected provider

private struct UsageBoardProviderDetail: View {
    let provider: UsageBoardProvider
    let width: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: IUSpace.tabContentGap) {
            self.status
            if self.provider.metrics.isEmpty {
                if self.provider.attention == .ready {
                    IUText(L("No windows reported yet."), muted: true)
                }
            } else {
                LazyVGrid(
                    columns: self.columns(count: self.provider.metrics.count),
                    alignment: .leading,
                    spacing: IUSpace.chromeGap)
                {
                    ForEach(self.provider.metrics) { metric in
                        UsageBoardMetricRow(metric: metric, compact: false)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .iuCard(padding: IUSpace.panelPadding)
                    }
                }
            }
            let facts = self.provider.lines.filter { !$0.value.isEmpty }
            if !facts.isEmpty {
                IUKeyValueList(facts.map { IUKeyValueList.Row($0.label, $0.value, id: $0.id) })
                    .padding(.horizontal, IUSpace.panelPadding)
                    .iuCard(padding: 0)
            }
            let notes = UsageBoardStatus.distinctNotes(self.provider)
            if !notes.isEmpty || !self.provider.email.isEmpty {
                VStack(alignment: .leading, spacing: IUSpace.unit) {
                    ForEach(Array(notes.enumerated()), id: \.offset) { _, note in
                        IUText(note, role: .caption, muted: true)
                            .textSelection(.enabled)
                    }
                    if !self.provider.email.isEmpty {
                        IUText(self.provider.email, role: .caption, muted: true)
                            .textSelection(.enabled)
                    }
                    IUText(L("Charts, accounts, and history stay in the classic menu."), role: .caption, muted: true)
                }
                .padding(.horizontal, IUSpace.unit)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var status: some View {
        if let label = UsageBoardStatus.label(self.provider.attention),
           let tone = UsageBoardStatus.tone(self.provider.attention)
        {
            VStack(alignment: .leading, spacing: IUSpace.unit) {
                IUStatusLabel(label, tone: tone)
                if !self.provider.subtitle.isEmpty, self.provider.subtitle != label {
                    IUText(self.provider.subtitle, role: .caption, muted: true)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .iuCard(padding: IUSpace.panelPadding)
        }
    }

    private func columns(count: Int) -> [GridItem] {
        let n = UsageBoardLayout.metricColumnCount(detailWidth: Double(self.width), itemCount: count)
        return Array(
            repeating: GridItem(.flexible(minimum: 160), spacing: IUSpace.chromeGap, alignment: .top),
            count: max(1, n))
    }
}

#if DEBUG
#Preview("Usage board") {
    UsageBoardView(session: UsageBoardPreviewData.session())
        .frame(width: CGFloat(UsageBoardLayout.preferredWidth), height: CGFloat(UsageBoardLayout.preferredHeight))
}
#endif
