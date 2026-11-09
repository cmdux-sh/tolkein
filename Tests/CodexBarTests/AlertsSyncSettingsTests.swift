import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

/// The Alerts and Sync panes' logic: the Sync confirmations, the Macs list order, the availability reasons, the
/// localized threshold summary, and search entries that match the rows' anchors.
@MainActor
struct AlertsSyncSettingsTests {
    // MARK: - Sync confirmations

    @Test
    func `turning on include secrets asks first and changes nothing until confirmed`() async {
        let settings = Self.makeSettings()
        settings.iCloudSyncIncludeSecrets = false
        let actions = SyncSettingsActions(settings: settings, state: CloudSyncState())

        #expect(actions.setIncludeSecrets(true) == .includeSecrets)
        #expect(!settings.iCloudSyncIncludeSecrets)

        await actions.confirm(.includeSecrets)
        #expect(settings.iCloudSyncIncludeSecrets)
    }

    @Test
    func `turning off include secrets applies at once without asking`() {
        let settings = Self.makeSettings()
        settings.iCloudSyncIncludeSecrets = true
        let actions = SyncSettingsActions(settings: settings, state: CloudSyncState())

        #expect(actions.setIncludeSecrets(false) == nil)
        #expect(!settings.iCloudSyncIncludeSecrets)
        #expect(actions.setIncludeSecrets(false) == nil)
        #expect(!settings.iCloudSyncIncludeSecrets)
    }

    @Test
    func `include secrets that is already on stays on without asking`() {
        let settings = Self.makeSettings()
        settings.iCloudSyncIncludeSecrets = true
        let actions = SyncSettingsActions(settings: settings, state: CloudSyncState())

        #expect(actions.setIncludeSecrets(true) == nil)
        #expect(settings.iCloudSyncIncludeSecrets)
    }

    @Test
    func `removing a Mac happens only when the confirmation is confirmed`() async {
        let state = CloudSyncState()
        var removed: [String] = []
        state.removeDeviceHandler = { removed.append($0) }
        let actions = SyncSettingsActions(settings: Self.makeSettings(), state: state)
        let confirmation = SyncSettingsConfirmation.removeMac(deviceID: "old", hostName: "Example MacBook")

        #expect(removed.isEmpty)
        await actions.confirm(confirmation)
        #expect(removed == ["old"])
    }

    @Test
    func `confirmations name the Mac and resolve every string`() {
        CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            let remove = SyncSettingsConfirmation.removeMac(deviceID: "old", hostName: "Example MacBook")
            #expect(remove.title == "Remove “Example MacBook”?")
            #expect(remove.confirmTitle == "Remove")
            #expect(remove.id != SyncSettingsConfirmation.includeSecrets.id)

            let secrets = SyncSettingsConfirmation.includeSecrets
            #expect(secrets.title == "Sync API keys, cookies and tokens?")
            #expect(secrets.confirmTitle == "Include Secrets")
            for confirmation in [remove, secrets] {
                #expect(!confirmation.message.hasPrefix("settings_sync_"))
                #expect(!confirmation.title.hasPrefix("settings_sync_"))
            }
        }
        CodexBarLocalizationOverride.$appLanguage.withValue("de") {
            let remove = SyncSettingsConfirmation.removeMac(deviceID: "old", hostName: "Example MacBook")
            #expect(remove.title == "„Example MacBook“ entfernen?")
        }
    }

    // MARK: - Sync page

    @Test
    func `Macs list this Mac first then the most recently seen then by name`() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        func device(_ id: String, _ name: String, secondsAgo: TimeInterval) -> DeviceSyncPayload {
            DeviceSyncPayload(
                deviceID: id,
                hostName: name,
                model: "Fixture",
                appVersion: "1.0",
                lastSeen: now.addingTimeInterval(-secondsAgo))
        }
        let devices = [
            device("b", "beta", secondsAgo: 60),
            device("current", "zulu", secondsAgo: 600),
            device("a", "Alpha", secondsAgo: 60),
            device("c", "Charlie", secondsAgo: 5),
        ]

        let sorted = SyncSettingsPage.sortedDevices(devices, currentDeviceID: "current")

        #expect(sorted.map(\.deviceID) == ["current", "c", "a", "b"])
    }

    @Test
    func `sync availability gives a reason only when sync cannot be turned on`() {
        CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            #expect(SyncSettingsPage.availabilityMessage(for: .available) == nil)
            #expect(SyncSettingsPage.availabilityMessage(for: .missingEntitlement)
                == "Requires a signed release build of Tolkein.")
            #expect(SyncSettingsPage.availabilityMessage(for: .noICloudAccount)
                == "Sign in to iCloud in System Settings to enable sync.")
            #expect(SyncSettingsPage.availabilityMessage(for: .restricted)
                == "iCloud access is restricted on this Mac.")
            #expect(SyncSettingsPage.relativeTime(nil) == "Never")
        }
    }

    // MARK: - Quota warnings

    @Test
    func `threshold summary follows the language's percent format`() {
        CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            #expect(ProviderQuotaWarningSettingsView.thresholdText([50, 20], enabled: true)
                == "Warning 50%, Critical 20%")
            #expect(ProviderQuotaWarningSettingsView.thresholdText([50, 20], enabled: false) == "Off")
            #expect(ProviderQuotaWarningSettingsView.thresholdText([0], enabled: true) == "depleted only")
        }
        CodexBarLocalizationOverride.$appLanguage.withValue("tr") {
            #expect(ProviderQuotaWarningSettingsView.thresholdText([80, 50, 20], enabled: true)
                == "Uyarı %80, Kritik %50, %20")
        }
    }

    @Test
    func `provider rows show the inherited thresholds only while a window is global`() {
        let settings = Self.makeSettings()
        settings.quotaWarningNotificationsEnabled = true
        settings.setQuotaWarningThresholds(.session, thresholds: [60, 25])
        settings.setQuotaWarningOverride(provider: .codex, window: .weekly, thresholds: [70, 30], enabled: true)
        let view = ProviderQuotaWarningSettingsView(provider: .codex, settings: settings)

        CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            #expect(view.inheritedSummary(for: .session) == "Inherited: Warning 60%, Critical 25%")
            #expect(view.inheritedSummary(for: .weekly) == nil)
        }

        view.overrideModeBinding(for: .weekly).wrappedValue = .off
        #expect(view.inheritedSummary(for: .weekly) == nil)
        view.overrideModeBinding(for: .weekly).wrappedValue = .global
        #expect(view.inheritedSummary(for: .weekly) != nil)
    }

    @Test
    func `override modes are offered in the order Global Custom Off`() {
        CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            #expect(ProviderQuotaWarningOverrideMode.allCases.map(\.title) == ["Global", "Custom", "Off"])
        }
    }

    // MARK: - Search

    @Test
    func `alerts search entries match the anchored rows`() {
        let ids = AlertsSettingsPane.searchEntries.map(\.id).filter { $0 != SettingsPane.alerts.persistenceToken }
        #expect(ids == AlertsSettingsPane.Setting.allCases.map(\.id))
        #expect(ids.allSatisfy { $0.hasPrefix("\(SettingsPane.alerts.persistenceToken)/") })
    }

    @Test
    func `sync search entries match the anchored rows`() {
        let ids = SyncSettingsPane.searchEntries.map(\.id).filter { $0 != SettingsPane.sync.persistenceToken }
        #expect(ids == SyncSettingsPane.Setting.allCases.map(\.id))
        #expect(ids.allSatisfy { $0.hasPrefix("\(SettingsPane.sync.persistenceToken)/") })
    }

    @Test
    func `search finds quota warning markers and delivery on the Alerts pane`() {
        CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            let entries = AlertsSettingsPane.searchEntries
            #expect(SettingsSearchIndex.ranked(entries, query: "markers").first?.id
                == AlertsSettingsPane.Setting.quotaWarningMarkers.id)
            #expect(SettingsSearchIndex.ranked(entries, query: "sound").first?.id
                == AlertsSettingsPane.Setting.sound.id)
            #expect(SettingsSearchIndex.ranked(entries, query: "critical").first?.id
                == AlertsSettingsPane.Setting.thresholdWarnings.id)
        }
    }

    private static func makeSettings() -> SettingsStore {
        let defaults = InMemoryUserDefaults()
        defaults.set("current", forKey: "iCloudSyncDeviceID")
        return testSettingsStore(suiteName: "AlertsSyncSettingsTests", userDefaults: defaults)
    }
}
