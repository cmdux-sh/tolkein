import CodexBarCore
import InternalUI
import SwiftUI

/// Menu Bar: the status item's icon style, its layout, the combined icon with Overview, and animation.
@MainActor
struct MenuBarSettingsPane: View {
    static let maxOverviewProviders = SettingsStore.mergedOverviewProviderLimit

    @Bindable var settings: SettingsStore
    @Bindable var store: UsageStore
    @State private var isOverviewProviderPopoverPresented = false

    init(context: SettingsPaneContext) {
        self.init(settings: context.settings, store: context.store)
    }

    init(settings: SettingsStore, store: UsageStore) {
        self.settings = settings
        self.store = store
    }

    var body: some View {
        MacSettingsPage(L("tab_menu_bar"), subtitle: L("settings_menu_bar_subtitle")) {
            self.iconSection
            MenuBarLayoutEditor(settings: self.settings, store: self.store)
            self.combinedIconSection
            self.overviewSection
            self.animationSection
        }
        .onAppear {
            self.reconcileOverviewSelection()
        }
        .onChange(of: self.settings.mergeIcons) { _, isEnabled in
            guard isEnabled else {
                self.isOverviewProviderPopoverPresented = false
                return
            }
            self.reconcileOverviewSelection()
        }
        .onChange(of: self.activeProvidersInOrder) { _, _ in
            if self.activeProvidersInOrder.isEmpty {
                self.isOverviewProviderPopoverPresented = false
            }
            self.reconcileOverviewSelection()
        }
    }

    // MARK: - Icon

    private var usesIconAndPercent: Bool {
        Self.layoutEditorEnabled(for: self.settings.menuBarIconStyle)
    }

    private var iconSection: some View {
        MacSettingsSection(L("section_icon")) {
            MacSettingsRow(L("menu_bar_style_title")) {
                MacPopUpButton(
                    MenuBarSettingsMenuOptions.iconStyles.map { ($0, $0.label) },
                    selection: self.$settings.menuBarIconStyle)
                    .accessibilityLabel(L("menu_bar_style_title"))
            }
            .settingsAnchor(SearchID.iconStyle)

            MacSettingsToggleRow(
                L("menu_bar_inactive_display_contrast_title"),
                subtitle: L("menu_bar_inactive_display_contrast_subtitle"),
                disabledReason: Self.requiresIconAndPercentReason,
                isOn: self.$settings.menuBarHighContrastOnInactiveDisplays)
                .disabled(!self.usesIconAndPercent)
                .settingsAnchor(SearchID.inactiveDisplayContrast)

            MacSettingsToggleRow(
                L("Color Pace Indicator"),
                subtitle: L("settings_color_pace_subtitle"),
                disabledReason: Self.requiresIconAndPercentReason,
                isOn: self.$settings.menuBarColorPace)
                .disabled(!self.usesIconAndPercent)
                .settingsAnchor(SearchID.colorPace)

            MacSettingsRow(L("Pace sign"), disabledReason: Self.requiresIconAndPercentReason) {
                MacPopUpButton(
                    [(false, L("Ahead of pace is +")), (true, L("Reserve is +"))],
                    selection: self.$settings.menuBarPaceReservePositive)
                    .accessibilityLabel(L("Pace sign"))
            }
            .disabled(!self.usesIconAndPercent)
            .settingsAnchor(SearchID.paceSign)

            MacSettingsToggleRow(L("Color by provider"), isOn: self.$settings.menuBarColorByProvider)
                .settingsAnchor(SearchID.colorByProvider)
        }
    }

    // MARK: - Combined icon

    private var mergedIconPresentation: MergedIconPresentation {
        self.settings.mergedIconPresentation(activeProviders: self.store.enabledFirstPartyProvidersForDisplay())
    }

    private var combinedIconSection: some View {
        let presentation = self.mergedIconPresentation
        let mergeIcons = self.settings.mergeIcons
        return MacSettingsSection(L("section_combined_icon")) {
            MacSettingsToggleRow(
                L("merge_icons_title"),
                subtitle: L("merge_icons_subtitle"),
                isOn: self.$settings.mergeIcons)
                .settingsAnchor(SearchID.mergeIcons)

            MacSettingsRow(
                L("merged_icon_style_title"),
                subtitle: L("merged_icon_style_subtitle"),
                disabledReason: Self.mergedIconStyleDisabledReason(
                    mergeIcons: mergeIcons,
                    iconStyle: self.settings.menuBarIconStyle,
                    eligibleProviderCount: presentation.eligibleProviders.count))
            {
                MacPopUpButton(
                    MenuBarSettingsMenuOptions.mergedIconStyles.map { ($0, $0.label) },
                    selection: Binding(
                        get: { self.mergedIconPresentation.effectiveStyle },
                        set: { self.settings.mergedIconDisplayStyle = $0 }))
                    .accessibilityLabel(L("merged_icon_style_title"))
            }
            .disabled(!presentation.canStack)
            .settingsAnchor(SearchID.mergedIconStyle)

            if let pair = presentation.stackedProviders {
                self.stackedRowProviderRow(
                    title: L("merge_icon_stacked_top_provider_title"),
                    selection: Binding(
                        get: { self.mergedIconPresentation.topSelection },
                        set: { self.settings.mergeIconStackedTopProvider = $0 }),
                    excluding: presentation.bottomSelection,
                    automaticProvider: pair.top)
                    .settingsAnchor(SearchID.stackedTopRow)
                self.stackedRowProviderRow(
                    title: L("merge_icon_stacked_bottom_provider_title"),
                    selection: Binding(
                        get: { self.mergedIconPresentation.bottomSelection },
                        set: { self.settings.mergeIconStackedBottomProvider = $0 }),
                    excluding: presentation.topSelection,
                    automaticProvider: pair.bottom)
                    .settingsAnchor(SearchID.stackedBottomRow)
            }

            MacSettingsRow(L("switcher_rows_title"), disabledReason: Self.mergeIconsReason) {
                MacPopUpButton(
                    MenuBarSettingsMenuOptions.switcherRows.map { ($0, $0.label) },
                    selection: self.$settings.switcherRowsOption)
                    .accessibilityLabel(L("switcher_rows_title"))
            }
            .disabled(!mergeIcons)
            .settingsAnchor(SearchID.switcherRows)

            UnifiedIconSourcePicker(
                selection: self.$settings.unifiedIconSource,
                disabledReason: Self.iconSourceDisabledReason(
                    mergeIcons: mergeIcons,
                    effectiveStyle: presentation.effectiveStyle))
                .disabled(!mergeIcons || presentation.effectiveStyle == .stacked)
                .settingsAnchor(SearchID.iconSource)
        }
    }

    private func stackedRowProviderRow(
        title: String,
        selection: Binding<UsageProvider?>,
        excluding: UsageProvider?,
        automaticProvider: UsageProvider) -> some View
    {
        let options: [UsageProvider?] = [nil] + self.mergedIconPresentation.eligibleProviders.filter { $0 != excluding }
        return MacSettingsRow(title) {
            MacPopUpButton(
                options.map { provider in
                    (
                        provider,
                        provider.map(self.providerDisplayName)
                            ?? "\(L("Automatic")) (\(self.providerDisplayName(automaticProvider)))")
                },
                selection: selection)
                .accessibilityLabel(title)
        }
    }

    // MARK: - Overview

    private var overviewSection: some View {
        let mergeIcons = self.settings.mergeIcons
        return MacSettingsSection(L("Overview")) {
            MacSettingsRow(
                L("overview_tab_providers_title"),
                subtitle: Self.overviewProviderSubtitle(
                    mergeIcons: mergeIcons,
                    hasProviders: !self.activeProvidersInOrder.isEmpty,
                    selectedNames: self.overviewSelectedProviders.map(self.providerDisplayName)),
                disabledReason: L("overview_enable_merge_icons_hint"))
            {
                Button(L("configure")) {
                    self.isOverviewProviderPopoverPresented = true
                }
                .buttonStyle(.mac())
                .disabled(self.activeProvidersInOrder.isEmpty)
                .popover(isPresented: self.$isOverviewProviderPopoverPresented, arrowEdge: .bottom) {
                    MenuBarOverviewProviderPicker(
                        providers: self.activeProvidersInOrder,
                        selected: self.overviewSelectedProviders,
                        limit: Self.maxOverviewProviders,
                        name: self.providerDisplayName,
                        setSelection: self.setOverviewProviderSelection)
                }
            }
            .disabled(!mergeIcons)
            .settingsAnchor(SearchID.overviewProviders)

            MacSettingsToggleRow(
                L("Show all accounts in Overview"),
                subtitle: L("Expand cached account usage. The six-provider limit still applies."),
                disabledReason: Self.mergeIconsReason,
                isOn: self.$settings.mergedOverviewAllAccounts)
                .disabled(!mergeIcons)
                .settingsAnchor(SearchID.overviewAllAccounts)

            MacSettingsRow(
                L("overview_layout_title"),
                subtitle: L("overview_layout_subtitle"),
                disabledReason: Self.mergeIconsReason)
            {
                MacPopUpButton(
                    MenuBarSettingsMenuOptions.mergedOverviewLayouts.map { ($0, $0.label) },
                    selection: self.$settings.mergedOverviewLayout)
                    .accessibilityLabel(L("overview_layout_title"))
            }
            .disabled(!mergeIcons)
            .settingsAnchor(SearchID.overviewLayout)
        }
    }

    private var activeProvidersInOrder: [ProviderInstanceID] {
        self.store.enabledProvidersForDisplay()
    }

    private var overviewSelectedProviders: [ProviderInstanceID] {
        self.settings.resolvedMergedOverviewProviders(
            activeProviders: self.activeProvidersInOrder,
            maxVisibleProviders: Self.maxOverviewProviders)
    }

    private func providerDisplayName(_ instanceID: ProviderInstanceID) -> String {
        if let provider = instanceID.firstPartyProvider { return self.providerDisplayName(provider) }
        return UserProviderPluginRegistry.plugin(for: instanceID)?.manifest.name ?? instanceID.rawValue
    }

    private func providerDisplayName(_ provider: UsageProvider) -> String {
        ProviderDescriptorRegistry.descriptor(for: provider).metadata.displayName
    }

    private func setOverviewProviderSelection(provider: ProviderInstanceID, isSelected: Bool) {
        _ = self.settings.setMergedOverviewProviderSelection(
            provider: provider,
            isSelected: isSelected,
            activeProviders: self.activeProvidersInOrder,
            maxVisibleProviders: Self.maxOverviewProviders)
    }

    private func reconcileOverviewSelection() {
        _ = self.settings.reconcileMergedOverviewSelectedProviders(
            activeProviders: self.activeProvidersInOrder,
            maxVisibleProviders: Self.maxOverviewProviders)
    }

    // MARK: - Animation

    private var animationSection: some View {
        MacSettingsSection(L("section_animation")) {
            MacSettingsToggleRow(
                L("surprise_me_title"),
                subtitle: L("surprise_me_subtitle"),
                disabledReason: Self.brandIconsReason,
                isOn: self.$settings.randomBlinkEnabled)
                // Brand icons (including stacked rows, which require them) never draw blink frames.
                    .disabled(self.settings.menuBarShowsBrandIconWithPercent)
                    .settingsAnchor(SearchID.surpriseMe)
        }
    }
}

// MARK: - Rules

extension MenuBarSettingsPane {
    static func overviewProviderLimitText(limit: Int = Self.maxOverviewProviders) -> String {
        L("overview_choose_providers", String(limit))
    }

    /// The layout editor, and the icon options that only the brand icon draws, need the Icon & percent style.
    static func layoutEditorEnabled(for style: MenuBarIconStyle) -> Bool {
        style == .iconAndPercent
    }

    static func layoutFooterText(for style: MenuBarIconStyle) -> String {
        self.layoutEditorEnabled(for: style)
            ? L("menu_bar_layout_footer")
            : L("menu_bar_layout_footer_requires_icon_and_percent", MenuBarIconStyle.iconAndPercent.label)
    }

    static var requiresIconAndPercentReason: String {
        L("settings_reason_requires_style", MenuBarIconStyle.iconAndPercent.label)
    }

    static var mergeIconsReason: String {
        L("settings_reason_requires_setting", L("merge_icons_title"))
    }

    /// Animation draws only on the Critters and Meter bars icons.
    static var brandIconsReason: String {
        L("settings_reason_brand_icons", MenuBarIconStyle.critters.label, MenuBarIconStyle.bars.label)
    }

    /// Why the combined icon style can't be changed, in the order `MergedIconPresentation.canStack` checks.
    static func mergedIconStyleDisabledReason(
        mergeIcons: Bool,
        iconStyle: MenuBarIconStyle,
        eligibleProviderCount: Int) -> String?
    {
        if !mergeIcons { return self.mergeIconsReason }
        if !self.layoutEditorEnabled(for: iconStyle) { return self.requiresIconAndPercentReason }
        if eligibleProviderCount < 2 { return L("settings_reason_two_providers") }
        return nil
    }

    /// Why the combined icon source can't be changed: it needs Merge icons, and Stacked picks its rows instead.
    static func iconSourceDisabledReason(mergeIcons: Bool, effectiveStyle: MergedIconDisplayStyle) -> String? {
        if !mergeIcons { return self.mergeIconsReason }
        if effectiveStyle ==
            .stacked { return L("settings_reason_stacked_source", MergedIconDisplayStyle.stacked.label) }
        return nil
    }

    /// The Overview providers row's subtitle: the chosen providers, or why there are none. Without Merge icons the
    /// row's disabled reason explains instead.
    static func overviewProviderSubtitle(mergeIcons: Bool, hasProviders: Bool, selectedNames: [String]) -> String? {
        guard mergeIcons else { return nil }
        guard hasProviders else { return L("overview_no_providers_hint") }
        guard !selectedNames.isEmpty else { return L("overview_no_providers_selected") }
        return selectedNames.joined(separator: ", ")
    }
}

/// The Configure… popover: one switch per enabled provider, at most `limit` on, in provider order.
@MainActor
struct MenuBarOverviewProviderPicker: View {
    let providers: [ProviderInstanceID]
    let selected: [ProviderInstanceID]
    let limit: Int
    let name: (ProviderInstanceID) -> String
    let setSelection: (ProviderInstanceID, Bool) -> Void

    var body: some View {
        let limitText = MenuBarSettingsPane.overviewProviderLimitText(limit: self.limit)
        VStack(alignment: .leading, spacing: MacSpace.settingsHeaderGap) {
            MacText(limitText, role: .subtitle)
            MacText(L("overview_rows_follow_order"), role: .caption, muted: true)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView(.vertical) {
                MacSettingsSection {
                    ForEach(self.providers, id: \.self) { provider in
                        MacSettingsToggleRow(
                            self.name(provider),
                            disabledReason: limitText,
                            isOn: Binding(
                                get: { self.selected.contains(provider) },
                                set: { self.setSelection(provider, $0) }))
                            .disabled(!self.selected.contains(provider) && self.selected.count >= self.limit)
                    }
                }
                .padding(.vertical, MacSpace.unit)
                .macSlimScrollers()
            }
            // About six rows, then it scrolls.
            .frame(maxHeight: MacSize.settingsRow * 6)
        }
        .padding(MacSpace.settingsPagePadding)
        .frame(width: MacSize.inspectorWidth + MacSpace.settingsPagePadding * 2)
    }
}

// MARK: - Options and search

enum MenuBarSettingsMenuOptions {
    static let iconStyles = MenuBarIconStyle.allCases
    static let switcherRows = SwitcherRowsOption.allCases
    static let mergedIconStyles = MergedIconDisplayStyle.allCases
    static let unifiedIconSources = UnifiedIconSource.allCases
    static let mergedOverviewLayouts = MergedOverviewLayout.allCases
}

extension MenuBarSettingsPane {
    /// The pane's searchable settings. Each row marks itself with `.settingsAnchor(_:)` for its case.
    enum SearchID: String, CaseIterable {
        case iconStyle
        case inactiveDisplayContrast
        case colorPace
        case paceSign
        case colorByProvider
        case layout
        case layoutPreset
        case layoutConditionals
        case layoutSize
        case layoutGap
        case layoutVertical
        case layoutMonospacedDigits
        case layoutWindowLabels
        case mergeIcons
        case mergedIconStyle
        case stackedTopRow
        case stackedBottomRow
        case switcherRows
        case iconSource
        case overviewProviders
        case overviewAllAccounts
        case overviewLayout
        case surpriseMe

        var entryID: String {
            "\(SettingsPane.menuBar.persistenceToken)/\(self.rawValue)"
        }
    }

    static var searchEntries: [SettingsSearchEntry] {
        let pane = SettingsPane.menuBar
        let icon = L("section_icon")
        let layout = L("menu_bar_layout_title")
        let display = L("Display")
        let combinedIcon = L("section_combined_icon")
        let overview = L("Overview")
        let animation = L("section_animation")
        return [
            .paneTitle(pane),
            pane.searchEntry(SearchID.iconStyle.rawValue, L("menu_bar_style_title"), keywords: icon),
            pane.searchEntry(
                SearchID.inactiveDisplayContrast.rawValue,
                L("menu_bar_inactive_display_contrast_title"),
                keywords: icon,
                L("menu_bar_inactive_display_contrast_subtitle")),
            pane.searchEntry(
                SearchID.colorPace.rawValue,
                L("Color Pace Indicator"),
                keywords: icon,
                L("settings_color_pace_subtitle")),
            pane.searchEntry(
                SearchID.paceSign.rawValue,
                L("Pace sign"),
                keywords: icon,
                L("Reserve is +"),
                L("Ahead of pace is +")),
            pane.searchEntry(SearchID.colorByProvider.rawValue, L("Color by provider"), keywords: icon),
            pane.searchEntry(
                SearchID.layout.rawValue,
                layout,
                keywords: L("Scope"),
                L("menu_bar_layout_scope_help"),
                L("menu_bar_layout_strip")),
            pane.searchEntry(SearchID.layoutPreset.rawValue, L("menu_bar_layout_preset"), keywords: layout),
            pane.searchEntry(
                SearchID.layoutConditionals.rawValue,
                L("menu_bar_layout_group_conditionals"),
                keywords: layout,
                L("menu_bar_layout_conditional_add")),
            pane.searchEntry(SearchID.layoutSize.rawValue, L("menu_bar_layout_size"), keywords: layout, display),
            pane.searchEntry(SearchID.layoutGap.rawValue, L("menu_bar_layout_gap"), keywords: layout, display),
            pane.searchEntry(
                SearchID.layoutVertical.rawValue,
                L("menu_bar_layout_vertical_adjustment"),
                keywords: layout,
                display),
            pane.searchEntry(
                SearchID.layoutMonospacedDigits.rawValue,
                L("menu_bar_layout_monospaced_digits"),
                keywords: layout,
                display),
            pane.searchEntry(
                SearchID.layoutWindowLabels.rawValue,
                L("menu_bar_layout_show_window_labels"),
                keywords: layout,
                display),
            pane.searchEntry(
                SearchID.mergeIcons.rawValue,
                L("merge_icons_title"),
                keywords: combinedIcon,
                L("merge_icons_subtitle")),
            pane.searchEntry(SearchID.mergedIconStyle.rawValue, L("merged_icon_style_title"), keywords: combinedIcon),
            pane.searchEntry(
                SearchID.stackedTopRow.rawValue,
                L("merge_icon_stacked_top_provider_title"),
                keywords: combinedIcon),
            pane.searchEntry(
                SearchID.stackedBottomRow.rawValue,
                L("merge_icon_stacked_bottom_provider_title"),
                keywords: combinedIcon),
            pane.searchEntry(SearchID.switcherRows.rawValue, L("switcher_rows_title"), keywords: combinedIcon),
            pane.searchEntry(SearchID.iconSource.rawValue, L("merged_icon_source_title"), keywords: combinedIcon),
            pane.searchEntry(
                SearchID.overviewProviders.rawValue,
                L("overview_tab_providers_title"),
                keywords: overview,
                combinedIcon),
            pane.searchEntry(
                SearchID.overviewAllAccounts.rawValue,
                L("Show all accounts in Overview"),
                keywords: overview,
                combinedIcon),
            pane.searchEntry(
                SearchID.overviewLayout.rawValue,
                L("overview_layout_title"),
                keywords: overview,
                L("overview_layout_subtitle")),
            pane.searchEntry(
                SearchID.surpriseMe.rawValue,
                L("surprise_me_title"),
                keywords: animation,
                L("surprise_me_subtitle")),
        ]
    }
}

extension View {
    /// Marks a Menu Bar row as the destination of its search entry.
    func settingsAnchor(_ id: MenuBarSettingsPane.SearchID) -> some View {
        self.settingsAnchor(id.entryID)
    }
}
