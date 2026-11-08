import InternalUI
import SwiftUI

/// Alerts: notifications for sign-in, credits, quota and resets, how quota warnings arrive, the usage-bar warning
/// markers and the reset celebrations. Every global quota-warning control is here; each provider's page can
/// override the thresholds (`ProviderQuotaWarningSettingsView`).
@MainActor
struct AlertsSettingsPane: View {
    let context: SettingsPaneContext

    var body: some View {
        AlertsSettingsPage(settings: self.context.settings)
    }
}

/// The Alerts page itself, which needs only the settings.
@MainActor
struct AlertsSettingsPage: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        let visibility = QuotaWarningSettingsVisibility(
            thresholdWarningsEnabled: self.settings.quotaWarningNotificationsEnabled,
            predictiveWarningsEnabled: self.settings.predictivePaceWarningNotificationsEnabled)

        MacSettingsPage(SettingsPane.alerts.title, subtitle: L("settings_alerts_subtitle")) {
            MacSettingsSection(L("settings_alerts_section_sign_in")) {
                MacSettingsToggleRow(
                    L("credential_expiry_notifications_title"),
                    subtitle: L("credential_expiry_notifications_subtitle"),
                    isOn: self.$settings.credentialExpiryNotificationsEnabled)
                    .settingsAnchor(AlertsSettingsPane.Setting.credentialExpiry.id)
                MacSettingsToggleRow(
                    L("codex_reset_credit_expiry_notifications_title"),
                    subtitle: L("codex_reset_credit_expiry_notifications_subtitle"),
                    isOn: self.$settings.codexResetCreditExpiryNotificationsEnabled)
                    .settingsAnchor(AlertsSettingsPane.Setting.resetCreditExpiry.id)
            }

            MacSettingsSection(
                L("settings_alerts_section_quota"),
                footer: visibility.showsThresholdControls ? L("quota_warning_global_threshold_subtitle") : nil)
            {
                MacSettingsToggleRow(
                    L("quota_depleted_title"),
                    subtitle: L("session_quota_notifications_subtitle"),
                    isOn: self.$settings.sessionQuotaNotificationsEnabled)
                    .settingsAnchor(AlertsSettingsPane.Setting.quotaDepleted.id)
                MacSettingsToggleRow(
                    L("upcoming_reset_notifications_title"),
                    subtitle: L("upcoming_reset_notifications_subtitle"),
                    isOn: self.$settings.upcomingResetNotificationsEnabled)
                    .settingsAnchor(AlertsSettingsPane.Setting.upcomingReset.id)
                MacSettingsToggleRow(
                    L("limit_reset_notifications_title"),
                    subtitle: L("limit_reset_notifications_subtitle"),
                    isOn: self.$settings.limitResetNotificationsEnabled)
                    .settingsAnchor(AlertsSettingsPane.Setting.limitReset.id)
                MacSettingsToggleRow(
                    L("predictive_pace_warnings_title"),
                    subtitle: L("predictive_pace_warnings_subtitle"),
                    isOn: self.$settings.predictivePaceWarningNotificationsEnabled)
                    .settingsAnchor(AlertsSettingsPane.Setting.predictivePace.id)
                MacSettingsToggleRow(
                    L("threshold_warnings_title"),
                    subtitle: L("quota_warning_notifications_subtitle"),
                    isOn: self.$settings.quotaWarningNotificationsEnabled)
                    .settingsAnchor(AlertsSettingsPane.Setting.thresholdWarnings.id)
                if visibility.showsThresholdControls {
                    GlobalQuotaWarningWindowRow(window: .session, settings: self.settings)
                    GlobalQuotaWarningWindowRow(window: .weekly, settings: self.settings)
                }
            }

            MacSettingsSection(L("settings_alerts_section_delivery")) {
                MacSettingsToggleRow(
                    L("quota_warning_sound"),
                    disabledReason: L("settings_alerts_delivery_disabled"),
                    isOn: self.$settings.quotaWarningSoundEnabled)
                    .settingsAnchor(AlertsSettingsPane.Setting.sound.id)
                MacSettingsToggleRow(
                    L("quota_warning_onscreen_alert"),
                    disabledReason: L("settings_alerts_delivery_disabled"),
                    isOn: self.$settings.quotaWarningOnScreenAlertEnabled)
                    .settingsAnchor(AlertsSettingsPane.Setting.onScreenAlert.id)
            }
            .disabled(!visibility.showsDeliveryControls)

            MacSettingsSection(L("settings_alerts_section_menu_markers")) {
                MacSettingsToggleRow(
                    L("show_quota_warning_markers_title"),
                    subtitle: L("show_quota_warning_markers_subtitle"),
                    isOn: self.$settings.quotaWarningMarkersVisible)
                    .settingsAnchor(AlertsSettingsPane.Setting.quotaWarningMarkers.id)
            }

            MacSettingsSection(L("section_celebrations")) {
                MacSettingsRow(L("confetti_on_reset_title"), subtitle: L("confetti_on_reset_subtitle")) {
                    MacPopUpButton(
                        ConfettiCelebrationOption.allCases.map { ($0, $0.label) },
                        selection: self.$settings.confettiCelebrationOption)
                }
                .settingsAnchor(AlertsSettingsPane.Setting.confetti.id)
            }

            MacSettingsSection(L("settings_alerts_overrides_title"), footer: L("settings_alerts_overrides_footer")) {}
                .settingsAnchor(AlertsSettingsPane.Setting.providerOverrides.id)
        }
    }
}

extension AlertsSettingsPane {
    /// The settings search can jump to. Each one's `id` is both its search entry's id and its row's anchor.
    enum Setting: String, CaseIterable {
        case credentialExpiry
        case resetCreditExpiry
        case quotaDepleted
        case upcomingReset
        case limitReset
        case predictivePace
        case thresholdWarnings
        case sound
        case onScreenAlert
        case quotaWarningMarkers
        case confetti
        case providerOverrides

        var id: String {
            SettingsPane.alerts.searchEntry(self.rawValue, "").id
        }
    }

    static var searchEntries: [SettingsSearchEntry] {
        let pane = SettingsPane.alerts
        let notifications = L("tab_notifications")
        let signIn = L("settings_alerts_section_sign_in")
        let quota = L("settings_alerts_section_quota")
        let delivery = L("settings_alerts_section_delivery")
        let thresholdWarning = L("quota_warnings_title")
        func entry(_ setting: Setting, _ title: String, keywords: String...) -> SettingsSearchEntry {
            SettingsSearchEntry(id: setting.id, pane: pane, title: title, keywords: keywords)
        }
        return [
            .paneTitle(pane, keywords: notifications),
            entry(.credentialExpiry, L("credential_expiry_notifications_title"), keywords: signIn, notifications),
            entry(
                .resetCreditExpiry,
                L("codex_reset_credit_expiry_notifications_title"),
                keywords: signIn,
                notifications),
            entry(.quotaDepleted, L("quota_depleted_title"), keywords: quota, notifications),
            entry(.upcomingReset, L("upcoming_reset_notifications_title"), keywords: quota, notifications),
            entry(.limitReset, L("limit_reset_notifications_title"), keywords: quota, notifications),
            entry(.predictivePace, L("predictive_pace_warnings_title"), keywords: quota, notifications),
            entry(
                .thresholdWarnings,
                L("threshold_warnings_title"),
                keywords: quota,
                thresholdWarning,
                L("Session"),
                L("quota_warning_weekly_capitalized"),
                L("quota_warning_warning"),
                L("quota_warning_critical")),
            entry(.sound, L("quota_warning_sound"), keywords: delivery, thresholdWarning),
            entry(.onScreenAlert, L("quota_warning_onscreen_alert"), keywords: delivery, thresholdWarning),
            entry(
                .quotaWarningMarkers,
                L("show_quota_warning_markers_title"),
                keywords: L("settings_alerts_section_menu_markers"),
                L("show_quota_warning_markers_subtitle")),
            entry(.confetti, L("confetti_on_reset_title"), keywords: L("section_celebrations")),
            entry(
                .providerOverrides,
                L("settings_alerts_overrides_title"),
                keywords: thresholdWarning,
                L("tab_providers")),
        ]
    }
}
