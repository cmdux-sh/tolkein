import SwiftUI

/// Privacy & Data: personal-info redaction, Keychain access, diagnostics, and preference import and export.
/// Stacks the old Advanced privacy and diagnostics sections with the old Transfer section until the Internal UI
/// rebuild replaces this file.
@MainActor
struct PrivacySettingsPane: View {
    let context: SettingsPaneContext

    var body: some View {
        Form {
            AdvancedPrivacySection(settings: self.context.settings)
            AdvancedDiagnosticsSection(settings: self.context.settings)
            PreferencesTransferSection(settings: self.context.settings)
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
        .scrollContentBackground(.hidden)
    }
}

extension PrivacySettingsPane {
    static var searchEntries: [SettingsSearchEntry] {
        let pane = SettingsPane.privacy
        let privacy = L("section_privacy")
        let keychain = L("section_keychain_access")
        let diagnostics = L("section_diagnostics")
        let portablePreferences = L("Portable preferences")
        return [
            .paneTitle(pane, keywords: L("tab_advanced")),
            pane.searchEntry("hidePersonalInfo", L("hide_personal_info_title"), keywords: privacy),
            pane.searchEntry("keychainAccess", L("disable_keychain_access_title"), keywords: privacy, keychain),
            pane.searchEntry("storageFootprints", L("show_provider_storage_usage_title"), keywords: diagnostics),
            pane.searchEntry("debugSettings", L("show_debug_settings_title"), keywords: diagnostics),
            pane.searchEntry("exportPreferences", L("Export Preferences…"), keywords: portablePreferences),
            pane.searchEntry("importPreferences", L("Import Preferences…"), keywords: portablePreferences),
            pane.searchEntry("switcherShortcuts", L("Provider Switcher Shortcuts…"), keywords: portablePreferences),
        ]
    }
}
