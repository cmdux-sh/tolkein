import SwiftUI

/// Sync: iCloud sync of settings, providers and usage snapshots across Macs.
/// Shows the old `ICloudSyncPane` until the Internal UI rebuild replaces this file.
@MainActor
struct SyncSettingsPane: View {
    let context: SettingsPaneContext

    var body: some View {
        ICloudSyncPane(settings: self.context.settings, state: self.context.cloudSyncState)
    }
}

extension SyncSettingsPane {
    static var searchEntries: [SettingsSearchEntry] {
        let pane = SettingsPane.sync
        let iCloudSync = L("iCloud Sync")
        return [
            .paneTitle(pane, keywords: iCloudSync),
            pane.searchEntry(
                "enabled",
                L("Sync settings and providers across your Macs via iCloud"),
                keywords: iCloudSync),
            pane.searchEntry("secrets", L("Include API keys, cookies, and tokens"), keywords: iCloudSync),
            pane.searchEntry("snapshots", L("Sync usage snapshots"), keywords: iCloudSync),
            pane.searchEntry("fleetAccounts", L("Show accounts from other Macs"), keywords: iCloudSync),
            pane.searchEntry("devices", L("Macs"), keywords: iCloudSync),
        ]
    }
}
