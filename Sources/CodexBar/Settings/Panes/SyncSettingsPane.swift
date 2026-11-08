import CodexBarCore
import InternalUI
import SwiftUI

/// Sync: iCloud sync of settings, providers and usage snapshots across Macs, its status, and the Macs in it.
@MainActor
struct SyncSettingsPane: View {
    let context: SettingsPaneContext

    var body: some View {
        SyncSettingsPage(settings: self.context.settings, state: self.context.cloudSyncState)
    }
}

/// The Sync page itself, which needs only the settings and the sync state.
@MainActor
struct SyncSettingsPage: View {
    private static let securityFootnote =
        "Secrets use iCloud end-to-end encryption via encryptedValues. " +
        "Hooks and machine-local paths never sync."
    private static let pausedMessage =
        "Sync is paused: another Mac uses a newer version of Tolkein. " +
        "Update to resume."

    @Bindable var settings: SettingsStore
    @Bindable var state: CloudSyncState
    @State private var confirmation: SyncSettingsConfirmation?

    /// - Parameter confirmation: a confirmation to show from the start (for snapshots).
    init(settings: SettingsStore, state: CloudSyncState, confirmation: SyncSettingsConfirmation? = nil) {
        self.settings = settings
        self.state = state
        self._confirmation = State(initialValue: confirmation)
    }

    var body: some View {
        MacSettingsPage(SettingsPane.sync.title, subtitle: L("settings_sync_subtitle")) {
            if self.state.status.needsAppUpdate {
                MacSettingsSection {
                    MacSettingsRow(L(Self.pausedMessage)) {
                        MacStatusLabel(L("settings_sync_update_needed"), tone: .warning)
                    }
                }
            }

            MacSettingsSection(L("iCloud Sync")) {
                MacSettingsToggleRow(
                    L("Sync settings and providers across your Macs via iCloud"),
                    disabledReason: Self.availabilityMessage(for: self.state.availability),
                    isOn: self.primarySyncBinding)
                    .disabled(!self.syncCanBeEnabled)
                    .settingsAnchor(SyncSettingsPane.Setting.enabled.id)
                MacSettingsToggleRow(L("Include API keys, cookies, and tokens"), isOn: self.includeSecretsBinding)
                    .disabled(!self.optionsEnabled)
                    .settingsAnchor(SyncSettingsPane.Setting.secrets.id)
                MacSettingsToggleRow(L("Sync usage snapshots"), isOn: self.snapshotsBinding)
                    .disabled(!self.optionsEnabled)
                    .settingsAnchor(SyncSettingsPane.Setting.snapshots.id)
                MacSettingsToggleRow(L("Show accounts from other Macs"), isOn: self.showFleetAccountsBinding)
                    .disabled(!self.optionsEnabled)
                    .settingsAnchor(SyncSettingsPane.Setting.fleetAccounts.id)
            }

            MacSettingsSection(L("Status")) {
                MacKeyValueList([
                    .init(L("Last successful fetch"), Self.relativeTime(self.state.status.lastSuccessfulFetchAt)),
                    .init(L("Last successful push"), Self.relativeTime(self.state.status.lastSuccessfulPushAt)),
                ])
                .padding(.horizontal, MacSpace.settingsRowPaddingX)
                .padding(.vertical, MacSpace.unit)
            }
            .settingsAnchor(SyncSettingsPane.Setting.status.id)

            MacSettingsSection(L("Macs"), footer: L(Self.securityFootnote)) {
                let devices = Self.sortedDevices(
                    Array(self.state.fleetDevices.values),
                    currentDeviceID: self.settings.iCloudSyncDeviceID)
                if devices.isEmpty {
                    MacEmptyState(
                        L("settings_sync_no_macs_title"),
                        systemImage: "desktopcomputer",
                        message: L("settings_sync_no_macs_message"),
                        size: .compact)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, MacSpace.cardPadding)
                } else {
                    ForEach(devices, id: \.deviceID) { device in
                        SyncDeviceRow(
                            device: device,
                            isCurrentDevice: device.deviceID == self.settings.iCloudSyncDeviceID,
                            canRemove: self.optionsEnabled)
                        {
                            self.confirmation = .removeMac(deviceID: device.deviceID, hostName: device.hostName)
                        }
                    }
                }
            }
            .settingsAnchor(SyncSettingsPane.Setting.devices.id)
        }
        .modifier(SyncConfirmationHost(confirmation: self.$confirmation) { confirmation in
            Task { await self.actions.confirm(confirmation) }
        })
    }

    private var actions: SyncSettingsActions {
        SyncSettingsActions(settings: self.settings, state: self.state)
    }

    private var syncCanBeEnabled: Bool {
        self.state.availability == .available
    }

    /// The options under the main switch (and Remove) work only while sync is on, available and not paused.
    private var optionsEnabled: Bool {
        self.syncCanBeEnabled && !self.state.status.needsAppUpdate && self.settings.iCloudSyncEnabled
    }

    private var primarySyncBinding: Binding<Bool> {
        Binding(
            get: { self.settings.iCloudSyncEnabled },
            set: { self.settings.iCloudSyncEnabled = $0 })
    }

    private var includeSecretsBinding: Binding<Bool> {
        Binding(
            get: { self.settings.iCloudSyncIncludeSecrets },
            set: { self.confirmation = self.actions.setIncludeSecrets($0) })
    }

    private var snapshotsBinding: Binding<Bool> {
        Binding(
            get: { self.settings.iCloudSyncSnapshotsEnabled },
            set: { self.settings.iCloudSyncSnapshotsEnabled = $0 })
    }

    private var showFleetAccountsBinding: Binding<Bool> {
        Binding(
            get: { self.settings.iCloudSyncShowFleetAccounts },
            set: { self.settings.iCloudSyncShowFleetAccounts = $0 })
    }

    /// Why sync cannot be turned on, or nil when it can.
    static func availabilityMessage(for availability: SyncAvailability) -> String? {
        switch availability {
        case .available:
            nil
        case .missingEntitlement:
            L("Requires a signed release build of Tolkein.")
        case .noICloudAccount:
            L("Sign in to iCloud in System Settings to enable sync.")
        case .restricted:
            L("iCloud access is restricted on this Mac.")
        }
    }

    /// This Mac first, then the most recently seen, then by name.
    static func sortedDevices(_ devices: [DeviceSyncPayload], currentDeviceID: String) -> [DeviceSyncPayload] {
        devices.sorted { lhs, rhs in
            let lhsIsCurrent = lhs.deviceID == currentDeviceID
            let rhsIsCurrent = rhs.deviceID == currentDeviceID
            if lhsIsCurrent != rhsIsCurrent {
                return lhsIsCurrent
            }
            if lhs.lastSeen != rhs.lastSeen {
                return lhs.lastSeen > rhs.lastSeen
            }
            return lhs.hostName.localizedCaseInsensitiveCompare(rhs.hostName) == .orderedAscending
        }
    }

    static func relativeTime(_ date: Date?) -> String {
        date?.relativeDescription() ?? L("Never")
    }
}

/// One Mac in the sync: its name and when it was last seen, with This Mac or a Remove button.
@MainActor
private struct SyncDeviceRow: View {
    let device: DeviceSyncPayload
    let isCurrentDevice: Bool
    let canRemove: Bool
    let remove: () -> Void

    var body: some View {
        MacSettingsRow(self.device.hostName, subtitle: L("Last seen %@", self.device.lastSeen.relativeDescription())) {
            if self.isCurrentDevice {
                MacBadge(L("This Mac"), tone: .accent)
            } else {
                Button(L("Remove"), role: .destructive, action: self.remove)
                    .buttonStyle(.mac(.destructive))
                    .disabled(!self.canRemove)
            }
        }
    }
}

// MARK: - Confirmations

/// A change on the Sync page that asks first.
enum SyncSettingsConfirmation: Identifiable, Equatable {
    /// Turning on Include API keys, cookies, and tokens.
    case includeSecrets
    /// Removing another Mac, with its synced usage, from iCloud.
    case removeMac(deviceID: String, hostName: String)

    var id: String {
        switch self {
        case .includeSecrets: "includeSecrets"
        case let .removeMac(deviceID, _): "removeMac-\(deviceID)"
        }
    }

    var title: String {
        switch self {
        case .includeSecrets: L("settings_sync_secrets_confirm_title")
        case let .removeMac(_, hostName): L("settings_sync_remove_mac_title", hostName)
        }
    }

    var message: String {
        switch self {
        case .includeSecrets: L("settings_sync_secrets_confirm_message")
        case .removeMac: L("settings_sync_remove_mac_message")
        }
    }

    var confirmTitle: String {
        switch self {
        case .includeSecrets: L("settings_sync_secrets_confirm_action")
        case .removeMac: L("Remove")
        }
    }

    var systemImage: String {
        switch self {
        case .includeSecrets: "key.fill"
        case .removeMac: "trash.fill"
        }
    }
}

/// What the Sync page's switches and buttons do, apart from the views, so the confirmations can be tested.
@MainActor
struct SyncSettingsActions {
    let settings: SettingsStore
    let state: CloudSyncState

    /// Include secrets: turning it on asks first (and returns the confirmation to show); turning it off applies
    /// at once.
    func setIncludeSecrets(_ isOn: Bool) -> SyncSettingsConfirmation? {
        if isOn, !self.settings.iCloudSyncIncludeSecrets {
            return .includeSecrets
        }
        self.settings.iCloudSyncIncludeSecrets = isOn
        return nil
    }

    /// Carries out a confirmed change.
    func confirm(_ confirmation: SyncSettingsConfirmation) async {
        switch confirmation {
        case .includeSecrets:
            self.settings.iCloudSyncIncludeSecrets = true
        case let .removeMac(deviceID, _):
            await self.state.requestDeviceRemoval(deviceID)
        }
    }
}

/// Shows a pending confirmation as a `MacAlert` over a dimmed page; the page takes no input meanwhile. Return
/// confirms and Escape cancels.
private struct SyncConfirmationHost: ViewModifier {
    @Binding var confirmation: SyncSettingsConfirmation?
    let confirm: (SyncSettingsConfirmation) -> Void

    func body(content: Content) -> some View {
        content
            .disabled(self.confirmation != nil)
            .accessibilityHidden(self.confirmation != nil)
            .overlay {
                if let confirmation = self.confirmation {
                    ZStack {
                        MacColor.scrim
                            .contentShape(Rectangle())
                            .accessibilityHidden(true)
                        MacAlert(
                            confirmation.title,
                            message: confirmation.message,
                            systemImage: confirmation.systemImage,
                            primary: (confirmation.confirmTitle, {
                                self.confirmation = nil
                                self.confirm(confirmation)
                            }),
                            secondary: (L("Cancel"), { self.confirmation = nil }))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .transition(.opacity)
                }
            }
            .macAnimation(MacSpring.fast, value: self.confirmation)
    }
}

extension SyncSettingsPane {
    /// The settings search can jump to. Each one's `id` is both its search entry's id and its row's anchor.
    enum Setting: String, CaseIterable {
        case enabled
        case secrets
        case snapshots
        case fleetAccounts
        case status
        case devices

        var id: String {
            SettingsPane.sync.searchEntry(self.rawValue, "").id
        }
    }

    static var searchEntries: [SettingsSearchEntry] {
        let pane = SettingsPane.sync
        let iCloudSync = L("iCloud Sync")
        func entry(_ setting: Setting, _ title: String, keywords: String...) -> SettingsSearchEntry {
            SettingsSearchEntry(id: setting.id, pane: pane, title: title, keywords: keywords)
        }
        return [
            .paneTitle(pane, keywords: iCloudSync),
            entry(.enabled, L("Sync settings and providers across your Macs via iCloud"), keywords: iCloudSync),
            entry(.secrets, L("Include API keys, cookies, and tokens"), keywords: iCloudSync),
            entry(.snapshots, L("Sync usage snapshots"), keywords: iCloudSync),
            entry(.fleetAccounts, L("Show accounts from other Macs"), keywords: iCloudSync),
            entry(
                .status,
                L("Status"),
                keywords: iCloudSync,
                L("Last successful fetch"),
                L("Last successful push")),
            entry(.devices, L("Macs"), keywords: iCloudSync, L("This Mac")),
        ]
    }
}
