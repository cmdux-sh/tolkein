import AppKit
import Foundation
import InternalUI
import SwiftUI
import Testing
@testable import CodexBar
@testable import CodexBarCore

/// Renders Settings → Costs (tracking on and off) and the Spend window (stress data, empty, off, the session
/// browser and its smallest size) in light and dark. Each render must succeed; set TOLKEIN_SNAPSHOT_DIR (or
/// CODEXBAR_SNAPSHOT_DIR) to also write the PNGs for design review (see Sources/CodexBar/AGENTS.md).
@MainActor
@Suite(.serialized)
struct SpendWindowSnapshotTests {
    private static let paneWidth = SettingsPane.windowWidth - SettingsPane.sidebarWidth
    private static let windowSize = SpendWindowIdentity.defaultSize

    @Test
    func `the Costs pane renders with tracking on and off`() async throws {
        let directory = try Self.outputDirectory()
        for appearance in [IUAppearance.light, .dark] {
            for (name, enabled, height) in [
                ("costs-on", true, CGFloat(1180)),
                ("costs-on-short", true, CGFloat(420)),
                ("costs-off", false, CGFloat(520)),
            ] {
                let session = try await Self.makeSession(suite: "SpendWindowSnapshot-\(name)", data: .stress)
                defer { session.tearDown() }
                session.settings.costUsageEnabled = enabled
                let pane = CostsSettingsPane(context: session.context) { _ in }
                try Self.render(
                    pane.codexBarLocalized(),
                    name: "\(name)-\(appearance.rawValue)",
                    appearance: appearance,
                    size: CGSize(width: Self.paneWidth, height: height),
                    directory: directory)
            }
        }
    }

    @Test
    func `the Spend window renders every state`() async throws {
        let directory = try Self.outputDirectory()
        let full = Self.windowSize
        let smallest = SpendWindowIdentity.minimumSize
        for appearance in [IUAppearance.light, .dark] {
            for item in [
                WindowCase(name: "spend-stress", size: CGSize(width: full.width, height: 3400)),
                WindowCase(name: "spend-stress-short", size: smallest),
                WindowCase(name: "spend-empty", data: .empty, size: full),
                WindowCase(name: "spend-off", data: .empty, enabled: false, size: full),
                WindowCase(name: "spend-sessions", sessions: true, size: full),
            ] {
                let session = try await Self.makeSession(suite: "SpendWindowSnapshot-\(item.name)", data: item.data)
                defer { session.tearDown() }
                session.settings.costUsageEnabled = item.enabled
                let navigation = SessionUsageNavigation()
                if item.sessions {
                    navigation.request = .init(context: Self.sessionContext(session), sessionID: "session-03")
                }
                let view = SpendWindowView(
                    settings: session.settings,
                    store: session.store,
                    navigation: navigation,
                    chrome: .drawn)
                try Self.render(
                    view.codexBarLocalized(),
                    name: "\(item.name)-\(appearance.rawValue)",
                    appearance: appearance,
                    size: item.size,
                    directory: directory)
            }
        }
    }

    @Test
    func `the range control offers a stored custom range`() {
        let standard = SpendWindowView.periodOptions(selected: .rolling(days: 30)).map(\.0)
        #expect(standard == [.rolling(days: 7), .rolling(days: 30), .rolling(days: 90), .monthToDate, .allTime])
        let custom = SpendWindowView.periodOptions(selected: .rolling(days: 14)).map(\.0)
        #expect(custom.last == .rolling(days: 14))
        #expect(custom.count == 6)
    }

    // MARK: - Rendering

    private static func outputDirectory() throws -> URL? {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["TOLKEIN_SNAPSHOT_DIR"] ?? environment["CODEXBAR_SNAPSHOT_DIR"] else {
            return nil
        }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func render(
        _ view: some View,
        name: String,
        appearance: IUAppearance,
        size: CGSize,
        directory: URL?) throws
    {
        let shot = IUSnapshot.render(
            view.environment(\.locale, Locale(identifier: "en_US")),
            appearance: appearance,
            width: size.width,
            height: size.height)
        let rendered = try #require(shot, "\(name) did not render")
        #expect(rendered.size == size)
        if let directory {
            try rendered.png.write(to: directory.appending(path: "\(name).png"))
        }
    }

    // MARK: - Data

    enum SnapshotData {
        case stress
        case empty
    }

    struct WindowCase {
        let name: String
        var data = SnapshotData.stress
        var enabled = true
        var sessions = false
        let size: CGSize
    }

    struct Session {
        let settings: SettingsStore
        let store: UsageStore
        let controller: SpendDashboardController
        let context: SettingsPaneContext

        @MainActor
        func tearDown() {
            self.controller.stop()
            self.store.stopSharedSpendDashboardPublication()
            self.settings.configFileWatcher?.stop()
        }
    }

    private static func makeSession(suite: String, data: SnapshotData) async throws -> Session {
        let settings = testSettingsStore(
            suiteName: suite,
            userDefaults: InMemoryUserDefaults(),
            config: testConfigWithAllProvidersDisabled())
        enableTestProviders([.cursor, .opencode, .claude, .mistral], settings: settings)
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.costUsageEnabled = true
        settings.preferredCurrencyCode = "auto"
        settings.costUsageBucketTimeZoneIdentifier = "America/Argentina/ComodRivadavia"
        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing,
            environmentBase: [:])
        store._test_providerRefreshOverride = { _ in Issue.record("Snapshots must not start a provider transport") }
        store._test_widgetSnapshotSaveOverride = { _ in }
        let now = Date()
        let configuration = SpendDashboardSource.configuration(settings: settings, store: store)
        let inputs = data == .stress ? Self.stressInputs(now: now, calendar: configuration.bucketCalendar) : []
        let controller = SpendDashboardController(
            userDefaults: InMemoryUserDefaults(),
            requestBuilder: { mode in
                SpendDashboardLoadRequest(
                    configuration: SpendDashboardSource.configuration(settings: settings, store: store),
                    capturedInputs: inputs,
                    unavailableSourceIDs: [],
                    codexRequests: [],
                    now: now,
                    force: mode.forcesLoader)
            },
            loader: { request in
                SpendDashboardLoadResult(inputs: request.capturedInputs, failedSourceIDs: [])
            },
            nowProvider: { now },
            publicationHandler: { store.spendDashboardPublication = $0 })
        store.sharedSpendDashboardControllerStorage = controller
        controller.selectPeriod(.rolling(days: 90))
        controller.update(configuration: configuration)
        try await SpendDashboardStateWait.until(timeout: .seconds(60)) { !controller.isRefreshing }
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
        return Session(settings: settings, store: store, controller: controller, context: context)
    }

    private static func sessionContext(_ session: Session) -> SessionUsageBrowserContext {
        let sessions = Self.sessions(now: Date())
        return SessionUsageBrowserContext(
            providerName: "OpenCode",
            windowLabel: "Last 90 days",
            sessions: sessions,
            currencyCode: "USD",
            costMultiplier: 1,
            timeZone: session.settings.costUsageBucketCalendar.timeZone)
    }

    /// Four sources over 90 days, one of them in euros, with long project paths, many models, sessions and hours.
    private static func stressInputs(now: Date, calendar: Calendar) -> [SpendDashboardModel.ProviderInput] {
        let today = calendar.startOfDay(for: now)
        func days(_ count: Int, scale: Double, models: [String]) -> [CostUsageDailyReport.Entry] {
            (0..<count).compactMap { offset -> CostUsageDailyReport.Entry? in
                guard offset % 9 != 4, let day = calendar.date(byAdding: .day, value: -offset, to: today) else {
                    return nil
                }
                let wave = 1 + sin(Double(offset) / 4) * 0.6
                let cost = (scale * wave * 100).rounded() / 100
                let tokens = Int(cost * 1_850_000)
                return self.entry(day: day, calendar: calendar, cost: cost, tokens: tokens, models: models)
            }
            .reversed()
        }
        let cursorDaily = days(90, scale: 14.2, models: ["example-large", "example-fast", "example-reasoning"])
        let openCodeDaily = days(60, scale: 3.4, models: ["sample-coder", "sample-coder-mini"])
        let claudeDaily = days(88, scale: 22.75, models: ["example-opus-like", "example-sonnet-like"])
        let mistralDaily = days(30, scale: 1.9, models: ["sample-medium"])
        let hours = (6...22).compactMap { hour -> CostUsageHourlyEntry? in
            guard let date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: today) else { return nil }
            return CostUsageHourlyEntry(hour: date, totalTokens: 620_000 + hour * 9000, costUSD: Double(hour) * 0.11)
        }
        let projects = [
            "tolkein-menu-bar-and-settings-window-rebuild-on-internal-ui",
            "example-dashboard",
            "payments-service",
            "a-very-long-monorepo-package-name-that-should-truncate-in-the-middle",
            "docs",
            "scratch",
            "infra-terraform-modules",
            "ios-app",
            "android-app",
            "website",
        ].enumerated().map { index, name in
            CostUsageProjectBreakdown(
                name: name,
                path: "/Users/example/Projects/clients/acme-corporation/\(name)",
                totalTokens: 40_000_000 / (index + 1),
                totalCostUSD: 180 / Double(index + 1),
                daily: [],
                modelBreakdowns: nil)
        }
        return [
            SpendDashboardModel.ProviderInput(
                provider: .cursor,
                displayName: "Cursor · engineering-team@acme-corporation.example",
                snapshot: self.snapshot(entries: cursorDaily, now: now, metered: 210.40, projects: projects)),
            SpendDashboardModel.ProviderInput(
                provider: .opencode,
                displayName: "OpenCode",
                snapshot: self.snapshot(
                    entries: openCodeDaily,
                    now: now,
                    sessions: self.sessions(now: now),
                    hourly: hours)),
            SpendDashboardModel.ProviderInput(
                provider: .claude,
                displayName: "Claude · personal",
                snapshot: self.snapshot(entries: claudeDaily, now: now)),
            SpendDashboardModel.ProviderInput(
                provider: .mistral,
                displayName: "Mistral",
                snapshot: self.snapshot(entries: mistralDaily, now: now, currencyCode: "EUR")),
        ]
    }

    private static func sessions(now: Date) -> [CostUsageSessionBreakdown] {
        (1...14).map { (index: Int) -> CostUsageSessionBreakdown in
            let title: String = index == 1
                ? "Rebuild the Settings window on Internal UI and move the dashboard into its own window"
                : "Session \(index)"
            let lastActivity: Date = now.addingTimeInterval(Double(-index) * 5400)
            let cost = 9.6 / Double(index)
            return CostUsageSessionBreakdown(
                sessionID: String(format: "session-%02d", index),
                lastActivity: lastActivity,
                inputTokens: 2_600_000 / index,
                cachedInputTokens: 1_200_000 / index,
                outputTokens: 300_000 / index,
                reasoningTokens: 120_000 / index,
                totalTokens: 4_100_000 / index,
                requestCount: 40 - index,
                costUSD: cost,
                modelBreakdowns: [],
                title: title)
        }
    }

    private static func snapshot(
        entries: [CostUsageDailyReport.Entry],
        now: Date,
        metered: Double? = nil,
        currencyCode: String = "USD",
        projects: [CostUsageProjectBreakdown] = [],
        sessions: [CostUsageSessionBreakdown] = [],
        hourly: [CostUsageHourlyEntry] = []) -> CostUsageTokenSnapshot
    {
        CostUsageTokenSnapshot(
            sessionTokens: entries.last?.totalTokens,
            sessionCostUSD: entries.last?.costUSD,
            last30DaysTokens: entries.compactMap(\.totalTokens).reduce(0, +),
            last30DaysCostUSD: entries.compactMap(\.costUSD).reduce(0, +),
            currencyCode: currencyCode,
            historyDays: 365,
            historyCoverageIsEstablished: true,
            meteredCostUSD: metered,
            costProvenance: metered == nil ? .listPriceEstimate : .mixed,
            daily: entries,
            projects: projects,
            sessions: sessions,
            hourly: hourly,
            updatedAt: now)
    }

    private static func entry(
        day: Date,
        calendar: Calendar,
        cost: Double,
        tokens: Int,
        models: [String]) -> CostUsageDailyReport.Entry
    {
        let share = Double(models.count)
        return CostUsageDailyReport.Entry(
            date: CostUsageScanner.CostUsageDayRange.dayKey(from: day, calendar: calendar),
            inputTokens: tokens * 6 / 10,
            outputTokens: tokens / 10,
            cacheReadTokens: tokens * 3 / 10,
            reasoningTokens: tokens / 20,
            totalTokens: tokens,
            requestCount: 12 * models.count,
            costUSD: cost,
            modelsUsed: models,
            modelBreakdowns: models.map { model in
                .init(
                    modelName: model,
                    costUSD: cost / share,
                    totalTokens: Int(Double(tokens) / share),
                    requestCount: 12,
                    inputTokens: Int(Double(tokens) * 0.6 / share),
                    outputTokens: Int(Double(tokens) * 0.1 / share),
                    cacheReadTokens: Int(Double(tokens) * 0.3 / share),
                    reasoningTokens: Int(Double(tokens) * 0.05 / share))
            },
            pricedRequestCount: 12 * models.count)
    }
}
