import AppKit
import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

/// The Spend window replaced Settings → Usage & Spend. These cover its one-window controller, the Costs pane's
/// link to it, and the Costs pane's sections, through seams that never present a window.
@MainActor
struct SpendWindowOpeningTests {
    @Test
    func `the controller makes one window and reuses it until it closes`() {
        _ = NSApplication.shared
        let navigation = SessionUsageNavigation()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: true)
        var made = 0
        var presented: [NSWindow] = []
        let controller = SpendWindowController(
            navigation: navigation,
            makeWindow: {
                made += 1
                return window
            },
            presentWindow: { presented.append($0) })

        #expect(controller.open(.dashboard) == .created)
        #expect(controller.open(.dashboard) == .reused)
        #expect(made == 1)
        #expect(presented.count == 2)
        #expect(presented.allSatisfy { $0 === window })
        #expect(window.identifier?.rawValue == SpendWindowIdentity.identifier)
        #expect(window.delegate === controller)
        #expect(!window.isReleasedWhenClosed)

        let frame = NSRect(x: 120, y: 140, width: 900, height: 700)
        window.setFrame(frame, display: false)
        controller.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: window))
        #expect(window.frame == frame)
        #expect(controller.open(.dashboard) == .created)
        #expect(made == 2)
        #expect(window.frame == frame)
    }

    @Test
    func `opening for sessions shows the browser and opening the dashboard clears it`() {
        _ = NSApplication.shared
        let navigation = SessionUsageNavigation()
        let controller = SpendWindowController(
            navigation: navigation,
            makeWindow: {
                NSWindow(
                    contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
                    styleMask: [.titled, .closable],
                    backing: .buffered,
                    defer: true)
            },
            presentWindow: { _ in })

        controller.open(.sessions(Self.sessionContext, sessionID: "session-2"))
        #expect(navigation.request?.sessionID == "session-2")
        #expect(navigation.request?.context.providerName == "Codex")

        controller.open(.dashboard)
        #expect(navigation.request == nil)
    }

    @Test
    func `the Costs link row opens the Spend window on its dashboard`() {
        let session = Self.makeSession(suite: "SpendWindowOpening-link", costUsageEnabled: true)
        defer { session.tearDown() }
        var opened: [String] = []
        let pane = CostsSettingsPane(context: session.context) { opened.append(Self.describe($0)) }

        pane.openSpendWindowFromLink()

        #expect(opened == ["dashboard"])
        _ = pane.body
    }

    @Test
    func `the Costs pane's sections follow cost tracking`() {
        #expect(CostsSettingsPane.sections(costUsageEnabled: false) == [.off, .timeZone])
        #expect(CostsSettingsPane.sections(costUsageEnabled: true) == [
            .tracking, .spend, .sources, .timeZone, .export,
        ])

        let session = Self.makeSession(suite: "SpendWindowOpening-sections", costUsageEnabled: false)
        defer { session.tearDown() }
        let pane = CostsSettingsPane(context: session.context) { _ in }
        #expect(pane.sections == [.off, .timeZone])
        _ = pane.body

        session.settings.costUsageEnabled = true
        #expect(pane.sections == [.tracking, .spend, .sources, .timeZone, .export])
        _ = pane.body

        session.settings.costUsageEnabled = false
        #expect(pane.sections == [.off, .timeZone])
    }

    @Test
    func `hiding native Codex waits for OpenCodex logs and says why`() {
        let session = Self.makeSession(suite: "SpendWindowOpening-opencodex", costUsageEnabled: true)
        defer { session.tearDown() }
        let pane = CostsSettingsPane(context: session.context) { _ in }

        session.settings.openCodexUsageLogsEnabled = false
        #expect(pane.hideNativeCodexDisabledReason == L("Requires OpenCodex usage logs."))
        session.settings.openCodexUsageLogsEnabled = true
        #expect(pane.hideNativeCodexDisabledReason == nil)
    }

    @Test
    func `every Costs row anchor has a search entry`() {
        let entries = CostsSettingsPane.searchEntries
        let ids = entries.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(entries.allSatisfy { $0.pane == .costs })
        let anchors = [
            CostsSettingsPane.Anchor.trackCosts,
            CostsSettingsPane.Anchor.openCodexLogs,
            CostsSettingsPane.Anchor.hideNativeCodex,
            CostsSettingsPane.Anchor.spendWindow,
            CostsSettingsPane.Anchor.sources,
            CostsSettingsPane.Anchor.timeZone,
            CostsSettingsPane.Anchor.useCurrentTimeZone,
            CostsSettingsPane.Anchor.copyJSON,
            CostsSettingsPane.Anchor.exportJSON,
            CostsSettingsPane.Anchor.shareStats,
        ]
        #expect(Set(anchors) == Set(ids).subtracting([SettingsPane.costs.persistenceToken]))
        let spendHits = SettingsSearchIndex.ranked(entries, query: L("Daily estimated spend")).map(\.id)
        #expect(spendHits.first == CostsSettingsPane.Anchor.spendWindow)
    }

    @Test
    func `the summary names the range and shows the totals`() {
        let empty = CostsSettingsPane.summaryRows(
            model: SpendDashboardModel(requestedDays: 30, groups: []),
            period: .rolling(days: 30),
            isRefreshing: false)
        #expect(empty.map(\.label) == [L("Time range"), L("Estimated spend")])
        #expect(empty[0].value == spendDashboardDayRangeText(30))
        #expect(empty[1].value == L("No local cost history yet"))

        let refreshing = CostsSettingsPane.summaryRows(
            model: SpendDashboardModel(requestedDays: 30, groups: []),
            period: .monthToDate,
            isRefreshing: true)
        #expect(refreshing[0].value == L("Month to date"))
        #expect(refreshing[1].value == L("Refreshing"))
    }

    // MARK: - Helpers

    static func describe(_ destination: SpendWindowDestination) -> String {
        switch destination {
        case .dashboard: "dashboard"
        case let .sessions(context, sessionID): "sessions:\(context.providerName):\(sessionID ?? "")"
        }
    }

    static var sessionContext: SessionUsageBrowserContext {
        SessionUsageBrowserContext(
            providerName: "Codex",
            windowLabel: "Last 30 days",
            sessions: [],
            currencyCode: "USD",
            costMultiplier: 1,
            timeZone: TimeZone(identifier: "UTC") ?? .current)
    }

    struct Session {
        let settings: SettingsStore
        let store: UsageStore
        let context: SettingsPaneContext

        @MainActor
        func tearDown() {
            self.store.stopSharedSpendDashboardPublication()
            self.settings.configFileWatcher?.stop()
        }
    }

    static func makeSession(suite: String, costUsageEnabled: Bool) -> Session {
        let settings = testSettingsStore(
            suiteName: suite,
            userDefaults: InMemoryUserDefaults(),
            config: testConfigWithAllProvidersDisabled())
        settings.costUsageEnabled = costUsageEnabled
        settings.refreshFrequency = .manual
        settings.statusChecksEnabled = false
        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing,
            environmentBase: [:])
        store.sharedSpendDashboardControllerStorage = SpendDashboardController(
            userDefaults: InMemoryUserDefaults(),
            requestBuilder: { _ in fatalError("The Costs pane must not load spend data") })
        let context = SettingsPaneContext(
            settings: settings,
            store: store,
            cloudSyncState: CloudSyncState(),
            updater: DisabledUpdaterController(),
            selection: PreferencesSelection(userDefaults: InMemoryUserDefaults()),
            managedCodexAccountCoordinator: ManagedCodexAccountCoordinator(),
            codexAccountPromotionCoordinator: CodexAccountPromotionCoordinator(
                settingsStore: settings,
                usageStore: store,
                managedAccountCoordinator: ManagedCodexAccountCoordinator()),
            runProviderLoginFlow: { _ in })
        return Session(settings: settings, store: store, context: context)
    }
}
