import CodexBarCore
import InternalUI
import SwiftUI

/// The menu-bar layout editor, as Internal UI settings sections: the scope, preset and preview; the strip of
/// placed tokens with its trash zone; one palette section per token group; the conditionals library; and the
/// display options. It sits in the Menu Bar pane's column, so each part is a `IUSettingsSection`.
///
/// It edits only while the menu bar uses the Icon & percent style; otherwise every section is disabled and the
/// scope row says why.
@MainActor
struct MenuBarLayoutEditor: View {
    @Bindable var settings: SettingsStore
    @Bindable var store: UsageStore

    @State private var scope: MenuBarLayoutEditorScope = .all
    @State private var selectedPosition: MenuBarLayoutPosition?
    @State private var conditionalDraft: MenuBarLayoutConditionalDraft?

    private var isEditable: Bool {
        MenuBarSettingsPane.layoutEditorEnabled(for: self.settings.menuBarIconStyle)
    }

    private var layout: MenuBarLayout {
        switch self.scope {
        case .all:
            self.settings.menuBarLayoutForGlobalEditing(representativeProvider: self.scopedProvider)
        case let .provider(provider):
            self.settings.menuBarLayout(for: provider)
        }
    }

    private var preset: MenuBarLayoutPreset {
        MenuBarLayoutPreset.matching(self.layout)
    }

    private var providers: [UsageProvider] {
        self.store.enabledFirstPartyProvidersForDisplay()
    }

    private var scopedProvider: UsageProvider? {
        switch self.scope {
        case .all: self.providers.first
        case let .provider(provider): provider
        }
    }

    private var persistenceProvider: UsageProvider? {
        switch self.scope {
        case .all: nil
        case let .provider(provider): provider
        }
    }

    private var persistenceSnapshot: UsageSnapshot? {
        self.persistenceProvider.flatMap { self.store.snapshot(for: $0.instanceID) }
    }

    private var sizeBinding: Binding<MenuBarLayoutSize> {
        Binding(
            get: { self.settings.menuBarLayoutSize },
            set: { size in
                MenuBarLayoutEditorPersistence.setSize(
                    size,
                    activating: self.layout,
                    for: self.persistenceProvider,
                    settings: self.settings)
            })
    }

    private var monospacedDigitsBinding: Binding<Bool> {
        Binding(
            get: { self.settings.menuBarLayoutMonospacedDigits },
            set: { enabled in
                self.settings.menuBarLayoutMonospacedDigits = enabled
                MenuBarLayoutEditorPersistence.activate(
                    self.layout, for: self.persistenceProvider, settings: self.settings)
            })
    }

    private var showWindowLabelsBinding: Binding<Bool> {
        Binding(
            get: { self.settings.menuBarLayoutShowWindowLabels },
            set: { enabled in
                self.settings.menuBarLayoutShowWindowLabels = enabled
                MenuBarLayoutEditorPersistence.activate(
                    self.layout, for: self.persistenceProvider, settings: self.settings)
            })
    }

    private var gapBinding: Binding<MenuBarLayoutGap> {
        Binding(
            get: { self.settings.menuBarLayoutGap },
            set: { gap in
                MenuBarLayoutEditorPersistence.setGap(
                    gap,
                    activating: self.layout,
                    for: self.persistenceProvider,
                    settings: self.settings)
            })
    }

    private var presetBinding: Binding<MenuBarLayoutPreset> {
        Binding(
            get: { self.preset },
            set: { self.applyPreset($0) })
    }

    private var paletteGroups: [MenuBarLayoutPaletteGroup] {
        [
            MenuBarLayoutPaletteGroup(
                id: "identity",
                title: L("menu_bar_layout_group_identity"),
                tokens: [.icon, .providerName, .accountLabel],
                includesLineBreak: false),
            MenuBarLayoutPaletteGroup(
                id: "usage",
                title: L("menu_bar_layout_group_usage"),
                tokens: MenuBarLayoutPaletteTokens.usage(
                    provider: self.persistenceProvider,
                    snapshot: self.persistenceSnapshot),
                includesLineBreak: false),
            MenuBarLayoutPaletteGroup(
                id: "time",
                title: L("menu_bar_layout_group_time"),
                tokens: MenuBarLayoutPaletteTokens.time,
                includesLineBreak: false),
            MenuBarLayoutPaletteGroup(
                id: "money",
                title: L("menu_bar_layout_group_money"),
                tokens: [.balance, .costToday, .costWindow, .spendAmount, .spendBudget],
                includesLineBreak: false),
            MenuBarLayoutPaletteGroup(
                id: "structure",
                title: L("menu_bar_layout_group_structure"),
                tokens: [.separatorDot] + MenuBarLayoutSeparator.allCases.map(MenuBarLayoutToken.separator)
                    + [.space],
                includesLineBreak: true),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: IUSpace.settingsSectionGap) {
            self.layoutSection
            self.stripSection
            ForEach(self.paletteGroups) { group in
                IUSettingsSection(group.title) {
                    self.palette(group)
                        .menuBarLayoutRowFrame()
                }
            }
            self.conditionalsSection
            IUSettingsSection(L("Display")) {
                self.displayOptions
            }
        }
        .disabled(!self.isEditable)
        .onDeleteCommand {
            self.removeSelectedToken()
        }
        .sheet(item: self.$conditionalDraft) { draft in
            MenuBarLayoutConditionalEditorSheet(
                draft: draft,
                provider: self.persistenceProvider,
                existingNames: Set(
                    self.settings.menuBarLayoutConditionals.map {
                        $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    }),
                onSave: self.saveConditionalDraft)
        }
        .onChange(of: self.scope) { _, _ in
            self.selectedPosition = nil
        }
    }

    // MARK: - Scope, overrides, preset and preview

    private var layoutSection: some View {
        IUSettingsSection(L("menu_bar_layout_title")) {
            IUSettingsRow(
                L("Scope"),
                subtitle: L("menu_bar_layout_scope_help"),
                disabledReason: MenuBarSettingsPane.requiresIconAndPercentReason)
            {
                IUPopUpButton(self.scopeOptions, selection: self.$scope)
                    .accessibilityLabel(L("Scope"))
            }
            .settingsAnchor(MenuBarSettingsPane.SearchID.layout)

            ForEach(self.overrideProviders, id: \.self) { provider in
                IUSettingsRow(
                    L(self.store.metadata(for: provider).displayName),
                    subtitle: L("menu_bar_layout_override_subtitle"))
                {
                    self.useAllProvidersLayoutButton(for: provider)
                }
            }

            IUSettingsRow(L("menu_bar_layout_preset")) {
                IUPopUpButton(self.presetOptions, selection: self.presetBinding)
                    .accessibilityLabel(L("menu_bar_layout_preset"))
            }
            .settingsAnchor(MenuBarSettingsPane.SearchID.layoutPreset)

            IUSettingsRow(self.scope.previewLabel) {
                self.preview
            }
        }
    }

    private var scopeOptions: [(MenuBarLayoutEditorScope, String)] {
        let scopes = [MenuBarLayoutEditorScope.all] + self.providers.map(MenuBarLayoutEditorScope.provider)
        return MenuSettingsPopUpOptions.options(scopes, selection: self.scope, label: self.scopeLabel)
    }

    private func scopeLabel(_ scope: MenuBarLayoutEditorScope) -> String {
        switch scope {
        case .all: L("menu_bar_layout_scope_all")
        case let .provider(provider): L(self.store.metadata(for: provider).displayName)
        }
    }

    /// Presets to choose from. Custom is never a choice; it is listed only while the layout matches no preset,
    /// so the pop-up can show it.
    private var presetOptions: [(MenuBarLayoutPreset, String)] {
        let presets = MenuBarLayoutPreset.allCases.filter { $0 != .custom }
        return MenuSettingsPopUpOptions.options(presets, selection: self.preset, label: \.label)
    }

    /// Providers whose saved layout differs from the all-providers one: every enabled override while editing all
    /// providers, or the selected provider when it has one.
    private var overrideProviders: [UsageProvider] {
        switch self.scope {
        case .all:
            self.scope.providersWithOverrides(settings: self.settings)
        case let .provider(provider):
            self.settings.menuBarLayoutOverrides[provider] != nil ? [provider] : []
        }
    }

    private func useAllProvidersLayoutButton(for provider: UsageProvider) -> some View {
        Button(L("menu_bar_layout_use_all")) {
            MenuBarLayoutEditorPersistence.useAllProvidersLayout(for: provider, settings: self.settings)
            self.selectedPosition = nil
        }
        .buttonStyle(.iu())
        .accessibilityLabel(L(
            "menu_bar_layout_use_all_accessibility",
            L(self.store.metadata(for: provider).displayName)))
    }

    private var preview: some View {
        MenuBarLayoutPreview(
            layout: self.layout,
            provider: self.scopedProvider,
            settings: self.settings,
            store: self.store)
            .padding(.horizontal, IUSpace.panelPadding)
            .padding(.vertical, IUSpace.unit)
            .frame(minHeight: IUSize.row)
            .iuWell(radius: IURadius.row)
    }

    // MARK: - Strip

    private var stripSection: some View {
        IUSettingsSection(
            L("menu_bar_layout_strip"),
            footer: MenuBarSettingsPane.layoutFooterText(for: self.settings.menuBarIconStyle))
        {
            VStack(alignment: .leading, spacing: IUSpace.unit * 2) {
                ForEach(Array(self.layout.lines.enumerated()), id: \.offset) { lineIndex, _ in
                    self.layoutLine(lineIndex)
                }
            }
            .menuBarLayoutRowFrame()

            if self.layout.lines.count == 2 {
                IUSettingsRow(L("menu_bar_layout_token_line_break")) {
                    Button(L("menu_bar_layout_remove_line_break")) {
                        self.write(MenuBarLayoutEditorMutations.removeLineBreak(from: self.layout))
                    }
                    .buttonStyle(.iu())
                }
            }

            MenuBarLayoutRemoveZone(
                canRemoveSelection: self.selectedPosition != nil,
                removeSelection: self.removeSelectedToken,
                onDrop: self.removeDropped)
                .menuBarLayoutRowFrame()
        }
    }

    private func layoutLine(_ lineIndex: Int) -> some View {
        let line = self.layout.lines[lineIndex]
        return MenuBarLayoutLineWell(
            isEmpty: line.isEmpty,
            accessibilityLabel: L("menu_bar_layout_line", lineIndex + 1),
            onDrop: { item in
                self.insert(item, at: MenuBarLayoutPosition(line: lineIndex, index: line.count))
            },
            content: {
                ForEach(Array(line.enumerated()), id: \.offset) { index, token in
                    self.placedChip(token, at: MenuBarLayoutPosition(line: lineIndex, index: index))
                }
            })
    }

    private func placedChip(_ token: MenuBarLayoutToken, at position: MenuBarLayoutPosition) -> some View {
        MenuBarLayoutEditorChip(
            title: self.chipTitle(for: token),
            systemImage: token.editorSystemImage,
            kind: .placed,
            isSelected: self.selectedPosition == position,
            accessibilityLabel: self.chipAccessibilityLabel(for: token),
            accessibilityHint: L("menu_bar_layout_chip_hint"),
            dragItem: .placed(token, at: position, in: self.layout),
            activate: { self.selectedPosition = position },
            removeActionTitle: L("Remove"),
            remove: { self.remove(at: position) })
            .dropDestination(for: MenuBarLayoutDragItem.self) { items, _ in
                self.insert(items.first, at: position)
            }
            .contextMenu {
                if case let .conditional(id) = token,
                   let conditional = self.settings.menuBarLayoutConditionals.first(where: { $0.id == id })
                {
                    Button(L("menu_bar_layout_conditional_edit")) {
                        self.conditionalDraft = MenuBarLayoutConditionalDraft(
                            mode: .edit(id),
                            conditional: conditional)
                    }
                }
            }
    }

    private func removeDropped(_ item: MenuBarLayoutDragItem?) -> Bool {
        guard let item, item.source != nil else { return false }
        let updated = MenuBarLayoutEditorMutations.remove(item, from: self.layout)
        guard updated != self.layout else { return false }
        self.write(updated)
        self.selectedPosition = nil
        return true
    }

    // MARK: - Palettes

    /// One palette group's chips, wrapping at the section's width. Clicking a chip appends it; dragging places it.
    func palette(_ group: MenuBarLayoutPaletteGroup) -> some View {
        MenuBarLayoutChipFlowLayout(spacing: IUSpace.chipGap) {
            ForEach(group.tokens, id: \.self) { token in
                MenuBarLayoutEditorChip(
                    title: token.editorLabel(
                        provider: self.persistenceProvider,
                        snapshot: self.persistenceSnapshot),
                    systemImage: token.editorSystemImage,
                    accessibilityLabel: token.editorAccessibilityLabel(
                        provider: self.persistenceProvider,
                        snapshot: self.persistenceSnapshot),
                    accessibilityHint: L("menu_bar_layout_palette_hint"),
                    dragItem: .palette(token),
                    activate: {
                        self.write(MenuBarLayoutEditorMutations.append(token, to: self.layout))
                    })
                    .help(token == .tokensPerMinute
                        ? L("Latest tokens per minute (OpenAI Admin API)")
                        : token == .tokensSparkline
                        ? L("Last hour of tokens per minute (OpenAI Admin API)") : "")
            }
            if group.includesLineBreak {
                MenuBarLayoutEditorChip(
                    title: L("menu_bar_layout_token_line_break"),
                    systemImage: "arrow.turn.down.right",
                    isDisabled: self.layout.lines.count == 2,
                    accessibilityLabel: L("menu_bar_layout_token_line_break"),
                    accessibilityHint: L("menu_bar_layout_palette_hint"),
                    dragItem: .lineBreak,
                    activate: {
                        self.write(MenuBarLayoutEditorMutations.addLineBreak(to: self.layout))
                    })
            }
        }
    }

    // MARK: - Conditionals

    private var conditionalsSection: some View {
        IUSettingsSection(L("menu_bar_layout_group_conditionals")) {
            HStack(alignment: .top, spacing: IUSpace.settingsRowPaddingX) {
                if self.settings.menuBarLayoutConditionals.isEmpty {
                    IUText(L("menu_bar_layout_conditional_none"), role: .caption, muted: true)
                        .frame(minHeight: IUControlMetrics.forSize(.large).height)
                } else {
                    MenuBarLayoutChipFlowLayout(spacing: IUSpace.chipGap) {
                        ForEach(self.settings.menuBarLayoutConditionals, id: \.id) { conditional in
                            self.conditionalPaletteChip(conditional: conditional)
                        }
                    }
                }
                Spacer(minLength: 0)
                Button(L("menu_bar_layout_conditional_add"), systemImage: "plus") {
                    self.conditionalDraft = MenuBarLayoutConditionalDraft(
                        mode: .create,
                        conditional: .makeDefault())
                }
                .buttonStyle(.iu())
                .help(L("menu_bar_layout_conditional_add"))
            }
            .menuBarLayoutRowFrame()
        }
        .settingsAnchor(MenuBarSettingsPane.SearchID.layoutConditionals)
    }

    private func conditionalPaletteChip(conditional: MenuBarLayoutConditional) -> some View {
        MenuBarLayoutEditorChip(
            title: conditional.displayName,
            systemImage: "switch.2",
            accessibilityLabel: conditional.displayName,
            dragItem: .palette(.conditional(id: conditional.id)),
            activate: {
                self.write(MenuBarLayoutEditorMutations.append(.conditional(id: conditional.id), to: self.layout))
            })
            .contextMenu {
                Button(L("menu_bar_layout_conditional_edit")) {
                    self.conditionalDraft = MenuBarLayoutConditionalDraft(
                        mode: .edit(conditional.id),
                        conditional: conditional)
                }
                Button(L("menu_bar_layout_conditional_duplicate")) {
                    self.duplicateConditional(conditional)
                }
                Button(L("menu_bar_layout_conditional_remove"), role: .destructive) {
                    self.settings.removeMenuBarLayoutConditional(id: conditional.id)
                }
            }
    }

    private func duplicateConditional(_ conditional: MenuBarLayoutConditional) {
        let existingNames = Set(self.settings.menuBarLayoutConditionals.map { $0.name.lowercased() })
        let copyName = MenuBarLayoutConditional.uniqueCopyName(
            basedOn: conditional.name,
            existingNames: existingNames)
        let copy = MenuBarLayoutConditional(
            name: copyName,
            clauses: conditional.clauses,
            thenToken: conditional.thenToken,
            elseToken: conditional.elseToken)
        self.settings.menuBarLayoutConditionals.append(copy)
    }

    private func saveConditionalDraft(_ draft: MenuBarLayoutConditionalDraft) {
        switch draft.mode {
        case .create:
            self.settings.menuBarLayoutConditionals.append(draft.conditional)
        case let .edit(id):
            guard let index = self.settings.menuBarLayoutConditionals.firstIndex(where: { $0.id == id })
            else { return }
            self.settings.menuBarLayoutConditionals[index] = draft.conditional
        }
    }

    // MARK: - Display options

    private var displayOptions: some View {
        MenuBarLayoutDisplayOptions(
            size: self.sizeBinding,
            gap: self.gapBinding,
            verticalAdjustment: self.$settings.menuBarLayoutVerticalAdjustment,
            monospacedDigits: self.monospacedDigitsBinding,
            showWindowLabels: self.showWindowLabelsBinding)
    }

    // MARK: - Mutations

    private func applyPreset(_ preset: MenuBarLayoutPreset) {
        guard let layout = preset.layout else { return }
        self.selectedPosition = nil
        self.write(layout)
    }

    private func insert(_ item: MenuBarLayoutDragItem?, at position: MenuBarLayoutPosition) -> Bool {
        guard let item else { return false }
        let updated = MenuBarLayoutEditorMutations.insert(item, at: position, in: self.layout)
        guard updated != self.layout else { return false }
        self.write(updated)
        self.selectedPosition = nil
        return true
    }

    private func removeSelectedToken() {
        guard let selectedPosition else { return }
        self.remove(at: selectedPosition)
    }

    private func remove(at position: MenuBarLayoutPosition) {
        let updated = MenuBarLayoutEditorMutations.remove(at: position, from: self.layout)
        guard updated != self.layout else { return }
        self.write(updated)
        self.selectedPosition = nil
    }

    private func chipTitle(for token: MenuBarLayoutToken) -> String {
        if case let .conditional(id) = token {
            return self.settings.menuBarLayoutConditionals
                .first(where: { $0.id == id })?.displayName
                ?? L("menu_bar_layout_token_conditional")
        }
        return token.editorLabel(provider: self.persistenceProvider, snapshot: self.persistenceSnapshot)
    }

    private func chipAccessibilityLabel(for token: MenuBarLayoutToken) -> String {
        if case .conditional = token {
            return self.chipTitle(for: token)
        }
        return token.editorAccessibilityLabel(
            provider: self.persistenceProvider,
            snapshot: self.persistenceSnapshot)
    }

    private func write(_ layout: MenuBarLayout) {
        MenuBarLayoutEditorPersistence.activate(
            layout,
            for: self.persistenceProvider,
            settings: self.settings)
    }
}

/// Size, gap and vertical-offset controls, and the two text options, as settings rows. The body is a list of
/// rows with no container, so a `IUSettingsSection` draws a hairline between each.
struct MenuBarLayoutDisplayOptions: View {
    @Binding var size: MenuBarLayoutSize
    @Binding var gap: MenuBarLayoutGap
    @Binding var verticalAdjustment: Int
    @Binding var monospacedDigits: Bool
    @Binding var showWindowLabels: Bool

    static let verticalAdjustmentRange = -20...20

    var body: some View {
        IUSettingsRow(L("menu_bar_layout_size")) {
            IUSegmentedControl(MenuBarLayoutSize.allCases.map { ($0, $0.label) }, selection: self.$size)
                .accessibilityLabel(L("menu_bar_layout_size"))
                .accessibilityValue(self.size.label)
        }
        .settingsAnchor(MenuBarSettingsPane.SearchID.layoutSize)
        IUSettingsRow(L("menu_bar_layout_gap")) {
            IUSegmentedControl(MenuBarLayoutGap.allCases.map { ($0, $0.label) }, selection: self.$gap)
                .accessibilityLabel(L("menu_bar_layout_gap"))
                .accessibilityValue(self.gap.label)
        }
        .settingsAnchor(MenuBarSettingsPane.SearchID.layoutGap)
        IUSettingsRow(L("menu_bar_layout_vertical_adjustment")) {
            IUStepper(value: self.$verticalAdjustment, in: Self.verticalAdjustmentRange)
                .accessibilityLabel(L("menu_bar_layout_vertical_adjustment"))
        }
        .settingsAnchor(MenuBarSettingsPane.SearchID.layoutVertical)
        IUSettingsToggleRow(L("menu_bar_layout_monospaced_digits"), isOn: self.$monospacedDigits)
            .settingsAnchor(MenuBarSettingsPane.SearchID.layoutMonospacedDigits)
        IUSettingsToggleRow(L("menu_bar_layout_show_window_labels"), isOn: self.$showWindowLabels)
            .settingsAnchor(MenuBarSettingsPane.SearchID.layoutWindowLabels)
    }
}
