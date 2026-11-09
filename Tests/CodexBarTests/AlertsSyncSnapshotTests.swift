import CodexBarCore
import Foundation
import InternalUI
import SwiftUI
import Testing
@testable import CodexBar

/// Renders the Alerts and Sync panes and a provider's quota-warning section in every state and both appearances,
/// with long Mac names, German strings and a height that must scroll. Each render must succeed; set
/// TOLKEIN_SNAPSHOT_DIR to also write the PNGs for design review (see Sources/CodexBar/AGENTS.md).
@MainActor
struct AlertsSyncSnapshotTests {
    private struct Case {
        let name: String
        var language = "en"
        /// Nil fits the view's own height; pages scroll, so they need one.
        let height: CGFloat?
        let view: () -> AnyView
    }

    /// The settings window's detail column at its default size.
    private static let width = SettingsPane.windowWidth - SettingsPane.sidebarWidth
    private static let tallPage: CGFloat = 1500

    private static var cases: [Case] {
        [
            Case(name: "alerts-warnings-off", height: tallPage) {
                AnyView(AlertsSettingsPage(settings: alertsSettings(threshold: false, pace: false)))
            },
            Case(name: "alerts-threshold-only", height: tallPage) {
                AnyView(AlertsSettingsPage(settings: alertsSettings(threshold: true, pace: false)))
            },
            Case(name: "alerts-pace-only", height: tallPage) {
                AnyView(AlertsSettingsPage(settings: alertsSettings(threshold: false, pace: true)))
            },
            Case(name: "alerts-threshold-only-de", language: "de", height: tallPage) {
                AnyView(AlertsSettingsPage(settings: alertsSettings(threshold: true, pace: true)))
            },
            Case(name: "alerts-short", height: 420) {
                AnyView(AlertsSettingsPage(settings: alertsSettings(threshold: true, pace: false)))
            },
            Case(name: "provider-global", height: nil) {
                providerSection(notifications: true, markers: false, overrides: false)
            },
            Case(name: "provider-custom-off", height: nil) {
                providerSection(notifications: true, markers: false, overrides: true)
            },
            Case(name: "provider-markers-only", height: nil) {
                providerSection(notifications: false, markers: true, overrides: true)
            },
            Case(name: "provider-disabled", height: nil) {
                providerSection(notifications: false, markers: false, overrides: true)
            },
            Case(name: "provider-custom-off-de", language: "de", height: nil) {
                providerSection(notifications: true, markers: false, overrides: true)
            },
            Case(name: "sync-unavailable", height: 900) {
                let state = CloudSyncState()
                state.availability = .noICloudAccount
                return AnyView(SyncSettingsPage(settings: syncSettings(enabled: false), state: state))
            },
            Case(name: "sync-three-macs", height: 900) {
                AnyView(SyncSettingsPage(settings: syncSettings(enabled: true), state: threeMacs()))
            },
            Case(name: "sync-three-macs-de", language: "de", height: 900) {
                AnyView(SyncSettingsPage(settings: syncSettings(enabled: true), state: threeMacs()))
            },
            Case(name: "sync-paused", height: 900) {
                let state = threeMacs()
                state.status.needsAppUpdate = true
                return AnyView(SyncSettingsPage(settings: syncSettings(enabled: true), state: state))
            },
            Case(name: "sync-confirm-remove", height: 700) {
                AnyView(SyncSettingsPage(
                    settings: syncSettings(enabled: true),
                    state: threeMacs(),
                    confirmation: .removeMac(deviceID: "studio", hostName: macNames[1])))
            },
            Case(name: "sync-confirm-secrets", height: 700) {
                AnyView(SyncSettingsPage(
                    settings: syncSettings(enabled: true, includeSecrets: false),
                    state: threeMacs(),
                    confirmation: .includeSecrets))
            },
        ]
    }

    @Test
    func `alerts sync and provider quota warnings render in every state and appearance`() throws {
        let directory = ProcessInfo.processInfo.environment["TOLKEIN_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0) }
        if let directory {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        for appearance in [IUAppearance.light, .dark] {
            for item in Self.cases {
                try CodexBarLocalizationOverride.$appLanguage.withValue(item.language) {
                    let shot = IUSnapshot.render(
                        item.view(),
                        appearance: appearance,
                        width: Self.width,
                        height: item.height)
                    let rendered = try #require(shot, "\(item.name) \(appearance.rawValue) did not render")
                    #expect(rendered.size.width == Self.width)
                    if let height = item.height {
                        #expect(rendered.size.height == height)
                    }
                    if let directory {
                        try rendered.png.write(to: directory.appending(path: "\(item.name)-\(appearance.rawValue).png"))
                    }
                }
            }
        }
    }

    // MARK: - Fixtures

    private static let macNames = [
        "Arturo’s MacBook Pro (16-inch, 2025) with a very long name",
        "Mac Studio M4 Ultra in the upstairs conference room, by the window",
        "Mac mini build server · rack 3 · data centre north",
    ]

    private static func alertsSettings(threshold: Bool, pace: Bool) -> SettingsStore {
        let settings = testSettingsStore(
            suiteName: "AlertsSyncSnapshotTests-alerts",
            userDefaults: InMemoryUserDefaults())
        settings.quotaWarningNotificationsEnabled = threshold
        settings.predictivePaceWarningNotificationsEnabled = pace
        settings.credentialExpiryNotificationsEnabled = true
        settings.setQuotaWarningThresholds(.session, thresholds: [50, 20])
        settings.setQuotaWarningThresholds(.weekly, thresholds: [80, 40])
        settings.setQuotaWarningWindowEnabled(.weekly, enabled: false)
        settings.confettiCelebrationOption = .weekly
        return settings
    }

    private static func providerSection(notifications: Bool, markers: Bool, overrides: Bool) -> AnyView {
        let settings = testSettingsStore(
            suiteName: "AlertsSyncSnapshotTests-provider",
            userDefaults: InMemoryUserDefaults())
        settings.quotaWarningNotificationsEnabled = notifications
        settings.quotaWarningMarkersVisible = markers
        settings.setQuotaWarningThresholds(.session, thresholds: [50, 20])
        settings.setQuotaWarningThresholds(.weekly, thresholds: [80, 50, 20])
        if overrides {
            settings.setQuotaWarningOverride(provider: .codex, window: .session, thresholds: [70, 30], enabled: true)
            settings.setQuotaWarningOverride(provider: .codex, window: .weekly, thresholds: nil, enabled: false)
        }
        return AnyView(
            ProviderQuotaWarningSettingsView(provider: .codex, settings: settings)
                .padding(IUSpace.settingsPagePadding))
    }

    private static func syncSettings(enabled: Bool, includeSecrets: Bool = true) -> SettingsStore {
        let defaults = InMemoryUserDefaults()
        defaults.set("this-mac", forKey: "iCloudSyncDeviceID")
        let settings = testSettingsStore(suiteName: "AlertsSyncSnapshotTests-sync", userDefaults: defaults)
        settings.iCloudSyncEnabled = enabled
        settings.iCloudSyncIncludeSecrets = includeSecrets
        return settings
    }

    private static func threeMacs() -> CloudSyncState {
        let state = CloudSyncState()
        let now = Date()
        state.status.lastSuccessfulFetchAt = now.addingTimeInterval(-90)
        state.status.lastSuccessfulPushAt = now.addingTimeInterval(-4 * 60)
        for (id, name, secondsAgo) in [
            ("this-mac", self.macNames[0], 30.0),
            ("studio", self.macNames[1], 5 * 3600.0),
            ("mini", self.macNames[2], 3 * 86400.0),
        ] {
            let device = DeviceSyncPayload(
                deviceID: id,
                hostName: name,
                model: "Fixture",
                appVersion: "1.0",
                lastSeen: now.addingTimeInterval(-secondsAgo))
            state.fleetDevices[device.recordName] = device
        }
        return state
    }
}
