import AppKit
import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

/// The menu items that used to open Settings → Usage & Spend now open the Spend window. The controller's
/// `spendWindowOpenHandler` records where they go instead of presenting a window.
extension StatusMenuTests {
    @Test
    func `the Overview spend card opens the Spend window`() throws {
        let (controller, _) = try self.makeSpendMenuController()
        defer { controller.releaseStatusItemsForTesting() }
        var opened: [String] = []
        controller.spendWindowOpenHandler = { opened.append(SpendWindowOpeningTests.describe($0)) }

        let menu = controller.makeMenu()
        controller.menuWillOpen(menu)
        defer { controller.menuDidClose(menu) }
        let item = try #require(menu.items.first { ($0.representedObject as? String) == "overviewSpendSummary" })

        #expect(item.isEnabled)
        #expect(item.target === controller)
        #expect(item.action == #selector(StatusItemController.showSpendWindow(_:)))
        let action = try #require(item.action)
        _ = (item.target as AnyObject).perform(action, with: item)

        #expect(opened == ["dashboard"])
    }

    @Test
    func `browsing cost history sessions opens the Spend window on the session browser`() throws {
        let (controller, snapshot) = try self.makeSpendMenuController()
        defer { controller.releaseStatusItemsForTesting() }
        var opened: [SpendWindowDestination] = []
        controller.spendWindowOpenHandler = { opened.append($0) }

        let browse = controller.costHistorySessionBrowser(provider: .codex, tokenSnapshot: snapshot, submenu: nil)
        browse("session-a")
        // The browser opens once the menu has left its tracking loop, on the next default-mode run loop pass.
        let deadline = Date().addingTimeInterval(2)
        while opened.isEmpty, Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }

        let destination = try #require(opened.first)
        guard case let .sessions(context, sessionID) = destination else {
            Issue.record("Expected the session browser, got \(SpendWindowOpeningTests.describe(destination))")
            return
        }
        #expect(opened.count == 1)
        #expect(sessionID == "session-a")
        #expect(context.providerName == ProviderDescriptorRegistry.descriptor(for: .codex).metadata.displayName)
        #expect(context.sessions.map(\.sessionID) == ["session-a", "session-b"])
        #expect(context.timeZone == controller.settings.costUsageBucketCalendar.timeZone)
    }

    private func makeSpendMenuController() throws -> (StatusItemController, CostUsageTokenSnapshot) {
        self.disableMenuCardsForTesting()
        let settings = self.makeSettings()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = true
        settings.selectedMenuProvider = .codex
        settings.mergedMenuLastSelectedWasOverview = true
        settings.costSummaryDisplayStyle = .both
        settings.costUsageEnabled = true
        enableTestProviders([.codex, .claude], settings: settings)

        let store = self.makeCodexStore(settings: settings, dashboardAuthorized: false)
        let now = Date()
        let components = Calendar.current.dateComponents([.year, .month, .day], from: now)
        let day = try String(
            format: "%04d-%02d-%02d",
            #require(components.year),
            #require(components.month),
            #require(components.day))
        let sessions = ["session-a", "session-b"].map { id in
            CostUsageSessionBreakdown(
                sessionID: id,
                lastActivity: now,
                inputTokens: 60,
                cachedInputTokens: nil,
                outputTokens: 40,
                totalTokens: 100,
                requestCount: 1,
                costUSD: 0.5,
                modelBreakdowns: [])
        }
        let snapshot = CostUsageTokenSnapshot(
            sessionTokens: 100,
            sessionCostUSD: 1,
            last30DaysTokens: 100,
            last30DaysCostUSD: 1,
            costProvenance: .listPriceEstimate,
            daily: [
                CostUsageDailyReport.Entry(
                    date: day,
                    inputTokens: 60,
                    outputTokens: 40,
                    totalTokens: 100,
                    requestCount: 1,
                    costUSD: 1,
                    modelsUsed: ["test-model"],
                    modelBreakdowns: nil),
            ],
            sessions: sessions,
            updatedAt: now)
        store._setTokenSnapshotForTesting(snapshot, provider: .codex)

        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: UsageFetcher().loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: self.makeStatusBarForTesting())
        return (controller, snapshot)
    }
}
