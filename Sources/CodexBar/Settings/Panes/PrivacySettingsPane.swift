import AppKit
import CodexBarCore
import InternalUI
import SwiftUI
import UniformTypeIdentifiers

/// Privacy & Data: personal-info redaction, Keychain access, diagnostics, and exporting and importing preferences.
@MainActor
struct PrivacySettingsPane: View {
    let context: SettingsPaneContext

    var body: some View {
        PrivacySettingsPage(settings: self.context.settings)
    }
}

extension PrivacySettingsPane {
    static var searchEntries: [SettingsSearchEntry] {
        let pane = SettingsPane.privacy
        let privacy = L("section_privacy")
        let keychain = L("section_keychain_access")
        let diagnostics = L("section_diagnostics")
        let storageTitle = L("show_provider_storage_usage_title")
        let keychainTitle = L("disable_keychain_access_title")
        let preferences = L("section_your_preferences")
        let portablePreferences = L("Portable preferences")
        let advanced = SettingsSearchEntry.formerAdvancedKeyword
        return [
            .paneTitle(pane, keywords: advanced),
            pane.searchEntry("hidePersonalInfo", L("hide_personal_info_title"), keywords: privacy, advanced),
            pane.searchEntry("keychainAccess", keychainTitle, keywords: privacy, keychain, advanced),
            pane.searchEntry("storageFootprints", storageTitle, keywords: diagnostics, advanced),
            pane.searchEntry("debugSettings", L("show_debug_settings_title"), keywords: diagnostics, advanced),
            pane.searchEntry(
                "exportPreferences",
                L("Export Preferences…"),
                keywords: preferences,
                portablePreferences),
            pane.searchEntry(
                "importPreferences",
                L("Import Preferences…"),
                keywords: preferences,
                portablePreferences),
        ]
    }
}

@MainActor
private struct PrivacySettingsPage: View {
    @Bindable var settings: SettingsStore
    @State private var confirmation: SettingsConfirmation?

    var body: some View {
        MacSettingsPage(L("tab_privacy")) {
            MacSettingsSection(L("section_privacy"), footer: L("keychain_access_caption")) {
                MacSettingsToggleRow(
                    L("hide_personal_info_title"),
                    subtitle: L("hide_personal_info_subtitle") + " " + L("hide_cost_history_identity_subtitle"),
                    isOn: self.$settings.hidePersonalInfo)
                    .settingsAnchor("privacy/hidePersonalInfo")
                MacSettingsToggleRow(
                    L("disable_keychain_access_title"),
                    subtitle: L("disable_keychain_access_subtitle"),
                    isOn: self.$settings.debugDisableKeychainAccess)
                    .settingsAnchor("privacy/keychainAccess")
            }

            MacSettingsSection(L("section_diagnostics")) {
                MacSettingsToggleRow(
                    L("show_provider_storage_usage_title"),
                    subtitle: L("show_provider_storage_usage_subtitle"),
                    isOn: self.$settings.providerStorageFootprintsEnabled)
                    .settingsAnchor("privacy/storageFootprints")
                MacSettingsToggleRow(
                    L("show_debug_settings_title"),
                    subtitle: L("show_debug_settings_subtitle"),
                    isOn: self.$settings.debugMenuEnabled)
                    .settingsAnchor("privacy/debugSettings")
            }

            MacSettingsSection(
                L("section_your_preferences"),
                footer: L(
                    "Save display and notification preferences for your dotfiles. "
                        + "Accounts, credentials, login, local paths and consent stay on this Mac."))
            {
                MacSettingsLinkRow(L("Export Preferences…"), systemImage: "square.and.arrow.up") {
                    self.exportPreferences()
                }
                .settingsAnchor("privacy/exportPreferences")
                MacSettingsLinkRow(L("Import Preferences…"), systemImage: "square.and.arrow.down") {
                    self.chooseImport()
                }
                .settingsAnchor("privacy/importPreferences")
            }
        }
        .settingsConfirmation(self.$confirmation)
    }

    private func exportPreferences() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = PreferencesTransfer.defaultFileName
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try PreferencesTransfer.export(self.settings, to: url)
        } catch {
            self.showFailure(error)
        }
    }

    /// Reads the chosen file first, so a file that isn't a preferences document fails before anything is asked,
    /// then confirms before the import replaces the current preferences.
    private func chooseImport() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.nameFieldStringValue = PreferencesTransfer.defaultFileName
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let document = try PreferencesTransfer.document(at: url)
            self.confirmation = SettingsConfirmation(
                title: L("import_preferences_confirm_title"),
                message: L("import_preferences_confirm_message", url.lastPathComponent),
                systemImage: "square.and.arrow.down",
                confirmTitle: L("import_preferences_confirm_action"),
                action: { self.importPreferences(document) })
        } catch {
            self.showFailure(error)
        }
    }

    private func importPreferences(_ document: PreferencesDocument) {
        do {
            try self.settings.importPreferences(document)
        } catch {
            self.showFailure(error)
        }
    }

    private func showFailure(_ error: any Error) {
        self.confirmation = .notice(
            title: L("Preferences could not be transferred"),
            message: error.localizedDescription)
    }
}

/// Reading and writing the portable preferences file, apart from the panels that pick it.
@MainActor
enum PreferencesTransfer {
    static let defaultFileName = "preferences.json"

    static func export(_ settings: SettingsStore, to url: URL) throws {
        try settings.exportPreferences().encoded().write(to: url, options: .atomic)
    }

    static func document(at url: URL) throws -> PreferencesDocument {
        try PreferencesDocument(data: Data(contentsOf: url))
    }
}
