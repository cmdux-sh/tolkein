import SwiftUI

/// General: language, currency, terminal, login, refreshing and the open-menu shortcut.
/// Shows the old `GeneralPane` until the Internal UI rebuild replaces this file.
@MainActor
struct GeneralSettingsPane: View {
    let context: SettingsPaneContext

    var body: some View {
        GeneralPane(settings: self.context.settings)
    }
}

extension GeneralSettingsPane {
    static var searchEntries: [SettingsSearchEntry] {
        let pane = SettingsPane.general
        let system = L("section_system")
        let refreshing = L("section_refreshing")
        let statusSubtitle = L("check_provider_status_subtitle")
        return [
            .paneTitle(pane),
            pane.searchEntry("language", L("language_title"), keywords: system, L("language_subtitle")),
            pane.searchEntry("currency", L("currency_title"), keywords: system, L("currency_subtitle")),
            pane.searchEntry("terminal", L("terminal_app_title"), keywords: system, L("terminal_app_subtitle")),
            pane.searchEntry("launchAtLogin", L("start_at_login_title"), keywords: system),
            pane.searchEntry("refreshInterval", L("refresh_interval_title"), keywords: refreshing),
            pane.searchEntry("refreshOnOpen", L("refresh_on_open_title"), keywords: refreshing),
            pane.searchEntry("lowPowerMode", L("Low Power Mode"), keywords: refreshing),
            pane.searchEntry("providerStatus", L("check_provider_status_title"), keywords: refreshing, statusSubtitle),
            pane.searchEntry(
                "openMenuShortcut",
                L("open_menu_shortcut_title"),
                keywords: L("section_keyboard_shortcut")),
            pane.searchEntry("quit", L("quit_app")),
        ]
    }
}
