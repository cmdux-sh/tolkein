import SwiftUI

/// Menu: what the menu cards show, widgets, agent sessions and the cost summary.
/// Shows the old `MenuPane` until the Internal UI rebuild replaces this file.
@MainActor
struct MenuSettingsPane: View {
    let context: SettingsPaneContext

    var body: some View {
        MenuPane(settings: self.context.settings, store: self.context.store)
    }
}

extension MenuSettingsPane {
    static var searchEntries: [SettingsSearchEntry] {
        let pane = SettingsPane.menu
        let usage = L("section_usage")
        let content = L("section_content")
        let agentSessions = L("section_agent_sessions")
        let costSummary = L("section_cost_summary")
        return [
            .paneTitle(pane),
            pane.searchEntry("usageBarsFill", L("usage_bars_fill_title"), keywords: usage),
            pane.searchEntry("quotaWarningMarkers", L("show_quota_warning_markers_title"), keywords: usage),
            pane.searchEntry("pace", L("show_pace_title"), keywords: usage),
            pane.searchEntry("workDays", L("weekly_progress_work_days_title"), keywords: usage),
            pane.searchEntry("workdayTicks", L("workday_tick_appearance_title"), keywords: usage),
            pane.searchEntry("resetTimes", L("reset_times_title"), keywords: usage),
            pane.searchEntry("changelogLinks", L("show_provider_changelog_links_title"), keywords: content),
            pane.searchEntry("hoverHighlight", L("highlight_menu_cards_on_hover_title"), keywords: content),
            pane.searchEntry("overviewLayout", L("overview_layout_title"), keywords: content),
            pane.searchEntry("creditsExtraUsage", L("show_credits_extra_usage_title"), keywords: content),
            pane.searchEntry("multiAccountLayout", L("multi_account_layout_title"), keywords: content),
            pane.searchEntry("accountWidgets", L("account_widgets_title"), keywords: L("section_widgets")),
            pane.searchEntry("stayAwake", L("Stay Awake"), keywords: agentSessions),
            pane.searchEntry("agentSessions", L("agent_sessions_title"), keywords: agentSessions),
            pane.searchEntry("agentSessionLabels", L("agent_session_labels_title"), keywords: agentSessions),
            pane.searchEntry("agentSessionsRemote", L("agent_sessions_remote_title"), keywords: agentSessions),
            pane.searchEntry("agentSessionHosts", L("agent_sessions_hosts_title"), keywords: agentSessions),
            pane.searchEntry("costSummary", L("cost_summary_title"), keywords: costSummary),
            pane.searchEntry("costComparison", L("cost_comparison_periods_title"), keywords: costSummary),
        ]
    }
}
