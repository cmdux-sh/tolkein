import AppKit
import CodexBarCore
import InternalUI
import SwiftUI

/// Menu: what the menu cards show, the cost summary, agent sessions and widgets.
@MainActor
struct MenuSettingsPane: View {
    @Bindable var settings: SettingsStore
    @Bindable var store: UsageStore

    init(context: SettingsPaneContext) {
        self.init(settings: context.settings, store: context.store)
    }

    init(settings: SettingsStore, store: UsageStore) {
        self.settings = settings
        self.store = store
    }

    var body: some View {
        MacSettingsPage(L("tab_menu"), subtitle: L("settings_menu_subtitle")) {
            VStack(alignment: .leading, spacing: MacSpace.settingsSectionGap) {
                self.usageSection
                self.contentSection
                CostSummarySettingsSection(settings: self.settings, store: self.store)
                AgentSessionsSettingsSection(settings: self.settings)
                self.widgetsSection
            }
            // A click between the sections ends editing in the text fields, as it did in the old pane.
            .background(MenuSettingsFocusResigner())
        }
    }

    // MARK: - Usage

    private var usageSection: some View {
        MacSettingsSection(L("section_usage")) {
            MacSettingsRow(L("usage_bars_fill_title")) {
                MacPopUpButton(
                    MenuSettingsMenuOptions.usageBarsFill.map { ($0, $0.label) },
                    selection: self.$settings.usageBarsFillOption)
                    .accessibilityLabel(L("usage_bars_fill_title"))
            }
            .settingsAnchor(SearchID.usageBarsFill)

            MacSettingsToggleRow(
                L("show_pace_title"),
                subtitle: L("show_pace_subtitle"),
                isOn: self.$settings.paceVisible)
                .settingsAnchor(SearchID.pace)

            MacSettingsRow(
                L("weekly_progress_work_days_title"),
                subtitle: L("weekly_progress_work_days_subtitle"))
            {
                MacPopUpButton(
                    MenuSettingsPopUpOptions.options(
                        MenuSettingsMenuOptions.weeklyProgressWorkDays,
                        selection: self.settings.weeklyProgressWorkDays,
                        label: MenuSettingsMenuOptions.weeklyProgressWorkDaysLabel),
                    selection: self.$settings.weeklyProgressWorkDays)
                    .accessibilityLabel(L("weekly_progress_work_days_title"))
            }
            .settingsAnchor(SearchID.workDays)

            MacSettingsRow(
                L("workday_tick_appearance_title"),
                subtitle: L("workday_tick_appearance_subtitle"),
                disabledReason: L("settings_reason_work_days_automatic"))
            {
                MacPopUpButton(
                    MenuSettingsMenuOptions.workdayTickAppearances.map { ($0, $0.label) },
                    selection: self.$settings.workdayTickAppearance)
                    .accessibilityLabel(L("workday_tick_appearance_title"))
            }
            // Automatic work days draw no workday ticks to style.
            .disabled(self.settings.weeklyProgressWorkDays == nil)
            .settingsAnchor(SearchID.workdayTicks)

            MacSettingsRow(L("reset_times_title")) {
                MacPopUpButton(
                    MenuSettingsMenuOptions.resetTimes.map { ($0, $0.label) },
                    selection: self.$settings.resetTimesOption)
                    .accessibilityLabel(L("reset_times_title"))
            }
            .settingsAnchor(SearchID.resetTimes)
        }
    }

    // MARK: - Content

    private var contentSection: some View {
        MacSettingsSection(L("section_content")) {
            MacSettingsToggleRow(
                L("show_provider_changelog_links_title"),
                subtitle: L("show_provider_changelog_links_subtitle"),
                isOn: self.$settings.providerChangelogLinksEnabled)
                .settingsAnchor(SearchID.changelogLinks)

            MacSettingsToggleRow(
                L("highlight_menu_cards_on_hover_title"),
                isOn: self.$settings.highlightMenuCardsOnHover)
                .settingsAnchor(SearchID.hoverHighlight)

            MacSettingsToggleRow(
                L("show_credits_extra_usage_title"),
                subtitle: L("show_credits_extra_usage_subtitle"),
                isOn: self.$settings.showOptionalCreditsAndExtraUsage)
                .settingsAnchor(SearchID.creditsExtraUsage)

            MacSettingsRow(L("multi_account_layout_title")) {
                MacPopUpButton(
                    MenuSettingsMenuOptions.multiAccountLayouts.map { ($0, $0.label) },
                    selection: self.$settings.multiAccountMenuLayout)
                    .accessibilityLabel(L("multi_account_layout_title"))
            }
            .settingsAnchor(SearchID.multiAccountLayout)
        }
    }

    // MARK: - Widgets

    private var widgetsSection: some View {
        MacSettingsSection(L("section_widgets")) {
            MacSettingsToggleRow(
                L("account_widgets_title"),
                subtitle: L("account_widgets_description"),
                isOn: self.$settings.accountWidgetsEnabled)
                .onChange(of: self.settings.accountWidgetsEnabled) { _, enabled in
                    self.store.persistWidgetSnapshot(reason: "account-widgets-setting")
                    if enabled {
                        Task { await self.store.refresh() }
                    }
                }
                .settingsAnchor(SearchID.accountWidgets)
        }
    }
}

/// Clicking empty space in the pane ends text editing, so a typed value commits without pressing Return.
private struct MenuSettingsFocusResigner: View {
    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture {
                NSApplication.shared.keyWindow?.makeFirstResponder(nil)
            }
    }
}

// MARK: - Shared pieces

/// Pop-up choices for a setting. A pop-up shows only a selection it lists, so a value imported from elsewhere
/// that is not one of the usual choices is listed after them.
enum MenuSettingsPopUpOptions {
    static func options<Value: Hashable>(
        _ values: [Value],
        selection: Value,
        label: (Value) -> String) -> [(Value, String)]
    {
        let shown = values.contains(selection) ? values : values + [selection]
        return shown.map { ($0, label($0)) }
    }
}

/// A number typed into the library's control well, for values with a wide range. Like a native number field, it
/// commits on Return or when focus leaves, not on every keystroke.
struct MenuSettingsNumberField<Format: ParseableFormatStyle>: View where Format.FormatOutput == String {
    let title: String
    @Binding var value: Format.FormatInput
    let format: Format

    @Environment(\.macControlSize) private var controlSize
    @FocusState private var isFocused: Bool

    var body: some View {
        let metrics = MacControlMetrics.forSize(self.controlSize)
        TextField(self.title, value: self.$value, format: self.format)
            .labelsHidden()
            .textFieldStyle(.plain)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .font(MacTextRole.body.font)
            .focused(self.$isFocused)
            .padding(.horizontal, metrics.paddingX)
            .frame(width: MacSize.control * 2, height: metrics.height)
            .macWell(radius: metrics.radius)
            .macFocusRing(self.isFocused, radius: metrics.radius)
            .accessibilityLabel(self.title)
    }
}

// MARK: - Options and search

enum MenuSettingsMenuOptions {
    static let weeklyProgressWorkDays: [Int?] = [nil, 4, 5, 6, 7]
    static let workdayTickAppearances = WorkdayTickAppearance.allCases
    static let multiAccountLayouts = MultiAccountMenuLayout.allCases
    static let usageBarsFill = UsageBarsFillOption.allCases
    static let resetTimes = ResetTimesOption.allCases
    static let costSummaries = CostSummaryOption.allCases
    static let agentSessionLabelStyles = AgentSessionLabelStyle.allCases

    static func weeklyProgressWorkDaysLabel(_ workDays: Int?) -> String {
        switch workDays {
        case nil: L("Automatic")
        case 4: L("4 days")
        case 5: L("5 days")
        case 7: L("7 days")
        case let workDays?: L("%d days", workDays)
        }
    }
}

extension MenuSettingsPane {
    /// The pane's searchable settings. Each row marks itself with `.settingsAnchor(_:)` for its case.
    enum SearchID: String, CaseIterable {
        case usageBarsFill
        case pace
        case workDays
        case workdayTicks
        case resetTimes
        case changelogLinks
        case hoverHighlight
        case creditsExtraUsage
        case multiAccountLayout
        case costSummary
        case costHistoryWindow
        case costRollingDays
        case costComparison
        case stayAwake
        case agentSessions
        case agentSessionLabels
        case agentSessionsRemote
        case agentSessionsHideUnreachable
        case agentSessionHosts
        case accountWidgets

        var entryID: String {
            "\(SettingsPane.menu.persistenceToken)/\(self.rawValue)"
        }
    }

    static var searchEntries: [SettingsSearchEntry] {
        let pane = SettingsPane.menu
        let usage = L("section_usage")
        let content = L("section_content")
        let costSummary = L("section_cost_summary")
        let agentSessions = L("section_agent_sessions")
        return [
            .paneTitle(pane),
            pane.searchEntry(SearchID.usageBarsFill.rawValue, L("usage_bars_fill_title"), keywords: usage),
            pane.searchEntry(SearchID.pace.rawValue, L("show_pace_title"), keywords: usage, L("show_pace_subtitle")),
            pane.searchEntry(
                SearchID.workDays.rawValue,
                L("weekly_progress_work_days_title"),
                keywords: usage,
                L("weekly_progress_work_days_subtitle")),
            pane.searchEntry(SearchID.workdayTicks.rawValue, L("workday_tick_appearance_title"), keywords: usage),
            pane.searchEntry(SearchID.resetTimes.rawValue, L("reset_times_title"), keywords: usage),
            pane.searchEntry(
                SearchID.changelogLinks.rawValue,
                L("show_provider_changelog_links_title"),
                keywords: content),
            pane.searchEntry(
                SearchID.hoverHighlight.rawValue,
                L("highlight_menu_cards_on_hover_title"),
                keywords: content),
            pane.searchEntry(
                SearchID.creditsExtraUsage.rawValue,
                L("show_credits_extra_usage_title"),
                keywords: content),
            pane.searchEntry(SearchID.multiAccountLayout.rawValue, L("multi_account_layout_title"), keywords: content),
            pane.searchEntry(
                SearchID.costSummary.rawValue,
                L("cost_summary_title"),
                keywords: costSummary,
                L("show_cost_summary_subtitle")),
            pane.searchEntry(
                SearchID.costHistoryWindow.rawValue,
                L("cost_history_window_title"),
                keywords: costSummary,
                L("cost_history_window_help")),
            pane.searchEntry(
                SearchID.costRollingDays.rawValue,
                L("cost_history_rolling_days_title"),
                keywords: costSummary,
                L("cost_history_window_title")),
            pane.searchEntry(
                SearchID.costComparison.rawValue,
                L("cost_comparison_periods_title"),
                keywords: costSummary),
            pane.searchEntry(SearchID.stayAwake.rawValue, L("Stay Awake"), keywords: agentSessions),
            pane.searchEntry(SearchID.agentSessions.rawValue, L("agent_sessions_title"), keywords: agentSessions),
            pane.searchEntry(
                SearchID.agentSessionLabels.rawValue,
                L("agent_session_labels_title"),
                keywords: agentSessions),
            pane.searchEntry(
                SearchID.agentSessionsRemote.rawValue,
                L("agent_sessions_remote_title"),
                keywords: agentSessions),
            pane.searchEntry(
                SearchID.agentSessionsHideUnreachable.rawValue,
                L("agent_sessions_hide_unreachable_title"),
                keywords: agentSessions),
            pane.searchEntry(
                SearchID.agentSessionHosts.rawValue,
                L("agent_sessions_hosts_title"),
                keywords: agentSessions,
                L("agent_sessions_hosts_help")),
            pane.searchEntry(
                SearchID.accountWidgets.rawValue,
                L("account_widgets_title"),
                keywords: L("section_widgets")),
        ]
    }
}

extension View {
    /// Marks a Menu row as the destination of its search entry.
    func settingsAnchor(_ id: MenuSettingsPane.SearchID) -> some View {
        self.settingsAnchor(id.entryID)
    }
}
