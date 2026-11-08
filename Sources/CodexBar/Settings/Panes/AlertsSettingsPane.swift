import SwiftUI

/// Alerts: notifications for quota, resets and credentials, plus the reset celebrations.
/// Shows the old `NotificationsPane` until the Internal UI rebuild replaces this file.
@MainActor
struct AlertsSettingsPane: View {
    let context: SettingsPaneContext

    var body: some View {
        NotificationsPane(settings: self.context.settings)
    }
}

extension AlertsSettingsPane {
    static var searchEntries: [SettingsSearchEntry] {
        let pane = SettingsPane.alerts
        let notifications = L("tab_notifications")
        return [
            .paneTitle(pane, keywords: notifications),
            pane.searchEntry("credentialExpiry", L("credential_expiry_notifications_title"), keywords: notifications),
            pane.searchEntry("quotaDepleted", L("quota_depleted_title"), keywords: notifications),
            pane.searchEntry("thresholdWarnings", L("threshold_warnings_title"), keywords: notifications),
            pane.searchEntry("predictivePace", L("predictive_pace_warnings_title"), keywords: notifications),
            pane.searchEntry("limitReset", L("limit_reset_notifications_title"), keywords: notifications),
            pane.searchEntry(
                "resetCreditExpiry",
                L("codex_reset_credit_expiry_notifications_title"),
                keywords: notifications),
            pane.searchEntry("upcomingReset", L("upcoming_reset_notifications_title"), keywords: notifications),
            pane.searchEntry("confetti", L("confetti_on_reset_title"), keywords: L("section_celebrations")),
        ]
    }
}
