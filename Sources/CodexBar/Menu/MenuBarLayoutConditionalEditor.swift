import CodexBarCore
import InternalUI
import SwiftUI

struct MenuBarLayoutConditionalDraft: Identifiable {
    enum Mode: Hashable {
        case create
        case edit(UUID)
    }

    /// Sheet-presentation identity only, unrelated to `conditional.id`.
    let id: UUID
    let mode: Mode
    var conditional: MenuBarLayoutConditional

    init(mode: Mode, conditional: MenuBarLayoutConditional) {
        self.id = UUID()
        self.mode = mode
        self.conditional = conditional
    }
}

/// Creates or edits one conditional: its name, up to four clauses, and the tokens it shows either way. Laid out
/// as settings sections, with Cancel and Save pinned bottom-right; Save stays off until the name is unique.
@MainActor
struct MenuBarLayoutConditionalEditorSheet: View {
    /// The most clauses one conditional can combine.
    static let maxClauses = 4

    @Environment(\.dismiss) private var dismiss
    @State private var conditional: MenuBarLayoutConditional

    let draft: MenuBarLayoutConditionalDraft
    let provider: UsageProvider?
    let existingNames: Set<String>
    let onSave: (MenuBarLayoutConditionalDraft) -> Void

    init(
        draft: MenuBarLayoutConditionalDraft,
        provider: UsageProvider?,
        existingNames: Set<String>,
        onSave: @escaping (MenuBarLayoutConditionalDraft) -> Void)
    {
        self.draft = draft
        self.provider = provider
        self.existingNames = existingNames
        self.onSave = onSave
        self._conditional = State(initialValue: draft.conditional)
    }

    private var trimmedName: String {
        self.conditional.name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var reservedNames: Set<String> {
        var names = self.existingNames
        // The entry's own current name is allowed so an edit can be saved unchanged.
        names.remove(self.draft.conditional.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        return names
    }

    private var nameIsValid: Bool {
        !self.trimmedName.isEmpty && !self.reservedNames.contains(self.trimmedName.lowercased())
    }

    private var title: String {
        switch self.draft.mode {
        case .create: L("menu_bar_layout_conditional_add")
        case .edit: L("menu_bar_layout_conditional_edit")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: IUSpace.settingsSectionGap) {
            IUText(self.title, role: .title)
                .accessibilityAddTraits(.isHeader)

            IUSettingsSection {
                IUSettingsRow(L("menu_bar_layout_conditional_name")) {
                    VStack(alignment: .trailing, spacing: IUSpace.unit) {
                        IUTextField(L("menu_bar_layout_conditional_name_placeholder"), text: self.$conditional.name)
                            .frame(width: IUSize.settingsField)
                            .accessibilityLabel(L("menu_bar_layout_conditional_name"))
                        if !self.nameIsValid {
                            Text(L("menu_bar_layout_conditional_name_error"))
                                .font(IUTextRole.caption.font)
                                .foregroundStyle(IUColor.destructive)
                        }
                    }
                }
            }

            IUSettingsSection(L("menu_bar_layout_conditional_if")) {
                ForEach(self.conditional.clauses.indices, id: \.self) { index in
                    self.clauseRow(index: index)
                        .menuBarLayoutRowFrame()
                }
                HStack {
                    Button(L("menu_bar_layout_conditional_add_condition"), systemImage: "plus") {
                        self.conditional.clauses.append(
                            MenuBarConditionalClause(
                                combinator: .and,
                                predicate: MenuBarConditionalPredicate(
                                    metric: .automatic,
                                    comparison: .greaterThan,
                                    threshold: 0)))
                    }
                    .buttonStyle(.iu())
                    .disabled(self.conditional.clauses.count >= Self.maxClauses)
                    Spacer(minLength: 0)
                }
                .menuBarLayoutRowFrame()
            }

            IUSettingsSection(footer: self.conditional.editorSummary(provider: self.provider)) {
                IUSettingsRow(L("menu_bar_layout_conditional_then")) {
                    self.tokenPopUp(selection: self.thenBinding)
                }
                IUSettingsRow(L("menu_bar_layout_conditional_else")) {
                    self.tokenPopUp(selection: self.elseBinding)
                }
            }

            HStack(spacing: IUSpace.unit * 2) {
                Spacer()
                Button(L("Cancel"), role: .cancel) {
                    self.dismiss()
                }
                .buttonStyle(.iu())
                .keyboardShortcut(.cancelAction)
                Button(L("menu_bar_layout_conditional_save")) {
                    self.onSave(
                        MenuBarLayoutConditionalDraft(
                            mode: self.draft.mode,
                            conditional: self.conditional))
                    self.dismiss()
                }
                .buttonStyle(.iu(.primary))
                .keyboardShortcut(.defaultAction)
                .disabled(!self.nameIsValid)
            }
        }
        .padding(IUSpace.settingsPagePadding)
        // Wide enough for a clause's combinator, metric and direction on one line, and its test on the next.
        .frame(width: IUSize.settingsContentWidth)
        .background(IUColor.window)
    }

    /// One clause on two lines: what it measures (and how it joins the clause before), then the test.
    private func clauseRow(index: Int) -> some View {
        let metric = self.conditional.clauses.indices.contains(index)
            ? self.conditional.clauses[index].predicate.metric
            : MenuBarConditionalMetric.session
        return VStack(alignment: .leading, spacing: IUSpace.unit * 2) {
            HStack(spacing: IUSpace.unit * 2) {
                if index > 0 {
                    IUPopUpButton(
                        [
                            (MenuBarConditionalCombinator.and, L("menu_bar_layout_conditional_and")),
                            (MenuBarConditionalCombinator.or, L("menu_bar_layout_conditional_or")),
                        ],
                        selection: self.combinatorBinding(index))
                }
                IUPopUpButton(
                    MenuBarConditionalMetric.allCases.map { ($0, $0.editorLabel(provider: self.provider)) },
                    selection: self.metricBinding(index))
                if metric.supportsDirection {
                    IUPopUpButton(
                        [
                            (MenuBarConditionalDirection.used, L("menu_bar_layout_conditional_used")),
                            (MenuBarConditionalDirection.remaining, L("menu_bar_layout_conditional_remaining")),
                        ],
                        selection: self.directionBinding(index))
                }
                Spacer(minLength: 0)
                if self.conditional.clauses.count > 1 {
                    Button {
                        self.conditional.clauses.remove(at: index)
                    } label: {
                        Image(systemName: "minus.circle")
                            .frame(width: IUSize.iconTile, height: IUSize.iconTile)
                    }
                    .buttonStyle(.iuIcon)
                    .accessibilityLabel(L("Remove"))
                }
            }
            HStack(spacing: IUSpace.unit * 2) {
                IUPopUpButton(
                    MenuBarConditionalComparison.allCases.map { ($0, $0.symbol) },
                    selection: self.comparisonBinding(index))
                MenuBarConditionalThresholdField(
                    value: self.thresholdBinding(index),
                    range: metric.thresholdRange,
                    step: metric.thresholdStep,
                    accessibilityLabel: metric.editorLabel(provider: self.provider))
                IUText(metric.thresholdUnit, role: .body, muted: true)
            }
        }
    }

    private func combinatorBinding(_ index: Int) -> Binding<MenuBarConditionalCombinator> {
        Binding(
            get: {
                guard self.conditional.clauses.indices.contains(index) else { return .and }
                return self.conditional.clauses[index].combinator ?? .and
            },
            set: {
                guard self.conditional.clauses.indices.contains(index) else { return }
                self.conditional.clauses[index].combinator = $0
            })
    }

    private func metricBinding(_ index: Int) -> Binding<MenuBarConditionalMetric> {
        Binding(
            get: {
                guard self.conditional.clauses.indices.contains(index) else { return .session }
                return self.conditional.clauses[index].predicate.metric
            },
            set: {
                guard self.conditional.clauses.indices.contains(index) else { return }
                self.conditional.clauses[index].predicate.metric = $0
                // Re-normalize so switching metric families cannot leave a threshold outside the new
                // unit's range or a direction the new metric has no reading for.
                self.conditional.clauses[index].predicate =
                    self.conditional.clauses[index].predicate.normalized()
            })
    }

    private func directionBinding(_ index: Int) -> Binding<MenuBarConditionalDirection> {
        Binding(
            get: {
                guard self.conditional.clauses.indices.contains(index) else { return .used }
                return self.conditional.clauses[index].predicate.direction
            },
            set: {
                guard self.conditional.clauses.indices.contains(index) else { return }
                self.conditional.clauses[index].predicate.direction = $0
            })
    }

    private func comparisonBinding(_ index: Int) -> Binding<MenuBarConditionalComparison> {
        Binding(
            get: {
                guard self.conditional.clauses.indices.contains(index) else { return .greaterThan }
                return self.conditional.clauses[index].predicate.comparison
            },
            set: {
                guard self.conditional.clauses.indices.contains(index) else { return }
                self.conditional.clauses[index].predicate.comparison = $0
            })
    }

    private func thresholdBinding(_ index: Int) -> Binding<Double> {
        Binding(
            get: {
                guard self.conditional.clauses.indices.contains(index) else { return 0 }
                return self.conditional.clauses[index].predicate.threshold
            },
            set: {
                guard self.conditional.clauses.indices.contains(index) else { return }
                let metric = self.conditional.clauses[index].predicate.metric
                self.conditional.clauses[index].predicate.threshold = $0.clamped(to: metric.thresholdRange)
            })
    }

    private var thenBinding: Binding<MenuBarLayoutToken> {
        Binding(
            get: { self.conditional.thenToken },
            set: { self.conditional.thenToken = $0 })
    }

    private var elseBinding: Binding<MenuBarLayoutToken> {
        Binding(
            get: { self.conditional.elseToken },
            set: { self.conditional.elseToken = $0 })
    }

    private func tokenPopUp(selection: Binding<MenuBarLayoutToken>) -> some View {
        IUPopUpButton(
            MenuSettingsPopUpOptions.options(
                MenuBarLayoutPaletteTokens.conditionalBranch,
                selection: selection.wrappedValue,
                label: { $0.editorLabel(provider: self.provider) }),
            selection: selection)
            .accessibilityValue(selection.wrappedValue.editorAccessibilityLabel(provider: self.provider))
    }
}

/// A clause's threshold: a number field in the library's control well, with a stepper for the metric's step.
/// The value can be fractional (half hours) and spans wide ranges (up to a year of hours, a million dollars), so
/// it is typed rather than only stepped; `IUStepper` covers whole numbers only.
private struct MenuBarConditionalThresholdField: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let accessibilityLabel: String

    @Environment(\.iuControlSize) private var controlSize

    var body: some View {
        let metrics = IUControlMetrics.forSize(self.controlSize)
        HStack(spacing: IUSpace.unit) {
            TextField(self.accessibilityLabel, value: self.$value, format: .number)
                .labelsHidden()
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .font(metrics.font)
                .padding(.horizontal, metrics.paddingX)
                .frame(width: IUSize.control * 2, height: metrics.height)
                .iuWell(radius: metrics.radius)
            Stepper(value: self.$value, in: self.range, step: self.step) {
                EmptyView()
            }
            .labelsHidden()
            .accessibilityLabel(self.accessibilityLabel)
        }
    }
}

extension MenuBarLayoutConditional {
    /// The chip label: the required name, falling back to a generic label if somehow empty.
    var displayName: String {
        let trimmed = self.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? L("menu_bar_layout_token_conditional") : trimmed
    }

    /// Produces a summary string reflecting the left-fold AND/OR evaluation order. Mixed
    /// combinators parenthesize their accumulator so the reading matches `evaluatesTrue`.
    private func conditionText(provider: UsageProvider?) -> String {
        guard let first = self.clauses.first else { return "" }
        let mixed = Set(self.clauses.dropFirst().compactMap(\.combinator)).count > 1
        var text = Self.predicateText(first.predicate, provider: provider)
        for clause in self.clauses.dropFirst() {
            let joiner = (clause.combinator ?? .and) == .and
                ? L("menu_bar_layout_conditional_and")
                : L("menu_bar_layout_conditional_or")
            let pred = Self.predicateText(clause.predicate, provider: provider)
            text = mixed ? "(\(text)) \(joiner) \(pred)" : "\(text) \(joiner) \(pred)"
        }
        return text
    }

    private static func predicateText(
        _ predicate: MenuBarConditionalPredicate,
        provider: UsageProvider?)
        -> String
    {
        var metric = predicate.metric.editorLabel(provider: provider)
        if predicate.metric.supportsDirection {
            metric += " " + (predicate.direction == .used
                ? L("menu_bar_layout_conditional_used")
                : L("menu_bar_layout_conditional_remaining"))
        }
        let value = predicate.threshold
        // Whole hours read as "2h"; a half-hour step needs the decimal to stay truthful.
        let number = value == value.rounded() ? String(Int(value.rounded())) : String(format: "%.1f", value)
        let unit = predicate.metric.thresholdUnit
        let amount = predicate.metric.kind == .currencyUSD ? "\(number) \(unit)" : "\(number)\(unit)"
        return "\(metric) \(predicate.comparison.symbol) \(amount)"
    }

    func editorSummary(provider: UsageProvider?) -> String {
        let condition = self.conditionText(provider: provider)
        return L(
            "menu_bar_layout_conditional_summary",
            condition,
            self.thenToken.editorLabel(provider: provider),
            self.elseToken.editorLabel(provider: provider))
    }

    /// Generates a unique copy name that avoids collisions with existing library entries.
    static func uniqueCopyName(basedOn name: String, existingNames: Set<String>) -> String {
        let base = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let stem = base.isEmpty ? L("menu_bar_layout_token_conditional") : base
        var candidate = L("menu_bar_layout_conditional_copy_name", stem)
        var n = 2
        while existingNames.contains(candidate.lowercased()) {
            candidate = L("menu_bar_layout_conditional_copy_name_numbered", stem, n)
            n += 1
        }
        return candidate
    }
}

extension MenuBarConditionalMetric {
    // swiftlint:disable cyclomatic_complexity
    /// Reuses the palette token labels so a metric and the block it measures always read the same, and
    /// resolves lane names through the provider's own labels rather than hard-coding "Primary".
    func editorLabel(provider: UsageProvider?) -> String {
        switch self {
        case .session: MenuBarLayoutToken.percent(window: .session).editorLabel(provider: provider)
        case .weekly: MenuBarLayoutToken.percent(window: .weekly).editorLabel(provider: provider)
        case .scopedWeekly: L("menu_bar_layout_token_scoped_weekly")
        case .automatic: L("menu_bar_layout_token_auto")
        case .spend: MenuBarLayoutToken.percent(window: .spend).editorLabel(provider: provider)
        case .primaryLane: MenuBarLayoutToken.lanePercent(lane: .primary).editorLabel(provider: provider)
        case .secondaryLane: MenuBarLayoutToken.lanePercent(lane: .secondary).editorLabel(provider: provider)
        case .tertiaryLane: MenuBarLayoutToken.lanePercent(lane: .tertiary).editorLabel(provider: provider)
        case .sessionResetsIn: L(
                "menu_bar_layout_conditional_metric_resets_in",
                PercentWindow.session.providerLabel(provider: provider) ?? L("Session"))
        case .weeklyResetsIn: L(
                "menu_bar_layout_conditional_metric_resets_in",
                PercentWindow.weekly.providerLabel(provider: provider) ?? L("Weekly"))
        case .scopedWeeklyResetsIn: L(
                "menu_bar_layout_conditional_metric_resets_in",
                L("menu_bar_layout_conditional_metric_scoped_weekly"))
        case .automaticResetsIn: L("menu_bar_layout_conditional_metric_resets_in", L("Auto"))
        case .spendResetsIn: L("menu_bar_layout_conditional_metric_resets_in", L("Spend"))
        case .sessionPace: MenuBarLayoutToken.pace(window: .session).editorLabel(provider: provider)
        case .weeklyPace: MenuBarLayoutToken.pace(window: .weekly).editorLabel(provider: provider)
        case .automaticPace: L("menu_bar_layout_token_auto_pace")
        case .spendPace: MenuBarLayoutToken.pace(window: .spend).editorLabel(provider: provider)
        case .runsOutIn: L("menu_bar_layout_token_runs_out")
        case .balance: L("Balance")
        case .costToday: L("menu_bar_layout_token_cost_today")
        case .costWindow: L("menu_bar_layout_token_cost_window")
        case .spendAmount: MenuBarLayoutToken.spendAmount.editorLabel(provider: provider)
        }
    }
    // swiftlint:enable cyclomatic_complexity
}
