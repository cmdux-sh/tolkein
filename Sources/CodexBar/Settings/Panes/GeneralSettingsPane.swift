import AppKit
import CodexBarCore
import InternalUI
import KeyboardShortcuts
import SwiftUI

/// General: language, currency, terminal and login; refreshing; the keyboard shortcuts; the version and Quit.
@MainActor
struct GeneralSettingsPane: View {
    let context: SettingsPaneContext

    var body: some View {
        GeneralSettingsPage(settings: self.context.settings)
    }
}

extension GeneralSettingsPane {
    static var searchEntries: [SettingsSearchEntry] {
        let pane = SettingsPane.general
        let system = L("section_system")
        let refreshing = L("section_refreshing")
        let statusSubtitle = L("check_provider_status_subtitle")
        let shortcuts = L("section_keyboard_shortcut")
        let switcher = L("Provider Switcher Shortcuts")
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
            pane.searchEntry("openMenuShortcut", L("open_menu_shortcut_title"), keywords: shortcuts),
            pane.searchEntry(
                "switcherShortcuts",
                L("section_provider_switcher"),
                keywords: switcher,
                shortcuts,
                L("Previous provider"),
                L("Next provider")),
            pane.searchEntry(
                "switcherDefaults",
                L("provider_switcher_default_shortcuts"),
                keywords: switcher,
                L("Restore Defaults")),
            pane.searchEntry("quit", L("quit_app")),
        ]
    }
}

@MainActor
private struct GeneralSettingsPage: View {
    @Bindable var settings: SettingsStore
    @State private var confirmation: SettingsConfirmation?

    var body: some View {
        MacSettingsPage(L("tab_general")) {
            self.systemSection
            self.refreshingSection
            MacSettingsSection(L("section_keyboard_shortcut")) {
                OpenMenuShortcutRow(confirmation: self.$confirmation)
                    .settingsAnchor("general/openMenuShortcut")
            }
            ProviderSwitcherShortcutsSection(settings: self.settings)
            self.footer
        }
        .settingsConfirmation(self.$confirmation)
    }

    private var systemSection: some View {
        MacSettingsSection(L("section_system")) {
            MacSettingsRow(L("language_title"), subtitle: L("language_subtitle")) {
                MacPopUpButton(self.languageOptions, selection: self.$settings.appLanguage)
                    .frame(width: MacSize.settingsField)
                    .lineLimit(1)
            }
            .settingsAnchor("general/language")

            MacSettingsRow(L("currency_title"), subtitle: L("currency_subtitle")) {
                MacPopUpButton(self.currencyOptions, selection: self.$settings.preferredCurrencyCode)
                    .frame(width: MacSize.settingsField)
                    .lineLimit(1)
            }
            .settingsAnchor("general/currency")
            .onChange(of: self.settings.preferredCurrencyCode) { _, newValue in
                guard CurrencyExchange.requiresLiveRates(preferredCurrencyCode: newValue) else { return }
                Task {
                    await CurrencyExchange.shared.fetchLatestRatesIfNeeded(preferredCurrencyCode: newValue)
                }
            }

            MacSettingsRow(L("terminal_app_title"), subtitle: L("terminal_app_subtitle")) {
                MacPopUpButton(
                    GeneralSettingsMenuOptions.terminalApps(selected: self.settings.terminalApp).map { ($0, $0.label) },
                    selection: self.$settings.terminalApp)
            }
            .settingsAnchor("general/terminal")

            MacSettingsToggleRow(L("start_at_login_title"), isOn: self.$settings.launchAtLogin)
                .settingsAnchor("general/launchAtLogin")
        }
    }

    private var refreshingSection: some View {
        MacSettingsSection(
            L("section_refreshing"),
            footer: self.settings.refreshFrequency == .manual ? L("manual_refresh_hint") : nil)
        {
            MacSettingsRow(L("refresh_interval_title")) {
                MacPopUpButton(
                    GeneralSettingsMenuOptions.refreshFrequencies.map { ($0, $0.label) },
                    selection: self.$settings.refreshFrequency)
            }
            .settingsAnchor("general/refreshInterval")

            MacSettingsToggleRow(L("refresh_on_open_title"), isOn: self.$settings.refreshAllProvidersOnMenuOpen)
                .settingsAnchor("general/refreshOnOpen")

            MacSettingsRow(
                L("Low Power Mode"),
                subtitle: L(
                    "When on, runs automatic provider, local usage, and storage refreshes no more " +
                        "often than every 30 minutes. Manual refresh remains available. Automatic " +
                        "follows the system Low Power Mode setting."))
            {
                MacPopUpButton(
                    GeneralSettingsMenuOptions.lowPowerModePreferences.map { ($0, $0.label) },
                    selection: self.$settings.backgroundWorkLowPowerModePreference)
            }
            .settingsAnchor("general/lowPowerMode")

            MacSettingsToggleRow(
                L("check_provider_status_title"),
                subtitle: L("check_provider_status_subtitle"),
                isOn: self.$settings.statusChecksEnabled)
                .settingsAnchor("general/providerStatus")
        }
    }

    private var footer: some View {
        HStack(alignment: .center, spacing: MacSpace.panelPadding) {
            MacText(String(format: L("version_format"), AppVersion.displayString), role: .caption, muted: true)
                .textSelection(.enabled)
            Spacer(minLength: MacSpace.panelPadding)
            Button(L("quit_app")) { NSApp.terminate(nil) }
                .buttonStyle(.mac())
                .macControlSize(.large)
                .settingsAnchor("general/quit")
        }
        .padding(.horizontal, MacSpace.settingsRowPaddingX)
    }

    /// Every language by its own name; a stored code the list doesn't know stays visible.
    private var languageOptions: [(String, String)] {
        SettingsMenuPickerOptions.displayed(GeneralSettingsMenuOptions.languages, selection: self.settings.appLanguage)
            .map { ($0, AppLanguage(rawValue: $0)?.label ?? $0) }
    }

    private var currencyOptions: [(String, String)] {
        SettingsMenuPickerOptions.displayed(
            PreferredCurrencyOption.codes,
            selection: self.settings.preferredCurrencyCode)
            .map { ($0, PreferredCurrencyOption.label(for: $0)) }
    }
}

// MARK: - Shortcuts

/// A shortcut recorder with the reason the last shortcut was turned down, if any, under it.
@MainActor
private struct ShortcutRecorderControl: View {
    let label: String
    @Binding var shortcut: MacShortcut?
    let issue: String?

    var body: some View {
        VStack(alignment: .trailing, spacing: MacSpace.unit) {
            // Rules come from the bridges, which name the menu and app shortcuts already taken.
            MacShortcutRecorder(self.label, shortcut: self.$shortcut, reserved: [])
            if let issue {
                MacStatusLabel(issue, tone: .warning)
            }
        }
    }
}

/// The global Open menu hotkey. KeyboardShortcuts stores and registers it; the recorder edits it through
/// `OpenMenuShortcutBridge`, which applies the rules KeyboardShortcuts' own recorder used.
@MainActor
private struct OpenMenuShortcutRow: View {
    /// KeyboardShortcuts posts this whenever a stored shortcut changes, from here or anywhere else.
    private static let shortcutDidChange = Notification.Name("KeyboardShortcuts_shortcutByNameDidChange")

    @Binding var confirmation: SettingsConfirmation?
    @State private var shortcut: MacShortcut? = Self.storedShortcut()
    @State private var issue: String?

    var body: some View {
        MacSettingsRow(L("open_menu_shortcut_title")) {
            ShortcutRecorderControl(
                label: L("open_menu_shortcut_title"),
                shortcut: Binding(get: { self.shortcut }, set: { self.record($0) }),
                issue: self.issue)
        }
        .onReceive(NotificationCenter.default.publisher(for: Self.shortcutDidChange)) { _ in
            self.shortcut = Self.storedShortcut()
        }
    }

    private static func storedShortcut() -> MacShortcut? {
        KeyboardShortcuts.getShortcut(for: .openMenu).map { OpenMenuShortcutBridge.macShortcut($0) }
    }

    private func record(_ newValue: MacShortcut?) {
        self.issue = nil
        guard let newValue else {
            self.save(nil)
            return
        }
        let candidate = OpenMenuShortcutBridge.keyboardShortcut(newValue)
        switch OpenMenuShortcutBridge.liveVerdict(for: candidate) {
        case .accept:
            self.save(candidate)
        case let .reject(message):
            self.issue = message
        case .confirmSystemConflict:
            self.confirmation = SettingsConfirmation(
                title: L("open_menu_shortcut_system_conflict_title"),
                message: L("open_menu_shortcut_system_conflict_message", newValue.displayString),
                systemImage: "keyboard",
                confirmTitle: L("Use Anyway"),
                action: { self.save(candidate) })
        }
    }

    private func save(_ candidate: KeyboardShortcuts.Shortcut?) {
        KeyboardShortcuts.setShortcut(candidate, for: .openMenu)
        self.shortcut = Self.storedShortcut()
    }
}

/// The shortcuts that work while the provider switcher menu is open, one recorder per action, stored in the
/// `switcherShortcuts` format through `ProviderSwitcherShortcutBridge`.
@MainActor
private struct ProviderSwitcherShortcutsSection: View {
    @Bindable var settings: SettingsStore
    @State private var issues: [String: String] = [:]

    var body: some View {
        MacSettingsSection(L("section_provider_switcher"), footer: L("provider_switcher_shortcuts_footer")) {
            ForEach(ProviderSwitcherShortcuts.actions, id: \.self) { action in
                let label = ProviderSwitcherShortcutBridge.label(for: action)
                MacSettingsRow(label) {
                    ShortcutRecorderControl(
                        label: label,
                        shortcut: self.binding(for: action),
                        issue: self.issues[action])
                }
                // Search lands on the first action; every row needs a distinct id.
                .settingsAnchor(action == ProviderSwitcherShortcuts.actions.first
                    ? "general/switcherShortcuts"
                    : "general/switcherShortcuts/\(action)")
            }

            MacSettingsRow(
                L("provider_switcher_default_shortcuts"),
                disabledReason: L("provider_switcher_defaults_in_use"))
            {
                Button(L("Restore Defaults")) { self.save(ProviderSwitcherShortcuts.defaults, action: nil) }
                    .buttonStyle(.mac())
            }
            .disabled(self.settings.providerSwitcherShortcuts == ProviderSwitcherShortcuts.defaults)
            .settingsAnchor("general/switcherDefaults")
        }
    }

    private func binding(for action: String) -> Binding<MacShortcut?> {
        Binding(
            get: {
                let stored = self.settings.providerSwitcherShortcuts[action] ?? ""
                return ProviderSwitcherShortcutBridge.shortcut(for: stored)
            },
            set: { newValue in
                switch ProviderSwitcherShortcutBridge.assigning(
                    newValue,
                    to: action,
                    in: self.settings.providerSwitcherShortcuts)
                {
                case let .success(shortcuts):
                    self.save(shortcuts, action: action)
                case let .failure(issue):
                    self.issues[action] = ProviderSwitcherShortcutBridge.message(for: issue)
                }
            })
    }

    /// Stores the map; `action` names the row that changed, or nil when every row did.
    private func save(_ shortcuts: [String: String], action: String?) {
        do {
            try self.settings.setProviderSwitcherShortcuts(shortcuts)
            if let action {
                self.issues[action] = nil
            } else {
                self.issues = [:]
            }
        } catch {
            self.issues[action ?? ProviderSwitcherShortcuts.actions[0]] = error.localizedDescription
        }
    }
}
