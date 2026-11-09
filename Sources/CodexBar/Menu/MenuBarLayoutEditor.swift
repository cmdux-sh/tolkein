import AppKit
import CodexBarCore
import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let codexBarMenuLayoutItem = UTType(exportedAs: "com.steipete.codexbar.menu-layout-item")
}

struct MenuBarLayoutPosition: Codable, Hashable, Sendable {
    let line: Int
    let index: Int
}

struct MenuBarLayoutDragItem: Codable, Hashable, Transferable, Sendable {
    enum Content: Codable, Hashable, Sendable {
        case token(MenuBarLayoutToken)
        case lineBreak
    }

    let content: Content
    let source: MenuBarLayoutPosition?
    let sourceLayout: MenuBarLayout?

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .codexBarMenuLayoutItem)
    }

    static func palette(_ component: MenuBarLayoutToken) -> Self {
        Self(content: .token(component), source: nil, sourceLayout: nil)
    }

    static func placed(
        _ component: MenuBarLayoutToken,
        at source: MenuBarLayoutPosition,
        in layout: MenuBarLayout)
        -> Self
    {
        Self(content: .token(component), source: source, sourceLayout: layout)
    }

    static let lineBreak = Self(content: .lineBreak, source: nil, sourceLayout: nil)
}

enum MenuBarLayoutPaletteTokens {
    static func usage(provider: UsageProvider?, snapshot: UsageSnapshot?) -> [MenuBarLayoutToken] {
        [
            .percent(window: .session),
            .percent(window: .weekly),
            .percent(window: .scopedWeekly),
            .percent(window: .spend),
        ] + MenuBarLayoutLane.available(for: provider, snapshot: snapshot).map { .lanePercent(lane: $0) }
            + MenuBarLayoutNamedExtra.availableTokens(provider: provider, snapshot: snapshot) + [
                .percent(window: .automatic),
                .usageBar,
                .progressBar(window: .session),
                .progressBar(window: .weekly),
                .progressBar(window: .scopedWeekly),
                .progressBar(window: .automatic),
                .tokensPerMinute,
                .tokensSparkline,
                .pace(window: .session),
                .pace(window: .weekly),
                .pace(window: .automatic),
                .pace(window: .spend),
            ]
    }

    static let time: [MenuBarLayoutToken] = [
        .resetCountdown,
        .resetAbsolute,
        .windowResetCountdown(window: .session),
        .windowResetAbsolute(window: .session),
        .windowResetCountdown(window: .weekly),
        .windowResetAbsolute(window: .weekly),
        .windowResetCountdown(window: .spend),
        .windowResetAbsolute(window: .spend),
        .runsOut,
        .runsOutCompact,
    ]

    static let conditionalBranch: [MenuBarLayoutToken] = [
        .icon,
        .providerName,
        .accountLabel,
        .percent(window: .session),
        .percent(window: .weekly),
        .percent(window: .scopedWeekly),
        .percent(window: .spend),
        .percent(window: .automatic),
        .usageBar,
        .progressBar(window: .session),
        .progressBar(window: .weekly),
        .progressBar(window: .scopedWeekly),
        .progressBar(window: .automatic),
        .pace(window: .session),
        .pace(window: .weekly),
        .pace(window: .automatic),
        .pace(window: .spend),
    ] + Self.time + [
        .balance,
        .costToday,
        .tokensPerMinute,
        .tokensSparkline,
        .costWindow,
        .spendAmount,
        .spendBudget,
        .separatorDot,
    ] + MenuBarLayoutSeparator.allCases.map(MenuBarLayoutToken.separator) + [
        .space,
        .hidden,
    ]
}

enum MenuBarLayoutEditorMutations {
    static func append(_ component: MenuBarLayoutToken, to layout: MenuBarLayout) -> MenuBarLayout {
        var lines = layout.lines
        let line = max(0, lines.count - 1)
        lines[line].append(component)
        return MenuBarLayout(lines: lines)
    }

    static func insert(
        _ item: MenuBarLayoutDragItem,
        at target: MenuBarLayoutPosition,
        in layout: MenuBarLayout)
        -> MenuBarLayout
    {
        if case .lineBreak = item.content {
            return self.addLineBreak(to: layout, at: target.index)
        }

        guard case let .token(token) = item.content else { return layout }
        var lines = layout.lines
        guard !lines.isEmpty else { return MenuBarLayout(lines: [[token]]) }
        var targetLine = min(max(target.line, 0), lines.count - 1)
        var targetIndex = min(max(target.index, 0), lines[targetLine].count)

        if let source = item.source {
            guard item.sourceLayout == layout,
                  lines.indices.contains(source.line),
                  lines[source.line].indices.contains(source.index),
                  lines[source.line][source.index] == token
            else { return layout }
            lines[source.line].remove(at: source.index)
            if source.line == targetLine, source.index < targetIndex {
                targetIndex -= 1
            }
        }

        targetLine = min(max(targetLine, 0), lines.count - 1)
        targetIndex = min(max(targetIndex, 0), lines[targetLine].count)
        lines[targetLine].insert(token, at: targetIndex)
        return MenuBarLayout(lines: lines)
    }

    static func remove(at position: MenuBarLayoutPosition, from layout: MenuBarLayout) -> MenuBarLayout {
        guard layout.lines.indices.contains(position.line),
              layout.lines[position.line].indices.contains(position.index),
              layout.lines.reduce(0, { $0 + $1.count }) > 1
        else { return layout }
        var lines = layout.lines
        lines[position.line].remove(at: position.index)
        guard lines.joined().contains(where: { $0 != .space }) else { return layout }
        return MenuBarLayout(lines: lines)
    }

    static func remove(_ item: MenuBarLayoutDragItem, from layout: MenuBarLayout) -> MenuBarLayout {
        guard let source = item.source,
              item.sourceLayout == layout,
              case let .token(component) = item.content,
              layout.lines.indices.contains(source.line),
              layout.lines[source.line].indices.contains(source.index),
              layout.lines[source.line][source.index] == component
        else { return layout }
        return self.remove(at: source, from: layout)
    }

    static func addLineBreak(to layout: MenuBarLayout, at proposedIndex: Int? = nil) -> MenuBarLayout {
        guard layout.lines.count == 1 else { return layout }
        let line = layout.lines[0]
        guard !line.isEmpty else { return layout }
        if line.count == 1 {
            return MenuBarLayout(lines: [line, []])
        }
        let index = min(max(proposedIndex ?? line.count / 2, 1), line.count - 1)
        return MenuBarLayout(lines: [Array(line[..<index]), Array(line[index...])])
    }

    static func removeLineBreak(from layout: MenuBarLayout) -> MenuBarLayout {
        guard layout.lines.count == 2 else { return layout }
        return MenuBarLayout(lines: [layout.lines[0] + layout.lines[1]])
    }
}

enum MenuBarLayoutEditorScope: Hashable {
    case all
    case provider(UsageProvider)

    var previewLabel: String {
        switch self {
        case .all: L("menu_bar_layout_default_preview")
        case .provider: L("menu_bar_layout_live_preview")
        }
    }

    @MainActor
    func providersWithOverrides(settings: SettingsStore) -> [UsageProvider] {
        guard self == .all else { return [] }
        let overrides = settings.menuBarLayoutOverrides
        return settings.orderedFirstPartyProviders().filter {
            settings.providerEnablement[$0.instanceID] == true && overrides[$0] != nil
        }
    }
}

@MainActor
enum MenuBarLayoutEditorPersistence {
    static func useAllProvidersLayout(for provider: UsageProvider, settings: SettingsStore) {
        guard settings.providerEnablement[provider.instanceID] == true else { return }
        settings.removeMenuBarLayoutOverride(for: provider)
    }

    static func activate(
        _ layout: MenuBarLayout,
        for provider: UsageProvider?,
        settings: SettingsStore)
    {
        settings.menuBarIconStyle = .iconAndPercent
        settings.setMenuBarLayout(layout, for: provider)
    }

    static func setSize(
        _ size: MenuBarLayoutSize,
        activating layout: MenuBarLayout,
        for provider: UsageProvider?,
        settings: SettingsStore)
    {
        settings.menuBarLayoutSize = size
        self.activate(layout, for: provider, settings: settings)
    }

    static func setGap(
        _ gap: MenuBarLayoutGap,
        activating layout: MenuBarLayout,
        for provider: UsageProvider?,
        settings: SettingsStore)
    {
        settings.menuBarLayoutGap = gap
        self.activate(layout, for: provider, settings: settings)
    }
}

struct MenuBarLayoutPaletteGroup: Identifiable {
    let id: String
    let title: String
    let tokens: [MenuBarLayoutToken]
    let includesLineBreak: Bool
}

/// Left-aligned wrapping row layout for palette chips.
///
/// Palette chips have widely varying localized and user-defined widths. An adaptive
/// `LazyVGrid` would size them into equal columns and spread the leftover pane width between
/// them, and a plain `HStack` would push later chips outside the settings pane; this places each
/// chip at its natural width and wraps to the next row.
struct MenuBarLayoutChipFlowLayout: Layout {
    var spacing: CGFloat = 6

    /// Pure packing rule: subview indices grouped into rows that each stay within `maxWidth`.
    /// Kept separate from `Layout` so the wrapping contract is testable without faking subviews.
    /// A chip wider than `maxWidth` still occupies its own row rather than being dropped.
    static func rows(widths: [CGFloat], maxWidth: CGFloat, spacing: CGFloat) -> [[Int]] {
        var rows: [[Int]] = []
        var current: [Int] = []
        var currentWidth: CGFloat = 0
        for (index, width) in widths.enumerated() {
            let advance = current.isEmpty ? width : spacing + width
            if !current.isEmpty, currentWidth + advance > maxWidth {
                rows.append(current)
                current = [index]
                currentWidth = width
                continue
            }
            current.append(index)
            currentWidth += advance
        }
        if !current.isEmpty {
            rows.append(current)
        }
        return rows
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let rows = Self.rows(
            widths: sizes.map(\.width),
            maxWidth: proposal.width ?? .infinity,
            spacing: self.spacing)
        let rowWidths = rows.map { row in
            row.reduce(CGFloat.zero) { $0 + sizes[$1].width }
                + CGFloat(max(0, row.count - 1)) * self.spacing
        }
        let rowHeights = rows.map { row in
            row.reduce(CGFloat.zero) { max($0, sizes[$1].height) }
        }
        return CGSize(
            width: rowWidths.max() ?? 0,
            height: rowHeights.reduce(0, +) + CGFloat(max(0, rows.count - 1)) * self.spacing)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let rows = Self.rows(widths: sizes.map(\.width), maxWidth: bounds.width, spacing: self.spacing)
        var y = bounds.minY
        for row in rows {
            let rowHeight = row.reduce(CGFloat.zero) { max($0, sizes[$1].height) }
            var x = bounds.minX
            for index in row {
                let size = sizes[index]
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (rowHeight - size.height) / 2),
                    proposal: ProposedViewSize(size))
                x += size.width + self.spacing
            }
            y += rowHeight + self.spacing
        }
    }
}

@MainActor
struct MenuBarLayoutPreview: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    let layout: MenuBarLayout
    let provider: UsageProvider?
    @Bindable var settings: SettingsStore
    @Bindable var store: UsageStore

    private let renderer = MenuBarLayoutRenderer()

    var body: some View {
        let provider = self.provider ?? .codex
        let snapshot = self.store.snapshot(for: provider.instanceID)
        let data = snapshot.map { self.liveData(provider: provider, snapshot: $0) }
            ?? self.representativeData(provider: provider)
        let icon = ProviderBrandIcon.image(for: provider)
        let minute = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970 / 60) * 60)
        let appearanceName = self.colorScheme == .dark ? "darkAqua" : "aqua"
        let rendered = self.renderer.render(
            layout: self.layout,
            data: data,
            icon: icon,
            options: MenuBarLayoutRenderOptions(
                size: self.settings.menuBarLayoutSize,
                highContrast: self.settings.menuBarHighContrastOnInactiveDisplays
                    || (self.settings.menuBarColorByProvider && self.colorSchemeContrast == .increased),
                showUsed: self.settings.usageBarsShowUsed,
                conditionals: self.settings.menuBarLayoutConditionals,
                appearanceName: appearanceName,
                isDebugApp: false,
                now: minute,
                verticalAdjustment: self.settings.menuBarLayoutVerticalAdjustment,
                colorPace: self.settings.menuBarColorPace,
                colorByProvider: self.settings.menuBarColorByProvider,
                monospacedDigits: self.settings.menuBarLayoutMonospacedDigits,
                showWindowLabels: self.settings.menuBarLayoutShowWindowLabels))
        MenuBarLayoutPreviewText(rendered: rendered)
    }

    func liveData(provider: UsageProvider, snapshot: UsageSnapshot) -> MenuBarLayoutRenderData {
        let now = Date()
        let cost = self.store.tokenSnapshotForCurrentProviderConfig(for: provider)?.snapshot
        let costToday = MenuBarLayoutCostResolver.todayCostUSD(snapshot: cost, now: now)
        // Thresholds are USD, and `convertedCost` returns the source amount unchanged when no rate
        // exists, so keep the datum only when the conversion actually landed in USD.
        let toUSD = { (value: Double) -> Double? in
            let converted = UsageFormatter.convertedCost(
                value,
                preferredCurrency: "USD",
                providerCurrency: cost?.currencyCode)
            return converted.currencyCode == "USD" ? converted.value : nil
        }
        return self.store.menuBarLayoutRenderData(
            provider: provider,
            snapshot: snapshot,
            iconKey: provider.rawValue,
            accountLabel: self.settings.hidePersonalInfo ? nil : snapshot.accountEmail(for: provider),
            costs: MenuBarLayoutCostValues(
                today: costToday.map { UsageFormatter.currencyString($0, currencyCode: cost?.currencyCode ?? "USD") },
                last30Days: cost?.last30DaysCostUSD.map {
                    UsageFormatter.currencyString($0, currencyCode: cost?.currencyCode ?? "USD")
                },
                todayUSD: costToday.flatMap(toUSD),
                last30DaysUSD: cost?.last30DaysCostUSD.flatMap(toUSD)),
            now: now)
    }

    func representativeData(provider: UsageProvider) -> MenuBarLayoutRenderData {
        let now = Date()
        let session = RateWindow(
            usedPercent: 37,
            windowMinutes: 300,
            resetsAt: now.addingTimeInterval(2 * 60 * 60),
            resetDescription: nil)
        let weekly = RateWindow(
            usedPercent: 62,
            windowMinutes: 10080,
            resetsAt: now.addingTimeInterval(3 * 24 * 60 * 60),
            resetDescription: nil)
        let scopedWeekly = RateWindow(
            usedPercent: 45,
            windowMinutes: 10080,
            resetsAt: now.addingTimeInterval(4 * 24 * 60 * 60),
            resetDescription: nil)
        // Sample pace comes straight from the pure calculation rather than the store, so the palette
        // preview stays deterministic before any snapshot has been fetched.
        let samplePace = { (window: RateWindow) -> String? in
            MenuBarDisplayText.paceText(
                pace: UsagePace.weekly(window: window, now: now),
                reservePositive: self.settings.menuBarPaceReservePositive)
        }
        let samplePaceDelta = { (window: RateWindow) -> Double? in
            UsagePace.weekly(window: window, now: now)?.deltaPercent.rounded()
        }
        let spend = RateWindow(
            usedPercent: 46,
            windowMinutes: 30 * 24 * 60,
            resetsAt: now.addingTimeInterval(12 * 24 * 60 * 60),
            resetDescription: nil)
        return MenuBarLayoutRenderData(
            provider: provider.instanceID,
            iconKey: "\(provider.rawValue)-representative",
            providerName: L(self.store.metadata(for: provider).displayName),
            accountLabel: self.settings.hidePersonalInfo ? nil : L("menu_bar_layout_sample_account"),
            laneLabels: MenuBarLayoutLaneLabels(provider: provider, snapshot: nil),
            primary: MenuBarLayoutRenderWindow(session),
            secondary: MenuBarLayoutRenderWindow(weekly),
            tertiary: MenuBarLayoutRenderWindow(scopedWeekly),
            extraRateWindows: [],
            session: MenuBarLayoutRenderWindow(session),
            weekly: MenuBarLayoutRenderWindow(weekly),
            scopedWeekly: MenuBarLayoutRenderWindow(scopedWeekly),
            scopedWeeklyTitle: "Fable only",
            automatic: MenuBarLayoutRenderWindow(session),
            automaticText: nil,
            sessionPace: samplePace(session),
            weeklyPace: samplePace(weekly),
            automaticPace: samplePace(session),
            runsOut: L("Runs out in %@", "1d 16h"),
            // Provider-specific by design: only OpenRouter previews the Balance palette token.
            balance: provider == .openrouter ? "$12.34" : nil,
            tokensPerMinute: 49_000_000,
            tokensSparkline: .init(
                values: [30, 65, 40, 50, 35, 80, 45, 60, 151, 55, 70, 45, 60, 49].map { $0 * 1_000_000 },
                latest: 49_000_000),
            costToday: "$1.25",
            cost30d: "$20.00",
            metrics: MenuBarLayoutRenderMetrics(
                sessionPaceDelta: samplePaceDelta(session),
                weeklyPaceDelta: samplePaceDelta(weekly),
                automaticPaceDelta: samplePaceDelta(session),
                // 1d 16h == 40h, matching the sample `runsOut` text above.
                runsOutMinutes: 2400,
                // Provider-specific by design: Balance predicates mirror the OpenRouter preview amounts.
                balanceRemainingUSD: provider == .openrouter ? 12.34 : nil,
                balanceUsedUSD: provider == .openrouter ? 7.66 : nil,
                costTodayUSD: 1.25,
                cost30dUSD: 20,
                spendPaceDelta: samplePaceDelta(spend),
                spendUsedUSD: 460,
                spendRemainingUSD: 540),
            spend: MenuBarLayoutRenderWindow(spend),
            spendPace: samplePace(spend),
            spendAmount: "$460",
            spendBudget: "$460 / $1,000")
    }
}

@MainActor
struct MenuBarLayoutPreviewText: NSViewRepresentable {
    let rendered: MenuBarLayoutRenderedTitle

    func makeNSView(context: Context) -> NSStackView {
        let stack = NSStackView()
        self.configure(stack)
        return stack
    }

    func updateNSView(_ stack: NSStackView, context: Context) {
        self.configure(stack)
    }

    private func configure(_ stack: NSStackView) {
        for subview in stack.arrangedSubviews {
            stack.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }
        stack.orientation = .horizontal
        stack.spacing = 2
        stack.alignment = .centerY
        // The live status button renders an extracted leading icon as `button.image`; mirror that
        // in the preview so an icon-leading (or icon-only) preset stays visible in Preferences.
        if let icon = self.rendered.leadingIcon {
            let imageView = NSImageView(image: icon)
            imageView.imageScaling = .scaleProportionallyUpOrDown
            imageView.contentTintColor = .labelColor
            imageView.setContentHuggingPriority(.required, for: .horizontal)
            stack.addArrangedSubview(imageView)
        }
        let field = NSTextField(labelWithAttributedString: self.rendered.attributedTitle)
        field.alignment = .center
        field.lineBreakMode = .byClipping
        field.maximumNumberOfLines = 2
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        stack.addArrangedSubview(field)
        stack.setAccessibilityLabel(self.rendered.accessibilityLabel)
    }
}

extension MenuBarLayoutPreset {
    var label: String {
        switch self {
        case .iconAndPercent: L("menu_bar_layout_preset_icon_percent")
        case .iconOnly: L("menu_bar_layout_preset_icon_only")
        case .percentAndReset: L("menu_bar_layout_preset_percent_reset")
        case .compactStacked: L("menu_bar_layout_preset_compact_stacked")
        case .barsStacked: L("menu_bar_layout_preset_bars_stacked")
        case .custom: L("menu_bar_layout_preset_custom")
        }
    }
}

extension MenuBarLayoutSize {
    var label: String {
        switch self {
        case .small: L("menu_bar_layout_size_small")
        case .regular: L("menu_bar_layout_size_regular")
        case .large: L("menu_bar_layout_size_large")
        }
    }
}

extension MenuBarLayoutGap {
    var label: String {
        switch self {
        case .tight: L("menu_bar_layout_gap_tight")
        case .regular: L("menu_bar_layout_gap_regular")
        }
    }
}

extension MenuBarLayoutToken {
    func editorLabel(provider: UsageProvider?, snapshot: UsageSnapshot? = nil) -> String {
        if case let .lanePercent(lane) = self {
            return self.laneEditorLabel(lane: lane, provider: provider, snapshot: snapshot)
        }
        if case let .extraPercent(id) = self, let title = MenuBarLayoutNamedExtra.title(id: id) {
            return L("%@ %@", title, "%")
        }
        if let providerLabel = self.providerEditorLabel(provider: provider, snapshot: snapshot) {
            return providerLabel
        }
        return self.defaultEditorLabel
    }

    private func providerEditorLabel(provider: UsageProvider?, snapshot: UsageSnapshot?) -> String? {
        let window: PercentWindow? = switch self {
        case let .percent(window), let .pace(window),
             let .windowResetCountdown(window), let .windowResetAbsolute(window),
             let .progressBar(window): window
        default: nil
        }
        guard let window, let provider else { return nil }
        let preference: MenuBarPercentWindowPreference? = switch window {
        case .session: .session
        case .weekly: .weekly
        case .scopedWeekly, .automatic, .spend: nil
        }
        guard let localizedLabel = snapshot == nil
            ? window.providerLabel(provider: provider)
            : preference?.label(for: provider, snapshot: snapshot) else { return nil }
        return switch self {
        case .percent: L("%@ %@", localizedLabel, "%")
        case .pace: L("%@ %@", localizedLabel, L("display_mode_pace").lowercased())
        case .windowResetCountdown:
            L("%@: %@", localizedLabel, L("menu_bar_layout_token_resets_in"))
        case .windowResetAbsolute:
            L("%@: %@", localizedLabel, L("menu_bar_layout_token_reset_at"))
        case .progressBar:
            L("%@ %@", localizedLabel, L("menu_bar_layout_token_bar"))
        default: nil
        }
    }

    private var defaultEditorLabel: String {
        switch self {
        case .icon: L("menu_bar_layout_token_icon")
        case .providerName: L("menu_bar_layout_token_provider")
        case .accountLabel: L("menu_bar_layout_token_account")
        case .percent(window: .session): L("menu_bar_layout_token_session")
        case .percent(window: .weekly): L("menu_bar_layout_token_weekly")
        case .percent(window: .scopedWeekly): L("menu_bar_layout_token_scoped_weekly")
        case .percent(window: .automatic): L("menu_bar_layout_token_auto")
        case .percent(window: .spend): L("menu_bar_layout_token_spend")
        case let .lanePercent(lane): L("%@ %@", lane.rawValue.capitalized, "%")
        case .extraPercent: L("%@ %@", L("Usage"), "%")
        case .pace(window: .session): L("menu_bar_layout_token_session_pace")
        case .pace(window: .weekly): L("menu_bar_layout_token_weekly_pace")
        case .pace(window: .scopedWeekly): L("menu_bar_layout_token_weekly_pace")
        case .pace(window: .automatic): L("menu_bar_layout_token_auto_pace")
        case .pace(window: .spend): L("menu_bar_layout_token_spend_pace")
        case .usageBar: L("menu_bar_layout_token_bar")
        case let .progressBar(window):
            L("%@ %@", Self.resetWindowLabel(window), L("menu_bar_layout_token_bar"))
        case .resetCountdown: L("menu_bar_layout_token_resets_in")
        case .resetAbsolute: L("menu_bar_layout_token_reset_at")
        case let .windowResetCountdown(window):
            L("%@: %@", Self.resetWindowLabel(window), L("menu_bar_layout_token_resets_in"))
        case let .windowResetAbsolute(window):
            L("%@: %@", Self.resetWindowLabel(window), L("menu_bar_layout_token_reset_at"))
        case .runsOut: L("menu_bar_layout_token_runs_out")
        case .runsOutCompact: "\(L("menu_bar_layout_token_runs_out")) (compact)"
        case .balance: L("Balance")
        case .tokensPerMinute: L("Tokens / min")
        case .tokensSparkline: L("Tokens / min graph")
        case .costToday: L("menu_bar_layout_token_cost_today")
        case .costWindow: L("menu_bar_layout_token_cost_window")
        case .spendAmount: L("Spend")
        case .spendBudget: L("menu_bar_layout_token_spend_budget")
        case .separatorDot: "·"
        case let .separator(separator): separator.glyph
        case .space: L("menu_bar_layout_token_space")
        case .conditional: L("menu_bar_layout_token_conditional")
        case .hidden: L("menu_bar_layout_conditional_hide")
        }
    }

    private static func resetWindowLabel(_ window: PercentWindow) -> String {
        switch window {
        case .session: L("Session")
        case .weekly: L("Weekly")
        case .scopedWeekly: L("menu_bar_layout_conditional_metric_scoped_weekly")
        case .automatic: L("Automatic")
        case .spend: L("Spend")
        }
    }

    private func laneEditorLabel(
        lane: MenuBarLayoutLane,
        provider: UsageProvider?,
        snapshot: UsageSnapshot?)
        -> String
    {
        guard let provider else { return L("%@ %@", lane.rawValue.capitalized, "%") }
        let label = MenuBarLayoutLaneLabels(provider: provider, snapshot: snapshot).label(for: lane)
        return L("%@ %@", label, "%")
    }

    func editorAccessibilityLabel(provider: UsageProvider?, snapshot: UsageSnapshot? = nil) -> String {
        switch self {
        case .separatorDot: L("menu_bar_layout_token_separator_accessibility")
        case let .separator(separator): L(
                "menu_bar_layout_token_separator_glyph_accessibility",
                separator.accessibilityName)
        default: self.editorLabel(provider: provider, snapshot: snapshot)
        }
    }

    var editorSystemImage: String {
        switch self {
        case .icon: "app.dashed"
        case .providerName: "textformat"
        case .accountLabel: "person.crop.circle"
        case .percent, .lanePercent, .extraPercent: "percent"
        case .pace: "speedometer"
        case .usageBar, .progressBar: "chart.bar.fill"
        case .resetCountdown, .windowResetCountdown: "timer"
        case .resetAbsolute, .windowResetAbsolute: "clock"
        case .runsOut, .runsOutCompact: "hourglass.bottomhalf.filled"
        case .balance: "creditcard"
        case .tokensPerMinute: "speedometer"
        case .tokensSparkline: "chart.bar.xaxis"
        case .costToday, .spendAmount, .spendBudget: "dollarsign.circle"
        case .costWindow: "calendar.badge.clock"
        case .separatorDot, .separator: "smallcircle.filled.circle"
        case .space: "space"
        case .conditional: "switch.2"
        case .hidden: "eye.slash"
        }
    }
}
