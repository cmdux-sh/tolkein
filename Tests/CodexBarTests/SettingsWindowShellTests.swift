import AppKit
import CodexBarCore
import SwiftUI
import Testing
@testable import CodexBar

/// The real Settings window content in an offscreen window: one layout on every macOS version.
@MainActor
struct SettingsWindowShellTests {
    @Test
    func `toolbar is native without sort controls, and the window title follows the pane`() async throws {
        let (window, selection) = self.makeWindow()
        defer { window.contentViewController = nil }
        try await self.settle(window)

        let toolbar = try #require(window.toolbar)
        #expect(!toolbar.items.isEmpty)
        let labels = Set(toolbar.items.filter { !$0.isHidden }.map(\.label))
        // The old sort controls moved into the sidebar's provider menu.
        #expect(labels.isDisjoint(with: [L("Sort providers alphabetically"), L("Provider sorting")]))
        #expect(window.title == SettingsPane.menu.title)

        selection.pane = .alerts
        try await self.settle(window)
        #expect(window.title == SettingsPane.alerts.title)
    }

    @Test
    func `sidebar column keeps the settings width bounds`() async throws {
        let (window, _) = self.makeWindow()
        defer { window.contentViewController = nil }
        try await self.settle(window)

        let content = try #require(window.contentView)
        let split = try #require(self.splitView(in: content))
        let controller = try #require(split.delegate as? NSSplitViewController)
        let sidebar = try #require(controller.splitViewItems.first)
        #expect(sidebar.canCollapse)
        #expect(sidebar.minimumThickness == SettingsPane.sidebarMinWidth)
        #expect(sidebar.maximumThickness == SettingsPane.sidebarMaxWidth)
    }

    private func makeWindow() -> (NSWindow, PreferencesSelection) {
        _ = NSApplication.shared
        let settings = testSettingsStore(suiteName: #function, userDefaults: InMemoryUserDefaults())
        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing)
        let selection = PreferencesSelection(userDefaults: InMemoryUserDefaults())
        selection.pane = .menu
        let view = PreferencesView(
            settings: settings,
            store: store,
            updater: DisabledUpdaterController(),
            selection: selection)
            .defaultAppStorage(InMemoryUserDefaults())
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 620),
            styleMask: [.titled, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        let hosting = NSHostingController(rootView: view)
        hosting.sceneBridgingOptions = [.toolbars, .title]
        window.contentViewController = hosting
        return (window, selection)
    }

    private func splitView(in view: NSView) -> NSSplitView? {
        if let split = view as? NSSplitView { return split }
        return view.subviews.lazy.compactMap { self.splitView(in: $0) }.first
    }

    private func settle(_ window: NSWindow) async throws {
        for _ in 0..<20 {
            window.contentView?.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}
