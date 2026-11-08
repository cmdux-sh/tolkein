import CodexBarCore
import SwiftUI

// Sections of the retired Advanced pane. Privacy & Data stacks the privacy and diagnostics sections with the
// Transfer section. The command-line section moved to Integrations (`CommandLineInstallSection.swift`).

/// Personal-info redaction and the Keychain kill switch.
@MainActor
struct AdvancedPrivacySection: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        Section {
            Toggle(isOn: self.$settings.hidePersonalInfo) {
                SettingsRowLabel(
                    L("hide_personal_info_title"),
                    subtitle: L("hide_personal_info_subtitle") + " " + L("hide_cost_history_identity_subtitle"))
            }

            Toggle(isOn: self.$settings.debugDisableKeychainAccess) {
                SettingsRowLabel(
                    L("disable_keychain_access_title"),
                    subtitle: L("disable_keychain_access_subtitle"))
            }
        } header: {
            Text(L("section_privacy"))
        } footer: {
            SettingsSectionFooter(L("keychain_access_caption"))
        }
    }
}

/// Storage-footprint reporting and the switch that reveals the Debug pane.
@MainActor
struct AdvancedDiagnosticsSection: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        Section {
            Toggle(isOn: self.$settings.providerStorageFootprintsEnabled) {
                SettingsRowLabel(
                    L("show_provider_storage_usage_title"),
                    subtitle: L("show_provider_storage_usage_subtitle"))
            }

            Toggle(isOn: self.$settings.debugMenuEnabled) {
                SettingsRowLabel(L("show_debug_settings_title"), subtitle: L("show_debug_settings_subtitle"))
            }
        } header: {
            Text(L("section_diagnostics"))
        }
    }
}
