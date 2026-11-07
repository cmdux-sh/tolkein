import AppKit
import CodexBarCore
import MacDesignSystem
import SwiftUI

// The usage board, built from MacDesignSystem components (see docs/decisions.md):
//
// CodexBar                │ ┌ Codex ─────── Plus ┐ ┌ Cursor ── Cursor Pro ┐
// Overview                │ │ Session  49% left  │ │ Total     29% left   │
//   All providers         │ │ ▬▬▬▬▬▬▬▬▬▬──────── │ │ ▬▬▬▬▬──────────────  │
// Providers               │ └────────────────────┘ └──────────────────────┘
//   Codex           49%   │ ┌ Needs attention ──────────────────────────┐
//   Claude      ⚠   8%    │ │ Claude   ⚠ Sign-in needed                 │
// Classic menu · Refresh… │ └───────────────────────────────────────────┘

struct UsageBoardView: View {
    @Bindable var session: UsageBoardSession

    var body: some View {
        HStack(spacing: 0) {
            UsageBoardSidebar(session: self.session)
                .frame(width: CGFloat(UsageBoardLayout.sidebarWidth))
            Divider()
            UsageBoardDetail(session: self.session)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(MacColor.window)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Shared pieces

enum UsageBoardStatus {
    /// The library tone for a provider that needs attention, or nil when it is ready.
    static func tone(_ attention: UsageBoardAttention) -> MacStatusTone? {
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

    static func meterTone(percentLeft: Double) -> MacMeter.Tone {
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
                MacText(self.monogram, role: .micro, muted: true)
            }
        }
        .frame(width: MacSize.sidebarIcon, height: MacSize.sidebarIcon)
        .foregroundStyle(MacColor.primary)
        .accessibilityHidden(true)
    }
}

// MARK: - Sidebar

private struct UsageBoardSidebar: View {
    @Bindable var session: UsageBoardSession
    private static let allID = "all"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: MacSpace.unit * 2) {
                MacText("CodexBar", role: .title)
                Spacer(minLength: 0)
                if self.session.isRefreshing {
                    ProgressView().controlSize(.small).accessibilityLabel(L("Refreshing"))
                }
            }
            .padding(.horizontal, MacSpace.panelPadding + MacSpace.rowPaddingX)
            .padding(.top, MacSpace.panelPadding)

            MacSourceList(self.sections, selection: self.selection)
                .frame(maxHeight: .infinity)

            Divider()
            UsageBoardFooter(session: self.session)
        }
    }

    private var selection: Binding<String> {
        Binding(
            get: { self.session.selectionID ?? Self.allID },
            set: { self.session.select($0 == Self.allID ? nil : $0) })
    }

    private var sections: [MacSourceSection] {
        let providers = self.session.providers.map { provider in
            let icon = self.session.icon(provider.id)
            return MacSourceItem(
                provider.id,
                provider.name,
                systemImage: "gauge.medium",
                image: icon.map { Image(nsImage: $0).renderingMode($0.isTemplate ? .template : .original) },
                imageID: icon.map { "\(provider.id)-\(ObjectIdentifier($0).hashValue)" },
                detail: provider.attention == .ready
                    ? provider.headlinePercentText.map(UsageBoardLayout.shortPercent) : nil,
                status: UsageBoardStatus.tone(provider.attention))
        }
        return [
            MacSourceSection(L("Overview"), items: [
                MacSourceItem(Self.allID, L("All providers"), systemImage: "square.grid.2x2", detail: nil),
            ]),
            MacSourceSection(L("Providers"), items: providers),
        ]
    }
}

/// App commands: plain buttons in a footer, not rows in the source list (it is for places).
private struct UsageBoardFooter: View {
    let session: UsageBoardSession

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            UsageBoardCommandButton(title: L("Classic menu"), systemImage: "list.bullet.rectangle", kind: .plain) {
                self.session.onCommand(.classicMenu)
            }
            UsageBoardCommandButton(title: L("Refresh"), systemImage: "arrow.clockwise", kind: .plain) {
                self.session.onCommand(.refresh)
            }
            UsageBoardCommandButton(title: L("Settings..."), systemImage: "gearshape", kind: .plain) {
                self.session.onCommand(.settings)
            }
            UsageBoardCommandButton(title: L("Quit"), systemImage: "xmark.rectangle", kind: .plain) {
                self.session.onCommand(.quit)
            }
        }
        .padding(MacSpace.panelPadding)
    }
}

/// A command on the library button at the native large size, with a fixed icon slot so titles line up.
struct UsageBoardCommandButton: View {
    let title: String
    let systemImage: String
    var kind: MacButtonKind = .standard
    let action: () -> Void

    var body: some View {
        Button(action: self.action) {
            HStack(spacing: MacSpace.unit * 2) {
                Image(systemName: self.systemImage)
                    .frame(width: MacSize.sidebarIcon)
                    .foregroundStyle(MacColor.muted)
                Text(self.title)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.mac(self.kind))
        .macControlSize(.large)
        .accessibilityLabel(self.title)
    }
}

// MARK: - Detail

private struct UsageBoardDetail: View {
    @Bindable var session: UsageBoardSession

    var body: some View {
        GeometryReader { proxy in
            if let provider = self.session.selectedProvider {
                ScrollView {
                    UsageBoardProviderDetail(
                        provider: provider,
                        icon: self.session.icon(provider.id),
                        width: proxy.size.width - MacSpace.panelPadding * 2,
                        commands: self.session.providerCommands,
                        onCommand: self.session.onCommand)
                        .padding(MacSpace.panelPadding)
                        .macSlimScrollers()
                }
            } else if self.session.providers.isEmpty {
                Group {
                    if self.session.isShowingSkeleton {
                        MacStatusLabel(L("Refreshing"), tone: .busy)
                    } else {
                        MacText(L("No usage configured."), muted: true)
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
        let inset = MacSpace.panelPadding
        let content = CGSize(width: max(0, self.size.width - inset * 2), height: max(0, self.size.height - inset * 2))
        let ready = self.session.providers.filter { $0.attention == .ready }
        let attention = self.session.providers.filter { $0.attention != .ready }
        return UsageBoardMasonryLayout(
            minimumColumnWidth: CGFloat(UsageBoardLayout.overviewMinimumColumnWidth),
            spacing: MacSpace.chromeGap,
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
        .padding(inset)
        .clipped()
    }
}

private struct UsageBoardOverviewCard: View {
    let provider: UsageBoardProvider
    let icon: NSImage?
    let action: () -> Void

    var body: some View {
        Button(action: self.action) {
            VStack(alignment: .leading, spacing: MacSpace.unit * 2) {
                HStack(spacing: MacSpace.unit * 2) {
                    UsageBoardProviderIcon(monogram: self.provider.monogram, icon: self.icon)
                    MacText(self.provider.name, role: .subtitle)
                        .lineLimit(1)
                    Spacer(minLength: MacSpace.unit)
                    if let plan = self.provider.planText, !plan.isEmpty {
                        MacText(plan, role: .caption, muted: true)
                            .lineLimit(1)
                    }
                }
                let glance = UsageBoardLayout.glanceMetrics(self.provider.metrics)
                if glance.isEmpty {
                    MacText(L("No windows reported yet."), role: .caption, muted: true)
                } else {
                    ForEach(glance) { metric in
                        UsageBoardMetricRow(metric: metric, compact: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .macCard(padding: MacSpace.panelPadding)
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
        VStack(alignment: .leading, spacing: MacSpace.unit * 2) {
            MacText(L("Needs attention"), role: .subtitle)
            ForEach(self.providers) { provider in
                Button { self.select(provider.id) } label: {
                    HStack(spacing: MacSpace.unit * 2) {
                        UsageBoardProviderIcon(monogram: provider.monogram, icon: self.icon(provider.id))
                        MacText(provider.name, role: .body)
                            .lineLimit(1)
                        Spacer(minLength: MacSpace.unit)
                        if let label = UsageBoardStatus.label(provider.attention),
                           let tone = UsageBoardStatus.tone(provider.attention)
                        {
                            MacStatusLabel(label, tone: tone)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel([provider.name, UsageBoardStatus.label(provider.attention)]
                    .compactMap(\.self).joined(separator: ", "))
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .macCard(padding: MacSpace.panelPadding)
    }
}

/// One usage window: label and value on a line, the meter under it, then reset and detail text.
private struct UsageBoardMetricRow: View {
    let metric: UsageBoardMetric
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: MacSpace.unit) {
            HStack(alignment: .firstTextBaseline, spacing: MacSpace.unit * 2) {
                MacText(self.metric.title, role: .caption, muted: true)
                    .lineLimit(1)
                Spacer(minLength: MacSpace.unit)
                Text(self.compact ? UsageBoardLayout.explicitPercent(self.metric.percentText) : self.metric.percentText)
                    .font(MacTextRole.caption.font.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(MacColor.primary)
                    .lineLimit(1)
                if self.compact, let reset = UsageBoardLayout.shortReset(self.metric.resetText) {
                    Text(reset)
                        .font(MacTextRole.caption.font)
                        .monospacedDigit()
                        .foregroundStyle(MacColor.muted)
                        .lineLimit(1)
                }
            }
            if self.metric.showsBar, let left = self.metric.percentLeft {
                MacMeter(
                    self.metric.title,
                    fraction: left / 100,
                    tone: UsageBoardStatus.meterTone(percentLeft: left),
                    marker: self.compact ? nil : self.metric.pacePercent.map { $0 / 100 },
                    valueText: self.metric.percentText)
            }
            if !self.compact, let caption = self.caption {
                MacText(caption, role: .caption, muted: true)
                    .lineLimit(2)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(UsageBoardStatus.accessibilitySummary(self.metric))
    }

    private var caption: String? {
        let parts = [self.metric.resetText, self.metric.detailText].compactMap(\.self)
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

// MARK: - Selected provider

private struct UsageBoardProviderDetail: View {
    let provider: UsageBoardProvider
    let icon: NSImage?
    let width: CGFloat
    let commands: [UsageBoardCommand]
    let onCommand: (UsageBoardCommand.Action) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: MacSpace.tabContentGap) {
            self.header
            self.status
            if !self.commands.isEmpty {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 150), spacing: MacSpace.chromeGap, alignment: .leading)],
                    alignment: .leading,
                    spacing: MacSpace.chromeGap)
                {
                    ForEach(self.commands) { command in
                        UsageBoardCommandButton(title: command.title, systemImage: command.systemImage) {
                            self.onCommand(command.action)
                        }
                    }
                }
            }
            if self.provider.metrics.isEmpty {
                MacText(L("No windows reported yet."), muted: true)
            } else {
                LazyVGrid(
                    columns: self.columns(count: self.provider.metrics.count),
                    alignment: .leading,
                    spacing: MacSpace.chromeGap)
                {
                    ForEach(self.provider.metrics) { metric in
                        UsageBoardMetricRow(metric: metric, compact: false)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .macCard(padding: MacSpace.panelPadding)
                    }
                }
            }
            self.facts
            ForEach(Array(self.notes.enumerated()), id: \.offset) { _, note in
                MacText(note, role: .caption, muted: true)
                    .textSelection(.enabled)
            }
            MacText(L("Charts, accounts, and history stay in the classic menu."), role: .caption, muted: true)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: MacSpace.unit * 2) {
            UsageBoardProviderIcon(monogram: self.provider.monogram, icon: self.icon)
            VStack(alignment: .leading, spacing: MacSpace.unit / 2) {
                HStack(alignment: .firstTextBaseline, spacing: MacSpace.unit * 2) {
                    MacText(self.provider.name, role: .title)
                    if let plan = self.provider.planText, !plan.isEmpty {
                        MacText(plan, role: .caption, muted: true)
                    }
                }
                if !self.provider.email.isEmpty {
                    MacText(self.provider.email, role: .caption, muted: true)
                        .textSelection(.enabled)
                }
            }
        }
    }

    @ViewBuilder private var status: some View {
        if let label = UsageBoardStatus.label(self.provider.attention),
           let tone = UsageBoardStatus.tone(self.provider.attention)
        {
            VStack(alignment: .leading, spacing: MacSpace.unit) {
                MacStatusLabel(label, tone: tone)
                if !self.provider.subtitle.isEmpty, self.provider.subtitle != label {
                    MacText(self.provider.subtitle, role: .caption, muted: true)
                        .textSelection(.enabled)
                }
            }
        } else if !self.provider.subtitle.isEmpty {
            MacText(self.provider.subtitle, role: .caption, muted: true)
        }
    }

    /// Label and value pairs (balances, costs) on one card, like inspector rows.
    @ViewBuilder private var facts: some View {
        let valued = self.provider.lines.filter { !$0.value.isEmpty }
        if !valued.isEmpty {
            VStack(spacing: 0) {
                ForEach(valued) { line in
                    MacInspectorRow(line.label) {
                        Text(line.value)
                            .font(MacTextRole.body.font)
                            .monospacedDigit()
                            .foregroundStyle(MacColor.primary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
            }
            .macCard(padding: MacSpace.panelPadding)
        }
    }

    private var notes: [String] {
        self.provider.notes + self.provider.lines.filter(\.value.isEmpty).map(\.label)
    }

    private func columns(count: Int) -> [GridItem] {
        let n = UsageBoardLayout.metricColumnCount(detailWidth: Double(self.width), itemCount: count)
        return Array(
            repeating: GridItem(.flexible(minimum: 160), spacing: MacSpace.chromeGap, alignment: .top),
            count: max(1, n))
    }
}

#if DEBUG
#Preview("Usage board") {
    UsageBoardView(session: UsageBoardPreviewData.session())
        .frame(width: CGFloat(UsageBoardLayout.preferredWidth), height: CGFloat(UsageBoardLayout.preferredHeight))
}
#endif
